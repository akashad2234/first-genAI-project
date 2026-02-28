## Phase 3 – LLM Orchestrator (Groq)

This folder implements **Phase 3** from `ARCHITECTURE.md`:

- A thin Groq LLM client wrapper.
- An orchestrator that turns:
  - Structured user preferences, and
  - A list of restaurant candidates
  into a **prompt** for Groq and parses the JSON response into a Python object.

The code is written in **Python** to align with the planned FastAPI backend.  
You can use it from the backend later without modification.

---

### Environment & Dependencies

- **Python**: 3.9+ (recommended 3.11+)
- **Dependencies**:
  - `groq` (official Groq Python client)

Install:

```bash
pip install groq
```

Environment variables (used by the client):

- `GROQ_API_KEY` – your Groq API key (required at runtime).
- `GROQ_MODEL` – model name, e.g. `llama-3.3-70b-versatile`.
- `LLM_TEMPERATURE` – optional, default: `0.2`.
- `LLM_MAX_TOKENS` – optional, default: no explicit limit.

---

### Structure

- `llm_client.py` – `GroqLLMClient` that wraps Groq's `chat.completions.create`.
- `orchestrator.py` – builds prompts and parses Groq responses.

---

### Usage Example (pseudo-backend code)

```python
from phase3_llm.orchestrator import (
    UserPreferences,
    RestaurantCandidate,
    generate_restaurant_recommendations,
)

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
    # ... more candidates ...
]

result = generate_restaurant_recommendations(
    user_preferences=prefs,
    candidates=candidates,
    max_recommendations=5,
)

print(result.title)
print(result.summary)
for rec in result.recommendations:
    print(rec.restaurant_name, rec.match_score, rec.reason)
```

---

### Tests

We can add test cases **once a Groq API key is configured**.  
Recommended approach:

- Unit-test prompt-building and parsing logic with **mocked Groq responses**.
- Optionally add an **integration test** (skipped by default) that hits the real Groq API when `GROQ_API_KEY` is present.

