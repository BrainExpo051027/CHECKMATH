from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from database import repo

router = APIRouter(tags=["leaderboard"])


class UpdateScoreBody(BaseModel):
    username: str = Field(..., min_length=1, max_length=64)
    result: str = Field(..., min_length=3, max_length=8)
    score: int = Field(default=0, ge=0)


@router.get("/leaderboard")
def leaderboard() -> dict[str, Any]:
    return {"leaderboard": repo.get_leaderboard()}


@router.get("/resolve-user")
def resolve_user(username: str) -> dict[str, Any]:
    name = username.strip()
    if not name:
        raise HTTPException(status_code=400, detail="username required")
    uid = repo.ensure_user(name)
    return {"user_id": uid}


@router.post("/update-score")
def update_score(body: UpdateScoreBody) -> dict[str, Any]:
    uid = repo.ensure_user(body.username.strip())
    result = body.result.lower()
    if result not in ("win", "loss", "draw"):
        raise HTTPException(status_code=400, detail="Invalid result")
    repo.update_score_after_match(uid, result, body.score)
    newly = repo.check_and_unlock_achievements(uid)
    return {"ok": True, "user_id": uid, "achievements_unlocked": newly}
