from __future__ import annotations

import hashlib
import secrets
from typing import Any, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from database import repo

router = APIRouter(tags=["auth"])


def _hash_password(password: str) -> str:
    """Simple SHA-256 with random salt stored alongside."""
    salt = secrets.token_hex(16)
    h = hashlib.sha256((salt + password).encode()).hexdigest()
    return f"{salt}${h}"


def _verify_password(stored: str, password: str) -> bool:
    if "$" not in stored:
        return False
    salt, h = stored.split("$", 1)
    return h == hashlib.sha256((salt + password).encode()).hexdigest()


class RegisterBody(BaseModel):
    username: str = Field(..., min_length=2, max_length=32)
    password: str = Field(..., min_length=4, max_length=128)


class LoginBody(BaseModel):
    username: str = Field(..., min_length=1, max_length=32)
    password: str = Field(..., min_length=1, max_length=128)


class UpdateUsernameBody(BaseModel):
    user_id: int = Field(..., ge=1)
    new_username: str = Field(..., min_length=2, max_length=32)


@router.post("/register")
def register(body: RegisterBody) -> dict[str, Any]:
    existing = repo.get_user_by_username(body.username.strip())
    if existing:
        raise HTTPException(status_code=409, detail="Username already taken")
    pw_hash = _hash_password(body.password)
    user_id = repo.create_user(body.username.strip(), pw_hash)
    return {"ok": True, "user_id": user_id}


@router.post("/login")
def login(body: LoginBody) -> dict[str, Any]:
    user = repo.get_user_by_username(body.username.strip())
    if not user:
        raise HTTPException(status_code=401, detail="Invalid username or password")
    stored_hash = user.get("password_hash") or ""
    if not stored_hash or not _verify_password(stored_hash, body.password):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    stats = repo.get_user_stats(user["id"])
    return {"ok": True, "user_id": user["id"], **stats}


@router.get("/profile")
def profile(user_id: int) -> dict[str, Any]:
    if user_id < 1:
        raise HTTPException(status_code=400, detail="Invalid user_id")
    stats = repo.get_user_stats(user_id)
    if not stats:
        raise HTTPException(status_code=404, detail="User not found")
    return {"ok": True, **stats}


@router.post("/update-username")
def update_username(body: UpdateUsernameBody) -> dict[str, Any]:
    try:
        repo.update_username(body.user_id, body.new_username.strip())
        return {"ok": True}
    except RuntimeError as e:
        raise HTTPException(status_code=409, detail=str(e))
