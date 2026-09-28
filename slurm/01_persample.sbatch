#!/usr/bin/env bash

#SBATCH --job-name=binf6610-sample
#SBATCH --output=logs/sample_%A_%a.out
#SBATCH --error=logs/sample_%A_%a.err
#SBATCH --export=NONE

set -euo pipefail

PIPELINE_DIR="${SLURM_SUBMIT_DIR}"
source "${PIPELINE_DIR}/slurm/conf/slurm.env"

SHEET="${PIPELINE_DIR}/samplesheet.csv"
OUTDIR="${OUTDIR:-/scratch/${USER}/BINF6610-assignment2}"

module load "${MINICONDA_MODULE}"
export THREADS="${SLURM_CPUS_PER_TASK}"

export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

SAMPLE=$(
    awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" '
        NR == n + 1 { print $1 }
    ' "${SHEET}"
)

[[ -n "${SAMPLE}" ]] || {
    echo "task ${SLURM_ARRAY_TASK_ID}: no such row" >&2
    exit 64
}

echo "job_id=${SLURM_JOB_ID}" >&2
echo "array_task_id=${SLURM_ARRAY_TASK_ID}" >&2
echo "sample=${SAMPLE}" >&2
echo "threads=${THREADS}" >&2
echo "tmpdir=${TMPDIR}" >&2

apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --env REF="${REF}" \
    --env REGION="${REGION}" \
    --bind /courses/BINF6610.202710,"/scratch/${USER}" \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_sample.sh" \
    "${SHEET}" \
    "${OUTDIR}" \
    "${SAMPLE}" \
    quantify
