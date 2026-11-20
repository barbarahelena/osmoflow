# barbarahelena/osmoflow: Output

## Introduction

This document describes the output produced by the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [Database](#database) - The `osmo_refdb` reference database (only if downloaded by the pipeline)
- [Read preprocessing](#read-preprocessing) - fastp and Bowtie2 reports and read counts (only for the steps that were enabled)
- [Profile](#profile) - `osmotool profile` results for FASTQ-reads samples
- [Annotate](#annotate) - `osmotool annotate` results for assembly samples
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### Database

<details markdown="1">
<summary>Output files</summary>

- `database/`
  - `refdb/<release>/`: the unpacked `osmo_refdb` release, only present when `--osmo_db` was not provided.

</details>

### Read preprocessing

Only present for the steps that were enabled (see [Optional read preprocessing](usage.md#optional-read-preprocessing)).
The fastp and Bowtie2 reports are written per run: a sample with several runs (see [Run merging](usage.md#run-merging))
has one report per run, named `<sample>_<run_accession>`; a sample without a `run_accession` is named `<sample>`.
The preprocessed reads themselves (trimmed, host-filtered, merged, subsampled) are not saved.

<details markdown="1">
<summary>Output files</summary>

- `fastp/` (`--fastp`)
  - `<sample>[_<run_accession>].fastp.html`, `.fastp.json`: fastp quality-control report.
  - `<sample>[_<run_accession>].fastp.log`: fastp log.
- `bowtie2/` (`--host_bowtie2_index` / `--host_fasta`)
  - `<sample>[_<run_accession>].bowtie2.log`: Bowtie2 alignment summary (the share of reads that mapped to the host).
  - `<sample>[_<run_accession>].stats`: `samtools stats` of the alignment to the host.
- `readcounts/` (`--readcounts`)
  - `readcounts.csv`: columns `sample`, `stage`, `reads`, with a `raw` row (the reads in the samplesheet's FASTQ files, all runs added up) and a `final` row (the reads that went into `osmotool profile`) per sample. The counts come from the preprocessing steps' own reports (fastp's JSON, Bowtie2's log, subsampling), counting R1 only, so for paired-end data these are read pairs: the same fragments that osmotool's RPM is per million of (`# total_fragments` in `gene_counts.tsv`).

</details>

### Profile

<details markdown="1">
<summary>Output files</summary>

- `profile/<sample>/`
  - `<sample>.gene_counts.tsv`: per-gene `raw_count`, `RPM` (depth-normalised abundance) and `copies_per_genome` for each osmoadaptation gene family. Counts are in fragments, a read pair (each mate weighs 0.5) or a single-end read, and RPM is per million fragments (`# total_fragments` in the header), so paired-end and single-end samples give comparable values. When the `osmo_refdb` release ships a gene catalog (osmo_refdb v10+), reads are first assigned by nucleotide matching against the catalog, and the table also has `catalog_count` (reads assigned by the catalog), `catalog_ambiguous` (reads with valid placements on several families, split equally over them and not in `raw_count`) and `translated_count` (reads counted by the translated DIAMOND search); `raw_count` is `catalog_count + translated_count`. See the [osmotool README](https://github.com/barbarahelena/osmotool#gene-catalog-profile---catalog).
  - `<sample>.aln_stats.tsv`: alignment summary statistics (`total_fragments`, `fragments_assigned`, `pct_fragments_assigned`, ...).
- `profile/profile_<column>.tsv`, e.g. `profile_raw_count.tsv`, `profile_rpm.tsv`, `profile_copies_per_genome.tsv` and, with a catalog, `profile_catalog_count.tsv`, `profile_catalog_ambiguous.tsv`, `profile_translated_count.tsv`
  - Merged gene x sample matrices, one per value column: one row per gene, one column per profiled sample. Only produced when at least one sample was profiled.

</details>

Produced by `osmotool profile` (DIAMOND blastx) for samplesheet rows with `fastq_1`[, `fastq_2`].

### Annotate

<details markdown="1">
<summary>Output files</summary>

- `annotate/<sample>/`
  - `<sample>.gene_counts.tsv`: per-gene raw counts and `copies_per_kb` (gene-copy-number statistic) for each osmoadaptation gene family.
  - `<sample>.aln_stats.tsv`: alignment summary statistics.
  - `<sample>.systems.tsv`: multi-subunit system calls (e.g. `ect`), with presence, subunit count and co-localisation on a contig.
  - `<sample>.gene_coordinates.tsv`: contig, start, end and strand of each called osmoadaptation gene.
- `annotate/annotate_raw_count.tsv`, `annotate/annotate_copies_per_kb.tsv`
  - Merged gene x sample matrices, one per value column: one row per gene, one column per annotated sample. Only produced when at least one sample was annotated.
- `annotate/merged_systems.tsv`, `annotate/merged_gene_coordinates.tsv`
  - The `systems.tsv` and `gene_coordinates.tsv` of all assemblies in one long-format table each, with the sample in the first column. Only produced when at least one assembly has the file.

</details>

Produced by `osmotool annotate` (Prodigal + DIAMOND/HMMER) for samplesheet rows with `fasta`.

> [!NOTE]
> `profile` (RPM) and `annotate` (`copies_per_kb`) values measure different things and are not directly comparable — see the [osmotool README](https://github.com/barbarahelena/osmotool#output).

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report_<timestamp>.html`, `execution_timeline_<timestamp>.html`, `execution_trace_<timestamp>.txt` and `pipeline_dag_<timestamp>.html`.
  - Software versions of every tool the run used: `osmoflow_software_versions.yml`.
  - Parameters used by the pipeline run: `params_<timestamp>.json`.
  - `pipeline_report.html` and `pipeline_report.txt`, only when `--email` / `--email_on_fail` is used.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
