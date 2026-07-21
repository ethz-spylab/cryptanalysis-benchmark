import json
from argparse import ArgumentParser
from typing import Any

import requests
from pydantic import BaseModel, Field, TypeAdapter

SERVER_URL = "http://game_controller:8000"

#####################
# INPUT DATA MODELS #
#####################


class OracleQueryRequest(BaseModel):
    oracle_type: str
    arguments: dict[str, str] = Field(description="The input arguments for the oracle.")


class StagePayload(BaseModel):
    stage_payload: dict[str, Any] = Field(description="The payload for the stage")


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


####################
# GLOBAL VARIABLES #
####################
ACTION_URL_MAP = {
    "list_security_games": {
        "url": f"{SERVER_URL}/list_security_games",
        "method": "get",
        "response": TypeAdapter(ListSecurityGamesResponse),
    },
    "start_security_game": {
        "url": f"{SERVER_URL}/start_security_game",
        "method": "get",
        "response": TypeAdapter(
            StartSecurityGameResponse | MissingSecurityGameResponse
        ),
    },
    "game_description": {
        "url": f"{SERVER_URL}/game_description",
        "method": "get",
        "response": TypeAdapter(GameDescriptionResponse),
    },
    "game_status": {
        "url": f"{SERVER_URL}/game_status",
        "method": "get",
        "response": TypeAdapter(GameStatusResponse),
    },
    "execute_current_stage": {
        "url": f"{SERVER_URL}/execute_current_stage",
        "method": "post",
        "request": StagePayload,
        "response": TypeAdapter(ExecuteCurrentStageResponse),
    },
    "oracle_query": {
        "url": f"{SERVER_URL}/oracle_query",
        "method": "post",
        "request": OracleQueryRequest,
        "response": TypeAdapter(OracleQueryResponse),
    },
}

if __name__ == "__main__":
    # Parse arguments
    parser = ArgumentParser()
    parser.add_argument("--action", type=str, required=True)
    parser.add_argument(
        "--json",
        type=str,
        help='Payload as a JSON string (e.g., \'{"stage_payload": {"key": "value"}}\')',
    )
    args = parser.parse_args()

    # Parse payload from JSON string
    payload_dict = {}
    if args.json:
        try:
            payload_dict = json.loads(args.json)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON string: {e}")

    if args.action not in ACTION_URL_MAP:
        raise ValueError(
            f"Invalid action: {args.action}. Valid actions are: {list(ACTION_URL_MAP.keys())}"
        )

    url = ACTION_URL_MAP[args.action]["url"]
    method = ACTION_URL_MAP[args.action]["method"]

    if "request" in ACTION_URL_MAP[args.action]:
        # If possible, validate the payload
        data = (
            ACTION_URL_MAP[args.action]["request"]
            .model_validate(payload_dict)
            .model_dump()
        )
    else:
        data = payload_dict

    # Use the appropriate HTTP method
    if method == "get":
        response = requests.get(url, params=data)
    elif method == "post":
        response = requests.post(url, json=data)
    else:
        raise ValueError(f"Unsupported HTTP method: {method}")

    # Handle 404 errors with a clearer message
    if response.status_code == 404:
        error_detail = response.json().get("detail", "Resource not found")
        raise RuntimeError(f"Error: {error_detail}")

    response.raise_for_status()

    # Validate the response
    result = ACTION_URL_MAP[args.action]["response"].validate_python(response.json())
    if args.action == "oracle_query" and isinstance(result, OracleQueryResponse):
        # This makes it easier to parse the response in the attack script
        print(json.dumps(result.oracle_result))
    else:
        print(result)
