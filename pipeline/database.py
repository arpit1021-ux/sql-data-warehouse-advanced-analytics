"""Database connections: an external PostgreSQL server or a zero-setup embedded one."""

from __future__ import annotations

import logging
import os
import warnings
from collections.abc import Iterator
from contextlib import contextmanager

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo

from .config import DEFAULT_DATABASE, EMBEDDED_PGDATA_DIR

log = logging.getLogger(__name__)


CONNECT_TIMEOUT_SECONDS = 10


class EmbeddedServerUnavailable(RuntimeError):
    """Raised when no database URL is configured and pgserver is not installed."""


class DatabaseUnavailable(RuntimeError):
    """Raised when the configured PostgreSQL server cannot be reached or rejects the login."""


def open_connection(database_url: str) -> psycopg.Connection:
    """Open an autocommit connection that fails fast with an actionable message.

    Without a timeout, connecting to a port nobody listens on can hang for a long
    time on Windows, so a default connect_timeout is applied unless the URL sets one.
    """
    params = conninfo_to_dict(database_url)
    params.setdefault("connect_timeout", CONNECT_TIMEOUT_SECONDS)
    try:
        return psycopg.connect(make_conninfo(**params), autocommit=True)
    except psycopg.OperationalError as exc:
        where = f"{params.get('host', 'local socket')}:{params.get('port', 5432)}"
        first_line = str(exc).strip().splitlines()[0]
        raise DatabaseUnavailable(
            f"Cannot connect to PostgreSQL at {where} ({first_line}). "
            "Check that the server is running (for Docker: start Docker Desktop, then "
            "`docker compose up -d --wait`) and that DATABASE_URL has the right port and password."
        ) from exc


def start_embedded_server() -> str:
    """Start (or reuse) a local PostgreSQL 16 instance and return its admin connection URI."""
    warnings.filterwarnings("ignore", module="platformdirs")
    try:
        import pgserver  # imported lazily: only needed for embedded mode
    except ImportError as exc:
        raise EmbeddedServerUnavailable(
            "No database configured and the embedded server (pgserver) is not installed. "
            "pgserver supports Python 3.9-3.12; either use one of those versions, or start the "
            "Docker database (docker compose up -d) and set DATABASE_URL and WAREHOUSE_SOURCE_DIR "
            "- see the README quick start."
        ) from exc

    EMBEDDED_PGDATA_DIR.mkdir(parents=True, exist_ok=True)
    server = pgserver.get_server(EMBEDDED_PGDATA_DIR, cleanup_mode=None)
    log.info("Embedded PostgreSQL running (data directory: %s)", EMBEDDED_PGDATA_DIR)
    return server.get_uri()


def ensure_database(admin_uri: str, database: str = DEFAULT_DATABASE) -> str:
    """Create `database` on the server behind `admin_uri` if needed and return a URI to it."""
    with open_connection(admin_uri) as conn:
        exists = conn.execute("SELECT 1 FROM pg_database WHERE datname = %s", (database,)).fetchone()
        if not exists:
            conn.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(database)))
            log.info("Created database %s", database)
    params = conninfo_to_dict(admin_uri)
    params["dbname"] = database
    return make_conninfo(**params)


def resolve_database_url(database_url: str | None) -> str:
    """Use the given URL, then $DATABASE_URL, and fall back to the embedded server."""
    url = database_url or os.environ.get("DATABASE_URL")
    if url:
        return url
    return ensure_database(start_embedded_server())


@contextmanager
def connect(database_url: str) -> Iterator[psycopg.Connection]:
    """Autocommit connection that forwards server NOTICE messages to the log."""
    with open_connection(database_url) as conn:
        conn.add_notice_handler(lambda notice: log.debug("%s", notice.message_primary))
        yield conn
