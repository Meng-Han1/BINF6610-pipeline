process VALIDATE {
    container params.containers.tools

    input:
    path samplesheet
    path fastqs
    path ref
    path ref_fai
    path ref_dict
    path ref_index

    output:
    path samplesheet, emit: sheet

    script:
    """
    validate_samplesheet.sh ${samplesheet} ${ref.name}
    """
}
