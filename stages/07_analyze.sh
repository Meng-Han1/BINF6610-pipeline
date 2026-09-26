#!/usr/bin/env bash

set -euo pipefail

stage_analyze() {
    local merge_dir="${OUTDIR}/merge"
    local analyze_dir="${OUTDIR}/analyze"
    local input_vcf="${merge_dir}/cohort.vcf.gz"
    local output_vcf="${analyze_dir}/cohort.filtered.vcf.gz"
    local output_tbi="${output_vcf}.tbi"
    local before_count after_count

    log "Hard-filtering cohort variants"

    if [[ -z "$REF" ]]; then
        die "REF is not set"
    fi

    if [[ ! -s "$input_vcf" ]]; then
        die "cohort VCF missing or empty: $input_vcf"
    fi

    if [[ ! -s "${input_vcf}.tbi" ]]; then
        die "cohort VCF index missing or empty: ${input_vcf}.tbi"
    fi

    mkdir -p "$analyze_dir"

    before_count=$(bcftools view -H "$input_vcf" | wc -l | tr -d ' ')

    gatk VariantFiltration \
        -R "$REF" \
        -V "$input_vcf" \
        -O "$output_vcf" \
        --filter-expression "QD < 2.0" \
        --filter-name "QD2" \
        --filter-expression "QUAL < 30.0" \
        --filter-name "QUAL30"

    if [[ ! -s "$output_vcf" ]]; then
        die "filtered cohort VCF missing or empty"
    fi

    if [[ ! -s "$output_tbi" ]]; then
        die "filtered cohort VCF index missing or empty"
    fi

    if ! bcftools view -h "$output_vcf" >/dev/null; then
        die "filtered cohort VCF is not readable"
    fi

    after_count=$(bcftools view -H "$output_vcf" | wc -l | tr -d ' ')

    if [[ "$before_count" != "$after_count" ]]; then
        die "VariantFiltration changed the number of VCF records: ${before_count} -> ${after_count}"
    fi

    log "Variant filtering complete"
}
