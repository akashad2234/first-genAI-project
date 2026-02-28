"""
Streamlit UI for AI Restaurant Recommendation Service.
Uses the Phase 4 API (must be running on the configured base URL).
"""
import requests
import streamlit as st

st.set_page_config(
    page_title="Restaurant Recommendations",
    page_icon="🍽️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Default: API running locally
API_BASE = st.sidebar.text_input(
    "API base URL",
    value="http://localhost:8080",
    help="Phase 4 API must be running (e.g. Start-Phase4ApiServer on port 8080).",
)


def fetch_json(path: str):
    try:
        r = requests.get(f"{API_BASE.rstrip('/')}{path}", timeout=10)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        st.sidebar.error(f"Cannot reach API: {e}")
        return None


def fetch_places():
    data = fetch_json("/places")
    if data and "places" in data:
        return data["places"]
    return []


def fetch_cuisines():
    data = fetch_json("/cuisines")
    if data and "cuisines" in data:
        return data["cuisines"]
    return []


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


# Header
st.title("🍽️ Restaurant Recommendations")
st.caption("Set your preferences and get AI-powered restaurant suggestions (Groq).")

# Load options from API
places = fetch_places()
cuisines = fetch_cuisines()

if not places and not cuisines:
    st.warning(
        "Could not load places/cuisines. Ensure the Phase 4 API is running and the base URL is correct."
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
