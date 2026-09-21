#!/usr/bin/env bash
set -euo pipefail

# BINF6610 Week 1
# Germline variant-calling pipeline

SHEET=${1:-}
OUTDIR=${2:-}
LAST=${3:-publish}

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

    # The samplesheet must exist and must not be empty.
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

        # If a paired-end sample has an R2 path, validate it.
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

        # Paired-end samples must contain the same number of reads in R1 and R2.
        if [[ "$library_type" == "paired" &&
              "$r1_reads" -gt 0 &&
              "$r2_reads" -gt 0 &&
              "$r1_reads" -ne "$r2_reads" ]]; then
            log "ERROR: $id: R1 and R2 read counts differ: $r1_reads vs $r2_reads"
            errors=$(( errors + 1 ))
        fi

    done < <(tail -n +2 "$SHEET")

    # Report failure only after every sample has been checked.
    if (( errors > 0 )); then
        log "Validation failed: $errors problem(s)"
        exit 65
    fi

    log "Validation passed"
}

if [[ -z "$SHEET" || -z "$OUTDIR" ]]; then
    die "usage: $0 <samplesheet.csv> <outdir> [last-stage]"
fi

if [[ "$LAST" == "validate" ]]; then
    stage_validate
else
    die "only validate is implemented so far"
fi
