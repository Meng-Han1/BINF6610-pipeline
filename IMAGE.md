# Container Image

## Base image

mambaorg/micromamba:2.0.5-ubuntu24.04

mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned

bwa=0.7.19  
samtools=1.24  
bcftools=1.24  
gatk4=4.6.2.0  
fastqc=0.12.1  
fastp=1.3.7  
multiqc=1.35  
git=2.47.1

## The pushed image

docker.io/menghanbio/variant-call@sha256:a81d8570501553ede0c707f4136ce4b4634bee0309894474805f72760076ffd4

To rerun this pipeline in the future, the container image should be pulled by the digest above rather than by the mutable `1.0` tag. The Dockerfile records how the environment was built, while the pushed-image digest identifies the exact image that was tested and used on Explorer.
