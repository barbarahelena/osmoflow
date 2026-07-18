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
    profile_counts  = OSMOTOOL_PROFILE.out.counts  // channel: [ meta, path(*.gene_counts.tsv) ]
    profile_stats   = OSMOTOOL_PROFILE.out.stats   // channel: [ meta, path(*.aln_stats.tsv) ]
    annotate_counts = OSMOTOOL_ANNOTATE.out.counts // channel: [ meta, path(*.gene_counts.tsv) ]
    annotate_stats  = OSMOTOOL_ANNOTATE.out.stats  // channel: [ meta, path(*.aln_stats.tsv) ]
    versions        = ch_versions                  // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
