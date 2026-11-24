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
include { CAT_FASTQ            } from '../modules/local/cat_fastq'
include { SEQKIT_SAMPLE        } from '../modules/local/seqkit_sample'
include { READCOUNT            } from '../modules/local/readcount'
include { OSMOTOOL_DOWNLOAD_DB } from '../modules/local/osmotool/download_db'
include { OSMOTOOL_PROFILE     } from '../modules/local/osmotool/profile'
include { OSMOTOOL_ANNOTATE    } from '../modules/local/osmotool/annotate'
include { OSMOTOOL_MERGE_COUNTS           } from '../modules/local/osmotool/merge_counts'
include { OSMOTOOL_MERGE_UNITS            } from '../modules/local/osmotool/merge_units'
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
    // Optional read preprocessing (FASTQ samples only): fastp, host read removal, merging runs, subsampling, read counts.
    // Every step is off unless its parameter is set. fastp and host read removal run on each run (samplesheet row)
    // of a sample; the runs are merged before subsampling.
    //
    def ch_runs: Channel<Reads> = ch_samples
    def host_filter = params.host_bowtie2_index || params.host_fasta

    // Read counts (reads, or pairs for paired-end) come from the preprocessing steps themselves:
    // each reports how many reads it read and wrote, so no step re-reads the files to count them.
    // The raw count is taken from the first step that runs; the count after the last one travels
    // with the reads (read_count) to subsampling and to osmotool (--total_fragments).
    def ch_raw_counts = channel.empty()   // tuple(id, count), per run

    if (params.fastp) {
        def fastp = FASTP(ch_runs)
        def fastp_counts = fastp.map { r -> tuple(r, fastpReadCounts(r.json)) }
        ch_raw_counts = ch_raw_counts.mix(fastp_counts.map { r, counts -> tuple(r.id, counts[0]) })
        ch_runs = fastp_counts.map { r, counts -> record(id: r.id, single_end: r.single_end, run_accession: r.run_accession, fastq: r.fastq, read_count: counts[1]) }
    }

    if (host_filter) {
        def ch_host_index = params.host_bowtie2_index
            ? channel.value(file(params.host_bowtie2_index, checkIfExists: true))
            : BOWTIE2_BUILD(file(params.host_fasta, checkIfExists: true))
        def filtered = BOWTIE2_FILTERHOST(ch_runs, ch_host_index)
        def filtered_counts = filtered.map { r -> tuple(r, bowtie2ReadCounts(r.log, r.single_end)) }
        if (!params.fastp) {
            ch_raw_counts = ch_raw_counts.mix(filtered_counts.map { r, counts -> tuple(r.id, counts[0]) })
        }
        ch_runs = filtered_counts.map { r, counts -> record(id: r.id, single_end: r.single_end, run_accession: r.run_accession, fastq: r.fastq, read_count: counts[1]) }
    }

    //
    // MODULE: Merge the runs of a sample (samplesheet rows with the same sample name), with --perform_runmerging.
    // Samples with a single run are passed on as they are. The runs' read counts are added up.
    //
    def ch_reads = ch_runs.map { r -> record(id: r.id, single_end: r.single_end, fastq: r.fastq, read_count: r.read_count) }
    if (params.perform_runmerging) {
        // Sort the runs of a sample so the order of reads in the merged file does not depend on task order
        def ch_grouped = ch_runs
            .map { r -> tuple(r.id, r) }
            .groupBy()
            .map { id, runs ->
                def sorted = runs.toSorted { a, b -> (a.run_accession ?: '') <=> (b.run_accession ?: '') }
                def count  = sorted.every { r -> r.read_count != null } ? sorted.sum { r -> r.read_count } as Long : null
                tuple(id, sorted[0].single_end, sorted.size(), sorted.collectMany { r -> r.fastq }.toList(), count)
            }
        def merged = CAT_FASTQ(
            ch_grouped
                .filter { _id, _se, n, _fastq, _count -> n > 1 }
                .map { id, se, _n, fastq, count -> record(id: id, single_end: se, fastq: fastq, read_count: count) }
        )
        ch_reads = ch_grouped
            .filter { _id, _se, n, _fastq, _count -> n == 1 }
            .map { id, se, _n, fastq, count -> record(id: id, single_end: se, fastq: fastq, read_count: count) }
            .mix(merged)
    }

    //
    // MODULE: Subsample to --subsamplelevel reads (pairs) per sample
    //
    if (params.subsamplelevel) {
        def subsampled = SEQKIT_SAMPLE(ch_reads, params.subsamplelevel as Integer)
        if (!params.fastp && !host_filter) {
            // No earlier step counted the reads: subsampling did
            ch_raw_counts = ch_raw_counts.mix(subsampled.map { r -> tuple(r.id, r.reads_in.toLong()) })
        }
        ch_reads = subsampled.map { r -> record(id: r.id, single_end: r.single_end, fastq: r.fastq, read_count: r.reads_out.toLong()) }
    }

    def ch_readcounts: Channel<Path> = channel.empty()
    if (params.readcounts) {
        def ch_final_counts = ch_reads.map { r -> tuple(r.id, r.read_count) }
        if (!params.fastp && !host_filter && !params.subsamplelevel) {
            // No preprocessing step ran, so nothing counted the reads: count them here (raw = final)
            def counted = READCOUNT(ch_reads).map { r -> tuple(r.id, r.count.toLong()) }
            ch_raw_counts   = ch_raw_counts.mix(counted)
            ch_final_counts = counted
        }
        // One table with a raw and a final row per sample, sorted so it does not depend on task order.
        // The runs of a sample each have a raw count: they are added up into the sample's raw row.
        ch_readcounts = ch_readcounts.mix(WRITE_READCOUNTS(
            'readcounts.csv',
            channel.empty()
                .mix(ch_raw_counts.map { id, count -> "${id},raw,${count}" })
                .mix(ch_final_counts.map { id, count -> "${id},final,${count}" })
                .collect()
                .map { lines ->
                    def by_sample_stage = lines
                        .collect { line -> line.tokenize(',') }
                        .groupBy { fields -> [ fields[0], fields[1] ].join(',') }
                    def rows = by_sample_stage.keySet().collect { key ->
                        "${key},${by_sample_stage[key].sum { fields -> fields[2].toLong() }}"
                    }
                    ([ 'sample,stage,reads' ] + rows.toSorted()).join('\n') + '\n'
                }
        ))
    }

    //
    // MODULE: Profile FASTQ reads
    //
    // osmotool profile's unit table needs the release's report levels (osmo_refdb v10+). Checked here, on the
    // FASTQ samples only (annotate-only runs may use older releases), so the run stops with one message
    // instead of every sample's profile task failing and retrying.
    def ch_reads_checked = ch_reads
        .combine(ch_osmo_refdb)
        .map { r, db ->
            if (!db.resolve('osmo_refdb.profile_report_levels.tsv').exists())
                error "osmoflow needs osmo_refdb v10 or later for FASTQ samples: ${db} has no " +
                      "osmo_refdb.profile_report_levels.tsv. Pass --osmo_db with a v10 (or later) release."
            r
        }
    def profile_results = OSMOTOOL_PROFILE(ch_reads_checked, ch_osmo_refdb)

    //
    // MODULE: Annotate assemblies
    //
    def annotate_results = OSMOTOOL_ANNOTATE(ch_assemblies, ch_osmo_refdb)

    //
    // MODULE: Merge each mode's per-sample unit_counts.tsv (gene_counts.tsv with the release's report levels
    // applied) into unit x sample matrices, and for profile one long table of where the reads came from.
    // These are profile's results. annotate writes unit_counts.tsv only with osmo_refdb v11+ (annotate report
    // levels). Only runs for a mode with at least one sample that has the table.
    //
    def ch_profile_units = profile_results
        .map { r -> r.units }
        .collect()
    def ch_annotate_units = annotate_results
        .filter { r -> r.units != null }
        .map { r -> r.units }
        .collect()
    def merged_units_results = OSMOTOOL_MERGE_UNITS(
        channel.empty()
            .mix(ch_profile_units.map { units -> tuple('profile', units) })
            .mix(ch_annotate_units.map { units -> tuple('annotate', units) })
            .filter { _mode, units -> units }   // collect() gives [] when a mode has no tables: do not run the merge
            .map { mode, units -> record(mode: mode, units: units.toSorted { a, b -> a.name <=> b.name }) }
    )

    //
    // MODULE: Merge each mode's per-sample gene_counts.tsv into gene x sample matrices (one per value column).
    // For profile only with --profile_gene_matrices, since these ignore the report levels.
    // profile (RPM) and annotate (copies_per_kb) are never merged together -- see docs/output.md.
    // Only runs when the corresponding mode has at least one sample.
    //
    // collect() gives [] when a mode has no samples: filter those out so the merge does not run
    def ch_annotate_counts = annotate_results
        .map { r -> r.counts }
        .collect()
    def ch_gene_counts = channel.empty()
        .mix(ch_annotate_counts.map { counts -> tuple('annotate', counts) })
    if (params.profile_gene_matrices) {
        def ch_profile_counts = profile_results
            .map { r -> r.counts }
            .collect()
        ch_gene_counts = ch_gene_counts.mix(ch_profile_counts.map { counts -> tuple('profile', counts) })
    }
    def ch_merge_counts = ch_gene_counts
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
    profile            = profile_results             // channel: record(id, counts, units, stats)
    annotate           = annotate_results            // channel: record(id, counts, units?, stats, systems?, coordinates?)
    merged_units       = merged_units_results        // channel: record(mode, matrix: [ <mode>_unit_<column>.tsv, ... ], sources?)
    merged_counts      = merged_counts_results       // channel: record(mode, matrix: [ <mode>_<column>.tsv, ... ])
    merged_systems     = merged_systems_results      // channel: merged_systems.tsv
    merged_coordinates = merged_coordinates_results  // channel: merged_gene_coordinates.tsv
    readcounts         = ch_readcounts       // channel: readcounts.csv
    versions           = ch_versions         // channel: osmoflow_software_versions.yml
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Reads before and after fastp, from its JSON report: [ before, after ].
// read1_*: R1 alone, so read pairs for paired-end (summary.* counts both mates).
//
def fastpReadCounts(json: Path) -> List<Long> {
    def report = new groovy.json.JsonSlurper().parseText(json.text) as Map
    def before = report['read1_before_filtering'] as Map
    def after  = report['read1_after_filtering'] as Map
    return [ before['total_reads'] as Long, after['total_reads'] as Long ]
}

//
// Reads given to Bowtie2 and reads written out as not host, from its log: [ input, unaligned ].
// Pairs for paired-end: Bowtie2 counts a pair as one read, and --un-conc writes the pairs that
// did not align concordantly.
//
def bowtie2ReadCounts(log: Path, single_end: Boolean) -> List<Long> {
    def text      = log.text
    def total     = leadingNumber(text, 'reads; of these:')
    def unaligned = leadingNumber(text, single_end ? 'aligned 0 times' : 'aligned concordantly 0 times')
    if (total == null || unaligned == null) {
        error("Could not read the read counts from the Bowtie2 log ${log}")
    }
    return [ total, unaligned ]
}

// The number a line starts with, for the first line of `text` that contains `phrase`; null when none does.
// E.g. '    950 (95.00%) aligned concordantly 0 times' -> 950
def leadingNumber(text: String, phrase: String) -> Long? {
    def line = text.readLines().find { l -> l.contains(phrase) }
    return line != null ? line.trim().tokenize(' ')[0].toLong() : null
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
