#!/usr/bin/env bash

set -euo pipefail

stage_align() {
    local id condition replicate library_type r1 r2
    local trim_dir="${OUTDIR}/trim"
    local align_dir="${OUTDIR}/align"
    local trim_r1 trim_r2 bam rg

    log "Aligning reads"

    if [[ -z "$REF" ]]; then
        die "REF is not set"
    fi

    if [[ ! -s "$REF" ]]; then
        die "reference missing or empty: $REF"
    fi

    mkdir -p "$align_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        trim_r1="${trim_dir}/${id}_R1.trim.fastq.gz"
        trim_r2="${trim_dir}/${id}_R2.trim.fastq.gz"
        bam="${align_dir}/${id}.bam"
        rg="@RG\tID:${id}\tSM:${id}\tPL:ILLUMINA"

        if [[ "$library_type" == "paired" ]]; then
            log "BWA-MEM: $id paired-end"

            bwa mem \
                -R "$rg" \
                "$REF" \
                "$trim_r1" \
                "$trim_r2" \
            | samtools sort \
                -o "$bam"

        elif [[ "$library_type" == "single" ]]; then
            log "BWA-MEM: $id single-end"

            bwa mem \
                -R "$rg" \
                "$REF" \
                "$trim_r1" \
            | samtools sort \
                -o "$bam"

        else
            die "$id: unsupported library_type: $library_type"
        fi

        if [[ ! -s "$bam" ]]; then
            die "$id: alignment BAM missing or empty"
        fi

        if ! samtools quickcheck "$bam"; then
            die "$id: alignment BAM failed samtools quickcheck"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Alignment complete"
}
