# barbarahelena/osmoflow

[![Open in GitHub Codespaces](https://img.shields.io/badge/Open_In_GitHub_Codespaces-black?labelColor=grey&logo=github)](https://github.com/codespaces/new/barbarahelena/osmoflow)
[![GitHub Actions Linting Status](https://github.com/barbarahelena/osmoflow/actions/workflows/linting.yml/badge.svg)](https://github.com/barbarahelena/osmoflow/actions/workflows/linting.yml)
[![Cite with Zenodo](http://img.shields.io/badge/DOI-10.5281/zenodo.XXXXXXX-1073c8?labelColor=000000)](https://doi.org/10.5281/zenodo.XXXXXXX)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A525.04.0-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
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

The pipeline runs five processes:

1. **`OSMOTOOL_DOWNLOAD_DB`** — downloads and unpacks an `osmo_refdb` release, unless `--osmo_db` points at one already
2. **`OSMOTOOL_PROFILE`** — runs `osmotool profile` on samplesheet rows with `fastq_1`[, `fastq_2`]
3. **`OSMOTOOL_ANNOTATE`** — runs `osmotool annotate` on samplesheet rows with `fasta`
4. **`OSMOTOOL_MERGE_COUNTS`** — merges each mode's per-sample `gene_counts.tsv` into one gene x sample matrix (`profile_gene_counts.tsv` / `annotate_gene_counts.tsv`); the two modes are never merged together since RPM and `copies_per_kb` aren't comparable
5. **`OSMOTOOL_MERGE_SYSTEMS`** — merges each bin's `*.systems.tsv` from `OSMOTOOL_ANNOTATE` into one long-format `merged_systems.tsv` (one row per bin/system); only runs when at least one `annotate`-mode sample is present

## Usage

> [!NOTE]
> If you are new to Nextflow, please refer to [this page](https://nf-co.re/docs/usage/installation) on how to set up Nextflow. Make sure to [test your setup](https://nf-co.re/docs/usage/introduction#how-to-run-a-pipeline) with `-profile test` before running the workflow on actual data.

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
already-downloaded copy instead, pass `--osmo_db /path/to/osmo_refdb/v5`.

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
