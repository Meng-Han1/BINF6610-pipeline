#!/usr/bin/env bash

set -euo pipefail

stage_trim() {
    local id condition replicate library_type r1 r2
    local trim_dir="${OUTDIR}/trim"
    local out_r1 out_r2
    local html json

    log "Trimming reads"

    mkdir -p "$trim_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        out_r1="${trim_dir}/${id}_R1.trim.fastq.gz"
        html="${trim_dir}/${id}.fastp.html"
        json="${trim_dir}/${id}.fastp.json"

        if [[ "$library_type" == "paired" ]]; then
            out_r2="${trim_dir}/${id}_R2.trim.fastq.gz"

            log "fastp: $id paired-end"

            fastp \
                -i "$r1" \
                -I "$r2" \
                -o "$out_r1" \
                -O "$out_r2" \
                --html "$html" \
                --json "$json"

            if [[ ! -s "$out_r1" || ! -s "$out_r2" ||
                  ! -s "$html" || ! -s "$json" ]]; then
                die "$id: fastp paired-end output missing or empty"
            fi

            if ! gzip -t "$out_r1" 2>/dev/null ||
               ! gzip -t "$out_r2" 2>/dev/null; then
                die "$id: fastp produced an invalid gzip FASTQ"
            fi

        elif [[ "$library_type" == "single" ]]; then
            log "fastp: $id single-end"

            fastp \
                -i "$r1" \
                -o "$out_r1" \
                --html "$html" \
                --json "$json"

            if [[ ! -s "$out_r1" ||
                  ! -s "$html" || ! -s "$json" ]]; then
                die "$id: fastp single-end output missing or empty"
            fi

            if ! gzip -t "$out_r1" 2>/dev/null; then
                die "$id: fastp produced an invalid gzip FASTQ"
            fi

        else
            die "$id: unsupported library_type: $library_type"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Read trimming complete"
}
