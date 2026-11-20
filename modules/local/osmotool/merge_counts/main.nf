nextflow.enable.types = true

process OSMOTOOL_MERGE_COUNTS {
    tag mode
    label 'process_single'

    container "docker://barbarahelena/osmotool:0.9.1"

    input:
    record(mode: String, counts: List<Path>)   // mode: 'profile' or 'annotate', never mixed

    output:
    record(
        mode: mode,
        matrix: files("${mode}_*.tsv").toSorted { a, b -> a.name <=> b.name }
    )

    topic:
    tuple(task.process, 'pandas', file('pandas_version.txt')) >> 'versions'

    script:
    template 'merge_gene_counts.py'

    stub:
    """
    echo stub > pandas_version.txt
    touch ${mode}_raw_count.tsv
    """
}
