process READCOUNT {
    tag "${meta.id} (${stage})"
    label 'process_single'
    label 'seqkit'

    input:
    tuple val(meta), val(stage), path(reads)

    output:
    path "*.readcount.csv", emit: csv
    path "versions.yml",    emit: versions

    script:
    // Reads (pairs) in the first file; mates have the same number of reads
    """
    n=\$(seqkit stats -T ${reads[0]} | awk 'NR==2 {print \$4}')
    echo "${meta.id},${stage},\$n" > ${meta.id}.${stage}.readcount.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqkit: \$(seqkit version | sed "s/seqkit v//")
    END_VERSIONS
    """

    stub:
    """
    echo "${meta.id},${stage},0" > ${meta.id}.${stage}.readcount.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqkit: stub
    END_VERSIONS
    """
}
