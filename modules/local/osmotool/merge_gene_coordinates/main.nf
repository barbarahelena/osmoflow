nextflow.enable.types = true

process OSMOTOOL_MERGE_GENE_COORDINATES {
    tag 'gene_coordinates'
    label 'process_single'

    container "docker://barbarahelena/osmotool:0.11.1"

    input:
    coordinates: List<Path>   // *.gene_coordinates.tsv, one per genome/bin

    output:
    file('merged_gene_coordinates.tsv')

    topic:
    tuple(task.process, 'python', file('python_version.txt')) >> 'versions'

    script:
    template 'merge_gene_coordinates.py'

    stub:
    """
    echo stub > python_version.txt
    touch merged_gene_coordinates.tsv
    """
}
