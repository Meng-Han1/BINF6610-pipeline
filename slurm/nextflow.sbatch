#!/usr/bin/env bash

#SBATCH --job-name=binf6610-nf
#SBATCH --account=binf6610.202710
#SBATCH --partition=courses
#SBATCH --time=04:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH --output=nf-head-%j.out

set -euo pipefail

module load miniconda3/25.9.1
source activate /courses/BINF6610.202710/shared/env/binf6610

export NXF_APPTAINER_CACHEDIR=/scratch/${USER}/nxf-apptainer
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache

mkdir -p \
    "${NXF_APPTAINER_CACHEDIR}" \
    "${APPTAINER_CACHEDIR}"

nextflow run main.nf -profile explorer \
    --samplesheet /courses/BINF6610.202710/data/samplesheet-variant8.csv \
    --ref /courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa \
    --region chr20:1-10000000 \
    --outdir results-nf \
    -resume
