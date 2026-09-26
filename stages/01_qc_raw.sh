#!/usr/bin/env bash

set -euo pipefail

stage_qc_raw() {
    local id condition replicate library_type r1 r2
    local qc_dir="${OUTDIR}/qc_raw"
    local r1_base r2_base

    log "Running raw-read QC"

    mkdir -p "$qc_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        log "FastQC: $id R1"

        fastqc \
            -q -o "$qc_dir" \
            "$r1"

        r1_base=$(basename "$r1" .fastq.gz)

        if [[ ! -s "${qc_dir}/${r1_base}_fastqc.html" ||
              ! -s "${qc_dir}/${r1_base}_fastqc.zip" ]]; then
            die "$id: FastQC R1 output missing or empty"
        fi

        if [[ "$library_type" == "paired" ]]; then
            log "FastQC: $id R2"

            fastqc \
                -q -o "$qc_dir" \
                "$r2"

            r2_base=$(basename "$r2" .fastq.gz)

            if [[ ! -s "${qc_dir}/${r2_base}_fastqc.html" ||
                  ! -s "${qc_dir}/${r2_base}_fastqc.zip" ]]; then
                die "$id: FastQC R2 output missing or empty"
            fi
        fi

    done < <(tail -n +2 "$SHEET")

    log "Raw-read QC complete"
}
