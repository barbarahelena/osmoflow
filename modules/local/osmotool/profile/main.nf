process OSMOTOOL_PROFILE {
    tag "$meta.id"
    label 'process_medium'

    container "barbarahelena/osmotool:latest"

    input:
    tuple val(meta), path(reads)
    path osmo_refdb

    output:
    tuple val(meta), path("*.gene_counts.tsv"), emit: counts
    tuple val(meta), path("*.aln_stats.tsv"),   emit: stats
    path "versions.yml",                        emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def reads_args = meta.single_end ? "--singles ${reads[0]}" : "-1 ${reads[0]} -2 ${reads[1]}"
    """
    osmotool profile \\
        ${osmo_refdb} \\
        ${reads_args} \\
        --out_prefix ${prefix} \\
        --threads ${task.cpus} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        osmotool: \$(osmotool --version 2>&1)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.gene_counts.tsv
    touch ${prefix}.aln_stats.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        osmotool: stub
    END_VERSIONS
    """
}
