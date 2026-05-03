from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from services import game_logic as gl
from services.ai_bot import get_ai_move

router = APIRouter(tags=["game"])


class StartGameBody(BaseModel):
    difficulty: str = "medium"
    username: Optional[str] = "Player 1"
    game_mode: str = "vs_ai"
    opponent_name: Optional[str] = "Bot"


class MoveBody(BaseModel):
    game_id: str
    from_row: int = Field(..., ge=0, le=7)
    from_col: int = Field(..., ge=0, le=7)
    to_row: int = Field(..., ge=0, le=7)
    to_col: int = Field(..., ge=0, le=7)


class BotMoveBody(BaseModel):
    game_id: str


@router.post("/start-game")
def start_game(body: StartGameBody) -> dict[str, Any]:
    d = body.difficulty.lower().strip()
    if d not in ("easy", "medium", "hard"):
        raise HTTPException(status_code=400, detail="difficulty must be easy, medium, or hard")
        
    p1 = body.username if body.username else "Player 1"
    p2 = body.opponent_name if body.opponent_name else "Bot"
    gid, state = gl.create_game(d, body.game_mode, p1, p2)
    return {"game_id": gid, **state.to_dict()}


@router.post("/move")
def make_move(body: MoveBody) -> dict[str, Any]:
    state = gl.get_game(body.game_id)
    if not state:
        raise HTTPException(status_code=404, detail="Unknown game_id")

    ok, msg, st = gl.try_move(
        body.game_id,
        body.from_row,
        body.from_col,
        body.to_row,
        body.to_col,
    )
    if not ok or st is None:
        raise HTTPException(status_code=400, detail=msg)

    player_captured = st.last_capture

    # Bot moves are now requested asynchronously via /bot-move
    # if not st.game_over and st.current_turn == "ai" and st.game_mode == "vs_ai":
    #     _run_ai_until_human(st)

    return {
        "ok": True,
        **st.to_dict(),
        "message": msg,
        "player_captured": player_captured,
    }


@router.get("/game-state")
def game_state(game_id: str) -> dict[str, Any]:
    state = gl.get_game(game_id)
    if not state:
        raise HTTPException(status_code=404, detail="Unknown game_id")
    return state.to_dict()


@router.post("/bot-move")
def bot_move(body: BotMoveBody) -> dict[str, Any]:
    state = gl.get_game(body.game_id)
    if not state:
        raise HTTPException(status_code=404, detail="Unknown game_id")
        
    last_bot_move = None
    if state.current_turn == "ai" and not state.game_over:
        move = get_ai_move(state)
        if not move:
            gl.check_game_end(state)
        else:
            fr, fc = move["from"]
            tr, tc = move["to"]
            gl.apply_ai_move(state, fr, fc, tr, tc)
            last_bot_move = {"from": [fr, fc], "to": [tr, tc]}
            
    return {
        "ok": True,
        **state.to_dict(),
        "player_captured": state.last_capture,
        "last_bot_move": last_bot_move,
    }
