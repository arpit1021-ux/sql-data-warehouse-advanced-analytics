"""Command-line entry point.

    python -m pipeline run        build every layer, run quality gates, export Gold CSVs
    python -m pipeline check      run the quality gates against an existing build
    python -m pipeline export     re-export the Gold CSVs from an existing build

Connection: --database-url, else $DATABASE_URL, else an embedded PostgreSQL 16
started automatically in ~/.sql-dwh/pgdata (no installation needed).
"""

from __future__ import annotations

import argparse
import logging
import os
import sys

import psycopg

from . import config, steps
from .database import EmbeddedServerUnavailable, connect, resolve_database_url


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m pipeline", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("command", choices=["run", "check", "export"])
    parser.add_argument(
        "--database-url", help="PostgreSQL connection URL (default: $DATABASE_URL, else embedded)"
    )
    parser.add_argument(
        "--source-dir",
        default=os.environ.get("WAREHOUSE_SOURCE_DIR", str(config.RAW_DATA_DIR)),
        help="data/raw folder as seen by the database server (default: $WAREHOUSE_SOURCE_DIR, "
        "else %(default)s); use /data/raw with the docker-compose database",
    )
    parser.add_argument("--no-export", action="store_true", help="skip writing data/gold/*.csv after `run`")
    parser.add_argument("-v", "--verbose", action="store_true", help="show SQL files and server notices")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-5s %(message)s",
        datefmt="%H:%M:%S",
    )
    for noisy in ("psycopg", "pgserver"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    try:
        url = resolve_database_url(args.database_url)
    except EmbeddedServerUnavailable as exc:
        logging.error("%s", exc)
        return 1
    try:
        with connect(url) as conn:
            if args.command == "run":
                with steps.Timer("Initialise schemas"):
                    steps.init_schemas(conn)
                with steps.Timer("Bronze: load source files"):
                    steps.load_bronze(conn, args.source_dir)
                with steps.Timer("Silver: cleanse and standardise"):
                    steps.load_silver(conn)
                with steps.Timer("Gold: star schema and reports"):
                    steps.build_gold(conn)
                steps.print_load_log(conn)
            if args.command in ("run", "check"):
                with steps.Timer("Quality gates"):
                    steps.run_quality_checks(conn)
            if args.command == "export" or (args.command == "run" and not args.no_export):
                with steps.Timer("Export Gold layer"):
                    steps.export_gold(conn)
    except steps.QualityGateError as exc:
        logging.error("%s - see the FAIL lines above", exc)
        return 1
    except psycopg.Error as exc:
        logging.error("Database error: %s", str(exc).strip())
        return 1
    logging.info("Pipeline finished successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main())
