$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$phase1 = Split-Path -Parent $here

Import-Module (Join-Path $phase1 'src\Phase1Data.psm1') -Force

Describe 'Phase1Data' {
  It 'downloads a sample CSV and preprocesses it' {
    $raw = Get-ZomatoDataset -Mode Sample -SampleBytes 262144
    Test-Path $raw | Should Be $true

    $processed = Invoke-ZomatoPreprocessing -InputCsvPath $raw
    Test-Path $processed | Should Be $true

    # Validate headers include derived columns.
    $firstLine = Get-Content -LiteralPath $processed -TotalCount 1
    $firstLine | Should Match 'std_city'
    $firstLine | Should Match 'std_locality'
    $firstLine | Should Match 'std_rating'
    $firstLine | Should Match 'std_price_bucket'
    $firstLine | Should Match 'std_cuisines'

    # Ensure we have at least one data row after header.
    $twoLines = Get-Content -LiteralPath $processed -TotalCount 2
    ($twoLines.Count -ge 2) | Should Be $true
  }
}

