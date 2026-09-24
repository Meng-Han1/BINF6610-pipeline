#!/usr/bin/env bash
set -euo pipefail

# BINF6610 Week 1
# Germline variant-calling pipeline

SHEET=${1:-}
OUTDIR=${2:-}
LAST=${3:-publish}

REF=${REF:-}
REGION=${REGION:-}

log() {
    echo "$*" >&2
}

die() {
    echo "ERROR: $*" >&2
    exit 65
}

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

stage_validate() {
    local errors=0
    local id condition replicate library_type r1 r2
    local duplicate
    local r1_lines r2_lines
    local r1_reads r2_reads

    log "Validating inputs"

    if [[ ! -s "$SHEET" ]]; then
        log "ERROR: samplesheet missing or empty: $SHEET"
        exit 65
    fi

    # Check for duplicate sample IDs.
    while read -r duplicate; do
        [[ -z "$duplicate" ]] && continue
        log "ERROR: duplicate sample_id: $duplicate"
        errors=$(( errors + 1 ))
    done < <(awk -F, 'NR>1 { print $1 }' "$SHEET" | sort | uniq -d)

    # Validate every sample in the samplesheet.
    while IFS=, read -r id condition replicate library_type r1 r2; do
        r1_lines=0
        r2_lines=0
        r1_reads=0
        r2_reads=0

        # R1 is required for every sample.
        if [[ ! -s "$r1" ]]; then
            log "ERROR: $id: R1 missing or empty: $r1"
            errors=$(( errors + 1 ))
        elif ! gzip -t "$r1" 2>/dev/null; then
            log "ERROR: $id: R1 is not a valid gzip file: $r1"
            errors=$(( errors + 1 ))
        else
            r1_lines=$(gzip -dc "$r1" | wc -l)

            if (( r1_lines % 4 != 0 )); then
                log "ERROR: $id: R1 line count is not divisible by 4: $r1_lines"
                errors=$(( errors + 1 ))
            else
                r1_reads=$(( r1_lines / 4 ))
            fi
        fi

        # Paired-end samples must have an R2 path.
        if [[ "$library_type" == "paired" && -z "$r2" ]]; then
            log "ERROR: $id: paired library has no R2"
            errors=$(( errors + 1 ))
        fi

        # Validate R2 for paired-end samples.
        if [[ "$library_type" == "paired" && -n "$r2" ]]; then
            if [[ ! -s "$r2" ]]; then
                log "ERROR: $id: R2 missing or empty: $r2"
                errors=$(( errors + 1 ))
            elif ! gzip -t "$r2" 2>/dev/null; then
                log "ERROR: $id: R2 is not a valid gzip file: $r2"
                errors=$(( errors + 1 ))
            else
                r2_lines=$(gzip -dc "$r2" | wc -l)

                if (( r2_lines % 4 != 0 )); then
                    log "ERROR: $id: R2 line count is not divisible by 4: $r2_lines"
                    errors=$(( errors + 1 ))
                else
                    r2_reads=$(( r2_lines / 4 ))
                fi
            fi
        fi

        # Paired-end samples must have matching read counts.
        if [[ "$library_type" == "paired" &&
              "$r1_reads" -gt 0 &&
              "$r2_reads" -gt 0 &&
              "$r1_reads" -ne "$r2_reads" ]]; then
            log "ERROR: $id: R1 and R2 read counts differ: $r1_reads vs $r2_reads"
            errors=$(( errors + 1 ))
        fi

    done < <(tail -n +2 "$SHEET")

    if (( errors > 0 )); then
        log "Validation failed: $errors problem(s)"
        exit 65
    fi

    log "Validation passed"
}

stage_qc_raw() {
    local id condition replicate library_type r1 r2
    local qc_dir="${OUTDIR}/qc_raw"
    local r1_base r2_base

    log "Running raw-read QC"

    mkdir -p "$qc_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        log "FastQC: $id R1"

        fastqc \
            -q -o "$qc_dir" \
            "$r1"

        r1_base=$(basename "$r1" .fastq.gz)

        if [[ ! -s "${qc_dir}/${r1_base}_fastqc.html" ||
              ! -s "${qc_dir}/${r1_base}_fastqc.zip" ]]; then
            die "$id: FastQC R1 output missing or empty"
        fi

        if [[ "$library_type" == "paired" ]]; then
            log "FastQC: $id R2"

            fastqc \
                -q -o "$qc_dir" \
                "$r2"

            r2_base=$(basename "$r2" .fastq.gz)

            if [[ ! -s "${qc_dir}/${r2_base}_fastqc.html" ||
                  ! -s "${qc_dir}/${r2_base}_fastqc.zip" ]]; then
                die "$id: FastQC R2 output missing or empty"
            fi
        fi

    done < <(tail -n +2 "$SHEET")

    log "Raw-read QC complete"
}


stage_trim() {
    local id condition replicate library_type r1 r2
    local trim_dir="${OUTDIR}/trim"
    local out_r1 out_r2
    local html json

    log "Trimming reads"

    mkdir -p "$trim_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        out_r1="${trim_dir}/${id}_R1.trim.fastq.gz"
        html="${trim_dir}/${id}.fastp.html"
        json="${trim_dir}/${id}.fastp.json"

        if [[ "$library_type" == "paired" ]]; then
            out_r2="${trim_dir}/${id}_R2.trim.fastq.gz"

            log "fastp: $id paired-end"

            fastp \
                -i "$r1" \
                -I "$r2" \
                -o "$out_r1" \
                -O "$out_r2" \
                --html "$html" \
                --json "$json"

            if [[ ! -s "$out_r1" || ! -s "$out_r2" ||
                  ! -s "$html" || ! -s "$json" ]]; then
                die "$id: fastp paired-end output missing or empty"
            fi

            if ! gzip -t "$out_r1" 2>/dev/null ||
               ! gzip -t "$out_r2" 2>/dev/null; then
                die "$id: fastp produced an invalid gzip FASTQ"
            fi

        elif [[ "$library_type" == "single" ]]; then
            log "fastp: $id single-end"

            fastp \
                -i "$r1" \
                -o "$out_r1" \
                --html "$html" \
                --json "$json"

            if [[ ! -s "$out_r1" ||
                  ! -s "$html" || ! -s "$json" ]]; then
                die "$id: fastp single-end output missing or empty"
            fi

            if ! gzip -t "$out_r1" 2>/dev/null; then
                die "$id: fastp produced an invalid gzip FASTQ"
            fi

        else
            die "$id: unsupported library_type: $library_type"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Read trimming complete"
}


stage_align() {
    local id condition replicate library_type r1 r2
    local trim_dir="${OUTDIR}/trim"
    local align_dir="${OUTDIR}/align"
    local trim_r1 trim_r2 bam rg

    log "Aligning reads"

    if [[ -z "$REF" ]]; then
        die "REF is not set"
    fi

    if [[ ! -s "$REF" ]]; then
        die "reference missing or empty: $REF"
    fi

    mkdir -p "$align_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        trim_r1="${trim_dir}/${id}_R1.trim.fastq.gz"
        trim_r2="${trim_dir}/${id}_R2.trim.fastq.gz"
        bam="${align_dir}/${id}.bam"
        rg="@RG\tID:${id}\tSM:${id}\tPL:ILLUMINA"

        if [[ "$library_type" == "paired" ]]; then
            log "BWA-MEM: $id paired-end"

            bwa mem \
                -R "$rg" \
                "$REF" \
                "$trim_r1" \
                "$trim_r2" \
            | samtools sort \
                -o "$bam"

        elif [[ "$library_type" == "single" ]]; then
            log "BWA-MEM: $id single-end"

            bwa mem \
                -R "$rg" \
                "$REF" \
                "$trim_r1" \
            | samtools sort \
                -o "$bam"

        else
            die "$id: unsupported library_type: $library_type"
        fi

        if [[ ! -s "$bam" ]]; then
            die "$id: alignment BAM missing or empty"
        fi

        if ! samtools quickcheck "$bam"; then
            die "$id: alignment BAM failed samtools quickcheck"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Alignment complete"
}


stage_postprocess() {
    local id condition replicate library_type r1 r2
    local align_dir="${OUTDIR}/align"
    local post_dir="${OUTDIR}/postprocess"
    local input_bam output_bam metrics bai

    log "Postprocessing alignments"

    mkdir -p "$post_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        input_bam="${align_dir}/${id}.bam"
        output_bam="${post_dir}/${id}.markdup.bam"
        metrics="${post_dir}/${id}.dup_metrics.txt"
        bai="${output_bam}.bai"

        log "MarkDuplicates: $id"

        if [[ ! -s "$input_bam" ]]; then
            die "$id: input BAM missing or empty: $input_bam"
        fi

        gatk MarkDuplicates \
            -I "$input_bam" \
            -O "$output_bam" \
            -M "$metrics"

        if [[ ! -s "$output_bam" ]]; then
            die "$id: duplicate-marked BAM missing or empty"
        fi

        if [[ ! -s "$metrics" ]]; then
            die "$id: duplicate metrics missing or empty"
        fi

        if ! samtools quickcheck "$output_bam"; then
            die "$id: duplicate-marked BAM failed samtools quickcheck"
        fi

        log "Indexing BAM: $id"

        samtools index "$output_bam"

        if [[ ! -s "$bai" ]]; then
            die "$id: BAM index missing or empty"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Postprocessing complete"
}


stage_quantify() {
    local id condition replicate library_type r1 r2
    local post_dir="${OUTDIR}/postprocess"
    local gvcf_dir="${OUTDIR}/gvcf"
    local bam gvcf tbi

    log "Calling per-sample GVCFs"

    if [[ -z "$REF" ]]; then
        die "REF is not set"
    fi

    if [[ -z "$REGION" ]]; then
        die "REGION is not set"
    fi

    mkdir -p "$gvcf_dir"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        bam="${post_dir}/${id}.markdup.bam"
        gvcf="${gvcf_dir}/${id}.g.vcf.gz"
        tbi="${gvcf}.tbi"

        log "HaplotypeCaller: $id"

        if [[ ! -s "$bam" ]]; then
            die "$id: postprocessed BAM missing or empty: $bam"
        fi

        if [[ ! -s "${bam}.bai" ]]; then
            die "$id: BAM index missing or empty: ${bam}.bai"
        fi

        gatk HaplotypeCaller \
            -R "$REF" \
            -I "$bam" \
            -O "$gvcf" \
            -ERC GVCF \
            -L "$REGION"

        if [[ ! -s "$gvcf" ]]; then
            die "$id: GVCF missing or empty"
        fi

        if [[ ! -s "$tbi" ]]; then
            die "$id: GVCF index missing or empty"
        fi

        if ! bcftools view -h "$gvcf" >/dev/null; then
            die "$id: GVCF is not readable"
        fi

        if [[ "$(bcftools query -l "$gvcf")" != "$id" ]]; then
            die "$id: GVCF sample name does not match sample_id"
        fi
    done < <(tail -n +2 "$SHEET")

    log "Per-sample GVCF calling complete"
}


stage_merge() {
    local gvcf_dir="${OUTDIR}/gvcf"
    local merge_dir="${OUTDIR}/merge"
    local workspace="${merge_dir}/genomicsdb"
    local cohort_vcf="${merge_dir}/cohort.vcf.gz"
    local cohort_tbi="${cohort_vcf}.tbi"
    local id condition replicate library_type r1 r2
    local gvcf
    local -a variant_args=()
    local -a expected_samples=()
    local -a observed_samples=()

    log "Joint genotyping cohort"

    if [[ -z "$REF" ]]; then
        die "REF is not set"
    fi

    if [[ -z "$REGION" ]]; then
        die "REGION is not set"
    fi

    mkdir -p "$merge_dir"
    rm -rf "$workspace"

    while IFS=, read -r id condition replicate library_type r1 r2; do
        gvcf="${gvcf_dir}/${id}.g.vcf.gz"

        if [[ ! -s "$gvcf" ]]; then
            die "$id: GVCF missing or empty: $gvcf"
        fi

        if [[ ! -s "${gvcf}.tbi" ]]; then
            die "$id: GVCF index missing or empty: ${gvcf}.tbi"
        fi

        variant_args+=( -V "$gvcf" )
        expected_samples+=( "$id" )
    done < <(tail -n +2 "$SHEET")

    if (( ${#variant_args[@]} == 0 )); then
        die "no GVCFs found for joint genotyping"
    fi

    log "GenomicsDBImport: ${#expected_samples[@]} samples"

    gatk GenomicsDBImport \
        "${variant_args[@]}" \
        --genomicsdb-workspace-path "$workspace" \
        -L "$REGION"

    if [[ ! -d "$workspace" ]]; then
        die "GenomicsDB workspace was not created"
    fi

    if [[ ! -s "${workspace}/callset.json" ||
          ! -s "${workspace}/vidmap.json" ||
          ! -s "${workspace}/vcfheader.vcf" ]]; then
        die "GenomicsDB workspace is incomplete"
    fi

    log "GenotypeGVCFs"

    gatk GenotypeGVCFs \
        -R "$REF" \
        -V "gendb://${workspace}" \
        -O "$cohort_vcf" \
        -L "$REGION"

    if [[ ! -s "$cohort_vcf" ]]; then
        die "cohort VCF missing or empty"
    fi

    if [[ ! -s "$cohort_tbi" ]]; then
        die "cohort VCF index missing or empty"
    fi

    if ! bcftools view -h "$cohort_vcf" >/dev/null; then
        die "cohort VCF is not readable"
    fi

    mapfile -t observed_samples < <(bcftools query -l "$cohort_vcf")

    if (( ${#observed_samples[@]} != ${#expected_samples[@]} )); then
        die "cohort VCF sample count does not match samplesheet"
    fi

    for id in "${expected_samples[@]}"; do
        if ! printf '%s\n' "${observed_samples[@]}" | grep -Fxq "$id"; then
            die "$id: missing from cohort VCF"
        fi
    done

    log "Joint genotyping complete"
}


stage_analyze() {
    local merge_dir="${OUTDIR}/merge"
    local analyze_dir="${OUTDIR}/analyze"
    local input_vcf="${merge_dir}/cohort.vcf.gz"
    local output_vcf="${analyze_dir}/cohort.filtered.vcf.gz"
    local output_tbi="${output_vcf}.tbi"
    local before_count after_count

    log "Hard-filtering cohort variants"

    if [[ -z "$REF" ]]; then
        die "REF is not set"
    fi

    if [[ ! -s "$input_vcf" ]]; then
        die "cohort VCF missing or empty: $input_vcf"
    fi

    if [[ ! -s "${input_vcf}.tbi" ]]; then
        die "cohort VCF index missing or empty: ${input_vcf}.tbi"
    fi

    mkdir -p "$analyze_dir"

    before_count=$(bcftools view -H "$input_vcf" | wc -l | tr -d ' ')

    gatk VariantFiltration \
        -R "$REF" \
        -V "$input_vcf" \
        -O "$output_vcf" \
        --filter-expression "QD < 2.0" \
        --filter-name "QD2" \
        --filter-expression "QUAL < 30.0" \
        --filter-name "QUAL30"

    if [[ ! -s "$output_vcf" ]]; then
        die "filtered cohort VCF missing or empty"
    fi

    if [[ ! -s "$output_tbi" ]]; then
        die "filtered cohort VCF index missing or empty"
    fi

    if ! bcftools view -h "$output_vcf" >/dev/null; then
        die "filtered cohort VCF is not readable"
    fi

    after_count=$(bcftools view -H "$output_vcf" | wc -l | tr -d ' ')

    if [[ "$before_count" != "$after_count" ]]; then
        die "VariantFiltration changed the number of VCF records: ${before_count} -> ${after_count}"
    fi

    log "Variant filtering complete"
}


stage_qc_report() {
    local report_dir="${OUTDIR}/qc_report"
    local report="${report_dir}/multiqc_report.html"

    log "Building cohort QC report"

    mkdir -p "$report_dir"

    multiqc \
        -q \
        -f \
        -o "$report_dir" \
        "$OUTDIR"

    if [[ ! -s "$report" ]]; then
        die "MultiQC produced no report"
    fi

    log "QC report written"
}


stage_publish() {
    local results_dir="${OUTDIR}/results"
    local filtered_vcf="${OUTDIR}/analyze/cohort.filtered.vcf.gz"
    local filtered_tbi="${filtered_vcf}.tbi"
    local multiqc_report="${OUTDIR}/qc_report/multiqc_report.html"
    local published_vcf="${results_dir}/cohort.filtered.vcf.gz"
    local published_tbi="${published_vcf}.tbi"
    local published_multiqc="${results_dir}/multiqc_report.html"
    local manifest="${results_dir}/manifest.json"
    local script_dir git_sha started_at finished_at run_id
    local vcf_sha tbi_sha multiqc_sha n_variants

    log "Publishing final results"

    if [[ ! -s "$filtered_vcf" ]]; then
        die "filtered cohort VCF missing or empty: $filtered_vcf"
    fi

    if [[ ! -s "$filtered_tbi" ]]; then
        die "filtered cohort VCF index missing or empty: $filtered_tbi"
    fi

    if [[ ! -s "$multiqc_report" ]]; then
        die "MultiQC report missing or empty: $multiqc_report"
    fi

    mkdir -p "$results_dir"

    cp "$filtered_vcf" "$published_vcf"
    cp "$filtered_tbi" "$published_tbi"
    cp "$multiqc_report" "$published_multiqc"

    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

    git_sha=$(git -C "$script_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)

    if [[ "$git_sha" != "unknown" ]] &&
       [[ -n "$(git -C "$script_dir" status --porcelain 2>/dev/null)" ]]; then
        git_sha="${git_sha}-dirty"
    fi

    started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    finished_at="$started_at"
    run_id="${started_at}-${git_sha}"

    vcf_sha="sha256:$(shasum -a 256 "$published_vcf" | awk '{print $1}')"
    tbi_sha="sha256:$(shasum -a 256 "$published_tbi" | awk '{print $1}')"
    multiqc_sha="sha256:$(shasum -a 256 "$published_multiqc" | awk '{print $1}')"

    n_variants=$(bcftools view -H "$published_vcf" | wc -l | tr -d ' ')

    PIPELINE_GIT_SHA="$git_sha" \
    PIPELINE_RUN_ID="$run_id" \
    PIPELINE_STARTED_AT="$started_at" \
    PIPELINE_FINISHED_AT="$finished_at" \
    PIPELINE_REF="$REF" \
    PIPELINE_REGION="$REGION" \
    PIPELINE_SHEET="$SHEET" \
    PIPELINE_RESULTS_DIR="$results_dir" \
    PIPELINE_VCF_SHA="$vcf_sha" \
    PIPELINE_TBI_SHA="$tbi_sha" \
    PIPELINE_MULTIQC_SHA="$multiqc_sha" \
    PIPELINE_N_VARIANTS="$n_variants" \
    python3 - <<'PYJSON'
import csv
import json
import os

samples = []

with open(os.environ["PIPELINE_SHEET"], newline="") as handle:
    reader = csv.DictReader(handle)
    for row in reader:
        samples.append({
            "sample_id": row["sample_id"],
            "library_type": row["library_type"],
            "condition": row["condition"],
        })

manifest = {
    "pipeline": {
        "name": "variant-call",
        "version": "1.0.0",
        "implementation": "bash",
        "git_sha": os.environ["PIPELINE_GIT_SHA"],
        "run_id": os.environ["PIPELINE_RUN_ID"],
        "started_at": os.environ["PIPELINE_STARTED_AT"],
        "finished_at": os.environ["PIPELINE_FINISHED_AT"],
        "exit_status": "success",
    },
    "platform": {
        "kind": "laptop",
        "region": os.environ["PIPELINE_REGION"],
    },
    "reference": {
        "genome": os.environ["PIPELINE_REF"],
    },
    "samples": samples,
    "outputs": [
        {
            "stage": "analyze",
            "type": "cohort_vcf",
            "path": "cohort.filtered.vcf.gz",
            "checksum": os.environ["PIPELINE_VCF_SHA"],
        },
        {
            "stage": "analyze",
            "type": "cohort_vcf_index",
            "path": "cohort.filtered.vcf.gz.tbi",
            "checksum": os.environ["PIPELINE_TBI_SHA"],
        },
        {
            "stage": "qc_report",
            "type": "multiqc",
            "path": "multiqc_report.html",
            "checksum": os.environ["PIPELINE_MULTIQC_SHA"],
        },
    ],
    "metrics": [
        {
            "sample_id": None,
            "metric": "n_variants",
            "value": int(os.environ["PIPELINE_N_VARIANTS"]),
            "unit": "count",
            "stage": "analyze",
        }
    ],
}

out = os.path.join(os.environ["PIPELINE_RESULTS_DIR"], "manifest.json")
with open(out, "w") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PYJSON

    if [[ ! -s "$manifest" ]]; then
        die "manifest.json missing or empty"
    fi

    log "Published results:"
    ls -1 "$results_dir" >&2
}

if [[ -z "$SHEET" || -z "$OUTDIR" ]]; then
    die "usage: $0 <samplesheet.csv> <outdir> [last-stage]"
fi

stage_validate

if [[ "$LAST" == "validate" ]]; then
    exit 0
fi

stage_qc_raw

if [[ "$LAST" == "qc_raw" ]]; then
    exit 0
fi

stage_trim

if [[ "$LAST" == "trim" ]]; then
    exit 0
fi

stage_align

if [[ "$LAST" == "align" ]]; then
    exit 0
fi

stage_postprocess

if [[ "$LAST" == "postprocess" ]]; then
    exit 0
fi

stage_quantify

if [[ "$LAST" == "quantify" ]]; then
    exit 0
fi

stage_merge

if [[ "$LAST" == "merge" ]]; then
    exit 0
fi

stage_analyze

if [[ "$LAST" == "analyze" ]]; then
    exit 0
fi

stage_qc_report

if [[ "$LAST" == "qc_report" ]]; then
    exit 0
fi

stage_publish

if [[ "$LAST" == "publish" ]]; then
    exit 0
fi
