process BOWTIE2_FILTERHOST {
    tag "$meta.id"
    label 'process_high'
    label 'bowtie2'

    input:
    tuple val(meta), path(reads)
    path index

    output:
    tuple val(meta), path("*_unmapped*.fastq.gz"), emit: reads
    tuple val(meta), path("*.bowtie2.log"),        emit: log
    tuple val(meta), path("*.stats"),              emit: stats
    path "versions.yml",                           emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args          = task.ext.args ?: ''
    def prefix        = task.ext.prefix ?: "${meta.id}"
    def reads_args    = meta.single_end ? "-U ${reads[0]}" : "-1 ${reads[0]} -2 ${reads[1]}"
    def unmapped_args = meta.single_end ? "--un-gz ${prefix}_unmapped.fastq.gz" : "--un-conc-gz ${prefix}_unmapped.fastq.gz"
    def rename        = meta.single_end ? "" : """
    mv ${prefix}_unmapped.fastq.1.gz ${prefix}_unmapped_1.fastq.gz
    mv ${prefix}_unmapped.fastq.2.gz ${prefix}_unmapped_2.fastq.gz
    """
    """
    INDEX=`find -L ./ -name "*.rev.1.bt2" | sed "s/\\.rev.1.bt2\$//"`
    [ -z "\$INDEX" ] && INDEX=`find -L ./ -name "*.rev.1.bt2l" | sed "s/\\.rev.1.bt2l\$//"`
    [ -z "\$INDEX" ] && echo "Bowtie2 index files not found" 1>&2 && exit 1

    bowtie2 \\
        -x \$INDEX \\
        ${reads_args} \\
        --threads ${task.cpus} \\
        --reorder \\
        ${unmapped_args} \\
        ${args} \\
        2> >(tee ${prefix}.bowtie2.log >&2) \\
        | samtools sort --threads ${task.cpus} -o ${prefix}.bam -

    samtools stats ${prefix}.bam --threads ${task.cpus} > ${prefix}.stats
    rm ${prefix}.bam
    ${rename}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bowtie2: \$(bowtie2 --version 2>&1 | head -n 1 | sed "s/^.*bowtie2-align-s version //; s/ .*//")
        samtools: \$(samtools --version 2>&1 | sed -n "1s/^samtools //p")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def touch_reads = meta.single_end ? "${prefix}_unmapped.fastq.gz" : "${prefix}_unmapped_1.fastq.gz ${prefix}_unmapped_2.fastq.gz"
    """
    touch ${touch_reads} ${prefix}.bowtie2.log ${prefix}.stats

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bowtie2: stub
        samtools: stub
    END_VERSIONS
    """
}
