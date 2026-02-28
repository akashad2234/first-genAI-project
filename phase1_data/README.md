## Phase 1 – Data Layer (Hugging Face Zomato Dataset)

This folder implements **Phase 1** from `ARCHITECTURE.md`:

- Download the dataset from Hugging Face: `ManikaSaini/zomato-restaurant-recommendation` (`zomato.csv`)
- Cache it locally under `data/raw/`
- Preprocess it into a cleaned, standardized CSV under `data/processed/`

---

### Is the data loaded correctly?

Yes. Phase 1:

1. **Downloads** the CSV from Hugging Face (full file or a sample via range request).
2. **Preprocesses** it by:
   - Detecting columns (city, locality, cuisines, rating, price, etc.) with case-insensitive names.
   - Adding normalized columns: `std_city`, `std_locality`, `std_rating`, `std_price_bucket`, `std_cuisines`.
   - Keeping all original columns so the processed file is self-contained.

The processed CSV is validated by `Invoke-Pester .\phase1_data\tests`. Phase 4 reads this file directly for recommendations and for `/places` and `/cuisines`.

---

### Download once, then use directly

You can **download the data once** and **use the processed file everywhere** (Phase 4 API, scripts, etc.) without re-downloading.

**Option A – Script (project root)**

```powershell
.\download_and_preprocess.ps1        # Sample (~256 KB, fast)
.\download_and_preprocess.ps1 -Full  # Full dataset (slower)
```

The script prints the path of the processed CSV. Use that path with Phase 4:

```powershell
Import-Module .\phase4_api\src\Phase4Api.psm1 -Force
Start-Phase4ApiServer -Port 8081 -DataCsvPath ".\data\processed\zomato_sample_processed.csv" -StaticRootPath ".\phase5_ui\public" -DotEnvPath ".\data\.env"
```

**Option B – Download + serve in one go**

```powershell
.\run_phase1_then_serve.ps1           # Sample then start API on 8080
.\run_phase1_then_serve.ps1 -UseFullDataset
```

**Output paths**

| Mode   | Raw file                    | Processed file                          |
|--------|-----------------------------|------------------------------------------|
| Sample | `data/raw/zomato_sample.csv` | `data/processed/zomato_sample_processed.csv` |
| Full   | `data/raw/zomato.csv`       | `data/processed/zomato_processed.csv`   |

Use the **processed** path with Phase 4. Re-run the download script only when you want to refresh data from Hugging Face.

---

### Quickstart (manual)

From the project root:

```powershell
Import-Module .\phase1_data\src\Phase1Data.psm1 -Force

# Download a small sample (fast) and preprocess it
$raw = Get-ZomatoDataset -Mode Sample
$processed = Invoke-ZomatoPreprocessing -InputCsvPath $raw

"Processed (use with Phase 4): $processed"
```

### Run tests

```powershell
Invoke-Pester .\phase1_data\tests
```
