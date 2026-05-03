from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware

from database.db import init_db
from routes import achievement_routes, auth_routes, game_routes, leaderboard_routes, multiplayer_routes

init_db()

app = FastAPI(title="CheckMath API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_routes.router)
app.include_router(game_routes.router)
app.include_router(leaderboard_routes.router)
app.include_router(achievement_routes.router)
app.include_router(multiplayer_routes.router)

@app.get("/")
def root() -> dict[str, str | list[str]]:
    return {
        "service": "CheckMath API",
        "docs": "/docs",
        "health": "/health",
        "endpoints": [
            "POST /start-game",
            "POST /move",
            "GET /game-state",
            "GET /leaderboard",
            "POST /update-score",
            "GET /achievements",
            "POST /unlock",
            "GET /resolve-user",
        ],
    }


@app.get("/favicon.ico", include_in_schema=False)
def favicon() -> Response:
    return Response(status_code=204)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
