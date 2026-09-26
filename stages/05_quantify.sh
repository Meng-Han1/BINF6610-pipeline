#!/usr/bin/env bash

set -euo pipefail

stage_quantify() {
    local id condition replicate library_type r1 r2
    local post_dir="${OUTDIR}/postprocess"
    local gvcf_dir="${OUTDIR}/gvcf"
    local bam gvcf tbi

    log "Calling per-sample GVCFs"

    if [[ -z "$REF" ]]; then
        die "REF is not set"
    fi

    if [[ -z "$REGION" ]]; then
        die "REGION is not set"
    fi

    mkdir -p "$gvcf_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        bam="${post_dir}/${id}.markdup.bam"
        gvcf="${gvcf_dir}/${id}.g.vcf.gz"
        tbi="${gvcf}.tbi"

        log "HaplotypeCaller: $id"

        if [[ ! -s "$bam" ]]; then
            die "$id: postprocessed BAM missing or empty: $bam"
        fi

        if [[ ! -s "${bam}.bai" ]]; then
            die "$id: BAM index missing or empty: ${bam}.bai"
        fi

        gatk HaplotypeCaller \
            -R "$REF" \
            -I "$bam" \
            -O "$gvcf" \
            -ERC GVCF \
            -L "$REGION"

        if [[ ! -s "$gvcf" ]]; then
            die "$id: GVCF missing or empty"
        fi

        if [[ ! -s "$tbi" ]]; then
            die "$id: GVCF index missing or empty"
        fi

        if ! bcftools view -h "$gvcf" >/dev/null; then
            die "$id: GVCF is not readable"
        fi

        if [[ "$(bcftools query -l "$gvcf")" != "$id" ]]; then
            die "$id: GVCF sample name does not match sample_id"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Per-sample GVCF calling complete"
}
