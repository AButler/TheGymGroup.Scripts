$ErrorActionPreference = 'Stop'

#1210277486 = Weston Addison (Standard - Existing Paid Freeze Ongoing)
$memberId = 1210277486

$baseUrl = 'https://tgg-dev.open-api.sandbox.perfectgym.com'

$gymIds = @{
  '1210093500' = @{ name = 'London East Croydon'; apiKey = '7ad2820f-80a5-4526-903c-cea9a771485e' } 
  '1210133180' = @{ name = 'Holborn Circus'; apiKey = 'f4800efd-5f8a-4e84-94dc-2cf629682726' } 
  '1210131000' = @{ name = 'Hounslow'; apiKey = '3322a8ee-7198-46ab-9c59-15a8e7f1c632' } 
  '1210130080' = @{ name = 'Ilford Romford Road'; apiKey = '355a447b-f1be-4e38-a924-ab148c54266d' } 
  '1210130920' = @{ name = 'Ilford Pioneer'; apiKey = 'b2660123-a7d7-4dfe-afcd-4760c632845d' } 
}

$crossStudioApiKey = $gymIds['1210093500'].apiKey

$member = Invoke-RestMethod -Uri "$baseUrl/v1/cross-studio/customers/$memberId" -Headers @{ "x-api-key" = $crossStudioApiKey }

Write-Host "Member: [$($member.id)] $($member.firstName) $($member.lastName)"

$memberHomeGym = $gymIds[$member.studioId.ToString()]

Write-Host "Home Gym: [$($member.studioId)] $($memberHomeGym.name)"

$apiKey = $memberHomeGym.apiKey

$contracts = Invoke-RestMethod -Uri "$baseUrl/v1/customers/$memberId/contracts" -Headers @{ "x-api-key" = $apiKey }

$primaryContract = $contracts | Where-Object { $_.contractStatus -eq 'ACTIVE' } | Select-Object -First 1

Write-Host "Primary Contract: [$($primaryContract.id)] $($primaryContract.rateName) - $($primaryContract.startDate)-$($primaryContract.endDate)"

Write-Host "----------"

$memberIdlePeriods = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods" -Headers @{ "x-api-key" = $apiKey }

#Write-Host (ConvertTo-Json $memberIdlePeriods)

if ($memberIdlePeriods.currentAndUpcomingIdlePeriods.count -gt 0) {
  Write-Host "Member has the following current/upcoming idle periods:"
  foreach ($idlePeriod in $memberIdlePeriods.currentAndUpcomingIdlePeriods) {
    $timePeriod = "$($idlePeriod.startDate) to $($idlePeriod.endDate)"
    if ($idlePeriod.unlimited) {
      $timePeriod = "$($idlePeriod.startDate) [ONGOING]"
    }
    
    Write-Host "  * [$($idlePeriod.id)] $timePeriod"
  }
}

$canUnfreeze = $false

$currentFreezePeriods = $memberIdlePeriods.currentAndUpcomingIdlePeriods | Where-Object { $_.startDate -le [DateTime]::Today.ToString("yyyy-MM-dd") }
if ($currentFreezePeriods.count -gt 0) {
  Write-Host "Member has current freeze."
  $canUnfreeze = $true
}
else {
  Write-Host "Member has no current freeze."
}

if (!$canUnfreeze) {
  Write-Host "Exiting without attempting unfreeze since member has no current freeze."
  exit 1
}

Write-Host "----------"
$currentFreezePeriod = $currentFreezePeriods | Select-Object -First 1

Write-Host "Previewing unfreeze..."
$unfreezeRequestBody = @{
  startDate = $currentFreezePeriod.startDate
  endDate   = [DateTime]::Today.ToString("yyyy-MM-dd")
  reasonId  = $currentFreezePeriod.idlePeriodReason.id
  unlimited = $false
}

Write-Host "/v1/memberships/$($primaryContract.id)/self-service/idle-periods/$($currentFreezePeriod.id)/preview"
Write-Host (ConvertTo-Json $unfreezeRequestBody)

$previewResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods/$($currentFreezePeriod.id)/preview" -Method Put -Headers @{ "x-api-key" = $apiKey } -Body ($unfreezeRequestBody | ConvertTo-Json) -ContentType "application/json"
  
Write-Host "Unfreeze Response: $($previewResponse | ConvertTo-Json -Depth 10)"