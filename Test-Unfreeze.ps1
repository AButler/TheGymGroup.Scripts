using namespace System.Management.Automation.Host

$ErrorActionPreference = 'Stop'

#1210277486 = Weston Addison (Standard - Existing Paid Freeze Ongoing)
#1210277488 = Walker Allison (Standard - Existing Paid Freeze Ongoing)
#1210285154 = Thomas Amelia (Standard - Existing Free Freeze Ongoing)
#1210287297 = Samuel Ava (Standard - Existing Free Freeze Ongoing)
$memberId = 1211104414

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
  endDate   = [DateTime]::Today.AddDays(-1).ToString("yyyy-MM-dd")
  reasonId  = $currentFreezePeriod.idlePeriodReason.id
  unlimited = $false
}

Write-Host "/v1/memberships/$($primaryContract.id)/self-service/idle-periods/$($currentFreezePeriod.id)/preview"
Write-Host (ConvertTo-Json $unfreezeRequestBody)

$previewResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods/$($currentFreezePeriod.id)/preview" -Method Put -Headers @{ "x-api-key" = $apiKey } -Body ($unfreezeRequestBody | ConvertTo-Json) -ContentType "application/json"
  
#Write-Host "Unfreeze Preview Response: $($previewResponse | ConvertTo-Json -Depth 10)"

Write-Host "Unfreeze Preview - Payment Schedule:"
$dueToday = 0;
$dueDate = '';
$paidPeriodFrom = '';
$paidPeriodTo = '';
foreach ($charge in $previewResponse.previewCharges) {
  Write-Host "  [$($charge.dueDate)] $($charge.paidPeriodFrom) - $($charge.paidPeriodTo) | $($charge.amount.amount.ToString("C")) - $($charge.description) [$($charge.chargeType)]"
  if ($charge.paidPeriodFrom -eq [DateTime]::Today.ToString("yyyy-MM-dd") -and $charge.chargeType -eq 'MEMBERSHIP_CHARGE') {
    $dueToday += $charge.amount.amount
    $dueDate = $charge.dueDate
    $paidPeriodFrom = $charge.paidPeriodFrom
    $paidPeriodTo = $charge.paidPeriodTo
  }
}

Write-Host "Total Due Today: $($dueToday.ToString("C"))"

$choices = [ChoiceDescription[]] @(
  [ChoiceDescription]::new("&Yes (Unfreeze Membership)", "Unfreeze the membership"),
  [ChoiceDescription]::new("&No (Skip)", "Do nothing")
)

$choice = $host.UI.PromptForChoice('Unfreeze', 'Do you want to unfreeze the membership?', $choices, 1)

if ($choice -eq 1) {
  Write-Host "Skipping"
  exit 0
}

$paymentRequestBody = ConvertTo-Json @{
  amount                  = $dueToday
  scope                   = 'ECOM'
  permittedPaymentChoices = @("CREDIT_CARD")
  referenceText           = 'Unfreeze Pro-Rata Fee'
  customerId              = $memberId
}

$sessionToken = Invoke-RestMethod -Uri "$baseUrl/v1/payments/user-session" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $paymentRequestBody -ContentType 'application/json'
Write-Host "  - Session Token: $($sessionToken.token)" -ForegroundColor Green
Write-Host "    http://localhost:3000/payment-page.html?paymentSessionToken=$($sessionToken.token)" -ForegroundColor DarkGray
$paymentRequestToken = Read-Host -Prompt "Enter payment request token"

$boundary = [Guid]::NewGuid().ToString()
$unfreezeMultipartBody = @( 
  "--$boundary",
  "Content-Disposition: form-data;name=`"data`"",
  "Content-Type: application/json",
  '',
  "$($unfreezeRequestBody | ConvertTo-Json)",
  "--$boundary--"
) -join "`r`n"

$unfreezeResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($primaryContract.id)/self-service/idle-periods/$($currentFreezePeriod.id)" -Method Put -Headers @{ "x-api-key" = $apiKey } -Body $unfreezeMultipartBody -ContentType "multipart/form-data; boundary=$boundary"

#Write-Host "Unfreeze Response: $($unfreezeResponse | ConvertTo-Json -Depth 10)"

$debtId = $null
$retryDebtAttempts = 0

while ($null -eq $debtId -and $retryDebtAttempts -lt 10) {
  $upcomingTransactions = Invoke-RestMethod -Uri "$baseUrl/v1/customers/$memberId/account/transactions/upcoming" -Method Get -Headers @{ "x-api-key" = $apiKey }

  $debtId = ($upcomingTransactions.result | Where-Object { $_.amount.amount -eq $dueToday -and $_.openAmount.amount -eq $dueToday -and $_.dueDate -eq $dueDate -and $_.paidPeriodFrom -eq $paidPeriodFrom -and $_.paidPeriodTo -eq $paidPeriodTo } | Select-Object -First 1).id

  if ($null -eq $debtId) { 
    Write-Host "Could not find matching upcoming transaction for unfreeze charge. Retrying in 1 seconds..." 
    Start-Sleep -Seconds 1
    $retryDebtAttempts++ 
  }
}

if ($null -eq $debtId) {
  Write-Host (ConvertTo-Json $upcomingTransactions -Depth 10)
  Write-Error "Could not find upcoming transaction for the unfreeze charge." 
  exit 1 
}

$bookPaymentBody = @{
  paymentRequestToken = $paymentRequestToken
  amount              = @{
    amount   = $dueToday
    currency = 'GBP' 
  } 
  debtClaimIds        = @($debtId)
}

$bookPaymentResponse = Invoke-RestMethod -Uri "$baseUrl/v1/customers/$memberId/account/payment" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body (ConvertTo-Json $bookPaymentBody) -ContentType 'application/json'

Write-Host "Membership unfrozen successfully."