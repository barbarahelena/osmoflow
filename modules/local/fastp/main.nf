nextflow.enable.types = true

process FASTP {
    tag run_accession ? "${id}_${run_accession}" : id
    label 'process_medium'
    label 'fastp'

    input:
    record(id: String, single_end: Boolean, run_accession: String?, fastq: List<Path>)

    output:
    record(
        id: id,
        single_end: single_end,
        run_accession: run_accession,
        fastq: files('*.fastp.fastq.gz').toSorted { a, b -> a.name <=> b.name },
        json: file('*.fastp.json'),
        html: file('*.fastp.html'),
        log: file('*.fastp.log')
    )

    topic:
    tuple(task.process, 'fastp', eval('fastp --version 2>&1 | sed -e "s/fastp //g"')) >> 'versions'

    script:
    def args       = task.ext.args ?: ''
    def prefix     = task.ext.prefix ?: (run_accession ? "${id}_${run_accession}" : id)
    def input_str  = single_end ? "--in1 ${fastq[0]}" : "--in1 ${fastq[0]} --in2 ${fastq[1]}"
    def output_str = single_end ? "--out1 ${prefix}.fastp.fastq.gz" : "--out1 ${prefix}_1.fastp.fastq.gz --out2 ${prefix}_2.fastp.fastq.gz"
    def pe_args    = single_end ? '' : '--detect_adapter_for_pe'
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
    """

    stub:
    def prefix      = task.ext.prefix ?: (run_accession ? "${id}_${run_accession}" : id)
    def touch_reads = single_end ? "${prefix}.fastp.fastq.gz" : "${prefix}_1.fastp.fastq.gz ${prefix}_2.fastp.fastq.gz"
    """
    touch ${touch_reads} ${prefix}.fastp.html ${prefix}.fastp.log
    echo '{"read1_before_filtering": {"total_reads": 0}, "read1_after_filtering": {"total_reads": 0}}' > ${prefix}.fastp.json
    """
}
