#!/usr/bin/env bash

set -euo pipefail

stage_qc_report() {
    local report_dir="${OUTDIR}/qc_report"
    local report="${report_dir}/multiqc_report.html"

    log "Building cohort QC report"

    mkdir -p "$report_dir"

    multiqc \
        -q \
        -f \
        -o "$report_dir" \
        "$OUTDIR"

    if [[ ! -s "$report" ]]; then
        die "MultiQC produced no report"
    fi

    log "QC report written"
}
