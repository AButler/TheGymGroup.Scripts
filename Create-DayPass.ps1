$ErrorActionPreference = 'Stop'

$memberId = Read-Host 'Enter existing Member ID'

if ([string]::IsNullOrEmpty($memberId)) {
  exit 1
}

$tenant = 'dev'
$baseUrl = "https://tgg-$tenant.open-api.sandbox.perfectgym.com"

$gymIds = (ConvertFrom-Json (Get-Content (Join-Path $PSScriptRoot 'api-keys.json') -Raw) -AsHashtable)[$tenant]

$dayPassesToPurchase = @(
  @{
    name         = '1 day pass'
    studioId     = '1210133180'
    daysInFuture = 0
  },
  @{
    name         = '3 day pass'
    studioId     = '1210133180'
    daysInFuture = 2
  }
)

$today = [DateOnly]::FromDateTime([DateTime]::Today)
$crossStudioApiKey = $gymIds['CrossStudio'].apiKey

Write-Host "Getting customer..."

$customer = Invoke-RestMethod -Uri "$baseUrl/v1/cross-studio/customers/$memberId" -Method Get -Headers @{ 'x-api-key' = $crossStudioApiKey }

$apiKey = $gymIds[$customer.studioId.ToString()].apiKey

$iteration = 1

foreach ($dayPass in $dayPassesToPurchase) {
  Write-Host "Day Pass $iteration/$($dayPassesToPurchase.Count)"
  Write-Host "  - Querying..."

  $purchasableDayPasses = Invoke-RestMethod -Uri "$baseUrl/v1/online-offers/purchasable" -Method Get -Headers @{ 'x-api-key' = $gymIds[$dayPass.studioId].apiKey }
  $dayPassDetails = ($purchasableDayPasses.result | Where-Object { $_.name -eq $dayPass.name })

  Write-Host "  - [$($dayPassDetails.onlineOfferId)] $($dayPassDetails.name) £$($dayPassDetails.price.amount)" -ForegroundColor Green

  Write-Host "  - Creating payment token..."
  $paymentRequestBody = ConvertTo-Json @{
    amount                  = $dayPassDetails.price.amount
    scope                   = 'ECOM'
    customerId              = $memberId
    permittedPaymentChoices = @("CREDIT_CARD")
    referenceText           = $dayPassDetails.name
  }
  $sessionToken = Invoke-RestMethod -Uri "$baseUrl/v1/payments/user-session" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $paymentRequestBody -ContentType 'application/json'

  Write-Host "  - Session Token: $($sessionToken.token)" -ForegroundColor Green
  Write-Host "    http://localhost:3000/payment-page.html?paymentSessionToken=$($sessionToken.token)" -ForegroundColor DarkGray

  $paymentRequestToken = Read-Host -Prompt "    Enter payment request token"

  Write-Host "  - Purchasing..."

  $purchaseBody = ConvertTo-Json @{
    onlineOfferId       = $dayPassDetails.onlineOfferId
    customerId          = $memberId
    validFrom           = $today.AddDays($dayPass.daysInFuture).ToString("yyyy-MM-dd")
    paymentRequestToken = $paymentRequestToken
  }

  Write-Host $purchaseBody -ForegroundColor DarkGray

  $purchaseResponse = Invoke-RestMethod -Uri "$baseUrl/v1/online-offers/purchase" -Method Post -Headers @{ 'x-api-key' = $gymIds[$dayPass.studioId].apiKey } -Body $purchaseBody -ContentType 'application/json' -StatusCodeVariable purchaseStatusCode -SkipHttpErrorCheck
  if ($purchaseStatusCode -ne 200) {
    Write-Error "Purchase failed with status code $purchaseStatusCode`n`n$(ConvertTo-Json $purchaseResponse -Depth 10)"
    exit 1
  }

  $iteration++
}

$purchasedDayPasses = Invoke-RestMethod -Uri "$baseUrl/v1/online-offers/$memberId/purchased" -Method Get -Headers @{ 'x-api-key' = $apiKey }

foreach ($purchasedDayPass in $purchasedDayPasses) {
  Write-Host "  - [$($purchasedDayPass.onlineOfferPurchaseId)] $($purchasedDayPass.name)" -ForegroundColor Green
}

Write-Host 'Done!'
