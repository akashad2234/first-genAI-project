import { useState, useEffect } from 'react'
import './App.css'

const API_BASE = '' // same origin (Vite proxy in dev)

export default function App() {
  const [places, setPlaces] = useState([])
  const [cuisines, setCuisines] = useState([])
  const [selectedPlace, setSelectedPlace] = useState('')
  const [pricePreference, setPricePreference] = useState('')
  const [minRating, setMinRating] = useState(4)
  const [selectedCuisine, setSelectedCuisine] = useState('')
  const [recommendations, setRecommendations] = useState([])
  const [explanation, setExplanation] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [loadingMeta, setLoadingMeta] = useState(true)

  useEffect(() => {
    Promise.all([
      fetch(`${API_BASE}/places`).then((r) => r.json()).then((d) => setPlaces(d.places || [])).catch(() => setPlaces([])),
      fetch(`${API_BASE}/cuisines`).then((r) => r.json()).then((d) => setCuisines(d.cuisines || [])).catch(() => setCuisines([])),
    ]).finally(() => setLoadingMeta(false))
  }, [])

  const handleGetRecommendations = async () => {
    setError('')
    setLoading(true)
    setRecommendations([])
    setExplanation('')
    const payload = {}
    if (selectedPlace && selectedPlace.trim()) payload.location = selectedPlace.trim()
    if (pricePreference) payload.price_preference = pricePreference
    if (minRating != null && minRating !== '') payload.min_rating = Number(minRating)
    if (selectedCuisine) payload.cuisine_preferences = [selectedCuisine]
    payload.num_results = 10

    try {
      const res = await fetch(`${API_BASE}/recommendations`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || data.detail || `Server error ${res.status}`)
      setRecommendations(data.restaurants || [])
      setExplanation(data.explanation || '')
      if (!(data.restaurants && data.restaurants.length)) setError('No recommendation returned. Try relaxing filters.')
      else setError('')
    } catch (err) {
      setError(err.message || 'Failed to load recommendations.')
      setRecommendations([])
      setExplanation('')
    } finally {
      setLoading(false)
    }
  }

  const categoryCards = cuisines.slice(0, 4).map((c) => ({
    label: c.charAt(0).toUpperCase() + c.slice(1),
    key: c,
  }))

  return (
    <div className="app-shell">
      <header className="header">
        <div className="header-left">
          <div className="avatar" aria-hidden />
          <div>
            <h1 className="greeting">Hello, Rachel!</h1>
            <p className="subgreeting">Wanna eat tonight?</p>
          </div>
        </div>
        <div className="header-icons">
          <button type="button" className="icon-btn" aria-label="Search">
            <span className="icon-search" />
          </button>
          <button type="button" className="icon-btn" aria-label="Saved">
            <span className="icon-book" />
          </button>
        </div>
      </header>

      <section className="section-categories">
        <div className="category-cards">
          {loadingMeta
            ? <div className="category-card placeholder">Loading…</div>
            : categoryCards.map((cat) => (
                <button
                  key={cat.key}
                  type="button"
                  className={`category-card ${selectedCuisine === cat.key ? 'selected' : ''}`}
                  onClick={() => setSelectedCuisine(selectedCuisine === cat.key ? '' : cat.key)}
                >
                  <span className="category-emoji">{cat.key === 'pizza' ? '🍕' : cat.key === 'sushi' ? '🍣' : cat.key === 'indian' ? '🍛' : '🍽️'}</span>
                  <span className="category-label">{cat.label}</span>
                  <span className="category-count">25+ Restaurants</span>
                </button>
              ))}
        </div>
        <div className="see-all-card">
          <div>
            <span className="see-all-title">See All Categories</span>
            <span className="see-all-count">{cuisines.length} Categories</span>
          </div>
          <div className="see-all-illus">🍰 🧋 🍳</div>
        </div>
      </section>

      <section className="section-filters">
        <label className="filter-label">Place</label>
        <select
          className="filter-select"
          value={selectedPlace}
          onChange={(e) => setSelectedPlace(e.target.value)}
          aria-label="Select place"
        >
          <option value="">All places</option>
          {places.map((p) => (
            <option key={p.label} value={p.label}>{p.label}</option>
          ))}
        </select>
        <div className="filter-row">
          <div className="filter-group">
            <label className="filter-label">Price</label>
            <select
              className="filter-select"
              value={pricePreference}
              onChange={(e) => setPricePreference(e.target.value)}
            >
              <option value="">Any</option>
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
              <option value="premium">Premium</option>
            </select>
          </div>
          <div className="filter-group">
            <label className="filter-label">Min rating</label>
            <input
              type="number"
              min="0"
              max="5"
              step="any"
              placeholder="0–5 (e.g. 4 or 4.5)"
              className="filter-input"
              value={minRating}
              onChange={(e) => setMinRating(e.target.value === '' ? '' : e.target.value)}
            />
          </div>
        </div>
        <button
          type="button"
          className="btn-primary"
          onClick={handleGetRecommendations}
          disabled={loading}
        >
          {loading ? 'Finding…' : 'Get recommendations'}
        </button>
        {error && <p className="error-msg">{error}</p>}
      </section>

      <section className="section-recommended">
        <h2 className="section-title">RECOMMENDED</h2>
        {explanation && <div className="explanation">{explanation}</div>}
        <div className="recommended-list">
          {recommendations.length === 0 && !loading && (
            <p className="empty-state">Select a place or filters and click “Get recommendations”.</p>
          )}
          {recommendations.map((r) => (
            <article key={r.id || r.name} className="rec-card">
              <div className="rec-icon">🍕</div>
              <div className="rec-details">
                <h3 className="rec-name">{r.name}</h3>
                <p className="rec-tagline">
                  {r.cuisines && r.cuisines.length ? r.cuisines.join(' • ') : 'Restaurant'}
                  {r.rating != null && ` • ★ ${Number(r.rating).toFixed(1)}`}
                </p>
                <p className="rec-meta">
                  {[r.locality, r.city].filter(Boolean).join(' • ')}
                  {r.price_bucket && ` • ${r.price_bucket}`}
                </p>
              </div>
            </article>
          ))}
        </div>
      </section>
    </div>
  )
}
