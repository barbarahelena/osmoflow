nextflow.enable.types = true

process OSMOTOOL_MERGE_UNITS {
    tag 'profile'
    label 'process_single'

    container "docker://barbarahelena/osmotool:0.11.1"

    input:
    units: List<Path>   // *.unit_counts.tsv, one per profiled sample

    output:
    record(
        raw_count: file('profile_unit_raw_count.tsv'),
        rpm: file('profile_unit_rpm.tsv'),
        sources: file('profile_read_sources.tsv')
    )

    topic:
    tuple(task.process, 'pandas', file('pandas_version.txt')) >> 'versions'

    script:
    template 'merge_unit_counts.py'

    stub:
    """
    echo stub > pandas_version.txt
    touch profile_unit_raw_count.tsv profile_unit_rpm.tsv profile_read_sources.tsv
    """
}
