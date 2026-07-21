import importlib
import inspect
from pathlib import Path

from .base import SecurityGame

__all__ = ["SecurityGame", "get_security_game", "IMPLEMENTED_SECURITY_GAMES"]


def _discover_security_games() -> dict[str, type[SecurityGame]]:
    """Automatically discover and register all SecurityGame subclasses in this package."""
    games = {}

    # Get the directory containing this __init__.py file
    package_dir = Path(__file__).parent

    # Find all Python files in this directory (excluding __init__.py and base.py)
    for py_file in package_dir.glob("*.py"):
        if py_file.name in ("__init__.py", "base.py"):
            continue

        # Import the module
        module_name = f".{py_file.stem}"
        try:
            module = importlib.import_module(module_name, package=__package__)

            # Find all classes in the module that are subclasses of SecurityGame
            for name, obj in inspect.getmembers(module, inspect.isclass):
                # Check if it's a subclass of SecurityGame but not SecurityGame itself
                if issubclass(obj, SecurityGame) and obj is not SecurityGame:
                    games[name] = obj
        except Exception as e:
            print(f"Warning: Failed to import {module_name}: {e}")

    return games


# Automatically discover and register all security games
IMPLEMENTED_SECURITY_GAMES = _discover_security_games()


def get_security_game(security_game_name: str) -> SecurityGame:
    if security_game_name not in IMPLEMENTED_SECURITY_GAMES:
        available_games = ", ".join(IMPLEMENTED_SECURITY_GAMES.keys())
        raise ValueError(
            f"Security game '{security_game_name}' not found. "
            f"Available games: {available_games}"
        )
    return IMPLEMENTED_SECURITY_GAMES[security_game_name]()
