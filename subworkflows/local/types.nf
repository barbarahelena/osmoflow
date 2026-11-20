nextflow.enable.types = true

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RECORD TYPES shared by the workflows of this pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// A FASTQ sample (samplesheet row with fastq_1[, fastq_2]): goes through 'osmotool profile'.
// A sample sequenced in several runs has one row per run, with the same id and a
// different run_accession; the runs are merged after host read removal (see --perform_runmerging).
record Reads {
    id: String
    single_end: Boolean
    run_accession: String?
    fastq: List<Path>       // [ fastq_1 ] or [ fastq_1, fastq_2 ]
    read_count: Long?       // reads (pairs for paired-end) in fastq, when a preprocessing step has counted them
}

// An assembly (samplesheet row with fasta): goes through 'osmotool annotate'
record Assembly {
    id: String
    fasta: Path
}
