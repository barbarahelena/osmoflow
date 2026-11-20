# barbarahelena/osmoflow: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.1.0 - [date]

Initial release of barbarahelena/osmoflow, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Run merging (`--perform_runmerging`): a FASTQ sample sequenced in several runs gets one samplesheet row per run (same `sample`, different `run_accession`); the runs are merged with `CAT_FASTQ` after host read removal. Works for single-end and paired-end reads.

### `Fixed`

- `SEQKIT_SAMPLE` runs `seqkit sample` in two-pass mode (`-2`), so subsampling by number no longer holds all reads in memory.

### `Dependencies`

- osmotool container 0.8.0 → 0.9.1. With an `osmo_refdb` release that ships a gene catalog, `osmotool profile` adds `catalog_count`, `catalog_ambiguous` and `translated_count` columns, merged into `profile_catalog_count.tsv`, `profile_catalog_ambiguous.tsv` and `profile_translated_count.tsv`.

### `Deprecated`

- The `snellius` profile was removed from `nextflow.config`.
