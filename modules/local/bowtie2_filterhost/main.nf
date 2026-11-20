nextflow.enable.types = true

process BOWTIE2_FILTERHOST {
    tag run_accession ? "${id}_${run_accession}" : id
    label 'process_high'
    label 'bowtie2'

    input:
    record(id: String, single_end: Boolean, run_accession: String?, fastq: List<Path>)
    index: Path   // directory with the Bowtie2 index (*.bt2)

    output:
    record(
        id: id,
        single_end: single_end,
        run_accession: run_accession,
        fastq: files('*_unmapped*.fastq.gz').toSorted { a, b -> a.name <=> b.name },
        log: file('*.bowtie2.log'),
        stats: file('*.stats')
    )

    topic:
    tuple(task.process, 'bowtie2',  eval('bowtie2 --version 2>&1 | head -n 1 | sed "s/^.*bowtie2-align-s version //; s/ .*//"')) >> 'versions'
    tuple(task.process, 'samtools', eval('samtools --version 2>&1 | sed -n "1s/^samtools //p"')) >> 'versions'

    script:
    def args          = task.ext.args ?: ''
    def prefix        = task.ext.prefix ?: (run_accession ? "${id}_${run_accession}" : id)
    def reads_args    = single_end ? "-U ${fastq[0]}" : "-1 ${fastq[0]} -2 ${fastq[1]}"
    def unmapped_args = single_end ? "--un-gz ${prefix}_unmapped.fastq.gz" : "--un-conc-gz ${prefix}_unmapped.fastq.gz"
    def rename        = single_end ? '' : """
    mv ${prefix}_unmapped.fastq.1.gz ${prefix}_unmapped_1.fastq.gz
    mv ${prefix}_unmapped.fastq.2.gz ${prefix}_unmapped_2.fastq.gz
    """
    // --reorder: reads come out in input order whatever the number of threads,
    // so subsampling afterwards picks the same reads on every run
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
    """

    stub:
    def prefix      = task.ext.prefix ?: (run_accession ? "${id}_${run_accession}" : id)
    def touch_reads = single_end ? "${prefix}_unmapped.fastq.gz" : "${prefix}_unmapped_1.fastq.gz ${prefix}_unmapped_2.fastq.gz"
    """
    touch ${touch_reads} ${prefix}.stats
    echo "0 reads; of these:" > ${prefix}.bowtie2.log
    echo "    0 (0.00%) aligned ${single_end ? '' : 'concordantly '}0 times" >> ${prefix}.bowtie2.log
    """
}
