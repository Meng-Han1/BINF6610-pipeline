#!/usr/bin/env bash

set -euo pipefail

stage_quantify() {
    local id condition replicate library_type r1 r2
    local post_dir="${OUTDIR}/postprocess"
    local gvcf_dir="${OUTDIR}/gvcf"
    local bam gvcf tbi
    local tmp_gvcf tmp_tbi

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

        tmp_gvcf="${gvcf_dir}/${id}.tmp.g.vcf.gz"
        tmp_tbi="${tmp_gvcf}.tbi"

        if [[ -s "$gvcf" && -s "$tbi" ]] &&
           bcftools view -h "$gvcf" >/dev/null 2>&1 &&
           [[ "$(bcftools query -l "$gvcf" 2>/dev/null)" == "$id" ]]; then
            log "HaplotypeCaller: $id already complete; skipping"
            continue
        fi

        rm -f "$gvcf" "$tbi" "$tmp_gvcf" "$tmp_tbi"

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
            -O "$tmp_gvcf" \
            -ERC GVCF \
            -L "$REGION"

        if [[ ! -s "$tmp_gvcf" ]]; then
            die "$id: temporary GVCF missing or empty"
        fi

        if [[ ! -s "$tmp_tbi" ]]; then
            die "$id: temporary GVCF index missing or empty"
        fi

        if ! bcftools view -h "$tmp_gvcf" >/dev/null; then
            die "$id: temporary GVCF is not readable"
        fi

        if [[ "$(bcftools query -l "$tmp_gvcf")" != "$id" ]]; then
            die "$id: temporary GVCF sample name does not match sample_id"
        fi

        mv "$tmp_gvcf" "$gvcf"
        mv "$tmp_tbi" "$tbi"

        if [[ ! -s "$gvcf" || ! -s "$tbi" ]]; then
            die "$id: final GVCF or index missing after publish"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Per-sample GVCF calling complete"
}
