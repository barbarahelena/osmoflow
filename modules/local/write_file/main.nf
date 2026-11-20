nextflow.enable.types = true

//
// Write text to a file. Used for the small text files of the run (software versions, read counts table),
// instead of collectFile, which has no well-defined type. The content goes into one single-quoted shell
// string (its own single quotes escaped), so it is written exactly as given; printf is a shell builtin,
// so no container is needed.
//
process WRITE_FILE {
    tag name
    label 'process_single'

    input:
    name: String
    content: String

    output:
    file(name)

    script:
    def quoted = "'" + content.replace("'", "'\\''") + "'"
    """
    printf '%s' ${quoted} > ${name}
    """

    stub:
    """
    touch ${name}
    """
}
