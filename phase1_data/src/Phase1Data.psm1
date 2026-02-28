Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
  $here = Split-Path -Parent $PSScriptRoot
  return Split-Path -Parent $here
}

function Ensure-Directory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Get-HuggingFaceDatasetFileUrl {
  param(
    [Parameter(Mandatory = $true)][string]$DatasetId,
    [Parameter(Mandatory = $true)][string]$Filename
  )
  return "https://huggingface.co/datasets/$DatasetId/resolve/main/$Filename"
}

function Invoke-HttpDownload {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [hashtable]$Headers
  )

  $outDir = Split-Path -Parent $OutFile
  Ensure-Directory -Path $outDir

  $params = @{
    Uri     = $Url
    OutFile = $OutFile
  }
  if ($Headers) { $params.Headers = $Headers }

  Invoke-WebRequest @params | Out-Null
}

function Save-HttpRangeToTextFile {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [Parameter(Mandatory = $true)][int]$MaxBytes
  )

  $request = [System.Net.HttpWebRequest]::Create($Url)
  $request.Method = 'GET'
  $request.UserAgent = 'phase1-data-ingestion'
  $request.AddRange(0, $MaxBytes - 1)

  $response = $request.GetResponse()
  try {
    $stream = $response.GetResponseStream()
    $ms = New-Object System.IO.MemoryStream
    try {
      $stream.CopyTo($ms)
      $rawBytes = $ms.ToArray()
    } finally {
      $ms.Dispose()
      $stream.Dispose()
    }
  } finally {
    $response.Close()
  }

  $text = [System.Text.Encoding]::UTF8.GetString([byte[]]$rawBytes)

  # Avoid truncating in the middle of a CSV row.
  $lastNewline = $text.LastIndexOf("`n")
  if ($lastNewline -gt 0) {
    $text = $text.Substring(0, $lastNewline + 1)
  }

  $outDir = Split-Path -Parent $OutFile
  Ensure-Directory -Path $outDir
  [System.IO.File]::WriteAllText($OutFile, $text, [System.Text.Encoding]::UTF8)
}

function Get-ZomatoDataset {
  <#
    Downloads/caches the Hugging Face dataset file.

    -Mode Full: downloads the whole CSV into data/raw/zomato.csv
    -Mode Sample: downloads the first ~N bytes into data/raw/zomato_sample.csv
  #>
  param(
    [ValidateSet('Full', 'Sample')][string]$Mode = 'Full',
    [string]$DatasetId = 'ManikaSaini/zomato-restaurant-recommendation',
    [string]$Filename = 'zomato.csv',
    [int]$SampleBytes = 262144
  )

  $root = Get-ProjectRoot
  $rawDir = Join-Path $root 'data\raw'
  Ensure-Directory -Path $rawDir

  $url = Get-HuggingFaceDatasetFileUrl -DatasetId $DatasetId -Filename $Filename

  if ($Mode -eq 'Sample') {
    $outFile = Join-Path $rawDir 'zomato_sample.csv'
    if (-not (Test-Path -LiteralPath $outFile)) {
      Save-HttpRangeToTextFile -Url $url -OutFile $outFile -MaxBytes $SampleBytes
    }
    return $outFile
  }

  $outFile = Join-Path $rawDir 'zomato.csv'
  if (-not (Test-Path -LiteralPath $outFile)) {
    Invoke-HttpDownload -Url $url -OutFile $outFile
  }
  return $outFile
}

function Normalize-CuisineList {
  param([string]$CuisineText)
  if ([string]::IsNullOrWhiteSpace($CuisineText)) { return @() }

  $CuisineText = $CuisineText -replace '\s+', ' '
  $CuisineText = $CuisineText.Trim()

  $parts = $CuisineText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
  $normalized = @()
  foreach ($p in $parts) {
    $t = $p.ToLowerInvariant()
    $t = $t -replace '[^a-z0-9 &\-]', ''
    $t = $t -replace '\s+', ' '
    $t = $t.Trim()
    if ($t) { $normalized += $t }
  }
  return $normalized
}

function Get-PriceBucket {
  param(
    [object]$PriceRange,
    [object]$AvgCostForTwo
  )

  $pr = $null
  if ($PriceRange -ne $null -and "$PriceRange" -match '^\s*\d+\s*$') {
    $pr = [int]("$PriceRange".Trim())
  }

  if ($pr -ge 1 -and $pr -le 4) {
    switch ($pr) {
      1 { return 'low' }
      2 { return 'medium' }
      3 { return 'high' }
      4 { return 'premium' }
    }
  }

  $cost = $null
  if ($AvgCostForTwo -ne $null -and "$AvgCostForTwo" -match '^\s*\d+(\.\d+)?\s*$') {
    $cost = [double]("$AvgCostForTwo".Trim())
  }

  if ($cost -ne $null) {
    if ($cost -le 500) { return 'low' }
    if ($cost -le 1000) { return 'medium' }
    if ($cost -le 2000) { return 'high' }
    return 'premium'
  }

  return ''
}

function Try-ParseRating {
  param([object]$Value)
  if ($Value -eq $null) { return $null }
  $s = "$Value".Trim()
  if ($s -eq '') { return $null }
  if ($s -match '^\d+(\.\d+)?$') {
    $r = [double]$s
    if ($r -ge 0 -and $r -le 5) { return $r }
  }
  return $null
}

function Invoke-ZomatoPreprocessing {
  <#
    Preprocesses raw CSV into a standardized "processed" CSV.

    Adds derived columns:
    - std_city
    - std_locality
    - std_rating
    - std_price_bucket
    - std_cuisines (pipe-separated normalized cuisines)
  #>
  param(
    [Parameter(Mandatory = $true)][string]$InputCsvPath,
    [string]$OutputCsvPath
  )

  if (-not (Test-Path -LiteralPath $InputCsvPath)) {
    throw "Input CSV not found: $InputCsvPath"
  }

  $root = Get-ProjectRoot
  $processedDir = Join-Path $root 'data\processed'
  Ensure-Directory -Path $processedDir

  if (-not $OutputCsvPath) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($InputCsvPath)
    $OutputCsvPath = Join-Path $processedDir "$base`_processed.csv"
  }

  $reader = New-Object System.IO.StreamReader($InputCsvPath, [System.Text.Encoding]::UTF8, $true)
  try {
    $headerLine = $reader.ReadLine()
    if ($null -eq $headerLine) { throw "CSV appears empty: $InputCsvPath" }

    $headers = $headerLine.Split(',')

    # Heuristic column picks (case-insensitive).
    $nameToIdx = @{}
    for ($i = 0; $i -lt $headers.Length; $i++) {
      $nameToIdx[$headers[$i].Trim().ToLowerInvariant()] = $i
    }

    function Pick-Col([string[]]$Candidates) {
      foreach ($c in $Candidates) {
        $k = $c.ToLowerInvariant()
        if ($nameToIdx.ContainsKey($k)) { return $k }
      }
      return $null
    }

    $cityCol     = Pick-Col @('city', 'City')
    $localityCol = Pick-Col @('locality', 'Locality', 'area', 'Area', 'location', 'Location')
    $cuisineCol  = Pick-Col @('cuisines', 'Cuisines', 'cuisine', 'Cuisine')
    $ratingCol   = Pick-Col @('aggregate_rating', 'Aggregate rating', 'rating', 'Rating')
    $priceCol    = Pick-Col @('price_range', 'Price range', 'price', 'Price')
    $costCol     = Pick-Col @('average_cost_for_two', 'Average Cost for two', 'avg_cost_for_two')

    $out = New-Object System.IO.StreamWriter($OutputCsvPath, $false, [System.Text.Encoding]::UTF8)
    try {
      $out.WriteLine(($headerLine + ',std_city,std_locality,std_rating,std_price_bucket,std_cuisines'))

      # Use TextFieldParser for robust CSV parsing (quotes, commas).
      Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
      $parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($InputCsvPath)
      try {
        $parser.SetDelimiters(@(','))
        $parser.HasFieldsEnclosedInQuotes = $true
        [void]$parser.ReadFields() # consume header

        while (-not $parser.EndOfData) {
          $fields = $parser.ReadFields()
          if ($null -eq $fields) { continue }

          $get = {
            param([string]$colKey)
            if (-not $colKey) { return $null }
            $idx = $nameToIdx[$colKey]
            if ($idx -ge 0 -and $idx -lt $fields.Length) { return $fields[$idx] }
            return $null
          }

          $city     = & $get $cityCol
          $locality = & $get $localityCol
          $cuisinesRaw = & $get $cuisineCol
          $ratingRaw   = & $get $ratingCol
          $priceRaw    = & $get $priceCol
          $costRaw     = & $get $costCol

          $stdRating = Try-ParseRating -Value $ratingRaw
          $priceBucket = Get-PriceBucket -PriceRange $priceRaw -AvgCostForTwo $costRaw

          $cuisineList = Normalize-CuisineList -CuisineText $cuisinesRaw
          $stdCuisines = ($cuisineList | Sort-Object -Unique) -join '|'

          $stdCity = if ($city) { "$city".Trim() } else { '' }
          $stdLocality = if ($locality) { "$locality".Trim() } else { '' }

          # Basic row validity: keep rows that have at least a city/locality or cuisines.
          if ($stdCity -eq '' -and $stdLocality -eq '' -and $stdCuisines -eq '') { continue }

          # Write original row back out (re-quoted as needed) + derived columns.
          $escaped = @()
          foreach ($f in $fields) {
            $v = if ($null -eq $f) { '' } else { [string]$f }
            if ($v.Contains('"')) { $v = $v.Replace('"', '""') }
            if ($v.Contains(',') -or $v.Contains('"') -or $v.Contains("`n") -or $v.Contains("`r")) {
              $v = '"' + $v + '"'
            }
            $escaped += $v
          }

          $derived = @(
            $stdCity,
            $stdLocality,
            $(if ($stdRating -ne $null) { [string]$stdRating } else { '' }),
            $priceBucket,
            $stdCuisines
          ) | ForEach-Object {
            $v = if ($null -eq $_) { '' } else { [string]$_ }
            if ($v.Contains('"')) { $v = $v.Replace('"', '""') }
            if ($v.Contains(',') -or $v.Contains('"') -or $v.Contains("`n") -or $v.Contains("`r")) {
              $v = '"' + $v + '"'
            }
            $v
          }

          $out.WriteLine((($escaped -join ',') + ',' + ($derived -join ',')))
        }
      } finally {
        if ($parser) { $parser.Close() }
      }
    } finally {
      $out.Flush()
      $out.Close()
    }
  } finally {
    $reader.Close()
  }

  return $OutputCsvPath
}

Export-ModuleMember -Function Get-ZomatoDataset, Invoke-ZomatoPreprocessing

