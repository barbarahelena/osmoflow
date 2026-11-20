nextflow.enable.types = true

process READCOUNT {
    tag "${id} (${stage})"
    label 'process_single'
    label 'seqkit'

    input:
    record(id: String, single_end: Boolean, fastq: List<Path>)
    stage: String   // 'raw' or 'final'

    output:
    file('*.readcount.csv')   // one line: sample,stage,reads

    topic:
    tuple(task.process, 'seqkit', eval('seqkit version | sed "s/seqkit v//"')) >> 'versions'

    script:
    // Reads (pairs) in the first file; mates have the same number of reads
    """
    n=\$(seqkit stats -T ${fastq[0]} | awk 'NR==2 {print \$4}')
    echo "${id},${stage},\$n" > ${id}.${stage}.readcount.csv
    """

    stub:
    """
    echo "${id},${stage},0" > ${id}.${stage}.readcount.csv
    """
}
