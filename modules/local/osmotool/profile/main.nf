nextflow.enable.types = true

process OSMOTOOL_PROFILE {
    tag id
    label 'process_medium'

    container "docker://barbarahelena/osmotool:0.8.0"

    input:
    record(id: String, single_end: Boolean, fastq: List<Path>)
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
    """
    osmotool profile \\
        ${osmo_refdb} \\
        ${reads_args} \\
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
