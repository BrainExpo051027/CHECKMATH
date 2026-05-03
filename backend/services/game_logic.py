"""
CheckMath: checkers on squares where (row + col) % 2 == 1 (symbol / 'white' tiles).
Row 0 is the bottom; human plays from bottom, AI from top.
SciDama rules applied: Mayor (must take max path length) and calculating based on chip values.
"""
from __future__ import annotations

import copy
import uuid
import random
from dataclasses import dataclass, field
from typing import Any, Literal, Optional, List, Dict, Tuple

from services.scoring import calculate_score

# Board layout: row 0 = bottom. Symbols on odd (row+col) cells only; even cells are "".
BOARD_SYMBOLS: list[list[str]] = [
    ["", "+", "", "-", "", "÷", "", "×"],
    ["-", "", "+", "", "×", "", "÷", ""],
    ["", "÷", "", "×", "", "+", "", "-"],
    ["×", "", "÷", "", "-", "", "+", ""],
    ["", "+", "", "-", "", "÷", "", "×"],
    ["-", "", "+", "", "×", "", "÷", ""],
    ["", "÷", "", "×", "", "+", "", "-"],
    ["×", "", "÷", "", "-", "", "+", ""],
]

EMPTY = 0
HUMAN_MAN = 1
HUMAN_KING = 2
AI_MAN = 3
AI_KING = 4

def piece_type(p: int) -> int:
    return p // 100 if p > 0 else 0

def piece_value(p: int) -> int:
    return p % 100 if p > 0 else 0

def make_piece(type_: int, value: int) -> int:
    return type_ * 100 + value

def is_play_square(r: int, c: int) -> bool:
    return 0 <= r < 8 and 0 <= c < 8 and (r + c) % 2 == 1

def initial_board() -> list[list[int]]:
    b = [[EMPTY] * 8 for _ in range(8)]
    human_vals = list(range(1, 13))
    ai_vals = list(range(1, 13))
    
    random.shuffle(human_vals)
    random.shuffle(ai_vals)
    
    h_idx = 0
    a_idx = 0
    for r in range(8):
        for c in range(8):
            if not is_play_square(r, c):
                continue
            if r < 3:
                b[r][c] = make_piece(HUMAN_MAN, human_vals[h_idx])
                h_idx += 1
            elif r > 4:
                b[r][c] = make_piece(AI_MAN, ai_vals[a_idx])
                a_idx += 1
    return b

def _is_human(p: int) -> bool:
    return piece_type(p) in (HUMAN_MAN, HUMAN_KING)

def _is_ai(p: int) -> bool:
    return piece_type(p) in (AI_MAN, AI_KING)

def _is_king(p: int) -> bool:
    return piece_type(p) in (HUMAN_KING, AI_KING)

def _directions_for_piece(p: int, side: Literal["human", "ai"]) -> list[tuple[int, int]]:
    if _is_king(p):
        return [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    if side == "human":
        return [(1, -1), (1, 1)]
    return [(-1, -1), (-1, 1)]

def _maybe_promote(r: int, c: int, p: int) -> int:
    pt = piece_type(p)
    val = piece_value(p)
    if pt == HUMAN_MAN and r == 7:
        return make_piece(HUMAN_KING, val)
    if pt == AI_MAN and r == 0:
        return make_piece(AI_KING, val)
    return p

@dataclass
class GameState:
    board: list[list[int]]
    current_turn: Literal["human", "ai"]
    human_score: float
    ai_score: float
    difficulty: str
    game_over: bool = False
    game_mode: str = "vs_ai"
    player1_name: str = "Player 1"
    player2_name: str = "Bot"
    winner: Optional[Literal["human", "ai", "draw"]] = None
    last_capture: bool = False
    last_moved_piece: Optional[Tuple[int, int]] = None
    calculations: List[str] = field(default_factory=list)
    player_captured: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "game_id": getattr(self, "_game_id", ""),
            "board": self.board,
            "current_turn": self.current_turn,
            "human_score": self.human_score,
            "ai_score": self.ai_score,
            "game_mode": self.game_mode,
            "player1_name": self.player1_name,
            "player2_name": self.player2_name,
            "difficulty": self.difficulty,
            "game_over": self.game_over,
            "winner": self.winner,
            "last_capture": self.last_capture,
            "player_captured": self.player_captured,
            "board_symbols": BOARD_SYMBOLS,
            "calculations": self.calculations,
        }

GAMES: dict[str, GameState] = {}

def create_game(difficulty: str, game_mode: str = "vs_ai", p1: str = "Player", p2: str = "Bot", starting_turn: str = "human") -> tuple[str, GameState]:
    gid = str(uuid.uuid4())
    state = GameState(
        board=initial_board(),
        current_turn=starting_turn,
        human_score=0.0,
        ai_score=0.0,
        difficulty=difficulty,
        game_mode=game_mode,
        player1_name=p1,
        player2_name=p2,
    )
    setattr(state, "_game_id", gid)
    GAMES[gid] = state
    return gid, state

def get_game(game_id: str) -> Optional[GameState]:
    return GAMES.get(game_id)

def count_pieces(board: list[list[int]], human: bool) -> int:
    s = 0
    for r in range(8):
        for c in range(8):
            if human and _is_human(board[r][c]):
                s += 1
            if not human and _is_ai(board[r][c]):
                s += 1
    return s

# --- MAYOR RULES IMPLEMENTATION ---
def get_all_paths_from(board: list[list[int]], r: int, c: int, human: bool) -> List[List[Dict]]:
    """Returns a list of all complete capture paths starting from (r,c)."""
    p = board[r][c]
    side: Literal["human", "ai"] = "human" if human else "ai"
    dirs = _directions_for_piece(p, side)
    
    paths = []
    
    for dr in (-2, 2):
        for dc in (-2, 2):
            nr, nc = r + dr, c + dc
            if not (0 <= nr < 8 and 0 <= nc < 8):
                continue
            if board[nr][nc] != EMPTY:
                continue
            
            mid_r, mid_c = (r + nr) // 2, (c + nc) // 2
            cap = board[mid_r][mid_c]
            enemy = _is_ai(cap) if human else _is_human(cap)
            if not enemy:
                continue
            
            step_r, step_c = dr // 2, dc // 2
            if (step_r, step_c) not in dirs:
                continue
            
            # Formulate the move
            move = {
                "from": [r, c],
                "to": [nr, nc],
                "capture": True,
                "captured_r": mid_r,
                "captured_c": mid_c
            }
            
            # Recurse from new position
            new_board = [row[:] for row in board]
            new_board[nr][nc] = new_board[r][c] # Piece moves
            new_board[r][c] = EMPTY
            new_board[mid_r][mid_c] = EMPTY # enemy removed
            
            sub_paths = get_all_paths_from(new_board, nr, nc, human)
            if not sub_paths:
                paths.append([move])
            else:
                for sub in sub_paths:
                    paths.append([move] + sub)
                    
    return paths

def all_legal_moves(board: list[list[int]], human: bool, must_start_at: Optional[Tuple[int,int]] = None) -> List[Dict]:
    """
    Finds all valid FIRST steps according to Mayor Rules.
    If must_start_at is given, we ONLY consider moves starting with that piece.
    """
    moves = []
    
    # 1. Gather all capture paths
    all_capture_paths = []
    starts = [must_start_at] if must_start_at else [(r, c) for r in range(8) for c in range(8)]
    
    for coord in starts:
        if coord is None: continue
        r, c = coord
        p = board[r][c]
        if human and not _is_human(p): continue
        if not human and not _is_ai(p): continue
        
        paths = get_all_paths_from(board, r, c, human)
        all_capture_paths.extend(paths)
        
    # 2. Filter longest paths (Mayor Rules)
    if all_capture_paths:
        max_len = max(len(p) for p in all_capture_paths)
        longest_paths = [p for p in all_capture_paths if len(p) == max_len]
        
        # We only return the FIRST step of the longest paths as valid next moves
        for p in longest_paths:
            move = p[0]
            # Ensure uniqueness
            if not any(m["from"] == move["from"] and m["to"] == move["to"] for m in moves):
                moves.append(move)
        return moves

    # 3. If no captures are possible, and we are NOT forced to start at a specific piece (mid-jump)
    if must_start_at is not None:
        return [] # Mid-capture but no more captures available == shouldn't happen, but just in case
        
    # Standard sliding moves
    for r in range(8):
        for c in range(8):
            p = board[r][c]
            if human and not _is_human(p): continue
            if not human and not _is_ai(p): continue
            
            side: Literal["human", "ai"] = "human" if human else "ai"
            dirs = _directions_for_piece(p, side)
            
            for dr, dc in dirs:
                nr, nc = r + dr, c + dc
                if 0 <= nr < 8 and 0 <= nc < 8 and board[nr][nc] == EMPTY:
                    moves.append({"from": [r, c], "to": [nr, nc], "capture": False})
                    
    return moves

def try_move(
    game_id: str,
    from_r: int,
    from_c: int,
    to_r: int,
    to_c: int,
) -> tuple[bool, str, Optional[GameState]]:
    state = GAMES.get(game_id)
    if not state or state.game_over:
        return False, "Invalid or finished game", None
    if state.current_turn != "human" and state.game_mode == "vs_ai":
        return False, "Not your turn", None

    is_human = (state.current_turn == "human")
    ok, msg = _apply_move(state, from_r, from_c, to_r, to_c, is_human)
    if not ok:
        return False, msg, None

    check_game_end(state)
    return True, "ok", state
    
def apply_ai_move(state: GameState, fr: int, fc: int, tr: int, tc: int) -> bool:
    ok, _ = _apply_move(state, fr, fc, tr, tc, False)
    return ok

def _apply_move(state: GameState, fr: int, fc: int, tr: int, tc: int, human: bool) -> tuple[bool, str]:
    b = state.board
    if not (is_play_square(fr, fc) and is_play_square(tr, tc)):
        return False, "Invalid squares"
    piece = b[fr][fc]
    if human and not _is_human(piece):
        return False, "Not your piece"
    if not human and not _is_ai(piece):
        return False, "Not your piece"

    # Enforce sequence starting from last moved piece if mid-capture
    must_start_at = state.last_moved_piece if state.last_capture else None
    
    legal_starts = all_legal_moves(b, human, must_start_at)
    match = next((m for m in legal_starts if m["from"] == [fr, fc] and m["to"] == [tr, tc]), None)
    
    if not match:
        return False, "Illegal move. Mayor rule dictates maximum capture sequence!"
        
    state.player_captured = match["capture"]

    if not match["capture"]:
        # Simple move
        b[tr][tc] = _maybe_promote(tr, tc, piece)
        b[fr][fc] = EMPTY
        state.current_turn = "ai" if human else "human"
        state.last_capture = False
        state.last_moved_piece = None
        return True, "ok"

    # Capture move
    mid_r, mid_c = match["captured_r"], match["captured_c"]
    captured_piece = b[mid_r][mid_c]
    
    b[mid_r][mid_c] = EMPTY
    b[tr][tc] = _maybe_promote(tr, tc, piece)
    b[fr][fc] = EMPTY
    
    # SCI-DAMA SCORING
    sym = BOARD_SYMBOLS[tr][tc]
    taker_val = piece_value(piece)
    taken_val = piece_value(captured_piece)
    
    if sym:
        result = calculate_score(float(taker_val), sym, float(taken_val))
        
        # Multipliers
        multiplier = 1
        desc = ""
        if _is_king(piece) and _is_king(captured_piece):
            multiplier = 4
            desc = " (Dama takes Dama x4)"
        elif _is_king(piece) or _is_king(captured_piece):
            multiplier = 2
            desc = " (Dama involved x2)"
            
        final_added = result * multiplier
        
        final_added = abs(result * multiplier)
        
        if human:
            state.human_score += final_added
            log = f"👤 {state.player1_name}: {taker_val} {sym} {taken_val} = {result}{desc} (+{final_added} to Score)"
        else:
            state.ai_score += final_added
            av = "🤖" if state.game_mode == "vs_ai" else "👤"
            log = f"{av} {state.player2_name}: {taker_val} {sym} {taken_val} = {result}{desc} (+{final_added} to Score)"
            
        state.calculations.insert(0, log)
        if len(state.calculations) > 10:
            state.calculations.pop()

    # Continue sequence?
    # We must check if `all_legal_moves` with `must_start_at=(tr, tc)` has ANY captures.
    # Since we enforced Mayor from the start, we are guaranteed to be on the longest path.
    # So if there's a capture left, it's the continuation.
    state.last_capture = True
    state.last_moved_piece = (tr, tc)
    
    next_moves = all_legal_moves(b, human, must_start_at=(tr, tc))
    if next_moves and next_moves[0]["capture"]:
        state.current_turn = "human" if human else "ai" # Same player
    else:
        state.current_turn = "ai" if human else "human" # Next player
        state.last_capture = False
        state.last_moved_piece = None
        
    return True, "ok"

def check_game_end(state: GameState) -> None:
    h = count_pieces(state.board, True)
    a = count_pieces(state.board, False)
    
    legal_moves_available = False
    if h > 0 and a > 0:
        legal = all_legal_moves(state.board, state.current_turn == "human", state.last_moved_piece if state.last_capture else None)
        legal_moves_available = len(legal) > 0
        
    if h == 0 or a == 0 or not legal_moves_available:
        state.game_over = True
        
        # End game tally: remaining chips are added to their respective owners.
        # If the chip is a Dama, its value is doubled.
        for r in range(8):
            for c in range(8):
                p = state.board[r][c]
                if p == EMPTY:
                    continue
                val = piece_value(p)
                mult = 2 if _is_king(p) else 1
                if _is_human(p):
                    state.human_score += (val * mult)
                else:
                    state.ai_score += (val * mult)
                    
        # Winner is whoever has the highest score
        if state.human_score > state.ai_score:
            state.winner = "human"
        elif state.ai_score > state.human_score:
            state.winner = "ai"
        else:
            state.winner = "draw"

def copy_board(board: list[list[int]]) -> list[list[int]]:
    return copy.deepcopy(board)

def copy_state(state: GameState) -> GameState:
    return GameState(
        board=copy_board(state.board),
        current_turn=state.current_turn,
        human_score=state.human_score,
        ai_score=state.ai_score,
        difficulty=state.difficulty,
        game_mode=state.game_mode,
        player1_name=state.player1_name,
        player2_name=state.player2_name,
        game_over=state.game_over,
        winner=state.winner,
        last_capture=state.last_capture,
        last_moved_piece=state.last_moved_piece,
        calculations=state.calculations[:]
    )
