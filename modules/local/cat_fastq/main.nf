nextflow.enable.types = true

//
// Merge the runs of one FASTQ sample (samplesheet rows with the same sample name) by concatenating
// their gzipped FASTQ files: concatenated gzip streams are a valid gzip file.
//
process CAT_FASTQ {
    tag id
    label 'process_single'
    label 'cat'

    input:
    record(id: String, single_end: Boolean, fastq: List<Path>)   // all runs of one sample: [ r1, r2, r1, r2, ... ] or [ r1, r1, ... ]

    stage:
    stageAs fastq, 'input*/*'   // runs can have the same file name

    output:
    record(
        id: id,
        single_end: single_end,
        fastq: files('*.merged.fastq.gz').toSorted { a, b -> a.name <=> b.name }
    )

    topic:
    tuple(task.process, 'cat', eval('cat --version 2>&1 | head -n 1 | sed "s/^.*coreutils) //"')) >> 'versions'

    script:
    def prefix = task.ext.prefix ?: id
    def cmd
    if (single_end) {
        cmd = "cat ${fastq.join(' ')} > ${prefix}.merged.fastq.gz"
    } else {
        def read1 = fastq.withIndex().findAll { _f, i -> i % 2 == 0 }.collect { f, _i -> f }
        def read2 = fastq.withIndex().findAll { _f, i -> i % 2 == 1 }.collect { f, _i -> f }
        cmd = "cat ${read1.join(' ')} > ${prefix}_1.merged.fastq.gz\n    cat ${read2.join(' ')} > ${prefix}_2.merged.fastq.gz"
    }
    """
    ${cmd}
    """

    stub:
    def prefix      = task.ext.prefix ?: id
    def touch_reads = single_end ? "${prefix}.merged.fastq.gz" : "${prefix}_1.merged.fastq.gz ${prefix}_2.merged.fastq.gz"
    """
    touch ${touch_reads}
    """
}
