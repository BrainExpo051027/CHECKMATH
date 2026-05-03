import sqlite3
from pathlib import Path

DB_DIR = Path(__file__).resolve().parent.parent
DB_NAME = str(DB_DIR / "checkmath.db")


def get_connection():
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    return conn


def _add_column_if_missing(cur, table, col, col_def):
    cur.execute(f"PRAGMA table_info({table})")
    existing = {row[1] for row in cur.fetchall()}
    if col not in existing:
        cur.execute(f"ALTER TABLE {table} ADD COLUMN {col} {col_def}")


def init_db():
    conn = get_connection()
    cur = conn.cursor()
    cur.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT,
            total_score INTEGER DEFAULT 0,
            wins INTEGER DEFAULT 0,
            losses INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS matches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            result TEXT,
            score INTEGER,
            date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS achievements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            title TEXT,
            unlocked INTEGER DEFAULT 0,
            UNIQUE(user_id, title),
            FOREIGN KEY (user_id) REFERENCES users(id)
        );
        """
    )
    # Safe migrations for new columns
    _add_column_if_missing(cur, "users", "password_hash", "TEXT")
    _add_column_if_missing(cur, "users", "level", "INTEGER DEFAULT 1")
    _add_column_if_missing(cur, "users", "gold", "INTEGER DEFAULT 0")
    _add_column_if_missing(cur, "users", "trophies", "INTEGER DEFAULT 0")
    conn.commit()
    conn.close()
