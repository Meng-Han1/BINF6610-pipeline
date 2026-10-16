import csv
import os
import re

from snakemake.utils import min_version

min_version("9.0")

configfile: "config.yaml"

KNOWN = {"samplesheet", "ref", "region", "outdir", "platform", "executor", "containers"}
unknown = sorted(set(config) - KNOWN)
if unknown:
    raise ValueError(f"unknown config key(s): {', '.join(unknown)}")

for key in ("samplesheet", "ref", "region"):
    if not config.get(key):
        raise ValueError(f"give --config {key}=...")

PIPELINE = {"name": "variant-call", "version": "1.0.0"}
OUT = config["outdir"]
BIN = os.path.join(workflow.basedir, "bin")
IMAGES = {name: f"docker://{image}" for name, image in config["containers"].items()}

REF = config["ref"]
REF_FAI = REF + ".fai"
REF_BWA = [REF + ext for ext in (".amb", ".ann", ".bwt", ".pac", ".sa")]
REF_DICT = os.path.splitext(REF)[0] + ".dict"

SHEET = config["samplesheet"]

with open(SHEET) as fh:
    ROWS = list(csv.DictReader(fh))

SAMPLES = [row["sample_id"] for row in ROWS]
PAIRED = [row["sample_id"] for row in ROWS if row["library_type"] == "paired"]
SINGLE = [row["sample_id"] for row in ROWS if row["library_type"] == "single"]

def resolve(path):
    return path if os.path.isabs(path) else os.path.join(os.path.dirname(SHEET), path)

READS = {
    row["sample_id"]: [resolve(row["r1_fastq"])]
    + ([resolve(row["r2_fastq"])] if row["library_type"] == "paired" else [])
    for row in ROWS
}

def one_of(names):
    return "|".join(map(re.escape, names)) if names else "(?!)"

def trimmed(wildcards):
    s = wildcards.sample
    if s in PAIRED:
        return [f"work/trim/{s}_R1.trim.fastq.gz", f"work/trim/{s}_R2.trim.fastq.gz"]
    return [f"work/trim/{s}_R1.trim.fastq.gz"]

rule all:
    input:
        f"{OUT}/cohort.filtered.vcf.gz",
        f"{OUT}/variants.tsv",
        f"{OUT}/multiqc_report.html",
        f"{OUT}/samples.tsv",
        f"{OUT}/manifest.json",

rule validate:
    input:
        sheet=SHEET,
        fastqs=[fq for reads in READS.values() for fq in reads],
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        "work/validate/samplesheet.csv",
    log:
        "logs/validate.log",
    container: IMAGES["tools"]
    shell:
        "({BIN}/validate_samplesheet.sh {input.sheet} {input.ref} && cp {input.sheet} {output}) 2> {log}"

rule fastqc:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        directory("work/fastqc/{sample}"),
    threads: 4
    log:
        "logs/fastqc/{sample}.log",
    container: IMAGES["fastqc"]
    shell:
        "(mkdir -p {output} && fastqc -q -t {threads} -o {output} {input.reads}) 2> {log}"

rule fastp_paired:
    input:
        r1=lambda wc: READS[wc.sample][0],
        r2=lambda wc: READS[wc.sample][1],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        r2="work/trim/{sample}_R2.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(PAIRED),
    threads: 4
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "fastp -w {threads} -i {input.r1} -I {input.r2} -o {output.r1} -O {output.r2}"
        " -j {output.json} -h {output.html} 2> {log}"

rule fastp_single:
    input:
        r1=lambda wc: READS[wc.sample][0],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(SINGLE),
    threads: 4
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        "fastp -w {threads} -i {input.r1} -o {output.r1}"
        " -j {output.json} -h {output.html} 2> {log}"

rule bwa_mem:
    input:
        reads=trimmed,
        ref=REF,
        ref_index=REF_BWA,
    output:
        bam="work/align/{sample}.bam",
    threads: 8
    log:
        "logs/bwa_mem/{sample}.log",
    container: IMAGES["bwa"]
    shell:
        r"""
        (
            bwa mem \
                -t {threads} \
                -R '@RG\tID:{wildcards.sample}\tSM:{wildcards.sample}\tPL:ILLUMINA' \
                {input.ref} {input.reads} \
            | samtools sort \
                -@ {threads} \
                -T work/align/{wildcards.sample}.sort \
                -o {output.bam}

            samtools quickcheck {output.bam}
        ) 2> {log}
        """

rule markduplicates:
    input:
        bam="work/align/{sample}.bam",
    output:
        bam="work/markdup/{sample}.markdup.bam",
        bai="work/markdup/{sample}.markdup.bam.bai",
        metrics="work/markdup/{sample}.dup_metrics.txt",
    threads: 4
    log:
        "logs/markduplicates/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        (
            gatk MarkDuplicates \
                -I {input.bam} \
                -O {output.bam} \
                -M {output.metrics}

            samtools index -@ {threads} {output.bam}
            samtools quickcheck {output.bam}
        ) 2> {log}
        """

rule haplotypecaller:
    input:
        bam="work/markdup/{sample}.markdup.bam",
        bai="work/markdup/{sample}.markdup.bam.bai",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        gvcf="work/gvcf/{sample}.g.vcf.gz",
        tbi="work/gvcf/{sample}.g.vcf.gz.tbi",
    threads: 8
    log:
        "logs/haplotypecaller/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        gatk HaplotypeCaller \
            -R {input.ref} \
            -I {input.bam} \
            -O {output.gvcf} \
            -ERC GVCF \
            -L '{config[region]}' \
            --native-pair-hmm-threads {threads} \
            > {log} 2>&1
        """

rule joint_genotype:
    input:
        gvcfs=expand("work/gvcf/{sample}.g.vcf.gz", sample=SAMPLES),
        tbis=expand("work/gvcf/{sample}.g.vcf.gz.tbi", sample=SAMPLES),
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        vcf="work/cohort/cohort.vcf.gz",
        tbi="work/cohort/cohort.vcf.gz.tbi",
    params:
        variants=lambda wc, input: " ".join(f"-V {g}" for g in input.gvcfs),
    threads: 4
    log:
        "logs/joint_genotype.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        (
            rm -rf work/cohort/genomicsdb
            gatk GenomicsDBImport \
                {params.variants} \
                --genomicsdb-workspace-path work/cohort/genomicsdb \
                -L '{config[region]}'

            gatk GenotypeGVCFs \
                -R {input.ref} \
                -V gendb://work/cohort/genomicsdb \
                -O {output.vcf} \
                -L '{config[region]}'
        ) > {log} 2>&1
        """

rule filter:
    input:
        vcf="work/cohort/cohort.vcf.gz",
        tbi="work/cohort/cohort.vcf.gz.tbi",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        vcf=f"{OUT}/cohort.filtered.vcf.gz",
        tbi=f"{OUT}/cohort.filtered.vcf.gz.tbi",
        table=f"{OUT}/variants.tsv",
    threads: 2
    log:
        "logs/filter.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        (
            before_count=$(bcftools view -H {input.vcf} | wc -l | tr -d ' ')

            gatk VariantFiltration \
                -R {input.ref} \
                -V {input.vcf} \
                -O {output.vcf} \
                --filter-expression "QD < 2.0" \
                --filter-name "QD2" \
                --filter-expression "QUAL < 30.0" \
                --filter-name "QUAL30"

            after_count=$(bcftools view -H {output.vcf} | wc -l | tr -d ' ')

            if [[ "$before_count" != "$after_count" ]]; then
                echo "VariantFiltration changed record count" >&2
                exit 1
            fi

            printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > {output.table}

            bcftools query \
                -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' \
                {output.vcf} >> {output.table}
        ) > {log} 2>&1
        """

rule multiqc:
    input:
        fastqc=expand("work/fastqc/{sample}", sample=SAMPLES),
        fastp=expand("work/trim/{sample}.fastp.json", sample=SAMPLES),
        metrics=expand("work/markdup/{sample}.dup_metrics.txt", sample=SAMPLES),
    output:
        f"{OUT}/multiqc_report.html",
    log:
        "logs/multiqc.log",
    container: IMAGES["multiqc"]
    shell:
        r"""
        (
            multiqc -q -f \
                -o work/multiqc \
                {input.fastqc} {input.fastp} {input.metrics}

            cp work/multiqc/multiqc_report.html {output}
        ) > {log} 2>&1
        """

PUBLISH_SHEET = rules.validate.output
PUBLISH_RESULTS = [*rules.filter.output, *rules.multiqc.output]

include: "rules/publish.smk"
