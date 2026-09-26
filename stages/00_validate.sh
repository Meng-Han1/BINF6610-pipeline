#!/usr/bin/env bash

set -euo pipefail

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
