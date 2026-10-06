#!/usr/bin/env bash

set -euo pipefail

SHEET=${1:?usage: validate_samplesheet.sh <samplesheet> <reference_name>}
REF_NAME=${2:?usage: validate_samplesheet.sh <samplesheet> <reference_name>}

errors=0

# The staged reference and its required indexes must all be present.
for f in \
    "${REF_NAME}" \
    "${REF_NAME}.fai" \
    "${REF_NAME}.amb" \
    "${REF_NAME}.ann" \
    "${REF_NAME}.bwt" \
    "${REF_NAME}.pac" \
    "${REF_NAME}.sa"
do
    if [[ ! -s "$f" ]]; then
        printf 'ERROR: reference file missing or empty: %s\n' "$f" >&2
        errors=$(( errors + 1 ))
    fi
done

# The sequence dictionary is ref.fa -> ref.dict, not ref.fa.dict.
REF_DICT="${REF_NAME%.*}.dict"

if [[ ! -s "$REF_DICT" ]]; then
    printf 'ERROR: reference dictionary missing or empty: %s\n' "$REF_DICT" >&2
    errors=$(( errors + 1 ))
fi

# Duplicate sample IDs.
while read -r duplicate; do
    [[ -z "$duplicate" ]] && continue
    printf 'ERROR: duplicate sample_id: %s\n' "$duplicate" >&2
    errors=$(( errors + 1 ))
done < <(awk -F, 'NR > 1 { print $1 }' "$SHEET" | sort | uniq -d)

while IFS=$'\t' read -r id library_type r1 r2; do
    r1=$(basename "$r1")
    r2=$(basename "$r2")

    r1_lines=0
    r2_lines=0
    r1_reads=0
    r2_reads=0

    if [[ ! -s "$r1" ]]; then
        printf 'ERROR: %s: R1 missing or empty: %s\n' "$id" "$r1" >&2
        errors=$(( errors + 1 ))
    elif ! gzip -t "$r1" 2>/dev/null; then
        printf 'ERROR: %s: R1 is not a valid gzip file: %s\n' "$id" "$r1" >&2
        errors=$(( errors + 1 ))
    else
        r1_lines=$(gzip -dc "$r1" | wc -l)
        if (( r1_lines % 4 != 0 )); then
            printf 'ERROR: %s: R1 line count is not divisible by 4: %s\n' \
                "$id" "$r1_lines" >&2
            errors=$(( errors + 1 ))
        else
            r1_reads=$(( r1_lines / 4 ))
        fi
    fi

    if [[ "$library_type" == "paired" && -z "$r2" ]]; then
        printf 'ERROR: %s: paired library has no R2\n' "$id" >&2
        errors=$(( errors + 1 ))
    fi

    if [[ "$library_type" == "paired" && -n "$r2" ]]; then
        if [[ ! -s "$r2" ]]; then
            printf 'ERROR: %s: R2 missing or empty: %s\n' "$id" "$r2" >&2
            errors=$(( errors + 1 ))
        elif ! gzip -t "$r2" 2>/dev/null; then
            printf 'ERROR: %s: R2 is not a valid gzip file: %s\n' "$id" "$r2" >&2
            errors=$(( errors + 1 ))
        else
            r2_lines=$(gzip -dc "$r2" | wc -l)
            if (( r2_lines % 4 != 0 )); then
                printf 'ERROR: %s: R2 line count is not divisible by 4: %s\n' \
                    "$id" "$r2_lines" >&2
                errors=$(( errors + 1 ))
            else
                r2_reads=$(( r2_lines / 4 ))
            fi
        fi
    elif [[ "$library_type" != "single" ]]; then
        printf 'ERROR: %s: unsupported library_type: %s\n' \
            "$id" "$library_type" >&2
        errors=$(( errors + 1 ))
    fi

    if [[ "$library_type" == "paired" &&
          "$r1_reads" -gt 0 &&
          "$r2_reads" -gt 0 &&
          "$r1_reads" -ne "$r2_reads" ]]; then
        printf 'ERROR: %s: R1 and R2 read counts differ: %s vs %s\n' \
            "$id" "$r1_reads" "$r2_reads" >&2
        errors=$(( errors + 1 ))
    fi

done < <(
    awk -F, '
        NR == 1 {
            for (i = 1; i <= NF; i++) {
                gsub(/\r/, "", $i)
                col[$i] = i
            }

            required[1] = "sample_id"
            required[2] = "library_type"
            required[3] = "r1_fastq"
            required[4] = "r2_fastq"

            for (i = 1; i <= 4; i++) {
                if (!(required[i] in col)) {
                    printf "ERROR: samplesheet has no %s column\\n", required[i] > "/dev/stderr"
                    exit 65
                }
            }
            next
        }

        /^[[:space:]]*$/ { next }

        {
            gsub(/\r/, "")
            printf "%s\\t%s\\t%s\\t%s\\n",
                $col["sample_id"],
                $col["library_type"],
                $col["r1_fastq"],
                $col["r2_fastq"]
        }
    ' "$SHEET"
)

if (( errors > 0 )); then
    printf 'Validation failed: %d problem(s)\n' "$errors" >&2
    exit 65
fi

printf 'Validation passed\n' >&2
