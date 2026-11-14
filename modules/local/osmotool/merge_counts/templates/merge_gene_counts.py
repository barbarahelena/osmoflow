#!/usr/bin/env python3
"""Merge per-sample osmotool *.gene_counts.tsv files into gene x sample matrices.

Each input file has '#'-prefixed metadata lines, then a tab-separated header row
starting with 'gene' followed by one or more value columns, e.g.
  profile:  gene, raw_count, RPM, copies_per_genome
  annotate: gene, raw_count, copies_per_kb
Every value column is merged into its own matrix, written as
<mode>_<column>.tsv (column name lowercased), e.g. profile_rpm.tsv.
Profile and annotate outputs must not be passed together, since their values
are not comparable.

Nextflow's `template` mechanism rewrites backslash escapes (e.g. \\n, \\t) in
this file before Python sees it, since the whole file is interpolated as a
Groovy string -- so avoid embedding \\n in single-line string literals; use
print()/multi-line strings with real newlines instead.
"""

from io import StringIO
from pathlib import Path

import pandas as pd

SUFFIX = ".gene_counts.tsv"

# Interpolated by Nextflow from the process' `mode` and `counts` inputs.
mode = "$mode"
counts = "$counts".split()


def read_gene_counts(path: Path) -> pd.DataFrame:
    with open(path) as fh:
        lines = [line for line in fh if not line.startswith("#")]
    df = pd.read_csv(StringIO("".join(lines)), sep="\t")
    return df.set_index("gene")


def sample_name(path: Path) -> str:
    name = path.name
    return name[: -len(SUFFIX)] if name.endswith(SUFFIX) else path.stem


tables = {}
for raw_path in counts:
    path = Path(raw_path)
    tables[sample_name(path)] = read_gene_counts(path)

# Value columns in the order they appear in the first file; every file of the
# same mode should share the same header.
value_cols = list(next(iter(tables.values())).columns)
for sample, df in tables.items():
    if list(df.columns) != value_cols:
        raise SystemExit(
            f"Column mismatch in sample '{sample}': {list(df.columns)} != {value_cols}"
        )

for col in value_cols:
    matrix = pd.DataFrame({sample: df[col] for sample, df in tables.items()})
    matrix = matrix.reindex(sorted(matrix.index), columns=sorted(matrix.columns))
    matrix.index.name = "gene"
    matrix.to_csv(f"{mode}_{col.lower()}.tsv", sep="\t")

with open("versions.yml", "w") as fh:
    print('"$task.process":', file=fh)
    print(f"    pandas: {pd.__version__}", file=fh)
