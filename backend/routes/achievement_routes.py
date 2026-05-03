from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from database import repo

router = APIRouter(tags=["achievements"])


class UnlockBody(BaseModel):
    user_id: int = Field(..., ge=1)
    title: str = Field(..., min_length=1, max_length=128)


@router.get("/achievements")
def achievements(user_id: int) -> dict[str, Any]:
    if user_id < 1:
        raise HTTPException(status_code=400, detail="Invalid user_id")
    repo.ensure_achievement_rows(user_id)
    rows = repo.get_achievements(user_id)
    return {"achievements": rows}


@router.post("/unlock")
def unlock(body: UnlockBody) -> dict[str, Any]:
    repo.ensure_achievement_rows(body.user_id)
    repo.set_achievement_unlocked(body.user_id, body.title, True)
    return {"ok": True, "title": body.title}
