# barbarahelena/osmoflow: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.1.0 - [date]

Initial release of barbarahelena/osmoflow, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Run merging (`--perform_runmerging`): a FASTQ sample sequenced in several runs gets one samplesheet row per run (same `sample`, different `run_accession`); the runs are merged with `CAT_FASTQ` after host read removal. Works for single-end and paired-end reads.

### `Changed`

- Read counts come from the preprocessing steps' own reports (fastp JSON, Bowtie2 log, `SEQKIT_SAMPLE`) instead of separate `READCOUNT` jobs, which now run only for `--readcounts` when no preprocessing step does. The count of the reads that go into `osmotool profile` is passed as `--total_fragments`, so osmotool skips its own counting pass.
- `SEQKIT_SAMPLE` reads each file once when the read count is known (fastp or host read removal ran), and subsamples R1 and R2 at the same time.
- Resources: `OSMOTOOL_PROFILE` 16 CPUs and 28 GB (was 4 CPUs, 24 GB), `FASTP` 16 CPUs and 8 GB (was 6 CPUs, 36 GB), `SEQKIT_SAMPLE` 8 CPUs and 8 GB. fastp writes its output reads at gzip level 1 (`-z 1`), subsampling at level 1 too.

### `Fixed`

- `SEQKIT_SAMPLE` no longer holds all reads in memory: it samples by proportion and keeps the first `--subsamplelevel` reads, streaming.

### `Dependencies`

- osmotool container 0.8.0 → 0.9.2. With an `osmo_refdb` release that ships a gene catalog, `osmotool profile` adds `catalog_count`, `catalog_ambiguous` and `translated_count` columns, merged into `profile_catalog_count.tsv`, `profile_catalog_ambiguous.tsv` and `profile_translated_count.tsv`.
- osmotool 0.9.2 counts `profile` in fragments for both read layouts: RPM is per million fragments (read pairs, or single-end reads), so paired-end RPM is 2× what earlier versions gave and now comparable to single-end; single-end RPM and `copies_per_genome` are unchanged. The `gene_counts.tsv` header lines and `aln_stats.tsv` keys are renamed (`total_reads` → `total_fragments`, ...).

### `Deprecated`

- The `snellius` profile was removed from `nextflow.config`.
