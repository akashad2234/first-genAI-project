## AI Restaurant Recommendation Service – Architecture

This project is an **AI-powered restaurant recommendation service** that:
- **Takes user preferences**: price, location, rating, cuisine (and optional constraints).
- **Retrieves and filters restaurant data** from a **Hugging Face dataset**: `ManikaSaini/zomato-restaurant-recommendation`.
- **Calls an LLM** (e.g. via `groq`) to generate **clear, natural-language recommendations**.
- Exposes a **simple interface** (CLI/SDK first, then API/UI) for end users or other services.

The work is divided into **phases**, so each phase is independently testable and shippable.

---

## High-Level System Overview

- **Client Layer**
  - Simple CLI, notebook, or HTTP API where users specify preferences: `price`, `place`, `rating`, `cuisine`, and optional constraints.
- **Orchestration & Recommendation Service**
  - Validates inputs and calls:
    - **Data Layer**: to fetch candidate restaurants from the Hugging Face dataset.
    - **Ranking & Scoring**: to filter and rank candidates by preference fit.
    - **LLM Layer**: to turn structured candidates + user preferences into clear recommendation text.
- **Data Layer**
  - Connects to Hugging Face dataset (`ManikaSaini/zomato-restaurant-recommendation`), performs caching and basic preprocessing (e.g., column normalization, type casting, feature extraction).
- **LLM Layer**
  - Uses `groq` (or another LLM provider) to:
    - Re-rank candidates if needed.
    - Generate human-friendly explanation (why each restaurant is recommended).
    - Enforce structured output format (e.g., top N results with name, address, key attributes, and reasoning).

---

## Phase Breakdown

### Phase 0 – Project & Environment Setup

- **Goal**: Have a reproducible environment and skeleton structure.
- **Key tasks**:
  - Define Python environment (`requirements.txt` already includes `groq`, `python-dotenv`, `pytest`).
  - Load `.env` configuration for API keys (LLM provider, optional Hugging Face token).
  - Establish base project layout, e.g.:
    - `phase1_data/` – data ingestion & preprocessing.
    - `phase3_llm/` – LLM orchestration and prompt templates.
    - `service/` – orchestration layer, API/CLI, business logic.
    - `tests/` – shared tests across phases.

---

### Phase 1 – Data Ingestion & Preprocessing (`phase1_data/`)

- **Goal**: Build a clean, queryable representation of the Zomato dataset from Hugging Face.
- **Responsibilities**:
  - **Dataset access**:
    - Use `datasets` or direct Hugging Face APIs to download `ManikaSaini/zomato-restaurant-recommendation`.
  - **Schema normalization**:
    - Standardize fields: `name`, `location`, `latitude/longitude` (if present), `cuisine`, `price_range`, `rating`, etc.
    - Normalize categorical values (e.g., cuisine names, price bands).
  - **Filtering utilities**:
    - Functions to filter by:
      - Price range (e.g., low/medium/high or numeric).
      - Place (city/area).
      - Minimum rating.
      - Cuisine(s) (exact or fuzzy matches).
  - **Data access API** (Python functions):
    - `load_dataset()`: returns base dataset.
    - `filter_restaurants(preferences)`: returns candidate subset.
  - **Outputs**:
    - Reusable data utilities in `phase1_data/src/`.
    - Tests in `phase1_data/tests/` to validate filters and schema assumptions.

---

### Phase 2 – Core Recommendation Logic & Ranking

- **Goal**: From user preferences + dataset, produce an ordered list of candidate restaurants with scores.
- **Responsibilities**:
  - **Preference model**:
    - Define a structured `UserPreferences` model: `price`, `place`, `rating`, `cuisine`, plus optional parameters (e.g., max distance, sort priority).
  - **Scoring & ranking**:
    - Implement a deterministic scoring function (non-LLM) that:
      - Scores each candidate based on closeness to user preferences.
      - Combines factors like rating, price suitability, cuisine match, and location.
    - Return top N (e.g., top 20) candidates to feed into the LLM.
  - **Explainability features**:
    - Attach meta-info like "matched cuisine: Italian", "within budget", "above rating threshold", etc., which can be passed to the LLM for better explanations.
  - **Outputs**:
    - Module (e.g., `service/recommender/core.py`) with:
      - `rank_candidates(preferences, dataset)` → ordered candidates + scores.
    - Unit tests to ensure ranking is stable and deterministic.

---

### Phase 3 – LLM Orchestration & Prompting (`phase3_llm/`)

- **Goal**: Use an LLM (via `groq` or similar) to convert ranked candidates into clear, user-friendly recommendations.
- **Responsibilities**:
  - **Prompt design**:
    - System and user prompts that:
      - Describe the role: “You are an AI restaurant recommendation assistant…”.
      - Provide the **user preferences** and **top ranked candidates** (with key attributes).
      - Ask for a fixed number of recommendations with:
        - Restaurant name.
        - Brief description.
        - Why it matches the preferences (price, place, rating, cuisine).
  - **LLM client**:
    - Wrapper around `groq` client:
      - `generate_recommendations(preferences, candidates)` → structured result.
    - Handle errors, timeouts, and retries.
  - **Output schema**:
    - Ensure the LLM returns either:
      - A JSON-like structure (parsed), or
      - A clearly delimited text format that is easy to parse.
  - **Safety & quality checks**:
    - Verify that all recommended restaurants are drawn from the candidate list (no hallucinations).
  - **Outputs**:
    - LLM service module in `phase3_llm/` with functions and prompt templates.
    - Tests using mocked LLM responses.

---

### Phase 4 – Service/API Layer & User Interface

- **Goal**: Provide a clean interface for users and other systems to call the recommendation service.
- **Responsibilities**:
  - **Service orchestration**:
    - A single entry point function, e.g.:
      - `get_restaurant_recommendations(preferences)` that:
        1. Validates inputs.
        2. Calls data filters (`phase1_data`).
        3. Ranks candidates (Phase 2).
        4. Calls LLM layer (Phase 3).
        5. Returns final structured recommendations.
  - **Interfaces**:
    - **CLI / Script**:
      - Simple script where users input preferences via arguments or prompts.
    - **HTTP API (optional later)**:
      - FastAPI/Flask route `POST /recommendations` accepting JSON preferences.
  - **Configuration management**:
    - Use `.env` file and `python-dotenv` to manage:
      - LLM API keys.
      - Environment-specific settings (e.g., dataset cache paths).

---

### Phase 5 – Evaluation, Testing & Monitoring

- **Goal**: Ensure correctness, reliability, and user satisfaction.
- **Responsibilities**:
  - **Unit & integration tests**:
    - Phase-specific tests (already leveraging `pytest`).
    - End-to-end test: fixed input preferences → deterministic candidate set → mocked LLM → expected formatted recommendations.
  - **Offline evaluation**:
    - Define simple quality metrics:
      - Coverage of user constraints (price, rating, cuisine).
      - Diversity of recommendations (not all from same area, if possible).
  - **Logging & observability**:
    - Log inputs, selected candidates (without sensitive data), and final LLM outputs for debugging.
  - **Error handling**:
    - Graceful messages when:
      - No restaurants match constraints.
      - LLM call fails (fallback to non-LLM explanation or raw list).

---

### Phase 6 – Deployment & Future Enhancements

- **Goal**: Make the service usable in real environments and plan for iteration.
- **Deployment options**:
  - Containerize the service (Docker) with:
    - A lightweight API (FastAPI).
    - Environment-based configuration for keys.
  - Deploy to a cloud platform (e.g., Azure, AWS, GCP, or a simple VM).
- **Future enhancements**:
  - Add **user feedback loop**:
    - Thumbs up/down or ratings on recommendations to refine scoring.
  - Add **personalization**:
    - Remember user history and preferences across sessions.
  - Extend to **multi-modal**:
    - Include images, menu highlights, or links if available in future datasets.

---

## Data Flow Summary (End-to-End)

1. **User** provides: `price`, `place`, `rating`, `cuisine`, and extra constraints.
2. **Service/API** validates input and calls **Data Layer** (`phase1_data`) to:
   - Load dataset from Hugging Face (`ManikaSaini/zomato-restaurant-recommendation`).
   - Filter restaurants to a relevant subset.
3. **Core Recommendation Logic** ranks candidates and annotates them with reasons (Phase 2).
4. **LLM Layer** (`phase3_llm`) receives:
   - User preferences.
   - Top-ranked candidates with attributes and reasons.
   - It returns clear, structured restaurant recommendations and explanations.
5. **Service/API** returns the recommendations to the user (CLI output or JSON via HTTP).

This phased architecture keeps the **data**, **ranking logic**, and **LLM reasoning** clearly separated, making it easy to iterate on each part without breaking the others.

