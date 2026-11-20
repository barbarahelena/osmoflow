nextflow.enable.types = true

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { workflowVersionToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { Reads; Assembly       } from '../subworkflows/local/types'

include { FASTP                } from '../modules/local/fastp'
include { BOWTIE2_BUILD        } from '../modules/local/bowtie2_build'
include { BOWTIE2_FILTERHOST   } from '../modules/local/bowtie2_filterhost'
include { SEQKIT_SAMPLE        } from '../modules/local/seqkit_sample'
include { READCOUNT as READCOUNT_RAW   } from '../modules/local/readcount'
include { READCOUNT as READCOUNT_FINAL } from '../modules/local/readcount'
include { OSMOTOOL_DOWNLOAD_DB } from '../modules/local/osmotool/download_db'
include { OSMOTOOL_PROFILE     } from '../modules/local/osmotool/profile'
include { OSMOTOOL_ANNOTATE    } from '../modules/local/osmotool/annotate'
include { OSMOTOOL_MERGE_COUNTS           } from '../modules/local/osmotool/merge_counts'
include { OSMOTOOL_MERGE_SYSTEMS          } from '../modules/local/osmotool/merge_systems'
include { OSMOTOOL_MERGE_GENE_COORDINATES } from '../modules/local/osmotool/merge_gene_coordinates'
include { WRITE_FILE as WRITE_READCOUNTS  } from '../modules/local/write_file'
include { WRITE_FILE as WRITE_VERSIONS    } from '../modules/local/write_file'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow OSMOFLOW {

    take:
    ch_samples: Channel<Reads>       // FASTQ samples, for 'osmotool profile'
    ch_assemblies: Channel<Assembly> // assemblies, for 'osmotool annotate'

    main:

    //
    // MODULE: Download the osmo_refdb reference database, unless a local copy was provided
    //
    def ch_osmo_refdb = params.osmo_db
        ? channel.value(file(params.osmo_db, checkIfExists: true))
        : OSMOTOOL_DOWNLOAD_DB(params.osmo_db_release as String)

    //
    // Optional read preprocessing (FASTQ samples only): fastp, host read removal, subsampling, read counts.
    // Every step is off unless its parameter is set.
    //
    def ch_reads: Channel<Reads> = ch_samples

    def ch_readcounts_raw = params.readcounts
        ? READCOUNT_RAW(ch_reads, 'raw')
        : channel.empty()

    if (params.fastp) {
        def fastp = FASTP(ch_reads)
        ch_reads = fastp.map { r -> record(id: r.id, single_end: r.single_end, fastq: r.fastq) }
    }

    if (params.host_bowtie2_index || params.host_fasta) {
        def ch_host_index = params.host_bowtie2_index
            ? channel.value(file(params.host_bowtie2_index, checkIfExists: true))
            : BOWTIE2_BUILD(file(params.host_fasta, checkIfExists: true))
        def filtered = BOWTIE2_FILTERHOST(ch_reads, ch_host_index)
        ch_reads = filtered.map { r -> record(id: r.id, single_end: r.single_end, fastq: r.fastq) }
    }

    if (params.subsamplelevel) {
        def subsampled = SEQKIT_SAMPLE(ch_reads, params.subsamplelevel as Integer)
        ch_reads = subsampled.map { r -> record(id: r.id, single_end: r.single_end, fastq: r.fastq) }
    }

    def ch_readcounts: Channel<Path> = channel.empty()
    if (params.readcounts) {
        def ch_readcounts_final = READCOUNT_FINAL(ch_reads, 'final')
        // One table with a raw and a final row per sample, sorted so it does not depend on task order
        ch_readcounts = ch_readcounts.mix(WRITE_READCOUNTS(
            'readcounts.csv',
            ch_readcounts_raw
                .mix(ch_readcounts_final)
                .map { f -> f.text.trim() }
                .collect()
                .map { lines -> ([ 'sample,stage,reads' ] + lines.toSorted()).join('\n') + '\n' }
        ))
    }

    //
    // MODULE: Profile FASTQ reads
    //
    def profile_results = OSMOTOOL_PROFILE(ch_reads, ch_osmo_refdb)

    //
    // MODULE: Annotate assemblies
    //
    def annotate_results = OSMOTOOL_ANNOTATE(ch_assemblies, ch_osmo_refdb)

    //
    // MODULE: Merge each mode's per-sample gene_counts.tsv into gene x sample matrices (one per value column).
    // profile (RPM) and annotate (copies_per_kb) are never merged together -- see docs/output.md.
    // Only runs when the corresponding mode has at least one sample.
    //
    // collect() gives [] when a mode has no samples: filter those out so the merge does not run
    def ch_profile_counts = profile_results
        .map { r -> r.counts }
        .collect()
    def ch_annotate_counts = annotate_results
        .map { r -> r.counts }
        .collect()
    def ch_merge_counts = channel.empty()
        .mix(ch_profile_counts.map { counts -> tuple('profile', counts) })
        .mix(ch_annotate_counts.map { counts -> tuple('annotate', counts) })
        .filter { _mode, counts -> counts }
        .map { mode, counts -> record(mode: mode, counts: counts.toSorted { a, b -> a.name <=> b.name }) }

    def merged_counts_results = OSMOTOOL_MERGE_COUNTS(ch_merge_counts)

    //
    // MODULE: Merge each bin's *.systems.tsv into one long-format table.
    // Only produced for the 'annotate' mode, and only runs when at least one bin has a systems.tsv.
    //
    def merged_systems_results = OSMOTOOL_MERGE_SYSTEMS(
        channel.empty()
            .mix(annotate_results.filter { r -> r.systems != null }.map { r -> r.systems }.collect())
            .filter { files -> files }   // collect() gives [] when no bin has one: do not run the merge
            .map { files -> files.toSorted { a, b -> a.name <=> b.name } }
    )

    //
    // MODULE: Merge each genome/bin's *.gene_coordinates.tsv into one long-format table.
    // Only produced for the 'annotate' mode, and only runs when at least one bin has a gene_coordinates.tsv.
    //
    def merged_coordinates_results = OSMOTOOL_MERGE_GENE_COORDINATES(
        channel.empty()
            .mix(annotate_results.filter { r -> r.coordinates != null }.map { r -> r.coordinates }.collect())
            .filter { files -> files }   // collect() gives [] when no bin has one: do not run the merge
            .map { files -> files.toSorted { a, b -> a.name <=> b.name } }
    )

    //
    // Collate software versions from the 'versions' topic channel. Each entry is [ process, tool, version ].
    // collect() waits until every process has reported; sorting makes the file independent of task order.
    //
    def ch_versions_topic: Channel<Tuple> = channel.topic('versions')
    def ch_versions = WRITE_VERSIONS(
        'osmoflow_software_versions.yml',
        ch_versions_topic
            .map { process, tool, version ->
                def v = (version instanceof Path) ? version.text.trim() : version.toString().trim()
                tuple(process.tokenize(':')[-1], "  ${tool}: ${v}")
            }
            .unique()
            .groupBy()
            .map { process, lines -> "${process}:\n${lines.toSorted().join('\n')}" }
            .collect()
            .map { sections -> (sections.toSorted() + [ workflowVersionToYAML() ]).join('\n') + '\n' }
    )

    emit:
    profile            = profile_results             // channel: record(id, counts, stats)
    annotate           = annotate_results            // channel: record(id, counts, stats, systems?, coordinates?)
    merged_counts      = merged_counts_results       // channel: record(mode, matrix: [ <mode>_<column>.tsv, ... ])
    merged_systems     = merged_systems_results      // channel: merged_systems.tsv
    merged_coordinates = merged_coordinates_results  // channel: merged_gene_coordinates.tsv
    readcounts         = ch_readcounts       // channel: readcounts.csv
    versions           = ch_versions         // channel: osmoflow_software_versions.yml
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
