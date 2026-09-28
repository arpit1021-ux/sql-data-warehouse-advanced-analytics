"""Parse and run the declarative data-quality checks in sql/quality/*.sql."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

import psycopg

_CHECK_PATTERN = re.compile(
    r"^--\s*@check\s+(?P<name>.+?)\s*\n--\s*@severity\s+(?P<severity>error|warn)\s*\n(?P<query>.*?);\s*$",
    re.MULTILINE | re.DOTALL,
)


@dataclass(frozen=True)
class Check:
    source: str
    name: str
    severity: str
    query: str


@dataclass(frozen=True)
class CheckResult:
    check: Check
    failing_rows: int

    @property
    def passed(self) -> bool:
        return self.failing_rows == 0


def load_checks(path: Path) -> list[Check]:
    """Return every `-- @check` block in a quality file, in file order."""
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    checks = [
        Check(path.stem, m["name"], m["severity"], m["query"].strip()) for m in _CHECK_PATTERN.finditer(text)
    ]
    if not checks:
        raise ValueError(f"No quality checks found in {path}")
    return checks


def run_check(conn: psycopg.Connection, check: Check) -> CheckResult:
    count = conn.execute(f"SELECT COUNT(*) FROM ({check.query}) AS failing_rows").fetchone()[0]
    return CheckResult(check, count)
