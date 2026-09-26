#!/usr/bin/env bash

#SBATCH --job-name=binf6610-cohort
#SBATCH --output=logs/cohort_%j.out
#SBATCH --error=logs/cohort_%j.err
#SBATCH --export=NONE

set -euo pipefail

PIPELINE_DIR="${SLURM_SUBMIT_DIR}"
source "${PIPELINE_DIR}/slurm/conf/slurm.env"

SHEET="${PIPELINE_DIR}/samplesheet.csv"
OUTDIR="/scratch/${USER}/BINF6610-assignment2"

module load "${MINICONDA_MODULE}"
source activate "${CONDA_ENV}"

export THREADS="${SLURM_CPUS_PER_TASK}"

export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "job_id=${SLURM_JOB_ID}" >&2
echo "threads=${THREADS}" >&2
echo "tmpdir=${TMPDIR}" >&2

REF="${REF}" \
REGION="${REGION}" \
THREADS="${THREADS}" \
TMPDIR="${TMPDIR}" \
bash "${PIPELINE_DIR}/run_pipeline.sh" \
    "${SHEET}" \
    "${OUTDIR}" \
    publish
