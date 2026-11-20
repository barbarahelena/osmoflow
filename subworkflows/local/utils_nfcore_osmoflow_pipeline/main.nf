//
// Subworkflow with functionality specific to the barbarahelena/osmoflow pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN     } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap          } from 'plugin/nf-schema'
include { samplesheetToList         } from 'plugin/nf-schema'
include { paramsHelp                } from 'plugin/nf-schema'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input             //  string: Path to input samplesheet
    perform_runmerging // boolean: Merge the runs (samplesheet rows with the same sample name) of a FASTQ sample
    help              // boolean: Display help message and exit
    help_full         // boolean: Show the full help message
    show_hidden       // boolean: Show hidden parameters in the help message

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR>"

    UTILS_NFSCHEMA_PLUGIN (
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        "",
        "",
        command,
        null
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

    //
    // Custom validation for pipeline parameters
    //
    validateInputParameters()

    //
    // Create channels from input file provided through params.input
    //
    // Each row is either FASTQ reads (fastq_1[, fastq_2]) for 'osmotool profile'
    // or an assembly (fasta) for 'osmotool annotate' -- schema_input.json enforces
    // exactly one of the two is set. Reads and assemblies go to separate channels
    // of Reads / Assembly records (see subworkflows/local/types.nf).
    //
    def rows = samplesheetToList(params.input, "${projectDir}/assets/schema_input.json")
    validateSampleNames(rows, perform_runmerging)

    def ch_rows = channel
        .fromList(rows)
        .map { meta, fastq_1, fastq_2, fasta ->
            validateInputSamplesheet(meta, fastq_1, fastq_2, fasta, params.input as Path)
        }

    def ch_reads = ch_rows
        .filter { row -> row.fastq }
        .map { row -> record(id: row.id, single_end: row.single_end, run_accession: row.run_accession, fastq: row.fastq, read_count: null) }

    def ch_assemblies = ch_rows
        .filter { row -> row.fasta }
        .map { row -> record(id: row.id, fasta: row.fasta) }

    emit:
    reads      = ch_reads
    assemblies = ch_assemblies
    versions   = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {

    take:
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output

    main:
    def summary_params = paramsSummaryMap()

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(
                summary_params,
                email,
                email_on_fail,
                plaintext_email,
                outdir,
                monochrome_logs,
                []
            )
        }

        completionSummary(monochrome_logs)
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Validate pipeline parameters
//
def validateInputParameters() {
    if (params.osmo_db) {
        def db_dir = file(params.osmo_db, checkIfExists: true)
        if (!db_dir.isDirectory()) {
            error("--osmo_db must be a directory (an unpacked osmo_refdb release), got a file: ${params.osmo_db}")
        }
        if (!db_dir.resolve('osmo_refdb.dmnd').exists()) {
            error("--osmo_db (${params.osmo_db}) does not contain 'osmo_refdb.dmnd' -- point it at an unpacked osmo_refdb release directory, e.g. the 'v9/' produced by 'osmotool download-db'")
        }
        if (params.osmo_db_release != 'latest') {
            log.warn("Both --osmo_db and --osmo_db_release were provided; --osmo_db_release is ignored since the database will not be downloaded")
        }
    }
}

//
// Validate a single row from the input samplesheet: exactly one of
// FASTQ reads (fastq_1[, fastq_2]) or an assembly (fasta) must be set.
// schema_input.json already enforces this; this is a defence-in-depth
// check against the one combination the schema cannot express
// (fastq_2 given alongside fasta, with fastq_1 absent).
//
def validateInputSamplesheet(meta, fastq_1, fastq_2, fasta, samplesheet) {
    if (fasta && fastq_2 && !fastq_1) {
        error("Please check input samplesheet -> sample '${meta.id}' provides both 'fasta' and 'fastq_2' without 'fastq_1'; a sample must be either FASTQ reads (fastq_1[, fastq_2]) or an assembly (fasta), not both")
    }

    if (fastq_1) {
        def single_end = !fastq_2
        def reads = (single_end ? [ fastq_1 ] : [ fastq_1, fastq_2 ]).collect { f -> resolveSamplesheetPath(file(f), samplesheet) }
        def run_accession = meta.run_accession ? meta.run_accession as String : null   // [] when the column is absent
        return [ id: meta.id as String, single_end: single_end, run_accession: run_accession, fastq: reads, fasta: null ]
    }

    return [ id: meta.id as String, single_end: null, run_accession: null, fastq: null, fasta: resolveSamplesheetPath(file(fasta), samplesheet) ]
}

//
// Validate the sample names of the whole samplesheet. A FASTQ sample may appear on several rows
// only when its runs are merged (--perform_runmerging): then each row needs its own run_accession,
// and the runs must all be single-end or all paired-end. An assembly appears on one row only.
//
def validateSampleNames(rows, perform_runmerging) {
    rows.findAll { row -> row[1] }.groupBy { row -> row[0].id }.each { id, sample_rows ->
        if (sample_rows.size() == 1) {
            return
        }
        if (!perform_runmerging) {
            error("Please check input samplesheet -> FASTQ sample '${id}' appears on ${sample_rows.size()} rows. Use --perform_runmerging to merge the runs of a sample, or give each row its own sample name")
        }
        def runs = sample_rows.collect { row -> row[0].run_accession }
        if (runs.any { run -> !run } || runs.unique(false).size() != runs.size()) {
            error("Please check input samplesheet -> FASTQ sample '${id}' appears on several rows: each row needs a different value in the 'run_accession' column")
        }
        if (sample_rows.collect { row -> !row[2] }.unique(false).size() > 1) {
            error("Please check input samplesheet -> the runs of FASTQ sample '${id}' mix single-end and paired-end reads; they cannot be merged")
        }
    }
    rows.findAll { row -> !row[1] }.groupBy { row -> row[0].id }.each { id, assembly_rows ->
        if (assembly_rows.size() > 1) {
            error("Please check input samplesheet -> assembly '${id}' appears on ${assembly_rows.size()} rows; assemblies are not merged, give each row its own sample name")
        }
    }
}

//
// Resolve a file from the samplesheet. A relative path is read relative to the launch directory
// (nf-schema makes it absolute against it); when the file is not there, look next to the samplesheet,
// so a samplesheet can list files relative to its own location (e.g. assets/test/samplesheet.csv).
//
def resolveSamplesheetPath(path, samplesheet) {
    if (path.scheme != 'file' || path.exists()) {
        return path
    }
    def launch = workflow.launchDir.toAbsolutePath().normalize()
    def abs    = path.toAbsolutePath().normalize()
    if (abs.startsWith(launch)) {
        def beside_sheet = samplesheet.toAbsolutePath().parent.resolve(launch.relativize(abs).toString()).normalize()
        if (beside_sheet.exists()) {
            return beside_sheet
        }
    }
    error("Please check input samplesheet -> file does not exist: ${path}")
}
//
// Generate methods description for MultiQC
//
def toolCitationText() {
    def citation_text = [
            "Tools used in the workflow included:",
            "osmotool (Verhaar BJH),",
            "DIAMOND (Buchfink et al. 2021),",
            "HMMER (Eddy 2011),",
            "Prodigal (Hyatt et al. 2010)",
            "."
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    def reference_text = [
            "<li>Buchfink B, Reuter K, Drost HG. Sensitive protein alignments at tree-of-life scale using DIAMOND. Nat Methods. 2021 Apr;18(4):366-368. doi: 10.1038/s41592-021-01101-x</li>",
            "<li>Eddy SR. Accelerated Profile HMM Searches. PLoS Comput Biol. 2011 Oct;7(10):e1002195. doi: 10.1371/journal.pcbi.1002195</li>",
            "<li>Hyatt D, Chen GL, Locascio PF, Land ML, Larimer FW, Hauser LJ. Prodigal: prokaryotic gene recognition and translation initiation site identification. BMC Bioinformatics. 2010 Mar 8;11:119. doi: 10.1186/1471-2105-11-119</li>"
        ].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = ""
    meta["tool_bibliography"] = ""

    // TODO nf-core: Only uncomment below if logic in toolCitationText/toolBibliographyText has been filled!
    // meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    // meta["tool_bibliography"] = toolBibliographyText()


    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
