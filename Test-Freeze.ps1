$ErrorActionPreference = 'Stop'

$memberId = Read-Host 'Enter existing Member ID'

if ([string]::IsNullOrEmpty($memberId)) {
  exit 1
}

$tenant = 'dev'
$baseUrl = "https://tgg-$tenant.open-api.sandbox.perfectgym.com"

$gymIds = (ConvertFrom-Json (Get-Content (Join-Path $PSScriptRoot 'api-keys.json') -Raw) -AsHashtable)[$tenant]

$crossStudioApiKey = $gymIds['CrossStudio'].apiKey

$member = Invoke-RestMethod -Uri "$baseUrl/v1/cross-studio/customers/$memberId" -Headers @{ "x-api-key" = $crossStudioApiKey }

Write-Host "Member: [$($member.id)] $($member.firstName) $($member.lastName)"

$memberHomeGym = $gymIds[$member.studioId.ToString()]

Write-Host "Home Gym: [$($member.studioId)] $($memberHomeGym.name)"

$apiKey = $memberHomeGym.apiKey

$contracts = Invoke-RestMethod -Uri "$baseUrl/v1/customers/$memberId/contracts" -Headers @{ "x-api-key" = $apiKey }

$primaryContract = $contracts | Where-Object { $_.contractStatus -eq 'ACTIVE' } | Select-Object -First 1

Write-Host "Primary Contract: [$($primaryContract.id)] $($primaryContract.rateName) - $($primaryContract.startDate)-$($primaryContract.endDate)"

$idlePeriodConfig = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods/config" -Headers @{ "x-api-key" = $apiKey }

Write-Host "----------"

#Write-Host (ConvertTo-Json $idlePeriodConfig)

$totalFree = $idlePeriodConfig.freeTerms.value

Write-Host "Idle Period Config:"
Write-Host "  * Max Terms: $($idlePeriodConfig.maxTerms)"
Write-Host "  * Monthly Fee: $($idlePeriodConfig.idlePeriodFeeCalculationConfig.idlePeriodAmountPerTermUnit.amount) $($idlePeriodConfig.idlePeriodFeeCalculationConfig.idlePeriodAmountPerTermUnit.currency)"
Write-Host "  * Unlimited Allowed: $($idlePeriodConfig.unlimitedAllowed)"
Write-Host "  * First Possible Start Date: $($idlePeriodConfig.firstPossibleStartDate)"

$firstPossibleStartDate = [DateOnly]::Parse($idlePeriodConfig.firstPossibleStartDate)

$memberIdlePeriods = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods" -Headers @{ "x-api-key" = $apiKey }
$memberIdlePeriodsRemaining = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods/remaining" -Headers @{ "x-api-key" = $apiKey }

#Write-Host (ConvertTo-Json $memberIdlePeriods)
#Write-Host (ConvertTo-Json $memberIdlePeriodsRemaining)

Write-Host "----------"

$canFreeFreeze = $false
if ($memberIdlePeriodsRemaining.remainingFreeTerms.unit -eq 'MONTH' -and $memberIdlePeriodsRemaining.remainingFreeTerms.value -gt 0) {
  Write-Host "Member has $($memberIdlePeriodsRemaining.remainingFreeTerms.value) free idle period terms remaining."
  $canFreeFreeze = $true
}
else {
  Write-Host "Member has no free idle period terms remaining."
}

Write-Host "----------"

if ($memberIdlePeriods.currentAndUpcomingIdlePeriods.count -gt 0) {
  Write-Host "Member has the following current/upcoming idle periods:"
  foreach ($idlePeriod in $memberIdlePeriods.currentAndUpcomingIdlePeriods) {
    $timePeriod = "$($idlePeriod.startDate) to $($idlePeriod.endDate)"
    if ($idlePeriod.unlimited) {
      $timePeriod = "$($idlePeriod.startDate) [ONGOING]"
    }
    
    Write-Host "  * [$($idlePeriod.id)] $timePeriod"
  }
  exit 1
}

$freezeStartDate = [DateOnly]::Parse($primaryContract.startDate)

while ($freezeStartDate -lt $firstPossibleStartDate) {
  $freezeStartDate = $freezeStartDate.AddMonths(1)
}
Write-Host "Freeze Start Date: $($freezeStartDate.ToString("yyyy-MM-dd"))"
Write-Host "----------"

if ($canFreeFreeze) {
  Write-Host "Creating free freeze..."
  $freezeRequestBody = @{
    startDate    = $freezeStartDate.ToString("yyyy-MM-dd")
    temporalUnit = "MONTH"
    termValue    = 1
    reasonId     = $idlePeriodConfig.idlePeriodReasons[0].id
  }

  $validateResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods/validate" -Method Post -Headers @{ "x-api-key" = $apiKey } -Body ($freezeRequestBody | ConvertTo-Json) -ContentType "application/json"
  
  if ($validateResponse.validationStatus -ne 'IDLEPERIOD_CREATABLE') {
    Write-Error "Idle period is not creatable: $($validateResponse.validationStatus)"
    exit 1
  }

  $boundary = [Guid]::NewGuid().ToString()
  $freezeRequestMultipartBody = @( 
    "--$boundary",
    "Content-Disposition: form-data;name=`"data`"",
    "Content-Type: application/json",
    '',
    "$($freezeRequestBody | ConvertTo-Json)",
    "--$boundary--"
  ) -join "`r`n"

  $freezeResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods" -Method Post -Headers @{ "x-api-key" = $apiKey } -Body $freezeRequestMultipartBody -ContentType "multipart/form-data; boundary=$boundary"

  Write-Host "Freeze Response: $($freezeResponse | ConvertTo-Json)"
}
else {
  Write-Host "Creating paid freeze..."

  $freezeRequestBody = @{
    startDate = $freezeStartDate.ToString("yyyy-MM-dd")
    unlimited = $true
    reasonId  = $idlePeriodConfig.idlePeriodReasons[0].id
  }

  Write-Host "-----------------------"
  Write-Host "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods/validate"
  Write-Host ($freezeRequestBody | ConvertTo-Json)
  Write-Host "-----------------------"

  $validateResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods/validate" -Method Post -Headers @{ "x-api-key" = $apiKey } -Body ($freezeRequestBody | ConvertTo-Json) -ContentType "application/json"
  
  if ($validateResponse.validationStatus -ne 'IDLEPERIOD_CREATABLE') {
    Write-Error "Idle period is not creatable: $($validateResponse.validationStatus)"
    exit 1
  }

  $boundary = [Guid]::NewGuid().ToString()
  $freezeRequestMultipartBody = @( 
    "--$boundary",
    "Content-Disposition: form-data;name=`"data`"",
    "Content-Type: application/json",
    '',
    "$($freezeRequestBody | ConvertTo-Json)",
    "--$boundary--"
  ) -join "`r`n"

  $freezeResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods" -Method Post -Headers @{ "x-api-key" = $apiKey } -Body $freezeRequestMultipartBody -ContentType "multipart/form-data; boundary=$boundary"

  Write-Host "Freeze Response: $($freezeResponse | ConvertTo-Json)"
}