nextflow.enable.types = true

process SEQKIT_SAMPLE {
    tag id
    label 'process_low'
    label 'seqkit'

    input:
    record(id: String, single_end: Boolean, fastq: List<Path>)
    subsamplelevel: Integer   // number of reads (pairs) to keep

    output:
    record(
        id: id,
        single_end: single_end,
        fastq: files('*_subsampled*.fastq.gz').toSorted { a, b -> a.name <=> b.name }
    )

    topic:
    tuple(task.process, 'seqkit', eval('seqkit version | sed "s/seqkit v//"')) >> 'versions'

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: id
    // The same seed for both mates keeps the pairs in sync. Samples with fewer reads are kept as they are.
    def cmds = single_end
        ? "seqkit sample -s 42 -n ${subsamplelevel} ${args} ${fastq[0]} -o ${prefix}_subsampled.fastq.gz"
        : (0..1).collect { i -> "seqkit sample -s 42 -n ${subsamplelevel} ${args} ${fastq[i]} -o ${prefix}_${i + 1}_subsampled.fastq.gz" }.join('\n    ')
    """
    ${cmds}
    """

    stub:
    def prefix      = task.ext.prefix ?: id
    def touch_reads = single_end ? "${prefix}_subsampled.fastq.gz" : "${prefix}_1_subsampled.fastq.gz ${prefix}_2_subsampled.fastq.gz"
    """
    touch ${touch_reads}
    """
}
