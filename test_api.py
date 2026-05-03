import requests

base = "http://127.0.0.1:8765"
res = requests.post(f"{base}/start-game", json={"difficulty": "easy"})
data = res.json()
gid = data["game_id"]
print("Game started:", gid)

# Make a normal move
move_data = {
    "game_id": gid,
    "from_row": 2,
    "from_col": 1,
    "to_row": 3,
    "to_col": 0
}
res2 = requests.post(f"{base}/move", json=move_data)
print("Move result:", res2.status_code, res2.json())
