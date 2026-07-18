#!/usr/bin/env python3
"""Merge per-sample osmotool *.gene_counts.tsv files into one gene x sample matrix.

Each input file has two leading '#'-prefixed metadata lines, then a tab-separated
header row (gene, raw_count, <value_col>) where <value_col> is 'rpm' (profile
mode) or 'copies_per_kb' (annotate mode). Only the third column is merged here --
profile and annotate outputs must not be passed together, since their values
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


def read_gene_counts(path: Path) -> pd.Series:
    with open(path) as fh:
        lines = [line for line in fh if not line.startswith("#")]
    df = pd.read_csv(StringIO("".join(lines)), sep="\t")
    value_col = df.columns[2]
    return df.set_index("gene")[value_col]


def sample_name(path: Path) -> str:
    name = path.name
    return name[: -len(SUFFIX)] if name.endswith(SUFFIX) else path.stem


columns = {}
for raw_path in counts:
    path = Path(raw_path)
    sample = sample_name(path)
    columns[sample] = read_gene_counts(path)

matrix = pd.DataFrame(columns)
matrix = matrix.reindex(sorted(matrix.index), columns=sorted(matrix.columns))
matrix.index.name = "gene"
matrix.to_csv(f"{mode}_gene_counts.tsv", sep="\t")

with open("versions.yml", "w") as fh:
    print('"$task.process":', file=fh)
    print(f"    pandas: {pd.__version__}", file=fh)
