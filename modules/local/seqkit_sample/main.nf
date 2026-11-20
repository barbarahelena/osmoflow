nextflow.enable.types = true

process SEQKIT_SAMPLE {
    tag id
    label 'process_low'
    label 'seqkit'

    input:
    record(id: String, single_end: Boolean, fastq: List<Path>, read_count: Long?)   // read_count: counted here when null
    subsamplelevel: Integer   // number of reads (pairs) to keep

    output:
    record(
        id: id,
        single_end: single_end,
        fastq: files('*_subsampled*.fastq.gz').toSorted { a, b -> a.name <=> b.name },
        reads_in: eval('cat reads_in.txt'),     // reads (pairs) before subsampling
        reads_out: eval('cat reads_out.txt')    // reads (pairs) kept
    )

    topic:
    tuple(task.process, 'seqkit', eval('seqkit version | sed "s/seqkit v//"')) >> 'versions'

    script:
    def args    = task.ext.args ?: ''
    def prefix  = task.ext.prefix ?: id
    def outputs = single_end ? [ "${prefix}_subsampled.fastq.gz" ] : [ "${prefix}_1_subsampled.fastq.gz", "${prefix}_2_subsampled.fastq.gz" ]
    // R1 and R2 are sampled at the same time; each file gets a reading and a writing seqkit
    def threads = Math.max(1, (single_end ? task.cpus : task.cpus.intdiv(2)).intdiv(2))
    // The read count is known when fastp or host read removal ran; otherwise count R1 here (an extra pass)
    def count   = read_count != null ? "${read_count}" : "\$(seqkit stats -T -j ${task.cpus} ${fastq[0]} | awk 'NR==2 {print \$4}')"
    def keep_all = (0..<fastq.size()).collect { i -> "ln -s ${fastq[i]} ${outputs[i]}" }.join('\n        ')
    // The same seed for R1 and R2 keeps the pairs in sync. awk keeps the first <level> reads (4 lines each)
    // and reads its input to the end: 'seqkit head' would stop reading early and break the pipe.
    def sample   = (0..<fastq.size()).collect { i ->
        "seqkit sample -p \$proportion -s 42 -j ${threads} ${args} ${fastq[i]} 2> sample_${i + 1}.log \\\n" +
        "            | awk 'NR <= ${4L * subsamplelevel}' \\\n" +
        "            | seqkit seq -j ${threads} --compress-level 1 -o ${outputs[i]} &\n" +
        "        pids=\"\$pids \$!\""
    }.join('\n        ')
    """
    reads_in=${count}

    if [ "\$reads_in" -le ${subsamplelevel} ]; then
        # No more reads than the subsample level: keep them all
        ${keep_all}
        reads_out=\$reads_in
    else
        # One pass: sample a proportion a little above level / reads_in (5 standard deviations,
        # so it practically always yields enough reads), then keep the first <level> of them
        proportion=\$(awk -v n=${subsamplelevel} -v t=\$reads_in 'BEGIN { p = (n + 5 * sqrt(n) + 10) / t; if (p > 1) p = 1; printf "%.8f", p }')
        pids=""
        ${sample}
        for pid in \$pids; do wait \$pid; done

        sampled=\$(grep -o '[0-9][0-9]* sequences outputted' sample_1.log | cut -d' ' -f1)
        reads_out=\$(( sampled < ${subsamplelevel} ? sampled : ${subsamplelevel} ))
    fi

    echo \$reads_in  > reads_in.txt
    echo \$reads_out > reads_out.txt
    """

    stub:
    def prefix      = task.ext.prefix ?: id
    def touch_reads = single_end ? "${prefix}_subsampled.fastq.gz" : "${prefix}_1_subsampled.fastq.gz ${prefix}_2_subsampled.fastq.gz"
    """
    touch ${touch_reads}
    echo ${read_count ?: 0} > reads_in.txt
    echo ${read_count ?: 0} > reads_out.txt
    """
}
