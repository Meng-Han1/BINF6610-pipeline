#!/usr/bin/env bash

set -euo pipefail

stage_postprocess() {
    local id condition replicate library_type r1 r2
    local align_dir="${OUTDIR}/align"
    local post_dir="${OUTDIR}/postprocess"
    local input_bam output_bam metrics bai

    log "Postprocessing alignments"

    mkdir -p "$post_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        input_bam="${align_dir}/${id}.bam"
        output_bam="${post_dir}/${id}.markdup.bam"
        metrics="${post_dir}/${id}.dup_metrics.txt"
        bai="${output_bam}.bai"

        log "MarkDuplicates: $id"

        if [[ ! -s "$input_bam" ]]; then
            die "$id: input BAM missing or empty: $input_bam"
        fi

        gatk MarkDuplicates \
            -I "$input_bam" \
            -O "$output_bam" \
            -M "$metrics"

        if [[ ! -s "$output_bam" ]]; then
            die "$id: duplicate-marked BAM missing or empty"
        fi

        if [[ ! -s "$metrics" ]]; then
            die "$id: duplicate metrics missing or empty"
        fi

        if ! samtools quickcheck "$output_bam"; then
            die "$id: duplicate-marked BAM failed samtools quickcheck"
        fi

        log "Indexing BAM: $id"

        samtools index -@ "$THREADS" "$output_bam"

        if [[ ! -s "$bai" ]]; then
            die "$id: BAM index missing or empty"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Postprocessing complete"
}
