process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref
    path ref_index

    output:
    tuple val(meta), path("${meta.id}.bam"), emit: bam

    script:
    """
    bwa mem \
        -t ${task.cpus} \
        -R '@RG\\tID:${meta.id}\\tSM:${meta.id}\\tPL:ILLUMINA' \
        ${ref} \
        ${reads} \
    | samtools sort \
        -@ ${task.cpus} \
        -T ${meta.id}.sort \
        -o ${meta.id}.bam

    samtools quickcheck ${meta.id}.bam
    """
}
