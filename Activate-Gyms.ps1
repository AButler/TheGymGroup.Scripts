param(
  [Parameter(Mandatory = $true)]
  [string]$InputFile,
  [switch]$Production
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -Path $InputFile)) {
  Write-Error "Input file '$InputFile' does not exist."
  exit 1
}

$urlSuffix = if ($Production) { ".open-api.perfectgym.com" } else { ".open-api.sandbox.perfectgym.com" }

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

  $tenant = $gym."Tenant Name"
  $baseUrl = "https://$($tenant)$($urlSuffix)"

  Invoke-RestMethod -Uri "$BaseUrl/v1/studios/confirmActivation" -Method Post -Headers @{ "x-api-key" = $apiKey }
}

Write-Host 'Done!'