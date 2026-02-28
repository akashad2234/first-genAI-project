## Phase 4 – API Layer (PowerShell)

This folder implements **Phase 4** (API layer) as a **PowerShell module + optional HTTP server**.

Why PowerShell here?
- Your environment currently has **no Python/Docker on PATH**, but Phase 4 needs to be testable now.
- This Phase 4 exposes a stable contract (`/recommendations`) that we can later re-implement in FastAPI without changing behavior.

---

### What’s included

- `src/Phase4Api.psm1`
  - Core recommendation logic using the **processed CSV** from Phase 1
  - Groq OpenAI-compatible call to generate an explanation
  - Optional `Start-Phase4ApiServer` HTTP server (best-effort; may require URL ACL on some Windows setups)
- `tests/Phase4Api.Tests.ps1`
  - Unit tests (always run)
  - Groq integration test (runs only if `GROQ_API_KEY` is available)
- `tests/fixtures/restaurants_processed.csv`
  - Tiny deterministic fixture dataset for tests

---

### Run the unit tests

From project root:

```powershell
Invoke-Pester .\phase4_api\tests
```

---

### Optional: run the local HTTP server

```powershell
Import-Module .\phase4_api\src\Phase4Api.psm1 -Force
Start-Phase4ApiServer -Port 8080 -DataCsvPath .\phase4_api\tests\fixtures\restaurants_processed.csv -DotEnvPath .\data\.env
```

Then POST:

```powershell
$body = @{
  price_preference = "medium"
  location = "Bangalore, Indiranagar"
  min_rating = 4.0
  cuisine_preferences = @("italian","pizza")
  num_results = 3
} | ConvertTo-Json

Invoke-RestMethod -Method Post -Uri http://localhost:8080/recommendations -ContentType "application/json" -Body $body
```

