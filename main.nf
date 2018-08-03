#!/usr/bin/env nextflow

/*
========================================================================================
                                    PIKAVIRUS
========================================================================================
 Method for metagenomics analysis with a novel mapping approach integrated with
 traditional assembly and blast annotation.
 #### Homepage / Documentation
 https://github.com/BU-ISCIII/PikaVirus
 @#### Authors
 BU-ISCIII <bioinformatica@isciii.es>
 Miguel Juliá <mjuliam@isciii.es>
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
Pipeline overview:
 - 0:   Check configuration file
 - 1:   Data quality control
 - 1.1: FastQC for raw sequencing reads quality control
 - 1.2: Quality trimming with Trimmommatic
 - 1.3: Quality control of the trimmed reads with fastQC
 - 1.4: Generate Quality Statistics
 - 2:   Mapping
 - 2.1: Mapping against human reference genome and removal of host reads
 - 2.2: Mapping against bacteria WG reference genomes
 - 2.3: Mapping against virus reference genomes
 - 2.4: Mapping against fungi WG reference genomes
 - 3:   Assembly with SPADES
 - 3.1: Bacteria Assembly
 - 3.2: Virus Assembly
 - 3.3: Fungi Assembly
 - 4:   Blast against references
 - 4.1: Bacteria Blast
 - 4.2: Virus Blast
 - 4.3: Fungi Blast
 - 5:   Calculate coverage and generate graphs
 - 5.1: For Bacteria
 - 5.2: For Virus
 - 5.3: For Fungi
 - 6:   Generate output in HTML and tsv table
 ----------------------------------------------------------------------------------------
*/

def helpMessage() {
    log.info"""
    =========================================
     PIKAVIRUS v${version}
    =========================================
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run BU-ISCIII/Pikavirus -c your_config_file -profile uppmax
    Mandatory arguments:
      -c                            Path to input your personalised config file. You can modify the example in BU-ISCIII/Pikavirus/nextflow.config to fit your analysis.
    Options:
      --no-bacteria                 Do not look for bacteria
      --no-virus                    Do not look for virus
      --no-fungi                    Do not look for fungil
      --no-trim                     Skip the adapter trimming step.
    Other options:
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --name                        Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic
    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Pipeline version
version = '1.0'

// Show help message
params.help = false
if (params.help){
    helpMessage()
    exit 0
}

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /\w+/) ){
  custom_runName = workflow.runName
}

/*
 * Create a channel for input read files
 */
Channel
    .fromFilePairs( "$readsDir/*R{1,2}*fastq*")
    .ifEmpty { exit 1, "Cannot find any reads matching: $readsDir/*R{1,2}*fastq*\nIf this is single-end data, please specify --singleEnd on the command line." }
    .into { read_pairs; raw_reads } 
    
/*
 * PREPROCESSING - Check config file integrity
 */
/*if(!params.c){
 *   exit 1, "No config file specified!" }
 */ 
 
/*
 * STEP 1.1 - FastQC
 */
process raw_fastqc {
    tag "$pair_id"
    publishDir "${resultsDir}/fastqc_raw", mode: 'symlink'
    module 'FastQC-0.11.3'

    input:
    set pair_id, file(reads) from read_pairs

    output:
    file '*R1_fastqc.zip' into raw_fastqc_results_zip_R1
    file '*R2_fastqc.zip' into raw_fastqc_results_zip_R2
    file '*.html' into raw_fastqc_results_html

    shell:
    '''
    sample=!{pair_id}
    lablog=${sample}.log
    
    echo "Step 1.1 - Running fastqc on !{reads}" >> $lablog
    
    echo "Command is: fastqc -q !{reads}" >> $lablog
    
    fastqc -q !{reads} 2>&1 >> $lablog
    
    echo "Step 1.1 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}
 
/*
 * STEP 1.2 - TRIMMING
 */ 
process trimming {
    tag "$name"
    module 'Trimmomatic-0.33'

    input:
    set val(name), file(reads) from raw_reads

    output:
    file '*_R1_paired.fastq' into trimmed_reads_R1, trimmed_paired_R1
    file '*_R2_paired.fastq' into trimmed_reads_R2, trimmed_paired_R2
    file '*_R1_unpaired.fastq' into trimmed_unpaired_R1
    file '*_R2_unpaired.fastq' into trimmed_unpaired_R2

    shell:
    '''
    sample=!{name}
    sample=${sample%_R*.fastq}
    lablog=${sample}.log
    
    echo "Step 1.2 - Trimming files !{reads}" >> $lablog
    
    echo "Command is: java -jar ${PathToTrimmomatic}/trimmomatic-0.33.jar PE -threads 10 -phred33 !{reads} ${sample}_R1_paired.fastq ${sample}_R1_unpaired.fastq ${sample}_R2_paired.fastq ${sample}_R2_unpaired.fastq ILLUMINACLIP:${PathToTrimmomatic}/adapters/NexteraPE-PE.fa:2:30:10 SLIDINGWINDOW:4:20 MINLEN:50" >> $lablog
    
    java -jar ${PathToTrimmomatic}/trimmomatic-0.33.jar PE -threads 10 -phred33 !{reads} ${sample}_R1_paired.fastq ${sample}_R1_unpaired.fastq ${sample}_R2_paired.fastq ${sample}_R2_unpaired.fastq ILLUMINACLIP:${PathToTrimmomatic}/adapters/NexteraPE-PE.fa:2:30:10 SLIDINGWINDOW:4:20 MINLEN:50 2>&1 >> $lablog
    
    echo "Step 1.2 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}

/*
 * STEP 1.3 - FastQC on trimmed reads
 */
process trimmed_fastqc {
    tag "$reads"
    publishDir "${resultsDir}/fastqc_trimmed", mode: 'symlink'
    module 'FastQC-0.11.3'

    input:
    file reads from trimmed_paired_R1.merge(trimmed_paired_R2)

    output:
    file '*R1_paired_fastqc.zip' into trimmed_fastqc_results_zip_R1
    file '*R2_paired_fastqc.zip' into trimmed_fastqc_results_zip_R2
    file '*.html' into trimmed_fastqc_results_html

    shell:
    '''
    sample="!{reads}"
    sample=($sample)
    sample=${sample[0]}
    sample=${sample%_R1_paired_fastqc.fastq}
    lablog=${sample}.log
    
    echo "Step 1.3 - Running fastqc on !{reads}" >> $lablog
    
    echo "Command is: fastqc -q !{reads}" >> $lablog
    
    fastqc -q !{reads} 2>&1 >> $lablog
    
    echo "Step 1.3 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}
 
 /*
 * STEP 1.4 - Generate Quality Statistics
 */
 process quality_fastqc {
     tag "$raw_reads"
     
     input:
     file raw_reads from raw_fastqc_results_zip_R1.concat(raw_fastqc_results_zip_R2)
     file trimmed_reads from trimmed_fastqc_results_zip_R1.concat(trimmed_fastqc_results_zip_R2)
     
     output:
     val "$sample" into quality_stats
     
     shell:
     '''
     mkdir -p ${resultsDir}/stats/data
     
     sample=!{raw_reads}
     sample=${sample%_fastqc.zip}
     dir=$sample
     dir=${dir%_R1*}
     dir=${dir%_R2*}
     
     if [[ $(echo $sample) =~ _R1 ]]
     then
         echo $dir >> ${resultsDir}/samples_id.txt
         dir=${dir}_R1
     else
         dir=${dir}_R2
     fi
     
     mkdir -p ${resultsDir}/stats/data/${dir}
     unzip !{raw_reads} -d ${resultsDir}/stats/data/$dir/${sample}_raw_fastqc
     mv ${resultsDir}/stats/data/$dir/${sample}_raw_fastqc/*/* ${resultsDir}/stats/data/$dir/${sample}_raw_fastqc/
     # rm -rf ${resultsDir}/stats/data/$dir/${sample}_raw_fastqc/$dir*
     
     sample=!{trimmed_reads}
     sample=${sample%_paired_fastqc.zip}
     dir=$sample
     dir=${dir%_R1*}
     dir=${dir%_R2*}
     
     if [[ $(echo $sample) =~ _R1 ]]
     then
         echo $dir >> ${resultsDir}/samples_id.txt
         dir=${dir}_R1
     else
         dir=${dir}_R2
     fi
     
     mkdir -p ${resultsDir}/stats/data/${dir}
     unzip !{trimmed_reads} -d ${resultsDir}/stats/data/$dir/${sample}_trimmed_fastqc
     mv ${resultsDir}/stats/data/$dir/${sample}_trimmed_fastqc/*/* ${resultsDir}/stats/data/$dir/${sample}_trimmed_fastqc/
     # rm -rf ${resultsDir}/stats/data/$dir/${sample}_raw_fastqc/$dir*
     '''
}
 
process quality_finish {
     tag "Finishing Quality Statistics"
     
     input:
     val x from quality_stats.count()
     
     output:
     val "$x" into stats_done
      
     shell:
     '''
     cat ${resultsDir}/samples_id.txt | sort -u > tmp
     mv tmp ${resultsDir}/samples_id.txt
     perl ${PIKAVIRUSDIR}/html/quality/listFastQCReports.pl ${resultsDir}/stats/data/ > ${resultsDir}/stats/table.html
     '''
}
 
 /*
 * STEP 2.1 - Host Removal
 */
process host_removal {
    tag "$sampleR1"
    publishDir "${resultsDir}/host/reads", mode: 'symlink'
    module 'bowtie/bowtie2-2.2.4:samtools/samtools-1.2'

    input:
    file sampleR1 from trimmed_reads_R1
    file sampleR2 from trimmed_reads_R2

    output:
    file "*_nohost_R1.fastq" into no_host_R1
    file "*_nohost_R2.fastq" into no_host_R2

    shell:
    '''
    sample=!{sampleR1}
    sample=${sample%.fastq}
    sample=${sample%_R1*}
    mappedSamFile=${sample}_mapped.sam
    mappedBamFile=${sample}_mapped.bam
    sortedBamFile=${sample}_sorted.bam
    mappedhost_bam=${sample}_host.bam
    # nohost_bam=${sample}_nohost.bam
    nohost_R1Fastq=${sample}_nohost_R1.fastq
    nohost_R2Fastq=${sample}_nohost_R2.fastq
    lablog=${sample}.log
    
    echo "Step 2.1 - Host Removal" >> $lablog
    
    echo "Command is: bowtie2 -fr -x $hostDB/WG/bwt2/hg38.AnalysisSet -q -1 !{sampleR1} -2 !{sampleR2} -S $mappedSamFile" >> $lablog
    
    #	BOWTIE2 MAPPING AGAINST HOS
    bowtie2 -fr -x $hostDB/WG/bwt2/hg38.AnalysisSet -q -1 !{sampleR1} -2 !{sampleR2} -S $mappedSamFile 2>&1 >> $lablog
    samtools view -Sb $mappedSamFile > $mappedBamFile
    samtools sort -O bam -T $sortedBamFile -o $sortedBamFile $mappedBamFile 2>&1 >> $lablog
    samtools index -b $sortedBamFile
    
    #	SEPARATE MAPPED READS AND FILTER HOST
    # samtools view -b -F 4 $sortedBamFile > $mappedhost_bam
    # samtools view -b -f 4 $sortedBamFile > $nohost_bam
    samtools view -F 0x40 $sortedBamFile | awk '{if($3 == "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $nohost_R1Fastq
    samtools view -f 0x40 $sortedBamFile | awk '{if($3 == "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $nohost_R2Fastq
    
    echo "Step 2.1 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}
 
 /*
 * STEP 2.2 - Mapping Bacteria
 */
process mapping_bacteria {
    tag "$noHostR1Fastq"
    publishDir "${resultsDir}/bacteria/reads", mode: 'symlink'
    module 'bowtie/bowtie2-2.2.4:samtools/samtools-1.2'

    input:
    file noHostR1Fastq from no_host_R1
    file noHostR2Fastq from no_host_R2

    output:
    file "*_bacteria.bam" into bacteria_bam
    file "*_bacteria_R1.fastq" into bacteria_R1
    file "*_bacteria_R2.fastq" into bacteria_R2
    file "*_nobacteria_R1.fastq" into no_bacteria_R1
    file "*_nobacteria_R2.fastq" into no_bacteria_R2

    shell:
    '''
    sample=!{noHostR1Fastq}
    sample=${sample%_nohost_R1.fastq}
    mappedSamFile=${sample}_mapped.sam
    mappedBamFile=${sample}_mapped.bam
    sortedBamFile=${sample}_sorted.bam
    mappedbacteria_bam=${sample}_bacteria.bam
    # nobacteria_bam=${sample}_nobacteria.bam
    BacteriaMappedR1Fastq=${sample}_bacteria_R1.fastq
    BacteriaMappedR2Fastq=${sample}_bacteria_R2.fastq
    noBacteriaMappedR1Fastq=${sample}_nobacteria_R1.fastq
    noBacteriaMappedR2Fastq=${sample}_nobacteria_R2.fastq
    lablog=${sample}.log
    
    echo "Step 2.2 - Mapping Bacteria" >> $lablog
    
    echo "Command is: bowtie2 -fr -x $bacDB/WG/bwt2/WG -q -1 !{noHostR1Fastq} -2 !{noHostR2Fastq} -S $mappedSamFile 2>&1 >> $lablog" >> $lablog
    
    #	BOWTIE2 MAPPING AGAINST BACTERIA
    bowtie2 -fr -x $bacDB/WG/bwt2/WG -q -1 !{noHostR1Fastq} -2 !{noHostR2Fastq} -S $mappedSamFile 2>&1 >> $lablog
    samtools view -Sb $mappedSamFile > $mappedBamFile
    samtools sort -O bam -T temp -o $sortedBamFile $mappedBamFile
    samtools index -b $sortedBamFile
    
    #	SEPARATE AND EXTRACT R1 AND R2 READS MAPPED TO WG
    samtools view -b -F 4 $sortedBamFile > $mappedbacteria_bam
    # samtools view -b -f 4 $sortedBamFile > $nobacteria_bam
    samtools view -F 0x40 $sortedBamFile | awk '{if($3 != "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $BacteriaMappedR1Fastq
    samtools view -f 0x40 $sortedBamFile | awk '{if($3 != "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $BacteriaMappedR2Fastq
    samtools view -F 0x40 $sortedBamFile | awk '{if($3 == "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $noBacteriaMappedR1Fastq
    samtools view -f 0x40 $sortedBamFile | awk '{if($3 == "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $noBacteriaMappedR2Fastq
    
    echo "Step 2.2 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}
 
 /*
 * STEP 2.3 - Mapping Virus
 */
process mapping_virus {
    tag "$noBacteriaR1Fastq"
    publishDir "${resultsDir}/virus/reads", mode: 'symlink'
    module 'bowtie/bowtie2-2.2.4:samtools/samtools-1.2'

    input:
    file noBacteriaR1Fastq from no_bacteria_R1
    file noBacteriaR2Fastq from no_bacteria_R2

    output:
    file "*_virus.bam" into virus_bam
    file "*_virus_R1.fastq" into virus_R1
    file "*_virus_R2.fastq" into virus_R2
    file "*_novirus_R1.fastq" into no_virus_R1
    file "*_novirus_R2.fastq" into no_virus_R2

    shell:
    '''
    sample=!{noBacteriaR1Fastq}
    sample=${sample%_nobacteria_R1.fastq}
    mappedSamFile=${sample}_mapped.sam
    mappedBamFile=${sample}_mapped.bam
    sortedBamFile=${sample}_sorted.bam
    mappedvirus_bam=${sample}_virus.bam
    # novirus_bam=${sample}_novirus.bam
    VirusMappedR1Fastq=${sample}_virus_R1.fastq
    VirusMappedR2Fastq=${sample}_virus_R2.fastq
    noVirusMappedR1Fastq=${sample}_novirus_R1.fastq
    noVirusMappedR2Fastq=${sample}_novirus_R2.fastq
    lablog=${sample}.log
    
    echo "Step 2.3 - Mapping Virus" >> $lablog
    
    echo "Command is: bowtie2 -a -fr -x $virDB/WG/bwt2/virus_all -q -1 !{noBacteriaR1Fastq} -2 !{noBacteriaR2Fastq} -S $mappedSamFile" >> $lablog
    
    #	BOWTIE2 MAPPING AGAINST VIRUS
    bowtie2 -a -fr -x $virDB/WG/bwt2/virus_all -q -1 !{noBacteriaR1Fastq} -2 !{noBacteriaR2Fastq} -S $mappedSamFile 2>&1 >> $lablog
    samtools view -Sb $mappedSamFile > $mappedBamFile
    samtools sort -O bam -T temp -o $sortedBamFile $mappedBamFile
    samtools index -b $sortedBamFile
    
    #	SEPARATE R1 AND R2 MAPPED READS AND FILTER HOST
    samtools view -b -F 4 $sortedBamFile > $mappedvirus_bam
    # samtools view -b -f 4 $sortedBamFile > $novirus_bam
    samtools view -F 0x40 $sortedBamFile | awk '{if($3 != "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $VirusMappedR1Fastq
    samtools view -f 0x40 $sortedBamFile | awk '{if($3 != "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $VirusMappedR2Fastq
    samtools view -F 0x40 $sortedBamFile | awk '{if($3 == "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $noVirusMappedR1Fastq
    samtools view -f 0x40 $sortedBamFile | awk '{if($3 == "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $noVirusMappedR2Fastq
    
    echo "Step 2.3 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}
 
 /*
 * STEP 2.4 - Mapping Fungi
 */
process mapping_fungi {
    tag "$noVirusR1Fastq"
    publishDir "${resultsDir}/fungi/reads", mode: 'symlink'
    module 'bowtie/bowtie2-2.2.4:samtools/samtools-1.2'

    input:
    file noVirusR1Fastq from no_virus_R1
    file noVirusR2Fastq from no_virus_R2

    output:
    file "*_fungi.bam" into fungi_bam
    file "*_fungi_R1.fastq" into fungi_R1
    file "*_fungi_R2.fastq" into fungi_R2
    file "*_nofungi_R1.fastq" into no_fungi_R1
    file "*_nofungi_R2.fastq" into no_fungi_R2

    shell:
    '''
    sample=!{noVirusR1Fastq}
    sample=${sample%_novirus_R1.fastq}
    mappedSamFile=${sample}_mapped.sam
    mappedBamFile=${sample}_mapped.bam
    sortedBamFile=${sample}_sorted.bam
    mappedfungi_bam=${sample}_fungi.bam
    # nofungi_bam=${sample}_nofungi.bam
    FungiMappedR1Fastq=${sample}_fungi_R1.fastq
    FungiMappedR2Fastq=${sample}_fungi_R2.fastq
    noFungiMappedR1Fastq=${sample}_nofungi_R1.fastq
    noFungiMappedR2Fastq=${sample}_nofungi_R2.fastq
    lablog=${sample}.log
    
    echo "Step 2.4 - Mapping Fungi" >> $lablog
    
    echo "Command is: bowtie2 -fr -x $fungiDB/WG/bwt2/fungi_all -q -1 !{noVirusR1Fastq} -2 !{noVirusR2Fastq} -S $mappedSamFile" >> $lablog
    
    #	BOWTIE2 MAPPING AGAINST FUNGI WG REFERENCE
    bowtie2 -fr -x $fungiDB/WG/bwt2/fungi_all -q -1 !{noVirusR1Fastq} -2 !{noVirusR2Fastq} -S $mappedSamFile 2>&1 >> $lablog
    samtools view -Sb $mappedSamFile > $mappedBamFile
    samtools sort -O bam -T temp -o $sortedBamFile $mappedBamFile
    samtools index -b $sortedBamFile
    
    #	SEPARATE R1 AND R2 MAPPED READS AND FILTER HOST
    samtools view -b -F 4 $sortedBamFile > $mappedfungi_bam
    # samtools view -b -f 4 $sortedBamFile > $nofungi_bam
    samtools view -F 0x40 $sortedBamFile | awk '{if($3 != "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $FungiMappedR1Fastq
    samtools view -f 0x40 $sortedBamFile | awk '{if($3 != "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $FungiMappedR2Fastq
    samtools view -F 0x40 $sortedBamFile | awk '{if($3 == "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $noFungiMappedR1Fastq
    samtools view -f 0x40 $sortedBamFile | awk '{if($3 == "*") print "@" $1 "\\n" $10 "\\n" "+" $1 "\\n" $11}' > $noFungiMappedR2Fastq
    
    echo "Step 2.4 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}
 
 /*
 * STEP 3.1 - Assembly Bacteria
 */
process assembly_bacteria {
    tag "$mappedR1Fastq"
    publishDir "${resultsDir}/bacteria/assembly", mode: 'symlink'
    module 'spades/spades-3.8.0:quast/quast-4.1'

    input:
    file mappedR1Fastq from bacteria_R1
    file mappedR2Fastq from bacteria_R2
    
    output:
    file "*_contigs.fa" into bacteria_contigs

    shell:
    '''
    sample=!{mappedR1Fastq}
    sample=${sample%_R1.fastq}
    contigs=${sample}_contigs.fa
    # transcripts=${sample}_transcripts.fa
    contigs_dir=${sample}_contigs
    quast_dir=${sample}_quast
    lablog=${sample}.log
    
    echo "Step 3.1 - Assembly bacteria" >> $lablog
    
    echo "Command is: spades.py --phred-offset 33 -1 !{mappedR1Fastq} -2 !{mappedR2Fastq} --meta -o $contigs_dir" >> $lablog
    
    mkdir $contigs_dir
    { # try
        spades.py --phred-offset 33 -1 !{mappedR1Fastq} -2 !{mappedR2Fastq} --meta -o $contigs_dir 2>&1 >> $lablog
    } || { # catch
        echo "SPADES was not able to assemble any contigs for $sample" >> $lablog
    }
    
    if [ -f $contigs_dir/contigs.fasta ]; then
        echo "Command is: metaquast.py -f $contigs_dir/contigs.fasta -o $quast_dir/" >> $lablog
        
        mkdir $quast_dir
        metaquast.py -f $contigs_dir/contigs.fasta -o $quast_dir/ 2>&1 >> $lablog
    else
       echo "QUAST can not run if SPADES did not find any contigs" >> $lablog
       
       touch $contigs_dir/contigs.fasta
    fi

    mv $contigs_dir/contigs.fasta $contigs

    echo "Step 3.1 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}

 /*
 * STEP 3.2 - Assembly Virus
 */
process assembly_virus {
    tag "$mappedR1Fastq"
    publishDir "${resultsDir}/virus/assembly", mode: 'symlink'
    module 'spades/spades-3.8.0:quast/quast-4.1'

    input:
    file mappedR1Fastq from virus_R1
    file mappedR2Fastq from virus_R2
    
    output:
    file "*_contigs.fa" into virus_contigs

    shell:
    '''
    sample=!{mappedR1Fastq}
    sample=${sample%_R1.fastq}
    contigs=${sample}_contigs.fa
    # transcripts=${sample}_transcripts.fa
    contigs_dir=${sample}_contigs
    quast_dir=${sample}_quast
    lablog=${sample}.log
    
    echo "Step 3.2 - Assembly Virus" >> $lablog
    
    echo "Command is: spades.py --phred-offset 33 -1 !{mappedR1Fastq} -2 !{mappedR2Fastq} --meta -o $contigs_dir" >> $lablog
    
    mkdir $contigs_dir
    { # try
        spades.py --phred-offset 33 -1 !{mappedR1Fastq} -2 !{mappedR2Fastq} --meta -o $contigs_dir 2>&1 >> $lablog
    } || { # catch
        echo "SPADES was not able to assemble any contigs for $sample" >> $lablog
    }
    
    if [ -f $contigs_dir/contigs.fasta ]; then
        echo "Command is: metaquast.py -f $contigs_dir/contigs.fasta -o $quast_dir/" >> $lablog
        
        mkdir $quast_dir
        metaquast.py -f $contigs_dir/contigs.fasta -o $quast_dir/ 2>&1 >> $lablog
    else
       echo "QUAST can not run if SPADES did not find any contigs" >> $lablog
       
       touch $contigs_dir/contigs.fasta
    fi

    cp $contigs_dir/contigs.fasta $contigs

    echo "Step 3.2 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}

 /*
 * STEP 3.3 - Assembly Fungi
 */
process assembly {
    tag "$mappedR1Fastq"
    publishDir "${resultsDir}/fungi/assembly", mode: 'symlink'
    module 'spades/spades-3.8.0:quast/quast-4.1'

    input:
    file mappedR1Fastq from fungi_R1
    file mappedR2Fastq from fungi_R2
    
    output:
    file "*_contigs.fa" into fungi_contigs

    shell:
    '''
    sample=!{mappedR1Fastq}
    sample=${sample%_R1.fastq}
    contigs=${sample}_contigs.fa
    # transcripts=${sample}_transcripts.fa
    contigs_dir=${sample}_contigs
    quast_dir=${sample}_quast
    lablog=${sample}.log
    
    echo "Step 3.3 - Assembly Fungi" >> $lablog
    
    echo "Command is: spades.py --phred-offset 33 -1 !{mappedR1Fastq} -2 !{mappedR2Fastq} --meta -o $contigs_dir" >> $lablog
    
    mkdir $contigs_dir
    { # try
        spades.py --phred-offset 33 -1 !{mappedR1Fastq} -2 !{mappedR2Fastq} --meta -o $contigs_dir 2>&1 >> $lablog
    } || { # catch
        echo "SPADES was not able to assemble any contigs for $sample" >> $lablog
    }
    
    if [ -f $contigs_dir/contigs.fasta ]; then
        echo "Command is: metaquast.py -f $contigs_dir/contigs.fasta -o $quast_dir/" >> $lablog
        
        mkdir $quast_dir
        metaquast.py -f $contigs_dir/contigs.fasta -o $quast_dir/ 2>&1 >> $lablog
    else
       echo "QUAST can not run if SPADES did not find any contigs" >> $lablog
       
       touch $contigs_dir/contigs.fasta
    fi
    
    cp $contigs_dir/contigs.fasta $contigs

    echo "Step 3.3 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}
 
 /*
 * STEP 4.1 - Blast Bacteria
 */
process blast_bacteria {
    tag "$bacteriaContig"
    publishDir "${resultsDir}/bacteria/blast", mode: 'symlink'
    module 'ncbi-blast/ncbi_blast-2.2.30+'

    input:
    file bacteriaContig from bacteria_contigs
    
    output:
    file "*_BLASTn_filtered.blast" into bacteria_blast

    shell:
    '''
    sample=!{bacteriaContig}
    sample=${sample%_contigs.fa}
    blastnResult=${sample}_BLASTn.blast
    blastnResultFiltered=${sample}_BLASTn_unsorted.blast
    blastnResultSorted=${sample}_BLASTn_filtered.blast
    lablog=${sample}.log
    
    echo "Step 4.1 - Blast Bacteria" >> $lablog
    
    echo "Command is: blastn -db ${bacDB}BLAST/blastn/BACTERIA_blastn -query !{bacteriaContig} -outfmt '6 stitle std qseq' > $blastnResult" >> $lablog
    
    # RUN BLASTn
    { # try
        blastn -db ${bacDB}BLAST/blastn/BACTERIA_blastn -query !{bacteriaContig} -outfmt '6 stitle std qseq' > $blastnResult
    } || { # catch
        echo "Query is Empty!" >> $lablog
        
        touch $blastnResult
    }
    awk -F "\t" '{if($4 >= 90 && $5>= 100) print $0}' $blastnResult > $blastnResultFiltered
    sort -k1 $blastnResultFiltered > $blastnResultSorted

    echo "Step 4.1 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}

 /*
 * STEP 4.2 - Blast Virus
 */
process blast_virus {
    tag "$virusContig"
    publishDir "${resultsDir}/virus/blast", mode: 'symlink'
    module 'ncbi-blast/ncbi_blast-2.2.30+'

    input:
    file virusContig from virus_contigs

    output:
    file "*_BLASTn_filtered.blast" into virus_blast
    
    shell:
    '''
    sample=!{virusContig}
    sample=${sample%_contigs.fa}
    blastnResult=${sample}_BLASTn.blast
    blastnResultFiltered=${sample}_BLASTn_unsorted.blast
    blastnResultSorted=${sample}_BLASTn_filtered.blast
    lablog=${sample}.log
    
    echo "Step 4.2 - Blast Virus" >> $lablog
    
    echo "Command is: blastn -db ${virDB}BLAST/blastn/VIRUS_blastn -query !{virusContig} -outfmt '6 stitle std qseq' > $blastnResult" >> $lablog
    
    # RUN BLASTn
    { # try
        blastn -db ${virDB}BLAST/blastn/VIRUS_blastn -query !{virusContig} -outfmt '6 stitle std qseq' > $blastnResult
    } || { # catch
        echo "Query is Empty!" >> $lablog
        
        touch $blastnResult
    }
    awk -F "\t" '{if($4 >= 90 && $5>= 100) print $0}' $blastnResult > $blastnResultFiltered
    sort -k1 $blastnResultFiltered > $blastnResultSorted
   
    echo "Step 4.2 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}

 /*
 * STEP 4.3 - Blast Fungi
 */
process blast_fungi {
    tag "$fungiContig"
    publishDir "${resultsDir}/fungi/blast", mode: 'symlink'
    module 'ncbi-blast/ncbi_blast-2.2.30+'

    input:
    file fungiContig from fungi_contigs
    
    output:
    file "*_BLASTn_filtered.blast" into fungi_blast

    shell:
    '''
    sample=!{fungiContig}
    sample=${sample%_contigs.fa}
    blastnResult=${sample}_BLASTn.blast
    blastnResultFiltered=${sample}_BLASTn_unsorted.blast
    blastnResultSorted=${sample}_BLASTn_filtered.blast
    lablog=${sample}.log
    
    echo "Step 4.3 - Fungi Bacteria" >> $lablog
    
    echo "Command is: blastn -db ${fungiDB}BLAST/blastn/FUNGI_blastn -query !{fungiContig} -outfmt '6 stitle std qseq'" >> $lablog
    
    # RUN BLASTn
    { # try
        blastn -db ${fungiDB}BLAST/blastn/FUNGI_blastn -query !{fungiContig} -outfmt '6 stitle std qseq' >> $blastnResult
    } || { # catch
        echo "Query is Empty!" >> $lablog
        
        touch $blastnResult
    }
    awk -F "\t" '{if($4 >= 90 && $5>= 100) print $0}' $blastnResult > $blastnResultFiltered
    sort -k1 $blastnResultFiltered > $blastnResultSorted
  
    echo "Step 4.3 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}
 
 /*
 * STEP 5.1 - Coverage Bacteria
 */
process coverage_bacteria {
    tag "$sampleBam"
    publishDir "${resultsDir}/bacteria/coverage", mode: 'symlink'
    module 'bedtools2/bedtools2-2.25.0:R/R-3.2.5'

    input:
    file sampleBam from bacteria_bam
    
    output:
    file "*_coverageTable.txt" into bacteria_coverage

    shell:
    '''
    sample=!{sampleBam}
    sample=${sample%.bam}
    genomeLength=${bacDB}/WG/genome_length.txt
    genomeCov=${sample}_genome_coverage.txt
    genomeGraph=${sample}_genome_bedgraph.txt
    lablog=${sample}.log
    
    echo "Step 5.1 - Coverage" >> $lablog
    
    echo "Command is: bedtools genomecov -ibam !{sampleBam} -g $genomeLength > $genomeCov" >> $lablog
    
    # COVERAGE TABLE
    bedtools genomecov -ibam !{sampleBam} -g $genomeLength > $genomeCov
    
    echo "Command is: bedtools genomecov -ibam !{sampleBam} -g $genomeLength -bga > $genomeGraph" >> $lablog
    
    # COVERAGE BEDGRAPH
    bedtools genomecov -ibam !{sampleBam} -g $genomeLength -bga > $genomeGraph
    
    echo "Command is: Rscript --vanilla ${PIKAVIRUSDIR}/graphs_coverage.R $( pwd )/ $sample" >> $lablog
    
    # R summary
    Rscript --vanilla ${PIKAVIRUSDIR}/graphs_coverage.R "$( pwd )/" $sample

    echo "Step 5.1 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}

 /*
 * STEP 5.2 - Coverage Virus
 */
process coverage_virus {
    tag "$sampleBam"
    publishDir "${resultsDir}/virus/coverage", mode: 'symlink'
    module 'bedtools2/bedtools2-2.25.0:R/R-3.2.5'

    input:
    file sampleBam from virus_bam
    
    output:
    file "*_coverageTable.txt" into virus_coverage

    shell:
    '''
    sample=!{sampleBam}
    sample=${sample%.bam}
    genomeLength=${bacDB}/WG/genome_length.txt
    genomeCov=${sample}_genome_coverage.txt
    genomeGraph=${sample}_genome_bedgraph.txt
    lablog=${sample}.log
    
    echo "Step 5.2 - Coverage Virus" >> $lablog
    
    echo "Command is: bedtools genomecov -ibam !{sampleBam} -g $genomeLength > $genomeCov" >> $lablog
    
    # COVERAGE TABLE
    bedtools genomecov -ibam !{sampleBam} -g $genomeLength > $genomeCov
    
    echo "Command is: bedtools genomecov -ibam !{sampleBam} -g $genomeLength -bga > $genomeGraph" >> $lablog
    
    # COVERAGE BEDGRAPH
    bedtools genomecov -ibam !{sampleBam} -g $genomeLength -bga > $genomeGraph
    
    echo "Command is: Rscript --vanilla ${PIKAVIRUSDIR}/graphs_coverage.R $( pwd )/ $sample" >> $lablog
    
    # R summary
    Rscript --vanilla ${PIKAVIRUSDIR}/graphs_coverage.R "$( pwd )/" $sample

    echo "Step 5.2 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}

 /*
 * STEP 5.3 - Coverage Fungi
 */
process coverage_fungi {
    tag "$sampleBam"
    publishDir "${resultsDir}/fungi/coverage", mode: 'symlink'
    module 'bedtools2/bedtools2-2.25.0:R/R-3.2.5'

    input:
    file sampleBam from fungi_bam
    
    output:
    file "*_coverageTable.txt" into fungi_coverage

    shell:
    '''
    sample=!{sampleBam}
    sample=${sample%.bam}
    genomeLength=${bacDB}/WG/genome_length.txt
    genomeCov=${sample}_genome_coverage.txt
    genomeGraph=${sample}_genome_bedgraph.txt
    lablog=${sample}.log
    
    echo "Step 5.3 - Coverage Fungi" >> $lablog
    
    echo "Command is: bedtools genomecov -ibam !{sampleBam} -g $genomeLength > $genomeCov" >> $lablog
    
    # COVERAGE TABLE
    bedtools genomecov -ibam !{sampleBam} -g $genomeLength > $genomeCov
    
    echo "Command is: bedtools genomecov -ibam !{sampleBam} -g $genomeLength -bga > $genomeGraph" >> $lablog
    
    # COVERAGE BEDGRAPH
    bedtools genomecov -ibam !{sampleBam} -g $genomeLength -bga > $genomeGraph
    
    echo "Command is: Rscript --vanilla ${PIKAVIRUSDIR}/graphs_coverage.R $( pwd )/ $sample" >> $lablog
    
    # R summary
    Rscript --vanilla ${PIKAVIRUSDIR}/graphs_coverage.R "$( pwd )/" $sample

    echo "Step 5.3 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}
 
 /*
 * STEP 6 - Generate Results
 */
process generate_summary_tables {
    tag "$blast_table"
    
    input:
    file blast_table from bacteria_blast.concat(virus_blast, fungi_blast)
    file coverage_table from bacteria_coverage.concat(virus_coverage, fungi_coverage)
    
    output:
    file "*_summary.tsv" into summary_tables
    
    beforeScript "mkdir -p ${resultsDir}/results/summary_tables"
    
    shell:
    '''
    lablog=results.log
    
    echo "Step 6 - Generate Results" >> $lablog
    
    # Create summary tables
    perl ${PIKAVIRUSDIR}/summary_tables.pl !{blast_table} !{coverage_table}
    cp *_summary.tsv ${resultsDir}/results/summary_tables
    '''
}

process generate_results {
    tag "results"
    module 'R/R-3.2.5'
    
    input:
    val x from summary_tables.count()
    val y from stats_done.count()
    
    shell:
    '''
    lablog=results.log
    
    # Copy logos and icons
    echo -e "Started copying logos and icons\n" >> $lablog
    echo -e "Finished copying logos and icons into $resultsDir" >> $lablog
    
    # Info page
    echo -e "Started creating info page\n" >> $lablog
    cat ${PIKAVIRUSDIR}/html/header.html > ${resultsDir}/results/info.html
    cat ${PIKAVIRUSDIR}/html/info/info_template.html >> ${resultsDir}/results/info.html
    cat ${PIKAVIRUSDIR}/html/footer.html >> ${resultsDir}/results/info.html
    echo -e "Finished creating info page" >> $lablog
    
    # Quality report
    echo -e "Started creating quality report\n" >> $lablog
    cp -r ${resultsDir}/stats/data ${resultsDir}/results/quality
    cp ${resultsDir}/stats/table.html ${resultsDir}/results/quality/table.html
    cat ${PIKAVIRUSDIR}/html/header.html > ${resultsDir}/results/quality.html
    cat ${PIKAVIRUSDIR}/html/quality/quality_template_1.html >> ${resultsDir}/results/quality.html
    cat ${resultsDir}/results/quality/table.html >> ${resultsDir}/results/quality.html
    cat ${PIKAVIRUSDIR}/html/quality/quality_template_2.html >> ${resultsDir}/results/quality.html
    cat ${PIKAVIRUSDIR}/html/footer.html >> ${resultsDir}/results/quality.html
    # rm ${resultsDir}/results/quality/table.html
    # rm -rf ${resultsDir}/stats
    echo -e "Finished creating quality report" >> $lablog
    
    # Per sample report
    mkdir -p "${resultsDir}/results/data/persamples"
    for organism in bacteria virus fungi
    do
        cat ${resultsDir}/samples_id.txt | while read sample
        do
            echo -e "$sample" >> $lablog
            # Create results table
            echo -e "\t$(date)\t Create results table (.txt)" >> $lablog
            echo -e "\t$(date)\t Rscript ${PIKAVIRUSDIR}/mergeResults.R $sample $organism $resultsDir $resultsDir/results/" >> $lablog
            Rscript ${PIKAVIRUSDIR}/html/persample/mergeResults.R $sample $organism $resultsDir/ $resultsDir/results/ 2>&1 >> $lablog
            # Create results html
            echo -e "\t$(date)\t Create results html file" >> $lablog
            echo -e "\t$(date)\t ${PIKAVIRUSDIR}/html/persample/createResultHtml.sh ${sample} ${organism}" >> $lablog
            bash ${PIKAVIRUSDIR}/html/persample/createResultHtml.sh ${sample} ${organism} 2>&1 >> $lablog
        done
    done
    bash ${PIKAVIRUSDIR}/html/persample/createSamplesHtml.sh 2>&1 >> $lablog

    # Summary
    mkdir -p ${resultsDir}/results/data/summary/
    for organism in bacteria virus fungi
    do
        cat ${resultsDir}/samples_id.txt | while read sample
        do
            echo -e "\t$sample" >> $lablog
            # Generate taxonomy statistics
            echo -e "\t\t$(date)\t Generate statistics" >> $lablog
            echo -e "\t\t${PIKAVIRUSDIR}/html/summary/statistics.sh ${resultsDir} ${organism} ${sample}" >> $lablog
            bash ${PIKAVIRUSDIR}/html/summary/statistics.sh ${resultsDir} ${organism} ${sample} 2>&1 >> $lablog
            # Copy statistics files to RESULTS data folder
            cp "${resultsDir}/${organism}/taxonomy/${sample}_${organism}_statistics.txt" "${resultsDir}/results/data/summary/" 2>&1 >> $lablog
        done
    done
    
    # Generates the html file once the txt statistics are finished and copied.
    echo -e "$(date)\t Create summary html file:" >> $lablog
    echo -e "${PIKAVIRUSDIR}/html/summary/createSummaryHtml.sh" >> $lablog
    bash ${PIKAVIRUSDIR}/html/summary/createSummaryHtml.sh 2>&1 >> $lablog
    
    echo "Step 6 - Complete!" >> $lablog
    echo "-------------------------------------------------" >> $lablog
    '''
}