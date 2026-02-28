$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$phase4 = Split-Path -Parent $here

Import-Module (Join-Path $phase4 'src\Phase4Api.psm1') -Force

Describe 'Phase4 API logic' {
  $fixture = Join-Path $phase4 'tests\fixtures\restaurants_processed.csv'

  It 'filters restaurants by price, location, rating, cuisine' {
    $prefs = [pscustomobject]@{
      price_preference = 'medium'
      location = 'Bangalore, Indiranagar'
      min_rating = 4.0
      cuisine_preferences = @('pizza')
      num_results = 5
    }

    $results = Get-RestaurantRecommendations -DataCsvPath $fixture -Preferences $prefs

    ($results.Count -ge 1) | Should Be $true
    @($results | Where-Object { $_.name -eq 'La Piazza' }).Count | Should Be 1
    @($results | Where-Object { $_.name -eq 'Pizza House' }).Count | Should Be 0  # wrong locality
  }

  It 'returns top N results sorted by rating (desc)' {
    $prefs = [pscustomobject]@{
      location = 'Bangalore'
      num_results = 2
    }

    $results = Get-RestaurantRecommendations -DataCsvPath $fixture -Preferences $prefs
    $results.Count | Should Be 2
    $results[0].name | Should Be 'Sushi Zen'
  }

  It 'calls Groq to generate explanation when GROQ_API_KEY exists' {
    $envPath = Join-Path (Split-Path -Parent $phase4) 'data\.env'
    Import-DotEnv -Path $envPath

    if (-not $env:GROQ_API_KEY) {
      Set-TestInconclusive 'GROQ_API_KEY not found; skipping Groq integration.'
      return
    }

    $prefs = [pscustomobject]@{
      price_preference = 'medium'
      location = 'Bangalore, Indiranagar'
      min_rating = 4.0
      cuisine_preferences = @('italian','pizza')
      num_results = 2
    }

    $results = Get-RestaurantRecommendations -DataCsvPath $fixture -Preferences $prefs
    $explanation = Get-GroqExplanation -Preferences $prefs -Restaurants $results

    ($explanation -is [string]) | Should Be $true
    ($explanation.Trim().Length -gt 20) | Should Be $true
  }
}

