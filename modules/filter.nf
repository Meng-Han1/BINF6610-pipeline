process FILTER {
    container params.containers.gatk

    input:
    tuple path(vcf), path(tbi)
    path ref
    path ref_fai
    path ref_dict

    output:
    path 'cohort.filtered.vcf.gz', emit: vcf
    path 'cohort.filtered.vcf.gz.tbi', emit: tbi
    path 'variants.tsv', emit: table

    script:
    """
    before_count=\$(bcftools view -H ${vcf} | wc -l | tr -d ' ')

    gatk VariantFiltration \
        -R ${ref} \
        -V ${vcf} \
        -O cohort.filtered.vcf.gz \
        --filter-expression "QD < 2.0" \
        --filter-name "QD2" \
        --filter-expression "QUAL < 30.0" \
        --filter-name "QUAL30"

    after_count=\$(bcftools view -H cohort.filtered.vcf.gz | wc -l | tr -d ' ')

    if [[ "\$before_count" != "\$after_count" ]]; then
        echo "VariantFiltration changed the number of VCF records: \$before_count -> \$after_count" >&2
        exit 1
    fi

    printf 'chrom\\tpos\\tref\\talt\\tqual\\tfilter\\n' > variants.tsv

    bcftools query \
        -f '%CHROM\\t%POS\\t%REF\\t%ALT\\t%QUAL\\t%FILTER\\n' \
        cohort.filtered.vcf.gz \
        >> variants.tsv
    """
}
