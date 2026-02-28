Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-DotEnv {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )
  if (-not (Test-Path -LiteralPath $Path)) { return }

  $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
  foreach ($line in $lines) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $idx = $t.IndexOf('=')
    if ($idx -lt 1) { continue }
    $k = $t.Substring(0, $idx).Trim()
    $v = $t.Substring($idx + 1).Trim()
    if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
    if ($k -ne '') {
      [System.Environment]::SetEnvironmentVariable($k, $v)
    }
  }
}

function ConvertTo-PreferenceObject {
  param([hashtable]$PreferenceHash)
  if (-not $PreferenceHash) { $PreferenceHash = @{} }
  return [pscustomobject]@{
    price_preference    = $PreferenceHash['price_preference']
    location            = $PreferenceHash['location']
    min_rating          = $PreferenceHash['min_rating']
    cuisine_preferences = $PreferenceHash['cuisine_preferences']
    num_results         = $PreferenceHash['num_results']
  }
}

function Normalize-Text([string]$s) {
  if ($null -eq $s) { return '' }
  return ($s.Trim().ToLowerInvariant() -replace '\s+', ' ')
}

function Split-LocationParts([string]$location) {
  $t = Normalize-Text $location
  if ($t -eq '') { return @() }
  $parts = @($t.Split(',') | ForEach-Object { Normalize-Text $_ } | Where-Object { $_ -ne '' })
  return $parts
}

function Parse-DoubleOrNull([object]$v) {
  if ($null -eq $v) { return $null }
  # Accept integers from JSON (e.g. min_rating: 4) as well as decimals and strings
  if ($v -is [int] -or $v -is [long] -or $v -is [decimal]) { return [double]$v }
  if ($v -is [double]) { return $v }
  $s = "$v".Trim()
  if ($s -eq '') { return $null }
  $d = 0.0
  if ([double]::TryParse($s, [ref]$d)) { return $d }
  return $null
}

function Get-ObjectPropertyValueOrNull {
  param(
    [Parameter(Mandatory = $true)][object]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $null }
  return $prop.Value
}

function Get-RestaurantNameFromRow {
  param([psobject]$Row)
  $candidates = @('name', 'restaurant name', 'restaurant_name', 'Name', 'Restaurant Name')
  foreach ($c in $candidates) {
    $v = Get-ObjectPropertyValueOrNull -Object $Row -Name $c
    if ($v -and "$v".Trim() -ne '') { return "$v".Trim() }
  }
  return 'Unknown'
}

function Get-RestaurantIdFromRow {
  param([psobject]$Row)
  $candidates = @('id', 'ID', 'restaurant_id', 'Restaurant ID')
  foreach ($c in $candidates) {
    $v = Get-ObjectPropertyValueOrNull -Object $Row -Name $c
    if ($v -ne $null -and "$v".Trim() -ne '') { return "$v".Trim() }
  }
  return $null
}

function Get-PlacesFromCsv {
  param([Parameter(Mandatory = $true)][string]$DataCsvPath)
  if (-not (Test-Path -LiteralPath $DataCsvPath)) { return @() }
  $rows = Import-Csv -LiteralPath $DataCsvPath
  $seen = @{}
  $places = @()
  foreach ($r in $rows) {
    $city = Normalize-Text (Get-ObjectPropertyValueOrNull -Object $r -Name 'std_city')
    $loc = Normalize-Text (Get-ObjectPropertyValueOrNull -Object $r -Name 'std_locality')
    $label = if ($city -and $loc) { "$city, $loc" } elseif ($city) { $city } elseif ($loc) { $loc } else { '' }
    if ($label -eq '') { continue }
    $key = $label.ToLowerInvariant()
    if (-not $seen[$key]) {
      $seen[$key] = $true
      $places += [pscustomobject]@{ label = $label; city = $city; locality = $loc }
    }
  }
  $places = $places | Sort-Object -Property label
  Write-Output -NoEnumerate @($places)
}

function Get-CuisinesFromCsv {
  param([Parameter(Mandatory = $true)][string]$DataCsvPath)
  if (-not (Test-Path -LiteralPath $DataCsvPath)) { return @() }
  $rows = Import-Csv -LiteralPath $DataCsvPath
  $seen = @{}
  foreach ($r in $rows) {
    $raw = Get-ObjectPropertyValueOrNull -Object $r -Name 'std_cuisines'
    if (-not $raw) { continue }
    $parts = @("$raw".Split('|') | ForEach-Object { Normalize-Text $_ } | Where-Object { $_ -ne '' })
    foreach ($p in $parts) {
      if (-not $seen[$p]) { $seen[$p] = $true }
    }
  }
  $list = @($seen.Keys | Sort-Object)
  Write-Output -NoEnumerate $list
}

function Get-RestaurantRecommendations {
  <#
    Core Phase 4 API logic:
    - loads processed CSV
    - filters by preferences
    - ranks by rating (desc)
  #>
  param(
    [Parameter(Mandatory = $true)][string]$DataCsvPath,
    [Parameter(Mandatory = $true)][psobject]$Preferences
  )

  if (-not (Test-Path -LiteralPath $DataCsvPath)) {
    throw "Processed data CSV not found: $DataCsvPath"
  }

  $rows = Import-Csv -LiteralPath $DataCsvPath

  $pricePref = Normalize-Text (Get-ObjectPropertyValueOrNull -Object $Preferences -Name 'price_preference')
  $minRating = Parse-DoubleOrNull (Get-ObjectPropertyValueOrNull -Object $Preferences -Name 'min_rating')
  $locationParts = @(Split-LocationParts (Get-ObjectPropertyValueOrNull -Object $Preferences -Name 'location'))
  $cuisines = @()
  $cuisinePrefVal = Get-ObjectPropertyValueOrNull -Object $Preferences -Name 'cuisine_preferences'
  if ($cuisinePrefVal -is [System.Collections.IEnumerable] -and -not ($cuisinePrefVal -is [string])) {
    $cuisines = @($cuisinePrefVal | ForEach-Object { Normalize-Text "$_" } | Where-Object { $_ -ne '' })
  } elseif ($cuisinePrefVal) {
    $cuisines = @(Normalize-Text "$cuisinePrefVal")
  }

  $numResults = 5
  $numResultsVal = Get-ObjectPropertyValueOrNull -Object $Preferences -Name 'num_results'
  if ($numResultsVal -ne $null -and "$numResultsVal" -match '^\d+$') {
    $numResults = [int]$numResultsVal
  }
  if ($numResults -lt 1) { $numResults = 1 }
  if ($numResults -gt 10) { $numResults = 10 }

  $filtered = $rows | Where-Object {
    $ok = $true

    $city = Normalize-Text $_.std_city
    $loc  = Normalize-Text $_.std_locality

    if ($locationParts.Count -gt 0) {
      # If user provides multiple parts (e.g., "City, Area"), require ALL parts to match
      # either city or locality so "Bangalore, Indiranagar" doesn't match other Bangalore areas.
      foreach ($p in $locationParts) {
        if (-not ($city -like "*$p*" -or $loc -like "*$p*")) { $ok = $false; break }
      }
    }

    if ($ok -and $pricePref -ne '') {
      $bucket = Normalize-Text $_.std_price_bucket
      if ($bucket -ne $pricePref) { $ok = $false }
    }

    if ($ok -and $minRating -ne $null) {
      $r = Parse-DoubleOrNull $_.std_rating
      if ($r -eq $null -or $r -lt $minRating) { $ok = $false }
    }

    if ($ok -and $cuisines.Count -gt 0) {
      $rowCuisines = @()
      if ($_.std_cuisines) {
        $rowCuisines = @("$($_.std_cuisines)".Split('|') | ForEach-Object { Normalize-Text $_ } | Where-Object { $_ -ne '' })
      }
      $hit = $false
      foreach ($c in $cuisines) {
        if ($rowCuisines -contains $c) { $hit = $true; break }
      }
      if (-not $hit) { $ok = $false }
    }

    $ok
  }

  $ranked = $filtered | Sort-Object `
    @{ Expression = { Parse-DoubleOrNull $_.std_rating }; Descending = $true }, `
    @{ Expression = { $_.name }; Descending = $false }

  $top = @($ranked | Select-Object -First $numResults)

  # Standardize the response restaurant fields (keep it simple).
  $restaurants = @()
  foreach ($r in $top) {
    $restaurants += [pscustomobject]@{
      id           = (Get-RestaurantIdFromRow -Row $r)
      name         = (Get-RestaurantNameFromRow -Row $r)
      city         = $r.std_city
      locality     = $r.std_locality
      rating       = Parse-DoubleOrNull $r.std_rating
      price_bucket = $r.std_price_bucket
      cuisines     = @("$($r.std_cuisines)".Split('|') | Where-Object { $_ -ne '' })
    }
  }

  # Ensure callers always receive an array (even when it has 0/1 elements).
  Write-Output -NoEnumerate $restaurants
}

function Invoke-GroqChatCompletion {
  param(
    [Parameter(Mandatory = $true)][object[]]$Messages,
    [string]$Model = $env:GROQ_MODEL,
    [double]$Temperature = 0.2,
    [int]$MaxTokens = 512
  )

  if (-not $Model -or $Model.Trim() -eq '') {
    $Model = 'llama-3.3-70b-versatile'
  }

  $apiKey = $env:GROQ_API_KEY
  if (-not $apiKey) {
    throw "GROQ_API_KEY is not set."
  }

  $uri = 'https://api.groq.com/openai/v1/chat/completions'
  $bodyObj = @{
    model       = $Model
    messages    = $Messages
    temperature = $Temperature
    max_tokens  = $MaxTokens
  }

  $json = $bodyObj | ConvertTo-Json -Depth 10
  $headers = @{
    Authorization = "Bearer $apiKey"
    'Content-Type' = 'application/json'
  }

  $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $json
  return $resp.choices[0].message.content
}

function Get-GroqExplanation {
  param(
    [Parameter(Mandatory = $true)][psobject]$Preferences,
    [Parameter(Mandatory = $true)][object[]]$Restaurants
  )

  $prefsJson = $Preferences | ConvertTo-Json -Depth 6
  $restaurantsJson = $Restaurants | ConvertTo-Json -Depth 6

  $system = @{
    role    = 'system'
    content = 'You are a helpful restaurant recommendation assistant. Provide a concise explanation for the selected restaurants.'
  }
  $user = @{
    role    = 'user'
    content = @"
User preferences (JSON):
$prefsJson

Selected restaurants (JSON):
$restaurantsJson

Write a short explanation (4-8 sentences) explaining why these restaurants match the user.
"@
  }

  return Invoke-GroqChatCompletion -Messages @($system, $user)
}

function Start-Phase4ApiServer {
  <#
    Best-effort local HTTP server using HttpListener.
    Note: On some Windows setups, listening on a port may require URL ACL registration.
  #>
  param(
    [int]$Port = 8080,
    [Parameter(Mandatory = $true)][string]$DataCsvPath,
    [string]$DotEnvPath,
    [string]$StaticRootPath,
    [switch]$Once
  )

  if ($DotEnvPath) {
    # Resolve .env path from project root (relative to this module) so it loads regardless of current directory
    $moduleDir = $PSScriptRoot
    $projectRoot = Split-Path (Split-Path $moduleDir -Parent) -Parent
    if (-not [System.IO.Path]::IsPathRooted($DotEnvPath)) {
      $DotEnvPath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $DotEnvPath))
    }
    if (Test-Path -LiteralPath $DotEnvPath) {
      Import-DotEnv -Path $DotEnvPath
    }
  }

  # Resolve paths so the server finds files even if working directory changes
  $DataCsvPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $DataCsvPath))
  if (-not (Test-Path -LiteralPath $DataCsvPath)) {
    throw "Data CSV not found: $DataCsvPath"
  }
  if ($StaticRootPath) {
    $StaticRootPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $StaticRootPath))
  }

  $prefix = "http://localhost:$Port/"
  $listener = New-Object System.Net.HttpListener
  $listener.Prefixes.Add($prefix)

  try {
    $listener.Start()
  } catch {
    throw "Failed to start HttpListener on $prefix. Error: $($_.Exception.Message)"
  }

  Write-Host "Phase4 API listening on $prefix (Ctrl+C to stop)"

  try {
    while ($listener.IsListening) {
      $ctx = $listener.GetContext()
      $req = $ctx.Request
      $res = $ctx.Response

      $path = $req.Url.AbsolutePath
      $method = $req.HttpMethod.ToUpperInvariant()

      $status = 200
      $responseObj = $null

      try {
        if ($method -eq 'GET' -and $path -eq '/places') {
          $places = Get-PlacesFromCsv -DataCsvPath $DataCsvPath
          $responseObj = @{ places = @($places) }
        }
        elseif ($method -eq 'GET' -and $path -eq '/cuisines') {
          $cuisines = Get-CuisinesFromCsv -DataCsvPath $DataCsvPath
          $responseObj = @{ cuisines = @($cuisines) }
        }
        elseif ($method -eq 'GET' -and $path -eq '/health') {
          $responseObj = @{ ok = $true }
        }
        elseif ($method -eq 'GET' -and $path -eq '/' -and $StaticRootPath) {
          # Serve index.html from static root
          $indexPath = Join-Path $StaticRootPath 'index.html'
          if (-not (Test-Path -LiteralPath $indexPath)) {
            $status = 500
            $responseObj = @{ error = "UI index.html not found at $indexPath" }
          } else {
            $html = Get-Content -LiteralPath $indexPath -Raw
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
            $res.StatusCode = 200
            $res.ContentType = 'text/html; charset=utf-8'
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            $res.OutputStream.Flush()
            $res.OutputStream.Close()
            if ($Once) { break }
            continue
          }
        }
        elseif ($method -eq 'POST' -and $path -eq '/recommendations') {
          $body = $null
          $sr = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
          try { $body = $sr.ReadToEnd() } finally { $sr.Close() }

          $parsed = $body | ConvertFrom-Json -ErrorAction Stop
          $prefHash = @{}
          foreach ($p in @('price_preference','location','min_rating','cuisine_preferences','num_results')) {
            $val = Get-ObjectPropertyValueOrNull -Object $parsed -Name $p
            if ($null -ne $val) { $prefHash[$p] = $val }
          }
          $prefs = ConvertTo-PreferenceObject -PreferenceHash $prefHash

          $restaurants = Get-RestaurantRecommendations -DataCsvPath $DataCsvPath -Preferences $prefs

          $explanation = $null
          $explanationError = $null
          if ($env:GROQ_API_KEY -and @($restaurants).Count -gt 0) {
            try {
              $explanation = Get-GroqExplanation -Preferences $prefs -Restaurants $restaurants
            } catch {
              $explanationError = $_.Exception.Message
              $explanation = $null
            }
          }

          $responseObj = @{
            restaurants = @($restaurants)
            explanation = $explanation
            explanation_error = $explanationError
          }
        }
        else {
          $status = 404
          $responseObj = @{ error = "Not found" }
        }
      } catch {
        $status = 500
        $responseObj = @{ error = "Server error"; detail = "$($_.Exception.Message)" }
      }

      $payload = ($responseObj | ConvertTo-Json -Depth 10)
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
      $res.StatusCode = $status
      $res.ContentType = 'application/json; charset=utf-8'
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
      $res.OutputStream.Close()

      if ($Once) { break }
    }
  } finally {
    $listener.Stop()
    $listener.Close()
  }
}

Export-ModuleMember -Function Import-DotEnv, Get-RestaurantRecommendations, Get-GroqExplanation, Get-PlacesFromCsv, Get-CuisinesFromCsv, Start-Phase4ApiServer

