"""Build the warehouse once per test session in a dedicated database.

Uses $TEST_DATABASE_URL (a server where the test role may CREATE DATABASE and
read data/raw) or, by default, the embedded PostgreSQL used by the pipeline.
"""

from __future__ import annotations

import os

import psycopg
import pytest
from psycopg.conninfo import conninfo_to_dict, make_conninfo

from pipeline import config, steps
from pipeline.database import start_embedded_server

TEST_DATABASE = "dwh_test"


@pytest.fixture(scope="session")
def database_url() -> str:
    admin_url = os.environ.get("TEST_DATABASE_URL") or start_embedded_server()
    with psycopg.connect(admin_url, autocommit=True) as conn:
        conn.execute(f'DROP DATABASE IF EXISTS "{TEST_DATABASE}" WITH (FORCE)')
        conn.execute(f'CREATE DATABASE "{TEST_DATABASE}"')
    params = conninfo_to_dict(admin_url)
    params["dbname"] = TEST_DATABASE
    return make_conninfo(**params)


@pytest.fixture(scope="session")
def source_dir() -> str:
    return os.environ.get("TEST_SOURCE_DIR", str(config.RAW_DATA_DIR))


@pytest.fixture(scope="session")
def warehouse(database_url: str, source_dir: str) -> psycopg.Connection:
    """Autocommit connection to a freshly built warehouse (all layers loaded)."""
    conn = psycopg.connect(database_url, autocommit=True)
    steps.init_schemas(conn)
    steps.load_bronze(conn, source_dir)
    steps.load_silver(conn)
    steps.build_gold(conn)
    yield conn
    conn.close()


def scalar(conn: psycopg.Connection, query: str, params: tuple = ()) -> object:
    return conn.execute(query, params).fetchone()[0]
