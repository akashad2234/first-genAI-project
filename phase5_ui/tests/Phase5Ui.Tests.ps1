$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$phase5 = Split-Path -Parent $here

Describe 'Phase5 UI' {
  It 'has a valid index.html with key elements' {
    $indexPath = Join-Path $phase5 'public\index.html'
    Test-Path $indexPath | Should Be $true

    $html = Get-Content -LiteralPath $indexPath -Raw
    $html | Should Match '<title>AI Restaurant Recommendation Service</title>'
    $html | Should Match 'id="prefs-form"'
    $html | Should Match 'id="cards"'
    $html | Should Match 'Get recommendations'
  }
}

