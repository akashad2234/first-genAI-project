## Phase 5 – Client UI

React-based UI matching the food-discovery layout: header (“Hello, Rachel!”, “Wanna eat tonight?”), category chips, **places dropdown**, and RECOMMENDED list from the API.

---

### Structure

- **React app (Vite)**  
  - `src/App.jsx` – main UI: header, categories, place dropdown, filters, “Get recommendations”, RECOMMENDED list.  
  - `public/` – legacy static HTML fallback.  
- **API**  
  - Uses Phase 4: `GET /places`, `GET /cuisines`, `POST /recommendations`.

---

### Run with Phase 4 (manual testing)

**Option A – React dev server (recommended)**

1. Start the Phase 4 API (from project root):

```powershell
Import-Module .\phase4_api\src\Phase4Api.psm1 -Force
Start-Phase4ApiServer -Port 8080 -DataCsvPath ".\phase4_api\tests\fixtures\restaurants_processed.csv" -DotEnvPath ".\data\.env"
```

2. In another terminal, from project root:

```powershell
cd phase5_ui
npm install
npm run dev
```

3. Open **http://localhost:5173/**  
   The Vite dev server proxies `/recommendations`, `/places`, `/cuisines` to port 8080.

**Option B – Use Phase 1 data (download + preprocess, then serve)**

From project root:

```powershell
.\run_phase1_then_serve.ps1
```

Then run the React app as in step 2 above (or build and serve the built app from Phase 4).

**Option C – Static UI on Phase 4**

Build the React app, then serve it from Phase 4:

```powershell
cd phase5_ui && npm install && npm run build && cd ..
Start-Phase4ApiServer -Port 8080 -DataCsvPath ".\data\processed\zomato_sample_processed.csv" -StaticRootPath ".\phase5_ui\dist" -DotEnvPath ".\data\.env"
```

Open **http://localhost:8080/**

---

### Tests

From project root:

```powershell
Invoke-Pester .\phase5_ui\tests
```

(Tests assert `public/index.html` content; React app is exercised manually.)
