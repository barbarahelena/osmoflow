#!/usr/bin/env python3
"""Merge per-sample osmotool *.unit_counts.tsv files of one mode.

unit_counts.tsv is gene_counts.tsv with the osmo_refdb release's report levels
applied: one row per reporting unit, either one family (report_level gene), the
summed close paralogs that cannot be told apart (group), or a unit that is not
reliable (none: raw_count and the value column are NA, never 0). profile and
annotate each have their own report levels, decided for short reads and for
full-length proteins.

Writes, for mode profile (value column RPM):
  profile_unit_raw_count.tsv  unit x sample matrix of raw_count (fragments)
  profile_unit_rpm.tsv        unit x sample matrix of RPM
  profile_read_sources.tsv    long table, one row per sample and unit: status
                              and, with a gene catalog, where the reads came
                              from (catalog_count, catalog_ambiguous,
                              translated_count)
and for mode annotate (value column COPIES_PER_KB):
  annotate_unit_raw_count.tsv      unit x sample matrix of raw_count (proteins)
  annotate_unit_copies_per_kb.tsv  unit x sample matrix of copies_per_kb

Units are in the release's manifest order, which keeps related units together.
Rows with status not_in_manifest (labels with reads that belong to no unit, e.g.
a fused-ORF reference) differ per sample, so they are left out of the matrices
and kept in profile_read_sources.tsv. Every sample must have the same units:
samples profiled against different releases are not merged.

Nextflow's `template` mechanism interpolates this whole file as a Groovy
string: dollar signs and backslash escapes are rewritten before Python sees
it, so this file uses neither, except for the inputs below.
"""

from io import StringIO
from pathlib import Path

import pandas as pd

SUFFIX = ".unit_counts.tsv"
TAB = chr(9)
SOURCE_COLS = ("raw_count", "catalog_count", "catalog_ambiguous", "translated_count")

# Interpolated by Nextflow from the process' `mode` and `units` inputs.
mode = "${mode}"
units = "${units.join(' ')}".split()
VALUE_COL = "RPM" if mode == "profile" else "COPIES_PER_KB"


def read_unit_counts(path: Path) -> pd.DataFrame:
    with open(path) as fh:
        body = "".join(line for line in fh if not line.startswith("#"))
    return pd.read_csv(StringIO(body), sep=TAB, keep_default_na=False, na_values=["NA"])


def sample_name(path: Path) -> str:
    name = path.name
    return name[: -len(SUFFIX)] if name.endswith(SUFFIX) else path.stem


tables = {sample_name(Path(p)): read_unit_counts(Path(p)) for p in units}
reported = {s: df[df["status"] != "not_in_manifest"].set_index("unit") for s, df in tables.items()}

first_sample, first = next(iter(reported.items()))
definition = list(zip(first.index, first["report_level"], first["members"]))
for sample, df in reported.items():
    if list(zip(df.index, df["report_level"], df["members"])) != definition:
        raise SystemExit(
            f"Sample '{sample}' has other reporting units than sample '{first_sample}': "
            "were they run against different osmo_refdb releases?"
        )

for col in ("raw_count", VALUE_COL):
    matrix = pd.DataFrame({s: df[col] for s, df in reported.items()})
    matrix = matrix.reindex(index=first.index, columns=sorted(matrix.columns))
    matrix.index.name = "unit"
    matrix.to_csv(f"{mode}_unit_{col.lower()}.tsv", sep=TAB, na_rep="NA")

if mode == "profile":
    long = pd.concat([df.assign(sample=s) for s, df in tables.items()], ignore_index=True)
    keep = ["sample", "unit", "report_level", "members", "status"] + [c for c in SOURCE_COLS if c in long.columns]
    long = long[keep].sort_values("sample", kind="stable")
    long.to_csv("profile_read_sources.tsv", sep=TAB, index=False, na_rep="NA")

# Version for the "versions" topic (eval() outputs only work in bash scripts)
with open("pandas_version.txt", "w") as fh:
    print(pd.__version__, file=fh)
