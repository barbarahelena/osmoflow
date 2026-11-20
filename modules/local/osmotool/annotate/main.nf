nextflow.enable.types = true

process OSMOTOOL_ANNOTATE {
    tag id
    label 'process_medium'

    container "docker://barbarahelena/osmotool:0.9.1"

    input:
    record(id: String, fasta: Path)
    osmo_refdb: Path

    output:
    record(
        id: id,
        counts: file('*.gene_counts.tsv'),
        stats: file('*.aln_stats.tsv'),
        systems: file('*.systems.tsv', optional: true),
        coordinates: file('*.gene_coordinates.tsv', optional: true)
    )

    topic:
    tuple(task.process, 'osmotool', eval('osmotool --version 2>&1 | sed "s/^osmotool //"')) >> 'versions'

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: id
    """
    osmotool annotate \\
        ${osmo_refdb} \\
        ${fasta} \\
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
