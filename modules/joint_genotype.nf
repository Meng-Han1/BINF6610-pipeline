process JOINT_GENOTYPE {
    container params.containers.gatk

    input:
    path gvcfs
    path tbis
    path ref
    path ref_fai
    path ref_dict

    output:
    tuple path('cohort.vcf.gz'),
          path('cohort.vcf.gz.tbi'),
          emit: vcf

    script:
    def variants = gvcfs.collect { "-V ${it}" }.join(' ')

    """
    gatk GenomicsDBImport \
        ${variants} \
        --genomicsdb-workspace-path genomicsdb \
        -L '${params.region}'

    gatk GenotypeGVCFs \
        -R ${ref} \
        -V gendb://genomicsdb \
        -O cohort.vcf.gz \
        -L '${params.region}'
    """
}
