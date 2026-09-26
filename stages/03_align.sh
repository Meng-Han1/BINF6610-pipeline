#!/usr/bin/env bash

set -euo pipefail

stage_align() {
    local id condition replicate library_type r1 r2
    local trim_dir="${OUTDIR}/trim"
    local align_dir="${OUTDIR}/align"
    local trim_r1 trim_r2 bam tmp_bam rg

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
        tmp_bam="${align_dir}/${id}.tmp.bam"

        rg="@RG\tID:${id}\tSM:${id}\tPL:ILLUMINA"

        if [[ -s "$bam" ]] && samtools quickcheck "$bam" 2>/dev/null; then
            log "BWA-MEM: $id already complete; skipping"
            continue
        fi

        rm -f "$bam" "$tmp_bam"

        if [[ ! -s "$trim_r1" ]]; then
            die "$id: trimmed R1 missing or empty: $trim_r1"
        fi

        if [[ "$library_type" == "paired" ]]; then
            if [[ ! -s "$trim_r2" ]]; then
                die "$id: trimmed R2 missing or empty: $trim_r2"
            fi

            log "BWA-MEM: $id paired-end"

            bwa mem \
                -t "$THREADS" \
                -R "$rg" \
                "$REF" \
                "$trim_r1" \
                "$trim_r2" \
            | samtools sort \
                -@ "$THREADS" \
                -T "${TMPDIR}/${id}.sort" \
                -o "$tmp_bam"

        elif [[ "$library_type" == "single" ]]; then
            log "BWA-MEM: $id single-end"

            bwa mem \
                -t "$THREADS" \
                -R "$rg" \
                "$REF" \
                "$trim_r1" \
            | samtools sort \
                -@ "$THREADS" \
                -T "${TMPDIR}/${id}.sort" \
                -o "$tmp_bam"

        else
            die "$id: unsupported library_type: $library_type"
        fi

        if [[ ! -s "$tmp_bam" ]]; then
            die "$id: temporary alignment BAM missing or empty"
        fi

        if ! samtools quickcheck "$tmp_bam"; then
            die "$id: temporary alignment BAM failed samtools quickcheck"
        fi

        mv "$tmp_bam" "$bam"

        if [[ ! -s "$bam" ]] || ! samtools quickcheck "$bam"; then
            die "$id: final alignment BAM missing, empty, or corrupt"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Alignment complete"
}
