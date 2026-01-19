$ErrorActionPreference = 'Stop'

$memberId = 1210656710

$baseUrl = 'https://tgg-dev.open-api.sandbox.perfectgym.com'

$gymIds = @{
  '1210093500' = @{ name = 'London East Croydon'; apiKey = '7ad2820f-80a5-4526-903c-cea9a771485e' } 
  '1210133180' = @{ name = 'Holborn Circus'; apiKey = 'f4800efd-5f8a-4e84-94dc-2cf629682726' } 
  '1210131000' = @{ name = 'Hounslow'; apiKey = '3322a8ee-7198-46ab-9c59-15a8e7f1c632' } 
  '1210130080' = @{ name = 'Ilford Romford Road'; apiKey = '355a447b-f1be-4e38-a924-ab148c54266d' } 
  '1210130920' = @{ name = 'Ilford Pioneer'; apiKey = 'b2660123-a7d7-4dfe-afcd-4760c632845d' } 
}

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

  Write-Host "  - [$($guestPassDetails.id)] $($guestPassDetails.name) £$($guestPassDetails.price.amount)" -ForegroundColor Green

  Write-Host "  - Purchasing..."

  $purchaseBody = ConvertTo-Json @{
    onlineOfferId = $guestPassDetails.id
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
  Write-Host "  - [$($purchasedPass.id)] $($purchasedPass.name)" -ForegroundColor Green
}

Write-Host 'Done!'
