# Run Phase 1 (download + preprocess Zomato data), then start Phase 4 API with that data.
# Usage: .\run_phase1_then_serve.ps1
# Optional: .\run_phase1_then_serve.ps1 -UseFullDataset  (downloads full CSV; slower)

param(
  [switch]$UseFullDataset
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

Import-Module (Join-Path $root 'phase1_data\src\Phase1Data.psm1') -Force
Import-Module (Join-Path $root 'phase4_api\src\Phase4Api.psm1') -Force

Write-Host "Phase 1: Downloading and preprocessing Zomato dataset..."
$mode = if ($UseFullDataset) { 'Full' } else { 'Sample' }
$rawCsv = Get-ZomatoDataset -Mode $mode
$processedCsv = Invoke-ZomatoPreprocessing -InputCsvPath $rawCsv
Write-Host "Processed data saved to: $processedCsv"

$envPath = Join-Path $root 'data\.env'
$staticRoot = Join-Path $root 'phase5_ui\dist'
if (-not (Test-Path $staticRoot)) {
  $staticRoot = Join-Path $root 'phase5_ui\public'
}

Write-Host "Phase 4: Starting API server (data from Phase 1). Open http://localhost:8080/"
Start-Phase4ApiServer -Port 8080 -DataCsvPath $processedCsv -StaticRootPath $staticRoot -DotEnvPath $envPath
