import uuid
from pathlib import Path
from typing import Any

import oracle_log
from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel, Field
from security_games import IMPLEMENTED_SECURITY_GAMES, SecurityGame, get_security_game
from yaml import Loader, load

####################
# GLOBAL VARIABLES #
####################
with open(Path(__file__).parent / "possible_security_games.yml", "r") as f:
    try:
        POSSIBLE_SECURITY_GAMES: list[str] = load(f, Loader=Loader)["security_games"]
    except Exception as e:
        raise Exception(f"Error loading possible security games: {e}")

    for security_game in POSSIBLE_SECURITY_GAMES:
        if security_game not in IMPLEMENTED_SECURITY_GAMES:
            raise Exception(
                f"Security game {security_game} not found. Choose from: {list(IMPLEMENTED_SECURITY_GAMES.keys())}"
            )

oracle_log.init()

app = FastAPI()
_CURRENT_SECURITY_GAME: SecurityGame | None = None
_CURRENT_GAME_ID: str | None = None

########################
# DEPENDENCY FUNCTIONS #
########################


def get_current_game() -> SecurityGame:
    """Dependency that ensures a security game is currently active."""
    if _CURRENT_SECURITY_GAME is None:
        raise HTTPException(
            status_code=404,
            detail="No security game started. Start a security game first.",
        )
    return _CURRENT_SECURITY_GAME


def get_current_game_id() -> str:
    """Dependency that returns the current game ID."""
    if _CURRENT_GAME_ID is None:
        raise HTTPException(
            status_code=404,
            detail="No security game started. Start a security game first.",
        )
    return _CURRENT_GAME_ID


#####################
# INPUT DATA MODELS #
#####################


class OracleQueryRequest(BaseModel):
    oracle_type: str
    arguments: dict[str, str] = Field(description="The input arguments for the oracle.")


class StagePayload(BaseModel):
    stage_payload: dict[str, Any] = Field(description="The payload for the stage.")


######################
# RETURN DATA MODELS #
######################


class ListSecurityGamesResponse(BaseModel):
    security_games: list[str]


class StartSecurityGameResponse(BaseModel):
    message: str
    game_id: str


class GameDescriptionResponse(BaseModel):
    game_description: str


class GameStatusResponse(BaseModel):
    game_id: str
    finished: bool
    success: bool
    game_description: str
    current_stage: int
    current_stage_description: str
    stages: int


class ExecuteCurrentStageResponse(BaseModel):
    stage_result: dict[str, Any]


class OracleQueryResponse(BaseModel):
    oracle_result: dict[str, str]


class MissingSecurityGameResponse(BaseModel):
    error: str = Field(default="No security game started. Start a security game first.")
    success: bool = Field(default=False)
    finished: bool = Field(default=True)


#################
# API ENDPOINTS #
#################


@app.get("/list_security_games")
def list_security_games() -> ListSecurityGamesResponse:
    return ListSecurityGamesResponse(security_games=POSSIBLE_SECURITY_GAMES)


@app.get("/start_security_game")
def start_security_game(
    security_game_name: str,
) -> StartSecurityGameResponse | MissingSecurityGameResponse:
    if security_game_name not in POSSIBLE_SECURITY_GAMES:
        return MissingSecurityGameResponse(
            error=f"Security game {security_game_name} not found. Choose from: {POSSIBLE_SECURITY_GAMES}"
        )
    global _CURRENT_SECURITY_GAME, _CURRENT_GAME_ID
    _CURRENT_SECURITY_GAME = get_security_game(security_game_name)
    _CURRENT_GAME_ID = str(uuid.uuid4())
    oracle_log.set_current_game(_CURRENT_GAME_ID, security_game_name)
    game_state = _CURRENT_SECURITY_GAME.game_state()
    secret_vars = {
        var: getattr(game_state, var, None)
        for var in game_state.required_state_variables()
    }
    print(f"Newly generated secrets: {secret_vars}")
    return StartSecurityGameResponse(
        message=f"Security game {security_game_name} started. Current stage: {_CURRENT_SECURITY_GAME.stages()[0].stage_description()}",
        game_id=_CURRENT_GAME_ID,
    )


@app.get("/game_description")
def game_description(
    game: SecurityGame = Depends(get_current_game),
) -> GameDescriptionResponse:
    return GameDescriptionResponse(game_description=game.game_description())


@app.get("/game_status")
def game_status(
    game: SecurityGame = Depends(get_current_game),
    game_id: str = Depends(get_current_game_id),
) -> GameStatusResponse:
    return GameStatusResponse(game_id=game_id, **game.game_status())


@app.post("/execute_current_stage")
def execute_current_stage(
    request: StagePayload,
    game: SecurityGame = Depends(get_current_game),
) -> ExecuteCurrentStageResponse:
    return ExecuteCurrentStageResponse(
        stage_result=game.execute_current_stage(request.stage_payload)
    )


@app.post("/oracle_query")
def oracle_query(
    request: OracleQueryRequest,
    game: SecurityGame = Depends(get_current_game),
) -> OracleQueryResponse:
    return OracleQueryResponse(
        oracle_result=game.oracle_query(request.oracle_type, request.arguments)
    )
