process OSMOTOOL_MERGE_GENE_COORDINATES {
    tag "gene_coordinates"
    label 'process_single'

    container "docker://barbarahelena/osmotool:0.6.0"

    input:
    path coordinates

    output:
    path "merged_gene_coordinates.tsv", emit: tsv
    path "versions.yml",                emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    template 'merge_gene_coordinates.py'

    stub:
    """
    touch merged_gene_coordinates.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: stub
    END_VERSIONS
    """
}
