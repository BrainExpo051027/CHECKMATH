from __future__ import annotations

import json
import random
from typing import Any, Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter(tags=["multiplayer"])

# In-memory room storage:
# { room_code: { 'host': ws, 'guest': ws, 'state': dict|None,
#                'host_name': str, 'guest_name': str, 'started': bool } }
_rooms: dict[str, dict[str, Any]] = {}


def _generate_code() -> str:
    return str(random.randint(1000, 9999))


def _make_initial_state(host_name: str = "Host", guest_name: str = "Guest", starting_turn: str = "human") -> dict[str, Any]:
    """Create a fresh SciDama board. host=human pieces, guest=ai pieces."""
    from services import game_logic as gl
    gid, st = gl.create_game("medium", "online_pvp", host_name, guest_name, starting_turn)
    state_dict = st.to_dict()
    state_dict["game_id"] = gid
    # current_turn=='human' means host's turn, 'ai' means guest's turn.
    return {"type": "state", "whose_turn": "host" if starting_turn == "human" else "guest", **state_dict}


def _state_with_role(room: dict[str, Any]) -> dict[str, Any]:
    """Return the stored state with an up-to-date whose_turn field."""
    s = dict(room["state"])
    ct = s.get("current_turn", "human")
    s["whose_turn"] = "host" if ct == "human" else "guest"
    # Include player names so clients can display them
    s["host_name"] = room.get("host_name", "Host")
    s["guest_name"] = room.get("guest_name", "Guest")
    return s


async def _broadcast(room_code: str, message: dict, skip: Optional[WebSocket] = None):
    room = _rooms.get(room_code)
    if not room:
        return
    text = json.dumps(message)
    for key in ("host", "guest"):
        ws = room.get(key)
        if ws and ws is not skip:
            try:
                await ws.send_text(text)
            except Exception:
                pass


@router.websocket("/ws/matchmaking/{room_code}")
async def matchmaking_ws(websocket: WebSocket, room_code: str):
    player_name: str = websocket.query_params.get("name", "").strip() or "Player"
    # Expected role from client (to prevent guests hijacking empty rooms)
    expected_role: str = websocket.query_params.get("role", "").strip()

    await websocket.accept()
    room = _rooms.setdefault(
        room_code,
        {
            "host": None, "guest": None, "state": None,
            "host_name": "", "guest_name": "", "started": False,
        },
    )
    
    print(f"[WS] Connect attempt: room={room_code}, name={player_name}")
    print(f"[WS] Room state currently: host={'connected' if room['host'] else 'empty'}, guest={'connected' if room['guest'] else 'empty'}")

    role = None
    if expected_role == "host":
        if room["host"] is not None:
            # Tell them it's already full
            print(f"[WS] Rejecting {player_name}: host already exists for {room_code}")
            await websocket.send_text(json.dumps({"type": "error", "message": "Host already exists"}))
            await websocket.close()
            return
            
        print(f"[WS] Assigning {player_name} as HOST in room {room_code}")
        # ── First connection becomes the HOST ──────────────────────────────
        room["host"] = websocket
        room["host_name"] = player_name
        role = "host"
        await websocket.send_text(json.dumps({
            "type": "joined",
            "role": "host",
            "room_code": room_code,
            "your_name": player_name,
        }))

    elif expected_role == "guest":
        if room["host"] is None:
            print(f"[WS] Rejecting {player_name}: room {room_code} doesn't exist or host disconnected")
            await websocket.send_text(json.dumps({"type": "error", "message": "Room not found or host disconnected"}))
            await websocket.close()
            # Clean up the empty room structure
            if room["host"] is None and room["guest"] is None:
                _rooms.pop(room_code, None)
            return
            
        if room["guest"] is not None:
            print(f"[WS] Rejecting {player_name}: room {room_code} is full")
            await websocket.send_text(json.dumps({"type": "error", "message": "Room full"}))
            await websocket.close()
            return

        # ── Second connection becomes the GUEST ────────────────────────────
        print(f"[WS] Assigning {player_name} as GUEST in room {room_code}")
        room["guest"] = websocket
        room["guest_name"] = player_name
        role = "guest"

        # Tell guest their role + host's name
        await websocket.send_text(json.dumps({
            "type": "joined",
            "role": "guest",
            "room_code": room_code,
            "your_name": player_name,
            "opponent_name": room["host_name"],
        }))

        # Tell host the guest's name (lobby update — does NOT start game)
        if room["host"]:
            try:
                await room["host"].send_text(json.dumps({
                    "type": "opponent_joined",
                    "opponent_name": player_name,
                }))
            except Exception:
                pass

        # If the host had already started the game and it's active
        if room["started"] and room["state"] is not None:
            state_msg = json.dumps(_state_with_role(room))
            for key in ("host", "guest"):
                ws = room.get(key)
                if ws:
                    try:
                        await ws.send_text(state_msg)
                    except Exception as e:
                        print(f"[WS] Error sending state to {key}: {e}")
                        pass
        elif room.get("coin_toss_active"):
            # Resend coin toss active state if guest reconnects during toss
            await websocket.send_text(json.dumps({"type": "coin_toss_start"}))

    else:
        # Invalid role passed
        await websocket.send_text(json.dumps({"type": "error", "message": "Invalid role requested"}))
        await websocket.close()
        return

    # ── Message loop ───────────────────────────────────────────────────────
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            msg_type = msg.get("type")

            # ── HOST: start the game (triggers coin toss) ─────────────────
            if msg_type == "start" and role == "host":
                room["coin_toss_active"] = True
                await _broadcast(room_code, {"type": "coin_toss_start"})

            # ── GUEST: choose coin side ───────────────────────────────────
            elif msg_type == "coin_toss_choose" and role == "guest" and room.get("coin_toss_active"):
                choice = msg.get("choice", "heads")
                # Flip the coin!
                result = random.choice(["heads", "tails"])
                
                if choice == result:
                    winner_role = "guest"
                    starting_turn = "ai"
                else:
                    winner_role = "host"
                    starting_turn = "human"

                await _broadcast(room_code, {
                    "type": "coin_toss_result",
                    "result": result,
                    "winner": winner_role
                })

                room["coin_toss_active"] = False
                room["started"] = True

                # Wait for animation to play on client side (about 3.5 seconds)
                import asyncio
                await asyncio.sleep(4.0)
                
                # Check if players are still in the room
                if room.get("host") is None or room.get("guest") is None:
                    continue

                # Create and broadcast actual game state
                room["state"] = _make_initial_state(
                    host_name=room["host_name"],
                    guest_name=room["guest_name"] or "Guest",
                    starting_turn=starting_turn
                )
                state_msg = json.dumps(_state_with_role(room))
                for key in ("host", "guest"):
                    ws = room.get(key)
                    if ws:
                        try:
                            await ws.send_text(state_msg)
                        except Exception:
                            pass

            # ── MOVE ──────────────────────────────────────────────────────
            elif msg_type == "move":
                gid = room["state"].get("game_id") if room["state"] else None
                fr = msg.get("from_row")
                fc = msg.get("from_col")
                tr = msg.get("to_row")
                tc = msg.get("to_col")

                if gid and all(v is not None for v in (fr, fc, tr, tc)):
                    try:
                        from services import game_logic as gl
                        state_obj = gl.get_game(gid)
                        if state_obj and not state_obj.game_over:
                            is_host_move = (role == "host")
                            expected_turn = "human" if is_host_move else "ai"

                            if state_obj.current_turn == expected_turn:
                                is_human = is_host_move
                                ok, msg_txt = gl._apply_move(state_obj, fr, fc, tr, tc, is_human)
                                if ok:
                                    gl.check_game_end(state_obj)
                                    room["state"] = {
                                        "type": "state",
                                        "game_id": gid,
                                        **state_obj.to_dict(),
                                    }
                                    await _broadcast(room_code, _state_with_role(room))
                                    continue
                                else:
                                    try:
                                        await websocket.send_text(json.dumps({
                                            "type": "error",
                                            "message": msg_txt,
                                        }))
                                    except Exception:
                                        pass
                                    continue
                            else:
                                try:
                                    await websocket.send_text(json.dumps({
                                        "type": "error",
                                        "message": "Not your turn",
                                    }))
                                except Exception:
                                    pass
                                continue
                    except Exception:
                        await _broadcast(room_code, msg, skip=websocket)

            # ── REMATCH ───────────────────────────────────────────────────
            elif msg_type == "rematch":
                room["state"] = _make_initial_state(
                    host_name=room["host_name"],
                    guest_name=room["guest_name"] or "Guest",
                )
                room["started"] = True
                await _broadcast(room_code, _state_with_role(room))

            elif msg_type == "chat":
                await _broadcast(room_code, msg, skip=websocket)

            else:
                await _broadcast(room_code, msg, skip=websocket)

    except WebSocketDisconnect as cd:
        print(f"[WS] Client {role} ({player_name}) disconnected from {room_code} with {cd.code}")
        pass
    except Exception as e:
        print(f"[WS] Exception for {role} ({player_name}) in {room_code}: {e}")
        pass
    finally:
        print(f"[WS] Cleaning up {role} ({player_name}) for room {room_code}")
        if role == "host":
            room["host"] = None
            room["started"] = False   # reset so next host can restart
        elif role == "guest":
            room["guest"] = None
            room["guest_name"] = ""
        if room["host"] is None and room["guest"] is None:
            _rooms.pop(room_code, None)
        else:
            remaining_ws = room.get("host") or room.get("guest")
            if remaining_ws:
                s = room.get("state")
                # If a game was aggressively in progress, trigger forfeit
                if s and not s.get("game_over"):
                    s["game_over"] = True
                    winner_entity = "ai" if role == "host" else "human"
                    s["winner"] = winner_entity
                    s["player_captured"] = False
                    
                    if winner_entity == "human":
                        s["human_score"] += 100.0
                    else:
                        s["ai_score"] += 100.0
                        
                    try:
                        await remaining_ws.send_text(json.dumps(_state_with_role(room)))
                    except Exception:
                        pass
                else:
                    # Otherwise (lobby phase), just notify they left
                    try:
                        await remaining_ws.send_text(json.dumps({"type": "opponent_left"}))
                    except Exception:
                        pass
