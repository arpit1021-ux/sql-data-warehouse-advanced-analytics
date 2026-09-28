"""Pipeline stages: build each warehouse layer, run quality gates, export Gold."""

from __future__ import annotations

import logging
import time
from pathlib import Path

import psycopg
from psycopg import sql

from . import config
from .quality import CheckResult, load_checks, run_check

log = logging.getLogger(__name__)


class QualityGateError(RuntimeError):
    """Raised when one or more `error`-severity quality checks fail."""


def run_sql_file(conn: psycopg.Connection, path: Path) -> None:
    log.debug("Executing %s", path.relative_to(config.REPO_ROOT))
    conn.execute(path.read_text(encoding="utf-8"))


def init_schemas(conn: psycopg.Connection) -> None:
    for script in config.SCHEMA_SCRIPTS:
        run_sql_file(conn, script)
    log.info("Schemas bronze, silver, gold and etl created")


def load_bronze(conn: psycopg.Connection, source_dir: str) -> None:
    for script in config.BRONZE_SCRIPTS:
        run_sql_file(conn, script)
    conn.execute("CALL bronze.load_bronze(%s)", (source_dir,))
    _log_layer_counts(conn, "bronze")


def load_silver(conn: psycopg.Connection) -> None:
    for script in config.SILVER_SCRIPTS:
        run_sql_file(conn, script)
    conn.execute("CALL silver.load_silver()")
    _log_layer_counts(conn, "silver")


def build_gold(conn: psycopg.Connection) -> None:
    for script in config.GOLD_SCRIPTS:
        run_sql_file(conn, script)
    for view in config.GOLD_EXPORTS:
        rows = conn.execute(sql.SQL("SELECT COUNT(*) FROM gold.{}").format(sql.Identifier(view))).fetchone()[
            0
        ]
        log.info("  gold.%-18s %8d rows", view, rows)


def run_quality_checks(conn: psycopg.Connection) -> list[CheckResult]:
    """Run every check; raise QualityGateError if any error-severity check fails."""
    results = [run_check(conn, check) for path in config.QUALITY_FILES for check in load_checks(path)]
    for result in results:
        status = "PASS" if result.passed else ("FAIL" if result.check.severity == "error" else "WARN")
        suffix = "" if result.passed else f"  ({result.failing_rows} rows)"
        log.info("  [%s] %s: %s%s", status, result.check.source, result.check.name, suffix)

    failures = [r for r in results if not r.passed and r.check.severity == "error"]
    warnings = [r for r in results if not r.passed and r.check.severity == "warn"]
    log.info(
        "Quality checks: %d passed, %d warnings, %d failed",
        len(results) - len(failures) - len(warnings),
        len(warnings),
        len(failures),
    )
    if failures:
        raise QualityGateError(f"{len(failures)} quality check(s) failed")
    return results


def export_gold(conn: psycopg.Connection, export_dir: Path = config.GOLD_EXPORT_DIR) -> list[Path]:
    """Write each Gold view to <export_dir>/<view>.csv in a deterministic row order."""
    export_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for view, order_by in config.GOLD_EXPORTS.items():
        target = export_dir / f"{view}.csv"
        query = sql.SQL(
            "COPY (SELECT * FROM gold.{} ORDER BY {}) TO STDOUT WITH (FORMAT csv, HEADER true)"
        ).format(sql.Identifier(view), sql.SQL(order_by))
        with target.open("wb") as handle, conn.cursor().copy(query) as copy:
            for chunk in copy:
                handle.write(chunk)
        written.append(target)
        log.info("  exported %s", target.relative_to(config.REPO_ROOT))
    return written


def print_load_log(conn: psycopg.Connection) -> None:
    rows = conn.execute(
        "SELECT layer, table_name, rows_loaded, duration_ms FROM etl.load_log ORDER BY log_id"
    ).fetchall()
    log.info("Load audit (etl.load_log):")
    for layer, table, count, duration in rows:
        log.info("  %-6s %-18s %8d rows %8.1f ms", layer, table, count, duration)


def _log_layer_counts(conn: psycopg.Connection, layer: str) -> None:
    rows = conn.execute(
        "SELECT table_name, rows_loaded FROM etl.load_log WHERE layer = %s ORDER BY log_id", (layer,)
    ).fetchall()
    total = sum(count for _, count in rows)
    log.info("%s layer loaded: %d tables, %d rows", layer.capitalize(), len(rows), total)


class Timer:
    def __init__(self, label: str) -> None:
        self.label = label

    def __enter__(self) -> Timer:
        self.start = time.perf_counter()
        log.info("== %s", self.label)
        return self

    def __exit__(self, *exc: object) -> None:
        if exc[0] is None:
            log.info("   done in %.2f s", time.perf_counter() - self.start)
