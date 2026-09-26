#!/usr/bin/env bash

set -euo pipefail

stage_merge() {
    local gvcf_dir="${OUTDIR}/gvcf"
    local merge_dir="${OUTDIR}/merge"
    local workspace="${merge_dir}/genomicsdb"
    local cohort_vcf="${merge_dir}/cohort.vcf.gz"
    local cohort_tbi="${cohort_vcf}.tbi"
    local id condition replicate library_type r1 r2
    local gvcf
    local -a variant_args=()
    local -a expected_samples=()
    local -a observed_samples=()

    log "Joint genotyping cohort"

    if [[ -z "$REF" ]]; then
        die "REF is not set"
    fi

    if [[ -z "$REGION" ]]; then
        die "REGION is not set"
    fi

    mkdir -p "$merge_dir"
    rm -rf "$workspace"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        gvcf="${gvcf_dir}/${id}.g.vcf.gz"

        if [[ ! -s "$gvcf" ]]; then
            die "$id: GVCF missing or empty: $gvcf"
        fi

        if [[ ! -s "${gvcf}.tbi" ]]; then
            die "$id: GVCF index missing or empty: ${gvcf}.tbi"
        fi

        variant_args+=( -V "$gvcf" )
        expected_samples+=( "$id" )
    done < <(tail -n +2 "$SHEET")

    if (( ${#variant_args[@]} == 0 )); then
        die "no GVCFs found for joint genotyping"
    fi

    log "GenomicsDBImport: ${#expected_samples[@]} samples"

    gatk GenomicsDBImport \
        "${variant_args[@]}" \
        --genomicsdb-workspace-path "$workspace" \
        -L "$REGION"

    if [[ ! -d "$workspace" ]]; then
        die "GenomicsDB workspace was not created"
    fi

    if [[ ! -s "${workspace}/callset.json" ||
          ! -s "${workspace}/vidmap.json" ||
          ! -s "${workspace}/vcfheader.vcf" ]]; then
        die "GenomicsDB workspace is incomplete"
    fi

    log "GenotypeGVCFs"

    gatk GenotypeGVCFs \
        -R "$REF" \
        -V "gendb://${workspace}" \
        -O "$cohort_vcf" \
        -L "$REGION"

    if [[ ! -s "$cohort_vcf" ]]; then
        die "cohort VCF missing or empty"
    fi

    if [[ ! -s "$cohort_tbi" ]]; then
        die "cohort VCF index missing or empty"
    fi

    if ! bcftools view -h "$cohort_vcf" >/dev/null; then
        die "cohort VCF is not readable"
    fi

    mapfile -t observed_samples < <(bcftools query -l "$cohort_vcf")

    if (( ${#observed_samples[@]} != ${#expected_samples[@]} )); then
        die "cohort VCF sample count does not match samplesheet"
    fi

    for id in "${expected_samples[@]}"; do
        if ! printf '%s\n' "${observed_samples[@]}" | grep -Fxq "$id"; then
            die "$id: missing from cohort VCF"
        fi
    done

    log "Joint genotyping complete"
}
