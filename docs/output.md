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

- `profile/profile_unit_raw_count.tsv`, `profile/profile_unit_rpm.tsv`
  - **The profile results.** Unit x sample matrices of `raw_count` (fragments: a read pair, each mate weighing 0.5, or a single-end read) and `RPM` (per million fragments of the sample), one row per reporting unit, one column per profiled sample. Built from each sample's `unit_counts.tsv`, which applies the `osmo_refdb` release's report levels (`osmo_refdb.profile_report_levels.tsv`, decided on the release's calibration reads):
    - a `gene` unit is one gene family, with the same count as in `gene_counts.tsv`;
    - a `group` unit (e.g. `opu_permease`) is the summed count of close paralogs that a short read cannot tell apart;
    - a `none` unit (e.g. `opuAC`) is not reliable on short reads and is `NA` in every sample. `NA` means "not measured reliably", never "gene absent".
  - Units are in the release's order, which keeps related units together (ect, opu, mrp, trk/ktr).
- `profile/profile_read_sources.tsv`
  - One long table, one row per sample and unit: `sample`, `unit`, `report_level`, `members`, `status` and `raw_count`, and with a gene catalog also `catalog_count`, `catalog_ambiguous` and `translated_count`. Use it to check where a unit's reads came from:
    - `catalog_count`: reads settled by near-exact nucleotide matching to a gene in the release's catalog;
    - `translated_count`: reads the catalog did not settle, called by the translated DIAMOND search; `raw_count` is `catalog_count + translated_count`;
    - `catalog_ambiguous`: reads with valid catalog placements on several families, split equally over them and not in `raw_count`.
  - `status` is `reported` (gene or group units), `excluded` or `catalog_only` (`none` units; `catalog_only` gives their catalog counts, with `raw_count` NA, for the units whose catalog counts the release says can be reported: v11 decides this per unit, while with v10, which doesn't say, `none` units are `excluded`) or `not_in_manifest` (a reference label with reads that belongs to no unit, e.g. a fused-ORF reference; these rows are not in the matrices).
- `profile/<sample>/`
  - `<sample>.unit_counts.tsv`: the per-sample table the matrices above are built from. See the [osmotool README](https://github.com/barbarahelena/osmotool#report-units-profile-mode).
  - `<sample>.gene_counts.tsv`: per-gene `raw_count`, `RPM` and `copies_per_genome` (reads per kb of the gene relative to ten single-copy marker genes), and with a gene catalog `catalog_count`, `catalog_ambiguous` and `translated_count`, for every gene family on its own, without the report levels. See the [osmotool README](https://github.com/barbarahelena/osmotool#gene-catalog-profile---catalog).
  - `<sample>.aln_stats.tsv`: alignment summary statistics (`total_fragments`, `fragments_assigned`, `pct_fragments_assigned`, ...).
- `profile/profile_<column>.tsv` (only with `--profile_gene_matrices`), e.g. `profile_raw_count.tsv`, `profile_rpm.tsv`, `profile_copies_per_genome.tsv` and, with a catalog, `profile_catalog_count.tsv`, `profile_catalog_ambiguous.tsv`, `profile_translated_count.tsv`
  - Gene x sample matrices, one per column of `gene_counts.tsv`. They ignore the report levels: every gene family is listed on its own, including those that are not reliable on short reads.

</details>

Produced by `osmotool profile` (the release's gene catalog first, then DIAMOND translated search for the other reads) for samplesheet rows with `fastq_1`[, `fastq_2`]. Needs `osmo_refdb` v10 or later: the pipeline stops before profiling when the release has no `osmo_refdb.profile_report_levels.tsv`.

### Annotate

<details markdown="1">
<summary>Output files</summary>

- `annotate/annotate_unit_raw_count.tsv`, `annotate/annotate_unit_copies_per_kb.tsv` (`osmo_refdb` v11 or later)
  - Unit x sample matrices of `raw_count` (proteins) and `copies_per_kb`, one row per reporting unit, one column per annotated sample. Built from each sample's `unit_counts.tsv`, which applies the release's annotate report levels (`osmo_refdb.annotate_report_levels.tsv`, decided on full-length calibration proteins with `--method hmm`), like the profile unit matrices above: a `gene` unit is one family, a `group` unit sums close paralogs, and a `none` unit is `NA` in every sample, never 0. A family with no called protein counts 0. The annotate report levels are not the profile ones, so a unit can be reported in one mode and `NA` in the other.
  - Releases before v11 have no annotate report levels: these matrices and the per-sample `unit_counts.tsv` are then not produced.
- `annotate/<sample>/`
  - `<sample>.unit_counts.tsv` (`osmo_refdb` v11 or later): the per-sample table the unit matrices are built from.
  - `<sample>.gene_counts.tsv`: per-gene raw counts and `copies_per_kb` (gene-copy-number statistic) for each osmoadaptation gene family, every family on its own, without the report levels.
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
