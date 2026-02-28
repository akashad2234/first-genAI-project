# Download Zomato data once and preprocess it. Use the output path with Phase 4.
# Usage: .\download_and_preprocess.ps1           → sample (~256 KB)
#        .\download_and_preprocess.ps1 -Full     → full dataset (large)

param(
  [switch]$Full
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

Import-Module (Join-Path $root 'phase1_data\src\Phase1Data.psm1') -Force

Write-Host "Downloading from Hugging Face (ManikaSaini/zomato-restaurant-recommendation)..."
$mode = if ($Full) { 'Full' } else { 'Sample' }
$rawCsv = Get-ZomatoDataset -Mode $mode

Write-Host "Preprocessing..."
$processedCsv = Invoke-ZomatoPreprocessing -InputCsvPath $rawCsv

Write-Host ""
Write-Host "Done. Data is loaded correctly. Use this path with Phase 4:"
Write-Host "  $processedCsv"
Write-Host ""
Write-Host "Example - start the API with this data:"
Write-Host '  Start-Phase4ApiServer -Port 8081 -DataCsvPath "' + $processedCsv + '" -StaticRootPath ".\phase5_ui\public" -DotEnvPath ".\data\.env"'
Write-Host ""
