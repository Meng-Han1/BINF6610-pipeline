process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta),
          path("${meta.id}.markdup.bam"),
          path("${meta.id}.markdup.bam.bai"),
          emit: bam

    path "${meta.id}.dup_metrics.txt", emit: metrics

    script:
    """
    gatk MarkDuplicates \
        -I ${bam} \
        -O ${meta.id}.markdup.bam \
        -M ${meta.id}.dup_metrics.txt

    samtools index -@ ${task.cpus} ${meta.id}.markdup.bam
    samtools quickcheck ${meta.id}.markdup.bam
    """
}
