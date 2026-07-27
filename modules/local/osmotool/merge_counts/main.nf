process OSMOTOOL_MERGE_COUNTS {
    tag "$mode"
    label 'process_single'

    container "docker://barbarahelena/osmotool:0.4.0"

    input:
    tuple val(mode), path(counts)

    output:
    tuple val(mode), path("${mode}_gene_counts.tsv"), emit: matrix
    path "versions.yml",                              emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    template 'merge_gene_counts.py'

    stub:
    """
    touch ${mode}_gene_counts.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pandas: stub
    END_VERSIONS
    """
}
