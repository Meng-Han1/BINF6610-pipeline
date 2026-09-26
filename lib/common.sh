#!/usr/bin/env bash

set -euo pipefail

log() {
    echo "$*" >&2
}

die() {
    echo "ERROR: $*" >&2
    exit 65
}

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)
