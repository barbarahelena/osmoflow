/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_osmoflow_pipeline'

include { OSMOTOOL_DOWNLOAD_DB } from '../modules/local/osmotool/download_db'
include { OSMOTOOL_PROFILE     } from '../modules/local/osmotool/profile'
include { OSMOTOOL_ANNOTATE    } from '../modules/local/osmotool/annotate'
include { OSMOTOOL_MERGE_COUNTS  } from '../modules/local/osmotool/merge_counts'
include { OSMOTOOL_MERGE_SYSTEMS } from '../modules/local/osmotool/merge_systems'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow OSMOFLOW {

    take:
    ch_samplesheet // channel: [ meta, reads|fasta ] read in from --input, meta.mode is 'profile' or 'annotate'
    main:

    ch_versions = channel.empty()

    //
    // Split the samplesheet: FASTQ reads go through 'osmotool profile',
    // assemblies go through 'osmotool annotate'
    //
    ch_samplesheet
        .branch { meta, input ->
            reads:    meta.mode == 'profile'
            assembly: meta.mode == 'annotate'
        }
        .set { ch_input }

    //
    // MODULE: Download the osmo_refdb reference database, unless a local copy was provided
    //
    if (params.osmo_db) {
        ch_osmo_refdb = Channel.value(file(params.osmo_db, checkIfExists: true))
    } else {
        OSMOTOOL_DOWNLOAD_DB ( params.osmo_db_release )
        ch_versions   = ch_versions.mix(OSMOTOOL_DOWNLOAD_DB.out.versions)
        ch_osmo_refdb = OSMOTOOL_DOWNLOAD_DB.out.db
    }

    //
    // MODULE: Profile FASTQ reads
    //
    OSMOTOOL_PROFILE ( ch_input.reads, ch_osmo_refdb )
    ch_versions = ch_versions.mix(OSMOTOOL_PROFILE.out.versions)

    //
    // MODULE: Annotate assemblies
    //
    OSMOTOOL_ANNOTATE ( ch_input.assembly, ch_osmo_refdb )
    ch_versions = ch_versions.mix(OSMOTOOL_ANNOTATE.out.versions)

    //
    // MODULE: Merge each mode's per-sample gene_counts.tsv into one gene x sample matrix.
    // profile (RPM) and annotate (copies_per_kb) are never merged together -- see docs/output.md.
    // Only runs when the corresponding mode has at least one sample.
    //
    OSMOTOOL_PROFILE.out.counts
        .map { meta, counts -> counts }
        .collect()
        .map { counts -> [ 'profile', counts ] }
        .set { ch_profile_counts }

    OSMOTOOL_ANNOTATE.out.counts
        .map { meta, counts -> counts }
        .collect()
        .map { counts -> [ 'annotate', counts ] }
        .set { ch_annotate_counts }

    OSMOTOOL_MERGE_COUNTS ( ch_profile_counts.mix(ch_annotate_counts) )
    ch_versions = ch_versions.mix(OSMOTOOL_MERGE_COUNTS.out.versions)

    //
    // MODULE: Merge each bin's *.systems.tsv into one long-format table.
    // Only produced for the 'annotate' mode, and only runs when at least one bin has a systems.tsv.
    //
    OSMOTOOL_ANNOTATE.out.systems
        .map { meta, systems -> systems }
        .collect()
        .filter { systems -> systems }
        .set { ch_annotate_systems }

    OSMOTOOL_MERGE_SYSTEMS ( ch_annotate_systems )
    ch_versions = ch_versions.mix(OSMOTOOL_MERGE_SYSTEMS.out.versions)

    //
    // Collate and save software versions
    //
    def topic_versions = Channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'osmoflow_software_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    emit:
    profile_counts   = OSMOTOOL_PROFILE.out.counts        // channel: [ meta, path(*.gene_counts.tsv) ]
    profile_stats    = OSMOTOOL_PROFILE.out.stats         // channel: [ meta, path(*.aln_stats.tsv) ]
    annotate_counts  = OSMOTOOL_ANNOTATE.out.counts       // channel: [ meta, path(*.gene_counts.tsv) ]
    annotate_stats   = OSMOTOOL_ANNOTATE.out.stats        // channel: [ meta, path(*.aln_stats.tsv) ]
    annotate_systems = OSMOTOOL_ANNOTATE.out.systems      // channel: [ meta, path(*.systems.tsv) ]
    merged_counts    = OSMOTOOL_MERGE_COUNTS.out.matrix   // channel: [ mode, path(<mode>_gene_counts.tsv) ]
    merged_systems   = OSMOTOOL_MERGE_SYSTEMS.out.tsv     // channel: path(merged_systems.tsv)
    versions         = ch_versions                        // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
