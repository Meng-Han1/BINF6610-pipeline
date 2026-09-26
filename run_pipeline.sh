#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

source "${SCRIPT_DIR}/lib/common.sh"

for stage_file in "${SCRIPT_DIR}"/stages/*.sh; do
    source "$stage_file"
done

SHEET=${1:-}
OUTDIR=${2:-}
LAST=${3:-publish}

REF=${REF:-}
REGION=${REGION:-}

if [[ -z "$SHEET" || -z "$OUTDIR" ]]; then
    die "usage: $0 <samplesheet.csv> <outdir> [last-stage]"
fi

case "$LAST" in
    validate|qc_raw|trim|align|postprocess|quantify|merge|analyze|qc_report|publish)
        ;;
    *)
        die "unknown stage: $LAST"
        ;;
esac

for stage in "${STAGES[@]}"; do
    "stage_${stage}"

    if [[ "$stage" == "$LAST" ]]; then
        exit 0
    fi
done
