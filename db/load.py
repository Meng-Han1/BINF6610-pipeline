#!/usr/bin/env python3
"""Load variant-calling runs and sample metadata into SQLite."""

import csv
import json
import os
import sqlite3
import sys


def read_tsv(path):
    """Read a TSV file, ignoring comment and blank lines."""
    with open(path, encoding="utf-8", newline="") as handle:
        lines = (
            line for line in handle
            if line.strip() and not line.lstrip().startswith("#")
        )
        yield from csv.DictReader(lines, delimiter="\t")


def nullable(value):
    """Convert empty values to SQL NULL."""
    return None if value is None or value.strip() == "" else value


def load_metadata(con, path):
    """Load metadata once per sample."""
    columns = (
        "sample_id", "sex", "population", "family",
        "father", "mother", "phenotype",
        "is_synthetic_phenotype",
    )

    for row in read_tsv(path):
        values = [nullable(row.get(column)) for column in columns]

        synthetic = values[-1]
        if synthetic is not None:
            if synthetic.lower() in ("true", "yes", "1"):
                values[-1] = 1
            elif synthetic.lower() in ("false", "no", "0"):
                values[-1] = 0
            else:
                values[-1] = int(synthetic)

        con.execute(
            """
            INSERT INTO samples (
                sample_id, sex, population, family,
                father, mother, phenotype, is_synthetic_phenotype
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (sample_id) DO NOTHING
            """,
            values,
        )


def load_run(con, folder):
    """Load one complete run in the caller's transaction."""
    with open(os.path.join(folder, "manifest.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)

    pipeline = manifest["pipeline"]
    run_id = pipeline["run_id"]

    if con.execute(
        "SELECT 1 FROM runs WHERE run_id = ?", (run_id,)
    ).fetchone():
        return f"{run_id}: already loaded, skipped"

    version = (
        pipeline["name"],
        pipeline["version"],
        pipeline["implementation"],
    )

    con.execute(
        """
        INSERT INTO pipelines (name, version, implementation)
        VALUES (?, ?, ?)
        ON CONFLICT (name, version, implementation) DO NOTHING
        """,
        version,
    )

    pipeline_id = con.execute(
        """
        SELECT pipeline_id FROM pipelines
        WHERE name = ? AND version = ? AND implementation = ?
        """,
        version,
    ).fetchone()[0]

    params = manifest["params"]
    platform = manifest["platform"]

    con.execute(
        """
        INSERT INTO runs (
            run_id, pipeline_id, started_at, finished_at,
            exit_status, platform, executor, samplesheet,
            reference, region, folder
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            run_id,
            pipeline_id,
            pipeline["started_at"],
            pipeline["finished_at"],
            pipeline["exit_status"],
            platform["kind"],
            platform.get("executor"),
            params.get("samplesheet"),
            params.get("ref"),
            params.get("region"),
            os.path.abspath(folder),
        ),
    )

    manifest_samples = {
        sample["sample_id"]: sample
        for sample in manifest["samples"]
    }

    sample_count = 0

    for sample in read_tsv(os.path.join(folder, "samples.tsv")):
        sample_id = sample["sample_id"]

        con.execute(
            """
            INSERT INTO samples (sample_id)
            VALUES (?)
            ON CONFLICT (sample_id) DO NOTHING
            """,
            (sample_id,),
        )

        con.execute(
            """
            INSERT INTO run_samples (
                run_id, sample_id, condition, library_type
            )
            VALUES (?, ?, ?, ?)
            """,
            (
                run_id,
                sample_id,
                sample["condition"],
                manifest_samples[sample_id]["library_type"],
            ),
        )

        sample_count += 1

    variant_count = 0

    for variant in read_tsv(os.path.join(folder, "variants.tsv")):
        quality = nullable(variant["qual"])

        con.execute(
            """
            INSERT INTO variants (
                run_id, chrom, pos, ref, alt, qual, filter
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                run_id,
                variant["chrom"],
                int(variant["pos"]),
                variant["ref"],
                variant["alt"],
                float(quality) if quality is not None else None,
                variant["filter"],
            ),
        )

        variant_count += 1

    for output in manifest["outputs"]:
        checksum = output["checksum"]
        if not checksum.startswith("sha256:"):
            raise ValueError(f"Unexpected checksum: {checksum}")

        con.execute(
            """
            INSERT INTO outputs (run_id, path, sha256)
            VALUES (?, ?, ?)
            """,
            (
                run_id,
                output["path"],
                checksum.removeprefix("sha256:"),
            ),
        )

    return (
        f"{run_id}: loaded {sample_count} samples, "
        f"{variant_count} variants, {len(manifest['outputs'])} outputs"
    )


def main():
    if len(sys.argv) < 4:
        sys.exit(
            "Usage: python3 db/load.py DATABASE METADATA RUN_FOLDER..."
        )

    database, metadata, *folders = sys.argv[1:]

    with sqlite3.connect(database) as con:
        con.execute("PRAGMA foreign_keys = ON")

        with con:
            load_metadata(con, metadata)

        for folder in folders:
            try:
                with con:
                    message = load_run(con, folder)
                print(message)
            except (sqlite3.Error, ValueError, KeyError) as error:
                print(f"{folder}: refused: {error}", file=sys.stderr)
                raise


if __name__ == "__main__":
    main()
