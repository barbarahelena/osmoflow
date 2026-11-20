nextflow.enable.types = true

process OSMOTOOL_MERGE_SYSTEMS {
    tag 'systems'
    label 'process_single'

    container "docker://barbarahelena/osmotool:0.9.1"

    input:
    systems: List<Path>   // *.systems.tsv, one per bin

    output:
    file('merged_systems.tsv')

    topic:
    tuple(task.process, 'python', file('python_version.txt')) >> 'versions'

    script:
    template 'merge_systems_tsv.py'

    stub:
    """
    echo stub > python_version.txt
    touch merged_systems.tsv
    """
}
