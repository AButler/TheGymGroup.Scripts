$ErrorActionPreference = 'Stop'

$memberId = 1210716791

$baseUrl = 'https://tgg-dev.open-api.sandbox.perfectgym.com'

$gymIds = @{
  '1210093500' = @{ name = 'London East Croydon'; apiKey = '7ad2820f-80a5-4526-903c-cea9a771485e' } 
  '1210133180' = @{ name = 'Holborn Circus'; apiKey = 'f4800efd-5f8a-4e84-94dc-2cf629682726' } 
  '1210131000' = @{ name = 'Hounslow'; apiKey = '3322a8ee-7198-46ab-9c59-15a8e7f1c632' } 
  '1210130080' = @{ name = 'Ilford Romford Road'; apiKey = '355a447b-f1be-4e38-a924-ab148c54266d' } 
  '1210130920' = @{ name = 'Ilford Pioneer'; apiKey = 'b2660123-a7d7-4dfe-afcd-4760c632845d' } 
}

$membershipOfferIds = @(
  1210475600,
  1210555910,
  1210404030,
  1210404633,
  1210404260,
  1210539870,
  1210404631,
  1210404632,
  1210404031,
  1210404261,
  1210555910,
  1210539870,
  1210404633,
  1210404261,
  1210404260,
  1210404631,
  1210475600,
  1210404632,
  1210404030,
  1210404031,
  1210404030,
  1210404633,
  1210539870,
  1210404631,
  1210475600,
  1210555910,
  1210404261,
  1210404632,
  1210404031,
  1210404260,
  1210404031,
  1210555910,
  1210539870,
  1210404633,
  1210475600,
  1210404260,
  1210404261,
  1210404632,
  1210404030,
  1210404631,
  1210555910,
  1210404031,
  1210404633,
  1210404260,
  1210404632,
  1210539870,
  1210404261,
  1210475600,
  1210404631,
  1210404030
)

#for ($i = 0; $i -lt 200; $i++) {
while ($true) {
  $gym = $gymIds.Keys | Get-Random
  $apiKey = $gymIds[$gym].apiKey
  $membershipOfferId = $membershipOfferIds | Get-Random
  $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
  $response = Invoke-WebRequest -Uri "$baseUrl/v1/memberships/membership-offers/$membershipOfferId" -Method Get -Headers @{ 'x-api-key' = $apiKey } -SkipHttpErrorCheck
  $statusCode = $response.StatusCode

  if ($statusCode -ne 200) {
    Write-Host ""
    Write-Host "Failed : $statusCode" -ForegroundColor Red
    Write-Host "Timestamp: $timestamp"
    Write-Host "URL: $baseUrl/v1/memberships/membership-offers/$membershipOfferId"
    Write-Host "x-api-key: $apiKey"
    Write-Host ""
    Write-Host $response.Content
    Write-Host ""
    Write-Host ""
    Start-Sleep -Seconds 1
  }
  else {
    Write-Host "." -NoNewline
    
    Start-Sleep -Milliseconds 100
  }
}


