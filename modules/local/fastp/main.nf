process FASTP {
    tag "$meta.id"
    label 'process_medium'
    label 'fastp'

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.fastp.fastq.gz"), emit: reads
    tuple val(meta), path("*.fastp.json"),     emit: json
    tuple val(meta), path("*.fastp.html"),     emit: html
    tuple val(meta), path("*.fastp.log"),      emit: log
    path "versions.yml",                       emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args      = task.ext.args ?: ''
    def prefix    = task.ext.prefix ?: "${meta.id}"
    def input_str  = meta.single_end ? "--in1 ${reads[0]}" : "--in1 ${reads[0]} --in2 ${reads[1]}"
    def output_str = meta.single_end ? "--out1 ${prefix}.fastp.fastq.gz" : "--out1 ${prefix}_1.fastp.fastq.gz --out2 ${prefix}_2.fastp.fastq.gz"
    def pe_args    = meta.single_end ? '' : '--detect_adapter_for_pe'
    """
    fastp \\
        ${input_str} \\
        ${output_str} \\
        --json ${prefix}.fastp.json \\
        --html ${prefix}.fastp.html \\
        --thread ${task.cpus} \\
        ${pe_args} \\
        ${args} \\
        2> >(tee ${prefix}.fastp.log >&2)

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastp: \$(fastp --version 2>&1 | sed -e "s/fastp //g")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def touch_reads = meta.single_end ? "${prefix}.fastp.fastq.gz" : "${prefix}_1.fastp.fastq.gz ${prefix}_2.fastp.fastq.gz"
    """
    touch ${touch_reads} ${prefix}.fastp.json ${prefix}.fastp.html ${prefix}.fastp.log

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastp: stub
    END_VERSIONS
    """
}
