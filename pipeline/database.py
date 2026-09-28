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


def start_embedded_server() -> str:
    """Start (or reuse) a local PostgreSQL 16 instance and return its admin connection URI."""
    warnings.filterwarnings("ignore", module="platformdirs")
    import pgserver  # imported lazily: only needed for embedded mode

    EMBEDDED_PGDATA_DIR.mkdir(parents=True, exist_ok=True)
    server = pgserver.get_server(EMBEDDED_PGDATA_DIR, cleanup_mode=None)
    log.info("Embedded PostgreSQL running (data directory: %s)", EMBEDDED_PGDATA_DIR)
    return server.get_uri()


def ensure_database(admin_uri: str, database: str = DEFAULT_DATABASE) -> str:
    """Create `database` on the server behind `admin_uri` if needed and return a URI to it."""
    with psycopg.connect(admin_uri, autocommit=True) as conn:
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
    with psycopg.connect(database_url, autocommit=True) as conn:
        conn.add_notice_handler(lambda notice: log.debug("%s", notice.message_primary))
        yield conn
