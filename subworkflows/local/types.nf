nextflow.enable.types = true

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RECORD TYPES shared by the workflows of this pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// A FASTQ sample (samplesheet row with fastq_1[, fastq_2]): goes through 'osmotool profile'
record Reads {
    id: String
    single_end: Boolean
    fastq: List<Path>       // [ fastq_1 ] or [ fastq_1, fastq_2 ]
}

// An assembly (samplesheet row with fasta): goes through 'osmotool annotate'
record Assembly {
    id: String
    fasta: Path
}
