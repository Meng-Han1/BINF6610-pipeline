#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

source "${SCRIPT_DIR}/lib/common.sh"

for stage_file in "${SCRIPT_DIR}"/stages/*.sh; do
    source "$stage_file"
done

SHEET=${1:-}
OUTDIR=${2:-}
SAMPLE=${3:-}
LAST=${4:-quantify}

REF=${REF:-}
REGION=${REGION:-}

if [[ -z "$SHEET" || -z "$OUTDIR" || -z "$SAMPLE" ]]; then
    die "usage: $0 <samplesheet.csv> <outdir> <sample_id> [last-stage]"
fi

case "$LAST" in
    validate|qc_raw|trim|align|postprocess|quantify)
        ;;
    merge|analyze|qc_report|publish)
        die "per-sample entry point refuses cohort stage: $LAST"
        ;;
    *)
        die "unknown stage: $LAST"
        ;;
esac

if [[ ! -s "$SHEET" ]]; then
    die "samplesheet missing or empty: $SHEET"
fi

TMP_SAMPLE_SHEET=$(mktemp)
trap 'rm -f "$TMP_SAMPLE_SHEET"' EXIT

head -n 1 "$SHEET" > "$TMP_SAMPLE_SHEET"

awk -F',' -v sample="$SAMPLE" '
    NR > 1 && $1 == sample { print }
' "$SHEET" >> "$TMP_SAMPLE_SHEET"

if [[ $(wc -l < "$TMP_SAMPLE_SHEET") -ne 2 ]]; then
    die "sample_id not found exactly once in samplesheet: $SAMPLE"
fi

SHEET="$TMP_SAMPLE_SHEET"

for stage in "${STAGES[@]}"; do
    "stage_${stage}"

    if [[ "$stage" == "$LAST" ]]; then
        exit 0
    fi
done
