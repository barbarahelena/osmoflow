nextflow.enable.types = true

process OSMOTOOL_DOWNLOAD_DB {
    tag release
    label 'process_low'

    container "docker://barbarahelena/osmotool:0.10.0"

    input:
    release: String   // osmo_refdb release, or 'latest'

    output:
    file('refdb/*')   // the unpacked release directory, e.g. refdb/v9

    topic:
    tuple(task.process, 'osmotool', eval('osmotool --version 2>&1 | sed "s/^osmotool //"')) >> 'versions'

    script:
    def args = task.ext.args ?: ''
    """
    mkdir -p refdb
    osmotool download-db \\
        --release ${release} \\
        --location refdb \\
        ${args}
    """

    stub:
    """
    mkdir -p refdb/${release}
    touch refdb/${release}/osmo_refdb.dmnd
    """
}
