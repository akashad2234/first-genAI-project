"""
Streamlit UI for AI Restaurant Recommendation Service.
Uses the Phase 4 API when available; falls back to bundled CSV when API is unreachable (e.g. on Streamlit Cloud).
"""
import csv
import os
import requests
import streamlit as st

st.set_page_config(
    page_title="Restaurant Recommendations",
    page_icon="🍽️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Path to fixture CSV: streamlit_app.py is in repo root, CSV in phase4_api/tests/fixtures/
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
FIXTURE_CSV = os.path.join(SCRIPT_DIR, "phase4_api", "tests", "fixtures", "restaurants_processed.csv")

# Default: API running locally
API_BASE = st.sidebar.text_input(
    "API base URL",
    value="http://localhost:8080",
    help="Phase 4 API must be running on this URL.",
)


def _norm(s):
    return (s or "").strip().lower().replace("  ", " ")


def load_places_cuisines_from_csv():
    """Load places and cuisines from fixture CSV when API is unavailable. Returns (places, cuisines)."""
    places = []
    cuisines_set = set()
    if not os.path.isfile(FIXTURE_CSV):
        return places, []
    try:
        with open(FIXTURE_CSV, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            seen_places = set()
            for row in reader:
                city = (row.get("std_city") or "").strip()
                locality = (row.get("std_locality") or "").strip()
                if city or locality:
                    label = f"{city}, {locality}".strip(", ")
                    key = (city, locality)
                    if key not in seen_places:
                        seen_places.add(key)
                        places.append({"label": label, "city": city, "locality": locality})
                raw = row.get("std_cuisines") or ""
                for part in raw.split("|"):
                    c = _norm(part)
                    if c:
                        cuisines_set.add(c)
    except Exception:
        return [], []
    places.sort(key=lambda p: p["label"])
    return places, sorted(cuisines_set)


def recommendations_from_csv(payload: dict):
    """Recommendations by filtering the fixture CSV (same logic as Phase 4 API). Returns {restaurants, explanation, explanation_error}."""
    if not os.path.isfile(FIXTURE_CSV):
        return {"restaurants": [], "explanation": None, "explanation_error": "CSV not found."}
    try:
        with open(FIXTURE_CSV, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
    except Exception as e:
        return {"restaurants": [], "explanation": None, "explanation_error": str(e)}

    location_raw = _norm(payload.get("location") or "")
    location_parts = [p for p in location_raw.split(",") if p.strip()] if location_raw else []
    price_pref = _norm(payload.get("price_preference") or "")
    min_rating = payload.get("min_rating")
    if min_rating is not None:
        try:
            min_rating = float(min_rating)
        except (TypeError, ValueError):
            min_rating = None
    cuisine_prefs = payload.get("cuisine_preferences") or []
    if not isinstance(cuisine_prefs, list):
        cuisine_prefs = [cuisine_prefs] if cuisine_prefs else []
    cuisine_prefs = [_norm(c) for c in cuisine_prefs if c]
    num_results = max(1, min(10, int(payload.get("num_results") or 5)))

    filtered = []
    for r in rows:
        city = _norm(r.get("std_city") or "")
        loc = _norm(r.get("std_locality") or "")
        if location_parts:
            if not all(
                (city and p in city) or (loc and p in loc) for p in location_parts
            ):
                continue
        if price_pref and _norm(r.get("std_price_bucket") or "") != price_pref:
            continue
        try:
            rat = float(r.get("std_rating") or 0)
        except (TypeError, ValueError):
            rat = 0
        if min_rating is not None and rat < min_rating:
            continue
        if cuisine_prefs:
            raw_c = (r.get("std_cuisines") or "").split("|")
            row_cuisines = {_norm(x) for x in raw_c if x}
            if not any(c in row_cuisines for c in cuisine_prefs):
                continue
        filtered.append(r)

    filtered.sort(key=lambda x: (-float(x.get("std_rating") or 0), x.get("name") or ""))
    top = filtered[:num_results]

    restaurants = []
    for r in top:
        cuisines_str = r.get("std_cuisines") or ""
        cuisines_list = [c.strip() for c in cuisines_str.split("|") if c.strip()]
        try:
            rating = float(r.get("std_rating") or 0)
        except (TypeError, ValueError):
            rating = None
        restaurants.append({
            "id": r.get("id"),
            "name": r.get("name") or "Unknown",
            "city": r.get("std_city") or "",
            "locality": r.get("std_locality") or "",
            "rating": rating,
            "price_bucket": r.get("std_price_bucket") or "",
            "cuisines": cuisines_list,
        })

    return {
        "restaurants": restaurants,
        "explanation": "Recommendations from offline data (API not connected). Start the Phase 4 API for AI explanations.",
        "explanation_error": None,
    }


def fetch_json(path: str, show_error: bool = True):
    try:
        r = requests.get(f"{API_BASE.rstrip('/')}{path}", timeout=10)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        if show_error:
            st.sidebar.error(f"Cannot reach API: {e}")
        return None


def check_api_health():
    """Return True if API is reachable."""
    try:
        r = requests.get(f"{API_BASE.rstrip('/')}/health", timeout=5)
        return r.status_code == 200
    except Exception:
        return False


def get_recommendations(payload: dict):
    try:
        r = requests.post(
            f"{API_BASE.rstrip('/')}/recommendations",
            json=payload,
            timeout=30,
        )
        r.raise_for_status()
        return r.json()
    except requests.exceptions.RequestException as e:
        st.error(f"Request failed: {e}")
        if hasattr(e, "response") and e.response is not None:
            try:
                st.code(e.response.text[:500])
            except Exception:
                pass
        return None


st.sidebar.markdown("---")
st.sidebar.markdown("**To fix \"Cannot reach API\"**")
st.sidebar.markdown("Start the Phase 4 API in a **separate** PowerShell terminal:")
st.sidebar.code(
    "cd path\\to\\first-genAI-project\n"
    "Import-Module .\\phase4_api\\src\\Phase4Api.psm1 -Force\n"
    "Start-Phase4ApiServer -Port 8080 "
    "-DataCsvPath \".\\phase4_api\\tests\\fixtures\\restaurants_processed.csv\" "
    "-StaticRootPath \".\\phase5_ui\\public\" -DotEnvPath \".\\data\\.env\"",
    language="powershell",
)
st.sidebar.markdown("Then refresh this page or click **Get recommendations**.")
st.sidebar.markdown("---")

# API status
api_ok = check_api_health()
if api_ok:
    st.sidebar.success(f"API OK: {API_BASE.rstrip('/')}")
else:
    st.sidebar.error(f"Cannot reach API at {API_BASE}")
    st.sidebar.markdown("Try **http://127.0.0.1:8080** if you use **localhost**.")
if st.sidebar.button("Retry connection"):
    st.rerun()
st.sidebar.markdown("---")


# Header
st.title("🍽️ Restaurant Recommendations")
st.caption("Set your preferences and get AI-powered restaurant suggestions (Groq).")

# Load options from API, fallback to CSV when API unreachable
places_resp = fetch_json("/places", show_error=False)
if places_resp and "places" in places_resp:
    places = places_resp["places"]
else:
    places = []

cuisines_resp = fetch_json("/cuisines", show_error=False)
if cuisines_resp and "cuisines" in cuisines_resp:
    cuisines = cuisines_resp["cuisines"]
else:
    cuisines = []

# Fallback: load from fixture CSV when API didn't return data (e.g. Streamlit Cloud)
if not places or not cuisines:
    csv_places, csv_cuisines = load_places_cuisines_from_csv()
    if not places:
        places = csv_places
    if not cuisines:
        cuisines = csv_cuisines
    if places or cuisines:
        st.sidebar.info("Using offline data (API not connected).")

if not places and not cuisines:
    st.warning(
        "Could not load places/cuisines. Ensure the fixture CSV exists at "
        "`phase4_api/tests/fixtures/restaurants_processed.csv`, or start the Phase 4 API (see sidebar)."
    )

place_labels = [p.get("label") or f"{p.get('city', '')}, {p.get('locality', '')}".strip(", ") or "Unknown" for p in places]
place_options = [""] + place_labels

# Preferences form
with st.form("preferences_form"):
    st.subheader("Preferences")
    c1, c2 = st.columns(2)

    with c1:
        location = st.selectbox(
            "Place",
            options=place_options,
            format_func=lambda x: "All places" if x == "" else x,
        )
        price = st.selectbox(
            "Price",
            options=["", "low", "medium", "high", "premium"],
            format_func=lambda x: "Any" if x == "" else x.capitalize(),
        )
        min_rating = st.number_input(
            "Minimum rating",
            min_value=0.0,
            max_value=5.0,
            value=4.0,
            step=0.1,
        )

    with c2:
        cuisine_selection = st.multiselect(
            "Cuisines",
            options=cuisines or [],
            default=[],
            format_func=lambda x: x.capitalize() if x else "",
        )
        num_results = st.number_input("Number of results", min_value=1, max_value=10, value=5)

    submitted = st.form_submit_button("Get recommendations")

if submitted:
    payload = {
        "num_results": num_results,
        "min_rating": min_rating,
    }
    if location:
        payload["location"] = location
    if price:
        payload["price_preference"] = price
    if cuisine_selection:
        payload["cuisine_preferences"] = cuisine_selection

    with st.spinner("Fetching recommendations…"):
        result = get_recommendations(payload)
    if result is None:
        # API unreachable: use CSV fallback so app works on Streamlit Cloud / without API
        result = recommendations_from_csv(payload)

    if result:
        restaurants = result.get("restaurants") or []
        explanation = result.get("explanation") or ""
        explanation_error = result.get("explanation_error") or ""

        st.success(f"Found **{len(restaurants)}** restaurant(s).")

        if explanation_error:
            st.warning(f"AI explanation: {explanation_error}")
        elif explanation:
            with st.expander("AI explanation", expanded=True):
                st.write(explanation)

        if not restaurants:
            st.info("No restaurants matched your filters. Try relaxing price, place, or cuisine.")
        else:
            for r in restaurants:
                name = r.get("name") or "Unknown"
                locality = r.get("locality") or ""
                city = r.get("city") or ""
                rating = r.get("rating")
                price_bucket = r.get("price_bucket") or ""
                cuisines_str = ", ".join(r.get("cuisines") or [])

                rating_str = f"⭐ {rating:.1f}" if isinstance(rating, (int, float)) else "–"
                meta = " • ".join(filter(None, [locality, city]))
                tags = [rating_str]
                if price_bucket:
                    tags.append(price_bucket)
                if cuisines_str:
                    tags.append(cuisines_str)

                st.markdown(f"### {name}")
                if meta:
                    st.caption(meta)
                st.write(" ".join(tags))
                st.divider()
