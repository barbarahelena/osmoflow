process BOWTIE2_BUILD {
    tag "$fasta.name"
    label 'process_high'
    label 'bowtie2'
    storeDir 'db'

    input:
    path fasta

    output:
    path "bowtie2", emit: index

    script:
    def args = task.ext.args ?: ''
    """
    mkdir bowtie2
    bowtie2-build ${args} --threads ${task.cpus} ${fasta} bowtie2/${fasta.baseName}
    """

    stub:
    """
    mkdir bowtie2
    touch bowtie2/${fasta.baseName}.{1..4}.bt2 bowtie2/${fasta.baseName}.rev.{1,2}.bt2
    """
}
