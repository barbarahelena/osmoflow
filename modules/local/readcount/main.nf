nextflow.enable.types = true

//
// Count the reads of a sample. Only used for --readcounts when no preprocessing step ran:
// fastp, Bowtie2 and subsampling report their read counts themselves.
//
process READCOUNT {
    tag id
    label 'process_single'
    label 'seqkit'

    input:
    record(id: String, single_end: Boolean, fastq: List<Path>)

    output:
    record(
        id: id,
        count: eval('cat count.txt')   // reads (pairs) in R1; mates have the same number of reads
    )

    topic:
    tuple(task.process, 'seqkit', eval('seqkit version | sed "s/seqkit v//"')) >> 'versions'

    script:
    """
    seqkit stats -T ${fastq[0]} | awk 'NR==2 {print \$4}' > count.txt
    """

    stub:
    """
    echo 0 > count.txt
    """
}
