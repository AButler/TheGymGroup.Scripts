param(
  [Parameter(Mandatory = $true)]
  [string]$InputFile,
  [Parameter(Mandatory = $true)]
  [ValidateSet("dev", "sit", "pat")]
  [string]$Environment
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -Path $InputFile)) {
  Write-Error "Input file '$InputFile' does not exist."
  exit 1
}

switch ($Environment) {
  "dev" {
    $BaseUrl = "https://tgg-dev.open-api.sandbox.perfectgym.com"
  }
  "sit" {
    $BaseUrl = "https://tgg-sit.open-api.sandbox.perfectgym.com"
  }
  "pat" {
    $BaseUrl = "https://tgg-pat.open-api.sandbox.perfectgym.com"
  }
}

try {
  $gyms = Get-Content -Path $InputFile | ConvertFrom-Csv
}
catch {
  Write-Error "Failed to read or parse the input file: $_"
  exit 1
}

foreach ($gym in $gyms) {
  Write-Host "Activating gym '$($gym."Studio Name")'..."
  $apiKey = $gym."Api Key"
  Write-Host "  * $apiKey"

  Invoke-RestMethod -Uri "$BaseUrl/v1/studios/confirmActivation" -Method Post -Headers @{ "x-api-key" = $apiKey }
}

Write-Host 'Done!'