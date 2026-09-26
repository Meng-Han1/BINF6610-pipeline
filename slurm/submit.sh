#!/usr/bin/env bash

set -euo pipefail

PIPELINE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "${PIPELINE_DIR}"

source "${PIPELINE_DIR}/slurm/conf/slurm.env"

mkdir -p logs

ARRAY_JOB_ID=$(
    sbatch \
        --parsable \
        --partition="${PARTITION}" \
        --time="${TIME}" \
        --mem="${MEM}" \
        --cpus-per-task="${CPUS}" \
        --array=1-8 \
        slurm/01_persample.sbatch
)

echo "submitted per-sample array: ${ARRAY_JOB_ID}"

COHORT_JOB_ID=$(
    sbatch \
        --parsable \
        --partition="${PARTITION}" \
        --time="${TIME}" \
        --mem="${MEM}" \
        --cpus-per-task="${CPUS}" \
        --dependency="afterok:${ARRAY_JOB_ID}" \
        --kill-on-invalid-dep=yes \
        slurm/02_cohort.sbatch
)

echo "submitted cohort job: ${COHORT_JOB_ID}"
echo "dependency: afterok:${ARRAY_JOB_ID}"
