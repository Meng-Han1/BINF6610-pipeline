#!/usr/bin/env bash
set -euo pipefail

# BINF6610 Week 1
# Germline variant-calling pipeline

SHEET=${1:-}
OUTDIR=${2:-}
LAST=${3:-publish}

REF=${REF:-}
REGION=${REGION:-}

log() {
    echo "$*" >&2
}

die() {
    echo "ERROR: $*" >&2
    exit 65
}

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

stage_validate() {
    local errors=0
    local id condition replicate library_type r1 r2
    local duplicate
    local r1_lines r2_lines
    local r1_reads r2_reads

    log "Validating inputs"

    if [[ ! -s "$SHEET" ]]; then
        log "ERROR: samplesheet missing or empty: $SHEET"
        exit 65
    fi

    # Check for duplicate sample IDs.
    while read -r duplicate; do
        [[ -z "$duplicate" ]] && continue
        log "ERROR: duplicate sample_id: $duplicate"
        errors=$(( errors + 1 ))
    done < <(awk -F, 'NR>1 { print $1 }' "$SHEET" | sort | uniq -d)

    # Validate every sample in the samplesheet.
    while IFS=, read -r id condition replicate library_type r1 r2; do
        r1_lines=0
        r2_lines=0
        r1_reads=0
        r2_reads=0

        # R1 is required for every sample.
        if [[ ! -s "$r1" ]]; then
            log "ERROR: $id: R1 missing or empty: $r1"
            errors=$(( errors + 1 ))
        elif ! gzip -t "$r1" 2>/dev/null; then
            log "ERROR: $id: R1 is not a valid gzip file: $r1"
            errors=$(( errors + 1 ))
        else
            r1_lines=$(gzip -dc "$r1" | wc -l)

            if (( r1_lines % 4 != 0 )); then
                log "ERROR: $id: R1 line count is not divisible by 4: $r1_lines"
                errors=$(( errors + 1 ))
            else
                r1_reads=$(( r1_lines / 4 ))
            fi
        fi

        # Paired-end samples must have an R2 path.
        if [[ "$library_type" == "paired" && -z "$r2" ]]; then
            log "ERROR: $id: paired library has no R2"
            errors=$(( errors + 1 ))
        fi

        # Validate R2 for paired-end samples.
        if [[ "$library_type" == "paired" && -n "$r2" ]]; then
            if [[ ! -s "$r2" ]]; then
                log "ERROR: $id: R2 missing or empty: $r2"
                errors=$(( errors + 1 ))
            elif ! gzip -t "$r2" 2>/dev/null; then
                log "ERROR: $id: R2 is not a valid gzip file: $r2"
                errors=$(( errors + 1 ))
            else
                r2_lines=$(gzip -dc "$r2" | wc -l)

                if (( r2_lines % 4 != 0 )); then
                    log "ERROR: $id: R2 line count is not divisible by 4: $r2_lines"
                    errors=$(( errors + 1 ))
                else
                    r2_reads=$(( r2_lines / 4 ))
                fi
            fi
        fi

        # Paired-end samples must have matching read counts.
        if [[ "$library_type" == "paired" &&
              "$r1_reads" -gt 0 &&
              "$r2_reads" -gt 0 &&
              "$r1_reads" -ne "$r2_reads" ]]; then
            log "ERROR: $id: R1 and R2 read counts differ: $r1_reads vs $r2_reads"
            errors=$(( errors + 1 ))
        fi

    done < <(tail -n +2 "$SHEET")

    if (( errors > 0 )); then
        log "Validation failed: $errors problem(s)"
        exit 65
    fi

    log "Validation passed"
}

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

if [[ -z "$SHEET" || -z "$OUTDIR" ]]; then
    die "usage: $0 <samplesheet.csv> <outdir> [last-stage]"
fi

stage_validate

if [[ "$LAST" == "validate" ]]; then
    exit 0
fi

stage_qc_raw

if [[ "$LAST" == "qc_raw" ]]; then
    exit 0
fi

stage_trim

if [[ "$LAST" == "trim" ]]; then
    exit 0
fi

stage_align

if [[ "$LAST" == "align" ]]; then
    exit 0
fi

die "stages after align are not implemented yet"
