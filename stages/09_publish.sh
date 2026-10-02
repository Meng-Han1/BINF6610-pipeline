#!/usr/bin/env bash

set -euo pipefail

stage_publish() {
    local results_dir="${OUTDIR}/results"
    local filtered_vcf="${OUTDIR}/analyze/cohort.filtered.vcf.gz"
    local filtered_tbi="${filtered_vcf}.tbi"
    local multiqc_report="${OUTDIR}/qc_report/multiqc_report.html"
    local published_vcf="${results_dir}/cohort.filtered.vcf.gz"
    local published_tbi="${published_vcf}.tbi"
    local published_multiqc="${results_dir}/multiqc_report.html"
    local manifest="${results_dir}/manifest.json"

    log "Publishing final results"

    if [[ ! -s "$filtered_vcf" ]]; then
        die "filtered cohort VCF missing or empty: $filtered_vcf"
    fi

    if [[ ! -s "$filtered_tbi" ]]; then
        die "filtered cohort VCF index missing or empty: $filtered_tbi"
    fi

    if [[ ! -s "$multiqc_report" ]]; then
        die "MultiQC report missing or empty: $multiqc_report"
    fi

    mkdir -p "$results_dir"

    cp "$filtered_vcf" "$published_vcf"
    cp "$filtered_tbi" "$published_tbi"
    cp "$multiqc_report" "$published_multiqc"

    bash "${HERE}/lib/write_manifest.sh" \
        "${results_dir}" \
        "${SHEET}" \
        "${REF}" \
        "${REGION}"

    if [[ ! -s "$manifest" ]]; then
        die "manifest.json missing or empty"
    fi

    log "Published results:"
    ls -1 "$results_dir" >&2
}
