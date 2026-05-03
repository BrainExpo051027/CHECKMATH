from typing import Any, Optional


def row_to_user(row) -> dict[str, Any]:
    if row is None:
        return {}
    return {
        "id": row["id"],
        "username": row["username"],
        "total_score": row["total_score"],
        "wins": row["wins"],
        "losses": row["losses"],
        "level": row["level"] if "level" in row.keys() else 1,
        "gold": row["gold"] if "gold" in row.keys() else 0,
        "trophies": row["trophies"] if "trophies" in row.keys() else 0,
    }


def achievement_row(row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "user_id": row["user_id"],
        "title": row["title"],
        "unlocked": bool(row["unlocked"]),
    }
