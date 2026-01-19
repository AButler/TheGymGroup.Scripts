$ErrorActionPreference = 'Stop'

$memberId = 1210465502

$baseUrl = 'https://tgg-dev.open-api.sandbox.perfectgym.com'

$gymIds = @{
  '1210093500' = @{ name = 'London East Croydon'; apiKey = '7ad2820f-80a5-4526-903c-cea9a771485e' } 
  '1210133180' = @{ name = 'Holborn Circus'; apiKey = 'f4800efd-5f8a-4e84-94dc-2cf629682726' } 
  '1210131000' = @{ name = 'Hounslow'; apiKey = '3322a8ee-7198-46ab-9c59-15a8e7f1c632' } 
  '1210130080' = @{ name = 'Ilford Romford Road'; apiKey = '355a447b-f1be-4e38-a924-ab148c54266d' } 
  '1210130920' = @{ name = 'Ilford Pioneer'; apiKey = 'b2660123-a7d7-4dfe-afcd-4760c632845d' } 
}

$dayPassesToPurchase = @(
  @{
    name         = '5 day pass'
    studioId     = '1210133180'
    daysInFuture = 1
  },
  @{
    name         = '3 day pass'
    studioId     = '1210131000'
    daysInFuture = 10
  }
)

$today = [DateOnly]::FromDateTime([DateTime]::Today)
$crossStudioApiKey = $($gymIds.Values)[0].apiKey
$paymentFilePath = Resolve-Path (Join-Path $PSScriptRoot 'payment-page.html')

Write-Host "Getting customer..."

$customer = Invoke-RestMethod -Uri "$baseUrl/v1/cross-studio/customers/$memberId" -Method Get -Headers @{ 'x-api-key' = $crossStudioApiKey }

$apiKey = $gymIds[$customer.studioId.ToString()].apiKey

$iteration = 1

foreach ($dayPass in $dayPassesToPurchase) {
  Write-Host "Day Pass $iteration/$($dayPassesToPurchase.Count)"
  Write-Host "  - Querying..."

  $purchasableDayPasses = Invoke-RestMethod -Uri "$baseUrl/v1/online-offers/purchasable" -Method Get -Headers @{ 'x-api-key' = $gymIds[$dayPass.studioId].apiKey }
  $dayPassDetails = ($purchasableDayPasses.result | Where-Object { $_.name -eq $dayPass.name })

  Write-Host "  - [$($dayPassDetails.id)] $($dayPassDetails.name) £$($dayPassDetails.price.amount)" -ForegroundColor Green

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
  Write-Host "    file:///$($paymentFilePath)?paymentSessionToken=$($sessionToken.token)" -ForegroundColor DarkGray

  $paymentRequestToken = Read-Host -Prompt "    Enter payment request token"

  Write-Host "  - Purchasing..."

  $purchaseBody = ConvertTo-Json @{
    onlineOfferId              = $dayPassDetails.id
    customerId                 = $memberId
    validFrom                  = $today.AddDays($dayPass.daysInFuture).ToString("yyyy-MM-dd")
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
  Write-Host "  - [$($purchasedDayPass.id)] $($purchasedDayPass.name)" -ForegroundColor Green
}

Write-Host 'Done!'
