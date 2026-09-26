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
    local script_dir git_sha started_at finished_at run_id
    local vcf_sha tbi_sha multiqc_sha n_variants

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

    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

    git_sha=$(git -C "$script_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)

    if [[ "$git_sha" != "unknown" ]] &&
       [[ -n "$(git -C "$script_dir" status --porcelain 2>/dev/null)" ]]; then
        git_sha="${git_sha}-dirty"
    fi

    started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    finished_at="$started_at"
    run_id="${started_at}-${git_sha}"

    vcf_sha="sha256:$(shasum -a 256 "$published_vcf" | awk '{print $1}')"
    tbi_sha="sha256:$(shasum -a 256 "$published_tbi" | awk '{print $1}')"
    multiqc_sha="sha256:$(shasum -a 256 "$published_multiqc" | awk '{print $1}')"

    n_variants=$(bcftools view -H "$published_vcf" | wc -l | tr -d ' ')

    PIPELINE_GIT_SHA="$git_sha" \
    PIPELINE_RUN_ID="$run_id" \
    PIPELINE_STARTED_AT="$started_at" \
    PIPELINE_FINISHED_AT="$finished_at" \
    PIPELINE_REF="$REF" \
    PIPELINE_REGION="$REGION" \
    PIPELINE_SHEET="$SHEET" \
    PIPELINE_RESULTS_DIR="$results_dir" \
    PIPELINE_VCF_SHA="$vcf_sha" \
    PIPELINE_TBI_SHA="$tbi_sha" \
    PIPELINE_MULTIQC_SHA="$multiqc_sha" \
    PIPELINE_N_VARIANTS="$n_variants" \
    python3 - <<'PYJSON'
import csv
import json
import os

samples = []

with open(os.environ["PIPELINE_SHEET"], newline="") as handle:
    reader = csv.DictReader(handle)
    for row in reader:
        samples.append({
            "sample_id": row["sample_id"],
            "library_type": row["library_type"],
            "condition": row["condition"],
        })

manifest = {
    "pipeline": {
        "name": "variant-call",
        "version": "1.0.0",
        "implementation": "bash",
        "git_sha": os.environ["PIPELINE_GIT_SHA"],
        "run_id": os.environ["PIPELINE_RUN_ID"],
        "started_at": os.environ["PIPELINE_STARTED_AT"],
        "finished_at": os.environ["PIPELINE_FINISHED_AT"],
        "exit_status": "success",
    },
    "platform": {
        "kind": "laptop",
        "region": os.environ["PIPELINE_REGION"],
    },
    "reference": {
        "genome": os.environ["PIPELINE_REF"],
    },
    "samples": samples,
    "outputs": [
        {
            "stage": "analyze",
            "type": "cohort_vcf",
            "path": "cohort.filtered.vcf.gz",
            "checksum": os.environ["PIPELINE_VCF_SHA"],
        },
        {
            "stage": "analyze",
            "type": "cohort_vcf_index",
            "path": "cohort.filtered.vcf.gz.tbi",
            "checksum": os.environ["PIPELINE_TBI_SHA"],
        },
        {
            "stage": "qc_report",
            "type": "multiqc",
            "path": "multiqc_report.html",
            "checksum": os.environ["PIPELINE_MULTIQC_SHA"],
        },
    ],
    "metrics": [
        {
            "sample_id": None,
            "metric": "n_variants",
            "value": int(os.environ["PIPELINE_N_VARIANTS"]),
            "unit": "count",
            "stage": "analyze",
        }
    ],
}

out = os.path.join(os.environ["PIPELINE_RESULTS_DIR"], "manifest.json")
with open(out, "w") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PYJSON

    if [[ ! -s "$manifest" ]]; then
        die "manifest.json missing or empty"
    fi

    log "Published results:"
    ls -1 "$results_dir" >&2
}
