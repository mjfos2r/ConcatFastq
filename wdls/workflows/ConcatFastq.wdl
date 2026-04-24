version 1.0
import "../structs/Structs.wdl"

workflow ConcatFastq {
    meta {
        description: "concat two fastq files together, generate simple reads stats for all files and the resulting output."
        author: "Michael J. Foster"
    }

    parameter_meta {
        fastq_1: "first fastq file to concat"
        fastq_2: "second fastq file to concat"
        sample_id: "our sample id, [optional: can default to basename of fastq_1"
    }

    input {
        File fastq_1
        File fastq_2
        String? sample_id
        RuntimeAttr? runtime_attr_override
    }

    # call our first task/workflow
    call Concatenate {
        input:
        fastq_1 = fastq_1,
        fastq_2 = fastq_2,
        sample_id = sample_id
    }

    output {
        File merged_fastq = Concatenate.merged_fastq
        File merged_seq_stats = Concatenate.merged_seq_stats
    }
}

task Concatenate {
    meta {
        description: "concat two fastq files together, generate simple reads stats for all files and the resulting output."
        author: "Michael J. Foster"
    }

    parameter_meta {
        fastq_1: "first fastq file to concat"
        fastq_2: "second fastq file to concat"
        sample_id: "our sample id, [optional: can default to basename of fastq_1"
    }

    input {
        File fastq_1
        File fastq_2
        String? sample_id
        RuntimeAttr? runtime_attr_override
    }

    String bn_input = basename(fastq_1)
    String fn_raw = select_first([sample_id, bn_input])
    String fn_clean = sub(fn_raw, "\\.fastq$", "")
    Float input_size = size([fastq_1, fastq_2], "GB")
    Int disk_size = 365 + 3*ceil(input_size)

    command <<<
    set -euo pipefail # if anything breaks crash out

    # get the number of procs we have available
    NPROCS=$( cat /proc/cpuinfo | grep '^processor' | tail -n1 | awk '{print $NF+1}' )

    echo "concatenating both fastq files provided and saving to:"
    echo "~{fn_clean}_combined.fastq.gz"
    cat ~{fastq_1} ~{fastq_2} > ~{fn_clean}_combined.fastq.gz
    echo "grabbing stats of both input and the concatenated output files..."
    seqkit stats -aT -i ~{fastq_1} > fq_1_stats.tsv
    seqkit stats -aT -i ~{fastq_2} | tail -n1 > fq_2_stats.tsv
    seqkit stats -aT -i ~{fn_clean}_combined.fastq.gz | tail -n1 > fq_m_stats.tsv

    cat fq_1_stats.tsv fq_2_stats.tsv fq_m_stats.tsv > fq_all_stats.tsv
    >>>

    output {
        File merged_fastq = "~{fn_clean}_combined.fastq.gz"
        File merged_seq_stats = "fq_all_stats.tsv"
    }

    RuntimeAttr default_attr = object {
        cpu_cores:          4,
        mem_gb:             16,
        disk_gb:            disk_size,
        boot_disk_gb:       50,
        preemptible_tries:  0,
        max_retries:        1,
        docker:             "mjfos2r/align-tools:latest"
    }
    RuntimeAttr runtime_attr = select_first([runtime_attr_override, default_attr])
    runtime {
        cpu:                    select_first([runtime_attr.cpu_cores,         default_attr.cpu_cores])
        memory:                 select_first([runtime_attr.mem_gb,            default_attr.mem_gb]) + " GiB"
        disks: "local-disk " +  select_first([runtime_attr.disk_gb,           default_attr.disk_gb]) + " SSD"
        bootDiskSizeGb:         select_first([runtime_attr.boot_disk_gb,      default_attr.boot_disk_gb])
        preemptible:            select_first([runtime_attr.preemptible_tries, default_attr.preemptible_tries])
        maxRetries:             select_first([runtime_attr.max_retries,       default_attr.max_retries])
        docker:                 select_first([runtime_attr.docker,            default_attr.docker])
    }
}