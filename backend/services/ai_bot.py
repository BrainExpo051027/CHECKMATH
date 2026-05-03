from __future__ import annotations

import random
from typing import Any, Optional

from services import game_logic as gl


def evaluate_material(board: list[list[int]]) -> float:
    v = 0.0
    for r in range(8):
        for c in range(8):
            p = board[r][c]
            if p == gl.EMPTY:
                continue
            
            val = gl.piece_value(p)
            type_ = gl.piece_type(p)
            
            if type_ == gl.HUMAN_MAN:
                v -= (3.0 + 0.1 * r + val * 0.01)
            elif type_ == gl.HUMAN_KING:
                v -= (5.0 + val * 0.01)
            elif type_ == gl.AI_MAN:
                v += (3.0 + 0.1 * (7 - r) + val * 0.01)
            elif type_ == gl.AI_KING:
                v += (5.0 + val * 0.01)
    return v


def evaluate_state(state: gl.GameState) -> float:
    if state.game_over:
        if state.winner == "ai":
            return 1e6
        if state.winner == "human":
            return -1e6
        return 0.0
    return evaluate_material(state.board)


def _minimax(state: gl.GameState, depth: int, alpha: float, beta: float) -> float:
    if depth == 0 or state.game_over:
        return evaluate_state(state)

    human_side = state.current_turn == "human"
    moves = gl.all_legal_moves(state.board, human_side)
    if not moves:
        return evaluate_state(state)

    if human_side:
        val = float("inf")
        for m in moves:
            ns = gl.copy_state(state)
            ok, _ = gl._apply_move(ns, m["from"][0], m["from"][1], m["to"][0], m["to"][1], human_side)
            if not ok:
                continue
            val = min(val, _minimax(ns, depth - 1, alpha, beta))
            beta = min(beta, val)
            if beta <= alpha:
                break
        return val

    val = float("-inf")
    for m in moves:
        ns = gl.copy_state(state)
        ok, _ = gl._apply_move(ns, m["from"][0], m["from"][1], m["to"][0], m["to"][1], human_side)
        if not ok:
            continue
        val = max(val, _minimax(ns, depth - 1, alpha, beta))
        alpha = max(alpha, val)
        if beta <= alpha:
            break
    return val


def random_move(board: list[list[int]]) -> Optional[dict[str, Any]]:
    moves = gl.all_legal_moves(board, False)
    if not moves:
        return None
    return random.choice(moves)


def greedy_move(board: list[list[int]]) -> Optional[dict[str, Any]]:
    moves = gl.all_legal_moves(board, False)
    if not moves:
        return None
    captures = [m for m in moves if m["capture"]]
    if captures:
        return random.choice(captures)
    return random.choice(moves)


def minimax_move(state: gl.GameState) -> Optional[dict[str, Any]]:
    moves = gl.all_legal_moves(state.board, False)
    if not moves:
        return None
    best: Optional[dict[str, Any]] = None
    best_score = float("-inf")
    for m in moves:
        ns = gl.copy_state(state)
        ok, _ = gl._apply_move(ns, m["from"][0], m["from"][1], m["to"][0], m["to"][1], False)
        if not ok:
            continue
        sc = _minimax(ns, 5, float("-inf"), float("inf"))
        if sc > best_score:
            best_score = sc
            best = m
    return best or moves[0]


def get_ai_move(state: gl.GameState) -> Optional[dict[str, Any]]:
    diff = (state.difficulty or "medium").lower()
    board = state.board
    if diff == "easy":
        return random_move(board)
    if diff == "medium":
        return greedy_move(board)
    if diff == "hard":
        return minimax_move(state)
    return greedy_move(board)
