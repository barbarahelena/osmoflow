nextflow.enable.types = true

process OSMOTOOL_MERGE_UNITS {
    tag mode
    label 'process_single'

    container "docker://barbarahelena/osmotool:0.11.1"

    input:
    record(mode: String, units: List<Path>)   // mode: 'profile' or 'annotate', never mixed; *.unit_counts.tsv, one per sample

    output:
    record(
        mode: mode,
        matrix: files("${mode}_unit_*.tsv").toSorted { a, b -> a.name <=> b.name },   // raw_count and RPM / copies_per_kb
        sources: file('profile_read_sources.tsv', optional: true)                     // profile only
    )

    topic:
    tuple(task.process, 'pandas', file('pandas_version.txt')) >> 'versions'

    script:
    template 'merge_unit_counts.py'

    stub:
    def value  = mode == 'profile' ? 'rpm' : 'copies_per_kb'
    def extras = mode == 'profile' ? 'profile_read_sources.tsv' : ''
    """
    echo stub > pandas_version.txt
    touch ${mode}_unit_raw_count.tsv ${mode}_unit_${value}.tsv ${extras}
    """
}
