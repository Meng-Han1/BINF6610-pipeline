#!/usr/bin/env bash
#SBATCH -A binf6610.202710
#SBATCH -p courses
#SBATCH -c 4
#SBATCH --mem=16G
#SBATCH -t 00:30:00
#SBATCH -o pull-%j.out

set -euo pipefail

export APPTAINER_CACHEDIR="/scratch/${USER}/apptainer-cache"

mkdir -p "${APPTAINER_CACHEDIR}"
mkdir -p "/scratch/${USER}/containers"

apptainer pull \
    "/scratch/${USER}/containers/variant-call.sif" \
    "docker://menghanbio/variant-call@sha256:a81d8570501553ede0c707f4136ce4b4634bee0309894474805f72760076ffd4"
