#!/usr/bin/env bash

set -euo pipefail

stage_postprocess() {
    local id condition replicate library_type r1 r2
    local align_dir="${OUTDIR}/align"
    local post_dir="${OUTDIR}/postprocess"
    local input_bam output_bam metrics bai
    local tmp_bam tmp_metrics tmp_bai

    log "Postprocessing alignments"

    mkdir -p "$post_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        input_bam="${align_dir}/${id}.bam"

        output_bam="${post_dir}/${id}.markdup.bam"
        metrics="${post_dir}/${id}.dup_metrics.txt"
        bai="${output_bam}.bai"

        tmp_bam="${post_dir}/${id}.tmp.markdup.bam"
        tmp_metrics="${post_dir}/${id}.tmp.dup_metrics.txt"
        tmp_bai="${tmp_bam}.bai"

        if [[ -s "$output_bam" &&
              -s "$bai" &&
              -s "$metrics" ]] &&
           samtools quickcheck "$output_bam" 2>/dev/null; then
            log "MarkDuplicates: $id already complete; skipping"
            continue
        fi

        rm -f \
            "$output_bam" \
            "$bai" \
            "$metrics" \
            "$tmp_bam" \
            "$tmp_bai" \
            "$tmp_metrics"

        if [[ ! -s "$input_bam" ]]; then
            die "$id: input BAM missing or empty: $input_bam"
        fi

        if ! samtools quickcheck "$input_bam"; then
            die "$id: input BAM failed samtools quickcheck"
        fi

        log "MarkDuplicates: $id"

        gatk MarkDuplicates \
            -I "$input_bam" \
            -O "$tmp_bam" \
            -M "$tmp_metrics"

        if [[ ! -s "$tmp_bam" ]]; then
            die "$id: temporary duplicate-marked BAM missing or empty"
        fi

        if [[ ! -s "$tmp_metrics" ]]; then
            die "$id: temporary duplicate metrics missing or empty"
        fi

        if ! samtools quickcheck "$tmp_bam"; then
            die "$id: temporary duplicate-marked BAM failed samtools quickcheck"
        fi

        log "Indexing BAM: $id"

        samtools index -@ "$THREADS" "$tmp_bam"

        if [[ ! -s "$tmp_bai" ]]; then
            die "$id: temporary BAM index missing or empty"
        fi

        mv "$tmp_bam" "$output_bam"
        mv "$tmp_bai" "$bai"
        mv "$tmp_metrics" "$metrics"

        if [[ ! -s "$output_bam" ||
              ! -s "$bai" ||
              ! -s "$metrics" ]] ||
           ! samtools quickcheck "$output_bam"; then
            die "$id: final postprocessing outputs missing, empty, or corrupt"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Postprocessing complete"
}
