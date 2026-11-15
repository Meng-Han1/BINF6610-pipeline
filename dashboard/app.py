#!/usr/bin/env python3
"""Interactive dashboard for variant-calling runs."""

import os
import sqlite3
import sys
from urllib.parse import parse_qs, quote

import pandas as pd
import dash_ag_grid as dag
import plotly.express as px
from dash import Dash, Input, Output, callback, ctx, dcc, html


if len(sys.argv) < 2:
    sys.exit("Usage: python3 dashboard/app.py DATABASE [PORT]")

DB = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8050

HERE = os.path.dirname(os.path.abspath(__file__))
Q1_PATH = os.path.join(HERE, "..", "db", "queries", "q1.sql")


def query(sql, params=()):
    """Run SQL against the database provided on the command line."""
    with sqlite3.connect(DB) as con:
        return pd.read_sql_query(sql, con, params=params)


def runs_page():
    """Display all pipeline runs using Assignment 9's q1.sql."""
    with open(Q1_PATH, encoding="utf-8") as f:
        runs = query(f.read())

    links = [
        html.Li(
            dcc.Link(
                str(run_id),
                href=f"/results?run={quote(str(run_id), safe='')}",
            )
        )
        for run_id in runs["run_id"]
    ]

    return [
        html.H1("Variant Calling — Runs"),
        html.P("Select a run to explore its results."),
        html.Ul(links),
        dag.AgGrid(
            id="runs-table",
            rowData=runs.to_dict("records"),
            columnDefs=[{"field": col} for col in runs.columns],
            columnSize="sizeToFit",
        ),
    ]


def results_page(run_id):
    """Display samples and variant sites for one pipeline run."""

    samples = query("""
        SELECT rs.sample_id,
               rs.condition,
               s.phenotype,
               s.is_synthetic_phenotype
        FROM run_samples AS rs
        JOIN samples AS s ON rs.sample_id = s.sample_id
        WHERE rs.run_id = ?
        ORDER BY rs.sample_id
    """, (run_id,))

    sites = query("""
        SELECT chrom, pos, ref, alt, qual, filter
        FROM variants
        WHERE run_id = ?
        ORDER BY chrom, pos
    """, (run_id,))

    # Three plots from the run's variant sites.
    # Keep the original filter strings, including combined filters.
    filter_counts = (
        sites.groupby("filter", dropna=False)
        .size()
        .reset_index(name="count")
    )

    fig_filter = px.bar(
        filter_counts,
        x="filter",
        y="count",
        title="How many sites passed, and why did the others fail?",
    )

    fig_qual = px.histogram(
        sites,
        x="qual",
        title="How confident are the calls?",
    )

    fig_position = px.histogram(
        sites,
        x="pos",
        title="Where along the region are the sites?",
    )

    return [
        html.H1(f"Results of {run_id}"),
        dcc.Link("Back to all runs", href="/"),

        html.H2("Variant Analysis"),
        dcc.Graph(id="plot-filter", figure=fig_filter),
        dcc.Graph(id="plot-qual", figure=fig_qual),
        dcc.Graph(id="plot-position", figure=fig_position),

        html.H2("Samples"),
        html.P(
            "Synthetic phenotype flags identify course-generated "
            "phenotype metadata."
        ),
        dag.AgGrid(
            id="samples-table",
            rowData=samples.to_dict("records"),
            columnDefs=[{"field": col} for col in samples.columns],
            columnSize="sizeToFit",
        ),

        html.H2("Variant Sites"),
        html.P(f"{len(sites):,} variant sites in this run."),
        dag.AgGrid(
            id="sites-table",
            rowData=sites.to_dict("records"),
            columnDefs=[{"field": col} for col in sites.columns],
            columnSize="sizeToFit",
        ),
    ]


app = Dash(__name__, suppress_callback_exceptions=True)

app.layout = [
    dcc.Location(id="url", refresh=False),
    html.Div(id="page", children=[]),
]


@callback(
    Output("page", "children"),
    Input("url", "pathname"),
    Input("url", "search"),
)
def draw_page(pathname, search):
    """Choose a page based on the browser's address."""
    if pathname == "/results":
        run_ids = parse_qs((search or "").lstrip("?")).get("run", [])
        if not run_ids:
            return [html.H2("No run selected"), dcc.Link("Back", href="/")]
        return results_page(run_ids[0])

    return runs_page()


@callback(
    Output("sites-table", "rowData"),
    Input("plot-filter", "clickData"),
    Input("url", "search"),
)
def filter_sites(click, search):
    """Show all sites, or only sites in the clicked filter category."""
    run_ids = parse_qs((search or "").lstrip("?")).get("run", [])
    if not run_ids:
        return []

    run_id = run_ids[0]

    if ctx.triggered_id == "plot-filter" and click is not None:
        point = click["points"][0]
        category = point.get("label", point.get("x"))

        sites = query("""
            SELECT chrom, pos, ref, alt, qual, filter
            FROM variants
            WHERE run_id = ? AND filter = ?
            ORDER BY chrom, pos
        """, (run_id, category))
    else:
        sites = query("""
            SELECT chrom, pos, ref, alt, qual, filter
            FROM variants
            WHERE run_id = ?
            ORDER BY chrom, pos
        """, (run_id,))

    return sites.to_dict("records")


if __name__ == "__main__":
    app.run(port=PORT, debug=True)
