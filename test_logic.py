import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), "backend"))

from services.game_logic import *

game_id, state = create_game("easy")
b = state.board
print("Board initialized.")

moves = all_legal_moves(b, True)
print(f"Legal human moves: {moves}")

if moves:
    m = moves[0]
    ok, msg, new_state = try_move(game_id, m["from"][0], m["from"][1], m["to"][0], m["to"][1])
    print(f"Applied move {m}: ok={ok}, msg={msg}")
else:
    print("NO MOVES?!")
