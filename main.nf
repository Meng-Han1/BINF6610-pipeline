include { VALIDATE }          from './modules/validate'
include { FASTQC }            from './modules/fastqc'
include { FASTP }             from './modules/fastp'
include { BWA_MEM }           from './modules/bwa_mem'
include { MARKDUPLICATES }    from './modules/markduplicates'
include { HAPLOTYPECALLER }   from './modules/haplotypecaller'
include { JOINT_GENOTYPE }    from './modules/joint_genotype'
include { FILTER }            from './modules/filter'
include { MULTIQC }           from './modules/multiqc'
include { PUBLISH }           from './modules/publish'

workflow {

    main:

    sheet = file(params.samplesheet)

    /*
     * Reference files are value channels.
     *
     * The FASTA sidecars are:
     *   ref.fa.fai
     *   ref.fa.amb
     *   ref.fa.ann
     *   ref.fa.bwt
     *   ref.fa.pac
     *   ref.fa.sa
     *
     * The sequence dictionary is ref.dict, not ref.fa.dict.
     */
    ref = file(params.ref)
    ref_fai = file("${params.ref}.fai")
    ref_dict = file(
        params.ref.replaceFirst(/\.[^\.]+$/, '') + '.dict'
    )
    ref_index = files("${params.ref}.{amb,ann,bwt,pac,sa}")

    /*
     * One item per sample:
     *   [meta, reads]
     *
     * meta follows the sample through every per-sample process.
     */
    ch_samples = channel.fromPath(sheet)
        .splitCsv(header: true)
        .map { row ->
            def meta = [
                id: row.sample_id,
                single_end: row.library_type == 'single'
            ]

            def r1 = sheet.parent.resolve(row.r1_fastq)
            def reads = meta.single_end
                ? [r1]
                : [r1, sheet.parent.resolve(row.r2_fastq)]

            [meta, reads]
        }

    /*
     * Stage 0 is a global barrier.
     * VALIDATE receives every FASTQ before any sample proceeds.
     */
    VALIDATE(
        sheet,
        ch_samples.map { _meta, reads -> reads }.collect(),
        ref,
        ref_fai,
        ref_dict,
        ref_index
    )

    ch_checked = ch_samples
        .combine(VALIDATE.out.sheet)
        .map { meta, reads, _validated -> [meta, reads] }

    /*
     * Per-sample stages.
     */
    FASTQC(ch_checked)
    FASTP(ch_checked)

    BWA_MEM(
        FASTP.out.reads,
        ref,
        ref_index
    )

    MARKDUPLICATES(BWA_MEM.out.bam)

    HAPLOTYPECALLER(
        MARKDUPLICATES.out.bam,
        ref,
        ref_fai,
        ref_dict
    )

    /*
     * Cohort barrier: wait for every sample's GVCF and index.
     */
    JOINT_GENOTYPE(
        HAPLOTYPECALLER.out.gvcf.collect(),
        HAPLOTYPECALLER.out.tbi.collect(),
        ref,
        ref_fai,
        ref_dict
    )

    FILTER(
        JOINT_GENOTYPE.out.vcf,
        ref,
        ref_fai,
        ref_dict
    )

    /*
     * Cohort QC report.
     */
    ch_qc = FASTQC.out.zip
        .mix(
            FASTP.out.json,
            MARKDUPLICATES.out.metrics
        )
        .collect()

    MULTIQC(ch_qc)

    /*
     * Stage 9 receives every final file it describes.
     */
    PUBLISH(
        VALIDATE.out.sheet,
        FILTER.out.vcf
            .mix(
                FILTER.out.tbi,
                FILTER.out.table,
                MULTIQC.out
            )
            .collect()
    )

    publish:

    vcf       = FILTER.out.vcf
    vcf_index = FILTER.out.tbi
    variants  = FILTER.out.table
    multiqc   = MULTIQC.out
    manifest  = PUBLISH.out.manifest
    samples   = PUBLISH.out.samples
}

output {

    vcf {
        path '.'
    }

    vcf_index {
        path '.'
    }

    variants {
        path '.'
    }

    multiqc {
        path '.'
    }

    manifest {
        path '.'
    }

    samples {
        path '.'
    }
}
