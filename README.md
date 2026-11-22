# barbarahelena/osmoflow

[![Open in GitHub Codespaces](https://img.shields.io/badge/Open_In_GitHub_Codespaces-black?labelColor=grey&logo=github)](https://github.com/codespaces/new/barbarahelena/osmoflow)
[![Cite with Zenodo](http://img.shields.io/badge/DOI-10.5281/zenodo.XXXXXXX-1073c8?labelColor=000000)](https://doi.org/10.5281/zenodo.XXXXXXX)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A526.10.0-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-3.5.2-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/3.5.2)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Seqera Platform](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Seqera%20Platform-%234256e7)](https://cloud.seqera.io/launch?pipeline=https://github.com/barbarahelena/osmoflow)

## Introduction

**barbarahelena/osmoflow** screens osmoadaptation genes (ectA/ectB/ectC, betL, kdpA, nhaA) in metagenomic data using
[osmotool](https://github.com/barbarahelena/osmotool). Depending on what each samplesheet row provides, a sample is
routed through one of osmotool's two modes: paired/single-end FASTQ reads are screened with `osmotool profile`
(DIAMOND blastx, optionally cascaded to HMMER), and assembly FASTA files are screened with `osmotool annotate`
(Prodigal + DIAMOND/HMMER). The `osmo_refdb` reference database is downloaded automatically from Zenodo unless you
already have a local copy.

The pipeline runs these steps:

1. **Read preprocessing** (FASTQ samples only, every step optional and off by default):
    - **`FASTP`** — quality filtering and adapter trimming (`--fastp`)
    - **`BOWTIE2_FILTERHOST`** — removal of host (e.g. human) reads with Bowtie2 (`--host_bowtie2_index`, or `--host_fasta` to build the index with **`BOWTIE2_BUILD`**)
    - **`CAT_FASTQ`** — merging the runs of a sample (samplesheet rows with the same sample name) (`--perform_runmerging`)
    - **`SEQKIT_SAMPLE`** — subsampling to an equal number of reads (pairs) per sample (`--subsamplelevel`)
    - **Read counts** — a table of read counts per sample before and after preprocessing (`--readcounts`), taken from the fastp, Bowtie2 and subsampling reports; a separate **`READCOUNT`** job only runs when none of those steps does
2. **`OSMOTOOL_DOWNLOAD_DB`** — downloads and unpacks an `osmo_refdb` release, unless `--osmo_db` points at one already
3. **`OSMOTOOL_PROFILE`** — runs `osmotool profile` on samplesheet rows with `fastq_1`[, `fastq_2`]
4. **`OSMOTOOL_ANNOTATE`** — runs `osmotool annotate` on samplesheet rows with `fasta`
5. **`OSMOTOOL_MERGE_COUNTS`** — merges each mode's per-sample `gene_counts.tsv` into one gene x sample matrix per value column (e.g. `profile_raw_count.tsv`, `profile_rpm.tsv`, `profile_copies_per_genome.tsv` and, when the `osmo_refdb` release ships a gene catalog, `profile_catalog_count.tsv`, `profile_catalog_ambiguous.tsv`, `profile_translated_count.tsv`; `annotate_raw_count.tsv`, `annotate_copies_per_kb.tsv`); the two modes are never merged together since RPM and `copies_per_kb` aren't comparable
6. **`OSMOTOOL_MERGE_SYSTEMS`** and **`OSMOTOOL_MERGE_GENE_COORDINATES`** — merge each bin's `*.systems.tsv` and `*.gene_coordinates.tsv` from `OSMOTOOL_ANNOTATE` into one long-format `merged_systems.tsv` and `merged_gene_coordinates.tsv`; only run when at least one `annotate`-mode sample produced them

## Usage

> [!NOTE]
> The pipeline needs Nextflow 26.10.0 or later (it uses Nextflow's static typing). If you are new to Nextflow, please refer to [this page](https://nf-co.re/docs/usage/installation) on how to set up Nextflow. Make sure to [test your setup](https://nf-co.re/docs/usage/introduction#how-to-run-a-pipeline) with `-profile test` before running the workflow on actual data.

First, prepare a samplesheet with your input data. Each row is *either* FASTQ reads *or* an assembly, not both:

`samplesheet.csv`:

```csv
sample,fastq_1,fastq_2,fasta
SAMPLE_PAIRED_END,reads/sample1_R1.fastq.gz,reads/sample1_R2.fastq.gz,
SAMPLE_SINGLE_END,reads/sample2.fastq.gz,,
SAMPLE_ASSEMBLY,,,assemblies/sample3.fasta
```

Now, you can run the pipeline using:

```bash
nextflow run barbarahelena/osmoflow \
   -profile <docker/singularity/.../institute> \
   --input samplesheet.csv \
   --outdir <OUTDIR>
```

By default, the `osmo_refdb` reference database is downloaded automatically (latest release). To reuse an
already-downloaded copy instead, pass `--osmo_db /path/to/osmo_refdb/<release>` (a directory containing `osmo_refdb.dmnd`).
FASTQ samples (`osmotool profile`) need osmo_refdb v10 or later, which ships a gene catalog; until v10 is on Zenodo,
`latest` downloads v9, which is annotate-only, so pass `--osmo_db` with a v10 release for FASTQ samples.

FASTQ samples can optionally be preprocessed before profiling. Each step is enabled by its own parameter:

```bash
nextflow run barbarahelena/osmoflow \
   -profile <docker/singularity/.../institute> \
   --input samplesheet.csv \
   --outdir <OUTDIR> \
   --fastp \
   --host_bowtie2_index /path/to/GRCh38_bowtie2_index \
   --subsamplelevel 10000000 \
   --readcounts
```

| Parameter | Step |
| --- | --- |
| `--fastp` | Quality filtering and adapter trimming with fastp (`--cut_right --cut_window_size 4 --cut_mean_quality 15 --length_required 70`; override with `ext.args` in a custom config) |
| `--host_bowtie2_index <dir>` / `--host_fasta <fa>` | Host read removal with Bowtie2; with a fasta the index is built first (stored in `db/` in the launch directory) |
| `--perform_runmerging` | Merge the runs of a sample (rows with the same `sample` and a different `run_accession`) after host read removal |
| `--subsamplelevel <n>` | Subsample to `n` reads (pairs) per sample; samples with fewer reads are kept as they are |
| `--readcounts` | `readcounts/readcounts.csv` with the number of reads per sample before (`raw`) and after (`final`) preprocessing |

See [docs/usage.md](docs/usage.md) for details.

> [!WARNING]
> Please provide pipeline parameters via the CLI or Nextflow `-params-file` option. Custom config files including those provided by the `-c` Nextflow option can be used to provide any configuration _**except for parameters**_; see [docs](https://nf-co.re/docs/usage/getting_started/configuration#custom-configuration-files).

## Credits

barbarahelena/osmoflow was originally written by barbarahelena.

We thank the following people for their extensive assistance in the development of this pipeline:

<!-- TODO nf-core: If applicable, make list of people who have also contributed -->

## Citations

<!-- TODO nf-core: Add citation for pipeline after first release. Uncomment lines below and update Zenodo doi and badge at the top of this file. -->
<!-- If you use barbarahelena/osmoflow for your analysis, please cite it using the following doi: [10.5281/zenodo.XXXXXX](https://doi.org/10.5281/zenodo.XXXXXX) -->

<!-- TODO nf-core: Add bibliography of tools and data used in your pipeline -->

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.

This pipeline uses code and infrastructure developed and maintained by the [nf-core](https://nf-co.re) community, reused here under the [MIT license](https://github.com/nf-core/tools/blob/main/LICENSE).

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).
