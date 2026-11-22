nextflow.enable.types = true

process OSMOTOOL_PROFILE {
    tag id
    label 'process_medium'

    container "docker://barbarahelena/osmotool:0.10.0"

    input:
    record(id: String, single_end: Boolean, fastq: List<Path>, read_count: Long?)   // read_count: pairs for paired-end
    osmo_refdb: Path

    output:
    record(
        id: id,
        counts: file('*.gene_counts.tsv'),
        stats: file('*.aln_stats.tsv')
    )

    topic:
    tuple(task.process, 'osmotool', eval('osmotool --version 2>&1 | sed "s/^osmotool //"')) >> 'versions'

    script:
    def args       = task.ext.args ?: ''
    def prefix     = task.ext.prefix ?: id
    def reads_args = single_end ? "--singles ${fastq[0]}" : "-1 ${fastq[0]} -2 ${fastq[1]}"
    // The read count from preprocessing: osmotool then skips its own counting pass over the reads
    def total_args = read_count != null ? "--total_fragments ${read_count}" : ''
    """
    osmotool profile \\
        ${osmo_refdb} \\
        ${reads_args} \\
        ${total_args} \\
        --out_prefix ${prefix} \\
        --threads ${task.cpus} \\
        ${args}
    """

    stub:
    def prefix = task.ext.prefix ?: id
    """
    touch ${prefix}.gene_counts.tsv
    touch ${prefix}.aln_stats.tsv
    """
}
