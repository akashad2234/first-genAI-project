import os
from pathlib import Path

import pytest

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover - handled gracefully at runtime
    load_dotenv = None  # type: ignore[assignment]

from phase3_llm.orchestrator import (
    UserPreferences,
    RestaurantCandidate,
    generate_restaurant_recommendations,
)


def _ensure_env_loaded() -> None:
    """
    Load GROQ_API_KEY from the project's data/.env file if possible.

    This allows you to keep your API key in data/.env (ignored by git)
    without having to export it manually every time.
    """
    if os.getenv("GROQ_API_KEY"):
        return

    if load_dotenv is None:
        # python-dotenv not installed; test will be skipped below.
        return

    # Assume project structure: <root>/phase3_llm/tests/test_integration_groq.py
    test_dir = Path(__file__).resolve().parent
    project_root = test_dir.parent.parent
    env_path = project_root / "data" / ".env"
    if env_path.is_file():
        load_dotenv(dotenv_path=env_path)


_ensure_env_loaded()

GROQ_API_KEY = os.getenv("GROQ_API_KEY")


pytestmark = pytest.mark.skipif(
    not GROQ_API_KEY,
    reason="GROQ_API_KEY not available in environment or data/.env",
)


def test_integration_generate_recommendations():
    """
    Integration test that calls the real Groq LLM.

    This test will only run if GROQ_API_KEY is available. Otherwise it is skipped.
    """
    prefs = UserPreferences(
        price_preference="medium",
        location="Bangalore, Indiranagar",
        min_rating=4.0,
        cuisine_preferences=["italian", "pizza"],
    )

    candidates = [
        RestaurantCandidate(
            id="123",
            name="La Piazza",
            city="Bangalore",
            locality="Indiranagar",
            price_bucket="medium",
            rating=4.4,
            cuisines=["italian", "pizza"],
        ),
        RestaurantCandidate(
            id="456",
            name="Budget Bites",
            city="Bangalore",
            locality="Koramangala",
            price_bucket="low",
            rating=4.0,
            cuisines=["indian", "fast food"],
        ),
    ]

    result = generate_restaurant_recommendations(
        user_preferences=prefs,
        candidates=candidates,
        max_recommendations=2,
    )

    assert result.title
    assert isinstance(result.summary, str)
    assert result.recommendations, "Expected at least one recommendation from Groq"

    for rec in result.recommendations:
        assert rec.restaurant_name
        assert isinstance(rec.reason, str) and rec.reason.strip()

