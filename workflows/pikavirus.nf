/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Check input path parameters to see if they exist
def checkPathParamList = [
    params.input, params.kraken2_db, params.vir_ref_dir,
    params.vir_dir_repo, params.outdir
]
for (param in checkPathParamList) { if (param) { file(param, checkIfExists: true) } }
if (params.input)                 { ch_input          = file(params.input)                 } else { exit 1, 'Input samplesheet file not specified!' }

//
// SUBWORKFLOW: Installed directly from nf-core/subworkflows
//
include { FASTQ_TRIM_FASTP_FASTQC } from '../subworkflows/nf-core/fastq_trim_fastp_fastqc'


//
// MODULE: Installed directly from nf-core/modules
//
include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { CAT_FASTQ              } from '../modules/nf-core/cat/fastq'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { samplesheetToList      } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_pikavirus_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIKAVIRUS {
    take:
    ch_samplesheet // channel: samplesheet read in from --input
    ch_kraken2_db
    vir_ref_dir
    vir_dir_repo


    main:
    ch_versions      = Channel.empty()
    ch_multiqc_files = Channel.empty()
    multiqc_report   = Channel.empty()

    //
    // Create channel from input file provided through params.input
    //
    
    def criteria = multiMapCriteria {
        meta, fastqs ->
            shortreads: meta.single_end != 'NA' ? tuple(meta, fastqs) : null
    }
    // See the documentation https://nextflow-io.github.io/nf-validation/samplesheets/fromSamplesheet/
    ch_samplesheet
        .multiMap (criteria)
        .set { ch_input }
    // reconfigure channels
    ch_input
        .shortreads
        .filter{ it != null }
        .set { ch_shortreads }

    //
    // MODULE: Cat fastqs if necessary
    //
    ch_shortreads
        .branch {
            meta, fastqs ->
                single  : fastqs.size() == 1
                    return [ meta, fastqs.flatten() ]
                multiple: fastqs.size() > 1
                    return [ meta, fastqs.flatten() ]
        }
        .set { ch_fastqs }

        CAT_FASTQ (
            ch_fastqs.multiple
        )
        .reads
        .mix( ch_fastqs.single )
        .set { ch_reads_concat }
        ch_versions = ch_versions.mix(CAT_FASTQ.out.versions)

    // ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]})
    // ch_versions = ch_versions.mix(FASTQC.out.versions.first())
    if (!params.skip_sra ) {
        println "rsa process not implemented yet"
    }
    ch_fastqc_raw_multiqc = Channel.empty()
    ch_fastqc_trim_multiqc = Channel.empty()
    ch_fastp_json_multiqc = Channel.empty()
    if (params.trimming == true) {
        FASTQ_TRIM_FASTP_FASTQC (
            ch_reads_concat,
            [],
            params.save_trimmed_fail,
            [],
            params.skip_fastp,
            params.skip_fastqc
        )
        ch_fastqc_raw_multiqc   = FASTQ_TRIM_FASTP_FASTQC.out.fastqc_raw_zip
        ch_fastqc_trim_multiqc  = FASTQ_TRIM_FASTP_FASTQC.out.fastqc_trim_zip
        ch_fastp_json_multiqc   = FASTQ_TRIM_FASTP_FASTQC.out.trim_json
        ch_versions = ch_versions.mix(FASTQ_TRIM_FASTP_FASTQC.out.versions)
    }
    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'pikavirus_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    // ASSEMBLY //































































































































































































































    // MAPPING //










































































    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/