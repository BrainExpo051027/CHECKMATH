from __future__ import annotations

import sqlite3
from typing import Any, Optional

from database.db import get_connection


def ensure_user(username: str) -> int:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "INSERT OR IGNORE INTO users (username, total_score, wins, losses, level, gold, trophies) VALUES (?, 0, 0, 0, 1, 0, 0)",
        (username,),
    )
    conn.commit()
    cur.execute("SELECT id FROM users WHERE username = ?", (username,))
    row = cur.fetchone()
    conn.close()
    if not row:
        raise RuntimeError("Failed to resolve user")
    return int(row["id"])


def create_user(username: str, password_hash: str) -> int:
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO users (username, password_hash, total_score, wins, losses, level, gold, trophies) VALUES (?, ?, 0, 0, 0, 1, 0, 0)",
            (username, password_hash),
        )
        conn.commit()
        return int(cur.lastrowid)
    except sqlite3.IntegrityError as e:
        conn.close()
        raise RuntimeError("Username already taken") from e
    finally:
        if conn:
            conn.close()


def update_username(user_id: int, new_username: str) -> None:
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "UPDATE users SET username = ? WHERE id = ?",
            (new_username, user_id),
        )
        conn.commit()
    except sqlite3.IntegrityError as e:
        conn.close()
        raise RuntimeError("Username already taken") from e
    finally:
        conn.close()


def get_user_by_username(username: str) -> Optional[dict[str, Any]]:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE username = ?", (username,))
    row = cur.fetchone()
    conn.close()
    if not row:
        return None
    return dict(row)


def update_user_stats(user_id: int, result: str, score: int) -> None:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO matches (user_id, result, score) VALUES (?, ?, ?)",
        (user_id, result, score),
    )
    if result == "win":
        cur.execute(
            "UPDATE users SET wins = wins + 1, total_score = total_score + ?, gold = gold + ?, trophies = trophies + 1 WHERE id = ?",
            (score, score // 10 + 5, user_id),
        )
    elif result == "loss":
        cur.execute(
            "UPDATE users SET losses = losses + 1 WHERE id = ?",
            (user_id,),
        )
    else:
        cur.execute(
            "UPDATE users SET total_score = total_score + ?, gold = gold + ? WHERE id = ?",
            (score, score // 20 + 1, user_id),
        )
    # Level up every 100 total_score
    cur.execute(
        "UPDATE users SET level = 1 + CAST(total_score / 100 AS INTEGER) WHERE id = ?",
        (user_id,),
    )
    conn.commit()
    conn.close()


def get_user_by_id(user_id: int) -> Optional[dict[str, Any]]:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE id = ?", (user_id,))
    row = cur.fetchone()
    conn.close()
    if not row:
        return None
    return dict(row)


def update_score_after_match(
    user_id: int, result: str, score: int
) -> None:
    update_user_stats(user_id, result, score)


def get_leaderboard() -> list[dict[str, Any]]:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        """
        SELECT username, total_score, wins, level, gold, trophies
        FROM users
        ORDER BY total_score DESC
        LIMIT 10
        """
    )
    rows = [dict(r) for r in cur.fetchall()]
    conn.close()
    return rows


def get_user_stats(user_id: int) -> dict[str, Any]:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE id = ?", (user_id,))
    user_row = cur.fetchone()
    cur.execute(
        "SELECT COUNT(*) as total_games FROM matches WHERE user_id = ?",
        (user_id,),
    )
    total_games_row = cur.fetchone()
    conn.close()
    if not user_row:
        return {}
    u = dict(user_row)
    total_games = total_games_row["total_games"] if total_games_row else 0
    wins = u.get("wins", 0)
    losses = u.get("losses", 0)
    win_rate = (wins / total_games * 100) if total_games > 0 else 0.0
    return {
        "id": u["id"],
        "username": u["username"],
        "total_score": u.get("total_score", 0),
        "wins": wins,
        "losses": losses,
        "level": u.get("level", 1),
        "gold": u.get("gold", 0),
        "trophies": u.get("trophies", 0),
        "total_games": total_games,
        "win_rate": round(win_rate, 1),
    }


def get_achievements(user_id: int) -> list[dict[str, Any]]:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT id, user_id, title, unlocked FROM achievements WHERE user_id = ?",
        (user_id,),
    )
    rows = [dict(r) for r in cur.fetchall()]
    conn.close()
    return rows


def ensure_achievement_rows(user_id: int) -> None:
    titles = ["First Win", "Win Streak", "Math Master"]
    conn = get_connection()
    cur = conn.cursor()
    for t in titles:
        cur.execute(
            """
            INSERT OR IGNORE INTO achievements (user_id, title, unlocked)
            VALUES (?, ?, 0)
            """,
            (user_id, t),
        )
    conn.commit()
    conn.close()


def set_achievement_unlocked(user_id: int, title: str, unlocked: bool = True) -> None:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "UPDATE achievements SET unlocked = ? WHERE user_id = ? AND title = ?",
        (1 if unlocked else 0, user_id, title),
    )
    conn.commit()
    conn.close()


def check_and_unlock_achievements(user_id: int) -> list[str]:
    u = get_user_by_id(user_id)
    if not u:
        return []
    ensure_achievement_rows(user_id)
    unlocked: list[str] = []
    conn = get_connection()
    cur = conn.cursor()

    if u["wins"] >= 1:
        cur.execute(
            "UPDATE achievements SET unlocked = 1 WHERE user_id = ? AND title = ? AND unlocked = 0",
            (user_id, "First Win"),
        )
        if cur.rowcount:
            unlocked.append("First Win")
    if u["wins"] >= 3:
        cur.execute(
            "UPDATE achievements SET unlocked = 1 WHERE user_id = ? AND title = ? AND unlocked = 0",
            (user_id, "Win Streak"),
        )
        if cur.rowcount:
            unlocked.append("Win Streak")
    if u["total_score"] >= 100:
        cur.execute(
            "UPDATE achievements SET unlocked = 1 WHERE user_id = ? AND title = ? AND unlocked = 0",
            (user_id, "Math Master"),
        )
        if cur.rowcount:
            unlocked.append("Math Master")

    conn.commit()
    conn.close()
    return unlocked
