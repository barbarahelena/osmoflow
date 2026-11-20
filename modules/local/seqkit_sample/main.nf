process SEQKIT_SAMPLE {
    tag "$meta.id"
    label 'process_low'
    label 'seqkit'

    input:
    tuple val(meta), path(reads)
    val subsamplelevel   // number of reads (pairs) to keep

    output:
    tuple val(meta), path("*_subsampled*.fastq.gz"), emit: reads
    path "versions.yml",                             emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    // Same seed for both mates keeps pairs in sync. Samples with fewer reads are kept as they are.
    def cmds = meta.single_end
        ? "seqkit sample -s 42 -n ${subsamplelevel} ${args} ${reads[0]} -o ${prefix}_subsampled.fastq.gz"
        : (0..1).collect { i -> "seqkit sample -s 42 -n ${subsamplelevel} ${args} ${reads[i]} -o ${prefix}_${i+1}_subsampled.fastq.gz" }.join('\n    ')
    """
    ${cmds}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqkit: \$(seqkit version | sed "s/seqkit v//")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def touch_reads = meta.single_end ? "${prefix}_subsampled.fastq.gz" : "${prefix}_1_subsampled.fastq.gz ${prefix}_2_subsampled.fastq.gz"
    """
    touch ${touch_reads}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqkit: stub
    END_VERSIONS
    """
}
