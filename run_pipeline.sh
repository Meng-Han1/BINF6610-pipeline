#!/usr/bin/env bash
set -euo pipefail

# BINF6610 Week 1
# Germline variant-calling pipeline

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

