# barbarahelena/osmoflow: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.1.0 - [date]

Initial release of barbarahelena/osmoflow, created with the [nf-core](https://nf-co.re/) template.

### `Added`

- Run merging (`--perform_runmerging`): a FASTQ sample sequenced in several runs gets one samplesheet row per run (same `sample`, different `run_accession`); the runs are merged with `CAT_FASTQ` after host read removal. Works for single-end and paired-end reads.

### `Changed`

- **Profile results are now per reporting unit** (breaking: output files renamed). `OSMOTOOL_MERGE_UNITS` merges each sample's `unit_counts.tsv`, which osmotool already wrote but osmoflow did not publish, into `profile/profile_unit_raw_count.tsv` and `profile/profile_unit_rpm.tsv`. These apply the `osmo_refdb` release's report levels: close paralogs are summed into one unit (e.g. `opu_permease`), and units that are not reliable on short reads (e.g. `opuAC`, `trkH`) are `NA`, never 0. `profile/profile_read_sources.tsv` replaces the `catalog_count`, `catalog_ambiguous` and `translated_count` matrices with one long table per sample and unit. The gene-level matrices (`profile_raw_count.tsv`, `profile_rpm.tsv`, `profile_copies_per_genome.tsv`, ...), which ignore the report levels, are only written with `--profile_gene_matrices`. Each sample's `unit_counts.tsv` is published in `profile/<sample>/`. `annotate` outputs are unchanged; the `unit_counts.tsv` that `osmotool annotate` writes with `osmo_refdb` v11 is not published yet.
- FASTQ samples need `osmo_refdb` v10 or later: before profiling, the pipeline checks for the release's `osmo_refdb.profile_report_levels.tsv` and stops with a message naming the release, instead of failing (and retrying) every sample's profile task. Runs with only assemblies are not checked: `annotate` does not use the report levels.
- Read counts come from the preprocessing steps' own reports (fastp JSON, Bowtie2 log, `SEQKIT_SAMPLE`) instead of separate `READCOUNT` jobs, which now run only for `--readcounts` when no preprocessing step does. The count of the reads that go into `osmotool profile` is passed as `--total_fragments`, so osmotool skips its own counting pass.
- `SEQKIT_SAMPLE` reads each file once when the read count is known (fastp or host read removal ran), and subsamples R1 and R2 at the same time.
- Resources: `OSMOTOOL_PROFILE` 16 CPUs and 28 GB (was 4 CPUs, 24 GB), `FASTP` 16 CPUs and 8 GB (was 6 CPUs, 36 GB), `SEQKIT_SAMPLE` 8 CPUs and 8 GB. fastp writes its output reads at gzip level 1 (`-z 1`), subsampling at level 1 too.

### `Fixed`

- Merged matrices write missing values as `NA`, as osmotool does (e.g. `copies_per_genome` with too few marker genes), instead of empty cells.
- `SEQKIT_SAMPLE` no longer holds all reads in memory: it samples by proportion and keeps the first `--subsamplelevel` reads, streaming.

### `Dependencies`

- osmotool container 0.10.0 → 0.11.1. `latest` now downloads osmo_refdb v10 (0.10.0 still downloaded v9, which is annotate-only). v11, the current release, is not on Zenodo yet (its DOI will follow): use it with `--osmo_db`. With v11, `profile` reports a `none` unit's catalog counts (`catalog_only`) only where the release says they can be reported, and `annotate` writes a `unit_counts.tsv` from the release's annotate report levels.
- osmotool container 0.9.2 → 0.10.0. `osmotool profile` needs an `osmo_refdb` release that ships a gene catalog (v10+) and stops with an error on v5–v9, which are annotate-only. `aln_stats.tsv` of `profile` records the catalog used (`catalog`, `catalog_dir`, `catalog_hmm_sha256`, ...).

- osmotool container 0.8.0 → 0.9.2. With an `osmo_refdb` release that ships a gene catalog, `osmotool profile` adds `catalog_count`, `catalog_ambiguous` and `translated_count` columns, merged into `profile_catalog_count.tsv`, `profile_catalog_ambiguous.tsv` and `profile_translated_count.tsv`.
- osmotool 0.9.2 counts `profile` in fragments for both read layouts: RPM is per million fragments (read pairs, or single-end reads), so paired-end RPM is 2× what earlier versions gave and now comparable to single-end; single-end RPM and `copies_per_genome` are unchanged. The `gene_counts.tsv` header lines and `aln_stats.tsv` keys are renamed (`total_reads` → `total_fragments`, ...).

### `Deprecated`

- The `snellius` profile was removed from `nextflow.config`.
