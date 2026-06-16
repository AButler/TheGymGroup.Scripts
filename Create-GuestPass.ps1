$ErrorActionPreference = 'Stop'

$memberId = Read-Host 'Enter existing Member ID'

if ([string]::IsNullOrEmpty($memberId)) {
  exit 1
}

$tenant = 'dev'
$baseUrl = "https://tgg-$tenant.open-api.sandbox.perfectgym.com"

$gymIds = (ConvertFrom-Json (Get-Content (Join-Path $PSScriptRoot 'api-keys.json') -Raw) -AsHashtable)[$tenant]

$guestPassesToPurchase = @(
  @{
    name         = 'Guest Pass'
    studioId     = '1210133180'
    daysInFuture = 1
  },
  @{
    name         = 'Guest Pass'
    studioId     = '1210131000'
    daysInFuture = 10
  }
)

$today = [DateOnly]::FromDateTime([DateTime]::Today)
$crossStudioApiKey = $($gymIds.Values)[0].apiKey

Write-Host "Getting customer..."

$customer = Invoke-RestMethod -Uri "$baseUrl/v1/cross-studio/customers/$memberId" -Method Get -Headers @{ 'x-api-key' = $crossStudioApiKey }

$apiKey = $gymIds[$customer.studioId.ToString()].apiKey

$iteration = 1

foreach ($guestPass in $guestPassesToPurchase) {
  Write-Host "Guest Pass $iteration/$($guestPassesToPurchase.Count)"
  Write-Host "  - Querying..."

  $purchasableGuestPasses = Invoke-RestMethod -Uri "$baseUrl/v1/online-offers/purchasable" -Method Get -Headers @{ 'x-api-key' = $gymIds[$guestPass.studioId].apiKey }
  $guestPassDetails = ($purchasableGuestPasses.result | Where-Object { $_.name -eq $guestPass.name })

  Write-Host "  - [$($guestPassDetails.onlineOfferId)] $($guestPassDetails.name) £$($guestPassDetails.price.amount)" -ForegroundColor Green

  Write-Host "  - Purchasing..."

  $purchaseBody = ConvertTo-Json @{
    onlineOfferId = $guestPassDetails.onlineOfferId
    customerId    = $memberId
    validFrom     = $today.AddDays($guestPass.daysInFuture).ToString("yyyy-MM-dd")
  }

  Write-Host $purchaseBody -ForegroundColor DarkGray

  $purchaseResponse = Invoke-RestMethod -Uri "$baseUrl/v1/online-offers/purchase" -Method Post -Headers @{ 'x-api-key' = $gymIds[$guestPass.studioId].apiKey } -Body $purchaseBody -ContentType 'application/json' -StatusCodeVariable purchaseStatusCode -SkipHttpErrorCheck
  if ($purchaseStatusCode -ne 200) {
    Write-Error "Purchase failed with status code $purchaseStatusCode`n`n$(ConvertTo-Json $purchaseResponse -Depth 10)"
    exit 1
  }

  $iteration++
}

$purchasedPasses = Invoke-RestMethod -Uri "$baseUrl/v1/online-offers/$memberId/purchased" -Method Get -Headers @{ 'x-api-key' = $apiKey }

foreach ($purchasedPass in $purchasedPasses) {
  Write-Host "  - [$($purchasedPass.onlineOfferPurchaseId)] $($purchasedPass.name)" -ForegroundColor Green
}

Write-Host 'Done!'
