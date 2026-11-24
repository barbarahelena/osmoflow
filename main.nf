#!/usr/bin/env nextflow

nextflow.enable.types = true
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    barbarahelena/osmoflow
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/barbarahelena/osmoflow
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { OSMOFLOW  } from './workflows/osmoflow'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_osmoflow_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_osmoflow_pipeline'
include { Reads; Assembly          } from './subworkflows/local/types'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PARAMETERS
    Typed: command-line values are converted to these types at launch, and a wrong type
    or an undeclared (misspelled) parameter stops the run before it starts.
    Infrastructure params read by config files (outdir, publish_dir_mode, config_profile_*, ...)
    are defined in nextflow.config. Keep defaults in sync with nextflow_schema.json.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

params {
    // Input (required for a run; optional here so --help works without it)
    input: Path?                    = null

    // osmotool reference database
    osmo_db: Path?                  = null       // unpacked osmo_refdb release; downloaded when not given
    osmo_db_release: String         = 'latest'   // FASTQ samples need v10+ (report levels)

    // Optional read preprocessing (FASTQ samples only; every step is off by default)
    fastp: Boolean                  = false      // quality filtering + adapter trimming with fastp
    host_bowtie2_index: Path?       = null       // Bowtie2 index (directory with *.bt2) for host read removal
    host_fasta: Path?               = null       // or a host genome fasta; the Bowtie2 index is built from it
    subsamplelevel: Integer?        = null       // subsample to this number of reads (pairs) per sample
    readcounts: Boolean             = false      // table with read counts per sample (raw and final)
    perform_runmerging: Boolean     = false      // merge the runs (rows with the same sample name) of a FASTQ sample

    // Profile outputs
    profile_gene_matrices: Boolean  = false      // also merge gene_counts.tsv into gene x sample matrices (ignore the report levels)

    // Output and notifications (outdir and monochrome_logs are also set in nextflow.config, which config files read; config wins)
    outdir: String?                 = null
    publish_dir_mode: String        = 'copy'
    email: String?                  = null
    email_on_fail: String?          = null
    plaintext_email: Boolean        = false
    monochrome_logs: Boolean        = false

    // Generic
    help: String?                   = null       // --help, or --help <parameter> for one parameter
    help_full: Boolean              = false
    show_hidden: Boolean            = false
    version: Boolean                = false
    validate_params: Boolean        = true
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow BARBARAHELENA_OSMOFLOW {

    take:
    reads: Channel<Reads>         // FASTQ samples read in from --input
    assemblies: Channel<Assembly> // assemblies read in from --input

    main:

    //
    // WORKFLOW: Run pipeline
    //
    OSMOFLOW (
        reads,
        assemblies
    )
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:
    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    def init = PIPELINE_INITIALISATION (
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.perform_runmerging,
        params.help,
        params.help_full,
        params.show_hidden
    )

    //
    // WORKFLOW: Run main workflow
    //
    BARBARAHELENA_OSMOFLOW (
        init.reads,
        init.assemblies
    )
    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION (
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        params.outdir,
        params.monochrome_logs,
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
