process OSMOTOOL_MERGE_SYSTEMS {
    tag "systems"
    label 'process_single'

    container "docker://barbarahelena/osmotool:0.5.0"

    input:
    path systems

    output:
    path "merged_systems.tsv", emit: tsv
    path "versions.yml",       emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    template 'merge_systems_tsv.py'

    stub:
    """
    touch merged_systems.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: stub
    END_VERSIONS
    """
}
