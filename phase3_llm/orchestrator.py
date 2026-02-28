from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from typing import Any, Dict, List, Optional

from .llm_client import GroqLLMClient


@dataclass
class UserPreferences:
    price_preference: Optional[str] = None  # e.g. "low" | "medium" | "high" | "premium"
    location: Optional[str] = None  # e.g. "Bangalore, Indiranagar"
    min_rating: Optional[float] = None  # e.g. 4.0
    cuisine_preferences: Optional[List[str]] = None  # e.g. ["italian", "pizza"]


@dataclass
class RestaurantCandidate:
    id: str
    name: str
    city: Optional[str] = None
    locality: Optional[str] = None
    price_bucket: Optional[str] = None  # "low" | "medium" | "high" | "premium"
    rating: Optional[float] = None
    cuisines: Optional[List[str]] = None

    # Optional raw fields if you want to pass through original dataset info.
    raw: Optional[Dict[str, Any]] = None


@dataclass
class LLMRecommendation:
    restaurant_id: Optional[str]
    restaurant_name: str
    match_score: Optional[float]
    reason: str


@dataclass
class LLMRecommendationsResult:
    title: str
    summary: str
    recommendations: List[LLMRecommendation]
    raw_response_text: str


def _build_system_prompt() -> str:
    return (
        "You are an AI restaurant recommendation assistant. "
        "Given a user's preferences and a list of candidate restaurants, "
        "you must select and clearly explain the best options for the user.\n\n"
        "Requirements:\n"
        "- Always base your answer ONLY on the provided candidate restaurants.\n"
        "- Prefer restaurants that match the requested cuisine, location, and price level.\n"
        "- Prefer higher ratings, but explain trade-offs when needed.\n"
        "- Output strictly in the JSON schema described in the instructions."
    )


def _build_user_prompt(
    user_preferences: UserPreferences,
    candidates: List[RestaurantCandidate],
    max_recommendations: int,
) -> str:
    prefs_dict = asdict(user_preferences)
    # Trim None fields for a cleaner prompt.
    clean_prefs = {k: v for k, v in prefs_dict.items() if v not in (None, [], "")}

    # Limit how many candidates we send to the model for context.
    truncated_candidates = candidates[:50]
    serialized_candidates: List[Dict[str, Any]] = []
    for c in truncated_candidates:
        d = asdict(c)
        # Avoid huge raw payloads; keep only shallow fields in 'raw'.
        if d.get("raw") and isinstance(d["raw"], dict):
            d["raw"] = {k: d["raw"][k] for k in list(d["raw"])[:8]}
        serialized_candidates.append(d)

    schema_description = {
        "title": "Short title summarizing the recommendation context",
        "summary": "1-2 paragraphs explaining your high-level reasoning",
        "recommendations": [
            {
                "restaurant_id": "id string or null",
                "restaurant_name": "string",
                "match_score": "number between 0 and 100 reflecting how well it matches the user preferences",
                "reason": "1-3 sentences explaining why this restaurant is a good choice",
            }
        ],
    }

    prompt = {
        "instructions": (
            "You are given:\n"
            "1) user_preferences: the user's stated preferences, and\n"
            "2) candidate_restaurants: a list of possible restaurants that you MUST choose from.\n\n"
            f"Select up to {max_recommendations} restaurants that best match the preferences.\n"
            "Return ONLY a single JSON object matching the 'response_schema' below. "
            "Do not include any extra commentary or markdown.\n"
        ),
        "user_preferences": clean_prefs,
        "candidate_restaurants": serialized_candidates,
        "response_schema": schema_description,
    }

    # Keep it as compact JSON for better token efficiency.
    return json.dumps(prompt, ensure_ascii=False, indent=2)


def _parse_llm_response(text: str) -> LLMRecommendationsResult:
    """
    Parse the LLM's JSON response text into a structured dataclass.
    """
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        # Surface a descriptive error that can be logged or handled upstream.
        snippet = text[:500]
        raise ValueError(f"Failed to parse LLM JSON response: {exc}. Snippet: {snippet!r}") from exc

    title = data.get("title") or "Restaurant Recommendations"
    summary = data.get("summary") or ""

    recs_data = data.get("recommendations") or []
    recommendations: List[LLMRecommendation] = []

    for item in recs_data:
        if not isinstance(item, dict):
            continue

        recommendations.append(
            LLMRecommendation(
                restaurant_id=item.get("restaurant_id"),
                restaurant_name=item.get("restaurant_name") or "",
                match_score=item.get("match_score"),
                reason=item.get("reason") or "",
            )
        )

    return LLMRecommendationsResult(
        title=title,
        summary=summary,
        recommendations=recommendations,
        raw_response_text=text,
    )


def generate_restaurant_recommendations(
    user_preferences: UserPreferences,
    candidates: List[RestaurantCandidate],
    max_recommendations: int = 5,
    client: Optional[GroqLLMClient] = None,
) -> LLMRecommendationsResult:
    """
    Main entry point for Phase 3.

    - Builds the system + user prompts.
    - Calls Groq's chat completion API via GroqLLMClient.
    - Parses the JSON result into a strongly-typed object.

    This function does not perform any network calls unless a Groq API key
    is available and the Groq client is installed.
    """
    if not candidates:
        raise ValueError("generate_restaurant_recommendations requires at least one candidate restaurant.")

    system_prompt = _build_system_prompt()
    user_prompt = _build_user_prompt(
        user_preferences=user_preferences,
        candidates=candidates,
        max_recommendations=max_recommendations,
    )

    if client is None:
        client = GroqLLMClient()

    messages: List[Dict[str, Any]] = [
        {
            "role": "system",
            "content": system_prompt,
        },
        {
            "role": "user",
            "content": user_prompt,
        },
    ]

    response_text = client.chat_completion(messages=messages)
    return _parse_llm_response(response_text)

