#!/usr/bin/env python3
"""Merge per-bin osmotool *.systems.tsv files into one long-format table.

Each input file has one row per system for a single bin. This script
concatenates all of them, adding a `bin_id` column (taken from the file
name) so the result is one row per (bin, system).

Nextflow's `template` mechanism rewrites backslash escapes (e.g. \\n, \\t) in
this file before Python sees it, since the whole file is interpolated as a
Groovy string -- so avoid embedding \\n in single-line string literals; use
print()/multi-line strings with real newlines instead.
"""

import csv
import platform
from pathlib import Path

SUFFIX = ".systems.tsv"

# Interpolated by Nextflow from the process' `systems` input.
systems = "$systems".split()


def bin_id(path: Path) -> str:
    name = path.name
    return name[: -len(SUFFIX)] if name.endswith(SUFFIX) else path.stem


with open("merged_systems.tsv", "w", newline="") as out_f:
    writer = None
    for raw_path in sorted(systems):
        path = Path(raw_path)
        with path.open(newline="") as in_f:
            reader = csv.DictReader(in_f, delimiter="\t")
            if writer is None:
                fieldnames = ["bin_id"] + reader.fieldnames
                writer = csv.DictWriter(out_f, fieldnames=fieldnames, delimiter="\t")
                writer.writeheader()
            for row in reader:
                writer.writerow({"bin_id": bin_id(path), **row})

with open("versions.yml", "w") as fh:
    print('"$task.process":', file=fh)
    print(f"    python: {platform.python_version()}", file=fh)
