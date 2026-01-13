$ErrorActionPreference = 'Stop'

$memberId = 1210573334
$addonProductsToAdd = @( 
  'Guest Pass'
  'Additional Gyms'
)
$addonsToRemove = @(
  'Yanga'
)

$baseUrl = 'https://tgg-dev.open-api.sandbox.perfectgym.com'
$cancellationReasonName = 'Unknown'

$gymIds = @{
  '1210093500' = @{ name = 'London East Croydon'; apiKey = '7ad2820f-80a5-4526-903c-cea9a771485e' } 
  '1210133180' = @{ name = 'Holborn Circus'; apiKey = 'f4800efd-5f8a-4e84-94dc-2cf629682726' } 
  '1210131000' = @{ name = 'Hounslow'; apiKey = '3322a8ee-7198-46ab-9c59-15a8e7f1c632' } 
  '1210130080' = @{ name = 'Ilford Romford Road'; apiKey = '355a447b-f1be-4e38-a924-ab148c54266d' } 
  '1210130920' = @{ name = 'Ilford Pioneer'; apiKey = 'b2660123-a7d7-4dfe-afcd-4760c632845d' } 
}

$today = [DateOnly]::FromDateTime([DateTime]::Today)
$crossStudioApiKey = $($gymIds.Values)[0].apiKey

Write-Host "Getting customer..."

$customer = Invoke-RestMethod -Uri "$baseUrl/v1/cross-studio/customers/$memberId" -Method Get -Headers @{ 'x-api-key' = $crossStudioApiKey }

$apiKey = $gymIds[$customer.studioId.ToString()].apiKey

Write-Host "Getting contracts..."

$contracts = Invoke-RestMethod -Uri "$baseUrl/v1/customers/$memberId/contracts" -Method Get -Headers @{ 'x-api-key' = $apiKey }

$activeContracts = $contracts | Where-Object { $_.contractStatus -eq 'ACTIVE' }

if ($activeContracts.Count -eq 0) {
  Write-Error "No active contracts found!"
  exit
}

if ($activeContracts.Count -gt 1) {
  Write-Error "Multiple active contracts found!"
  exit
}

$contract = $activeContracts[0]
$nextBillingDate = [DateOnly]::Parse($contract.endDate).AddDays(1)

Write-Host "Getting available addons..."
$purchasableAddons = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($contract.id)/self-service/additional-modules/purchasable" -Method Get -Headers @{ 'x-api-key' = $apiKey }
$visiblePurchasableAddons = $purchasableAddons | Where-Object { ($_.rateCodes | Where-Object { $_.name -eq 'API Browsable' }).Count -gt 0 }

Write-Host "Getting cancellation reasons..."
$cancellationReasons = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/self-service/contract-cancelation-reasons" -Method Get -Headers @{ 'x-api-key' = $apiKey }
$cancellationReason = $cancellationReasons | Where-Object { $_.cancelationReasonName -eq $cancellationReasonName }
if ($cancellationReason -eq $null) {
  Write-Error "Cancellation reason '$cancellationReasonName' not found!"
  exit
}

foreach ($addonToAdd in $addonProductsToAdd) {
  if (($visiblePurchasableAddons | Where-Object { ($_.rateCodes | Where-Object { $_.name -eq "Addon: $addonToAdd" }).Count -ge 1 }).Count -eq 0) {
    Write-Error "Addon '$addonToAdd' not found! Cannot add it."
    exit
  }
}

foreach ($addonToRemove in $addonsToRemove) {
  if (($contract.moduleContracts | Where-Object { ($_.rateCodes | Where-Object { $_.name -eq "Addon: $addonToRemove" }).Count -ge 1 }).Count -eq 0) {
    Write-Error "Existing addon '$addonToRemove' not found! Cannot remove it."
    exit
  }
}

$toAdd = @()
$toRemove = @()
$noChange = @()
$oldMonthlyTotal = 0.00
$newMonthlyTotal = 0.00
$todayPayment = 0.00

foreach ($addOn in $contract.moduleContracts) {
  $oldMonthlyTotal += $addOn.price

  $addonName = ($addOn.rateCodes | Where-Object { $_.name -like 'Addon:*' } | Select-Object -First 1).name.Replace('Addon: ', '')

  if ($addonsToRemove -contains $addonName) {
    $toRemove += @{ id = $addOn.id; name = $addon.rateName; price = $addOn.price; cancellationDate = $nextBillingDate }
  }
  else {
    $noChange += @{ id = $addOn.id; name = $addon.rateName; price = $addOn.price; }
    $newMonthlyTotal += $addOn.price
  }
}

foreach ($purchasableAddon in $visiblePurchasableAddons) {
  $addonName = ($purchasableAddon.rateCodes | Where-Object { $_.name -like 'Addon:*' } | Select-Object -First 1).name.Replace('Addon: ', '')

  if (($addonProductsToAdd -notcontains $addonName)) {
    continue
  }

  $paymentFrequencies = $purchasableAddon.paymentFrequencies | Where-Object { $_.type -ne 'FREE' }

  if ($paymentFrequencies.Count -eq 0) {
    Write-Error "No payment frequencies found for addon $($purchasableAddon.name)!"
    exit
  }
  
  if ($paymentFrequencies.Count -gt 1) {
    Write-Error "Multiple payment frequencies found for addon $($purchasableAddon.name)!"
    exit
  }

  $paymentFrequency = $paymentFrequencies[0]

  $newAddon = @{ 
    id                 = $purchasableAddon.id
    name               = $purchasableAddon.name
    price              = $paymentFrequency.price.amount
    paymentFrequencyId = $paymentFrequency.id
    proRata            = 999.99
    startDate          = $today
    hasOnlineTrial     = $null -ne $purchasableAddon.trialPeriodConfig
  }

  $toAdd += $newAddon
  $newMonthlyTotal += $newAddon.price
  $todayPayment += $newAddon.proRata
}

# Validate
#/v1/memberships/{contractId}/self-service/additional-modules/validate
foreach ($addon in $toAdd) {
  $body = [ordered]@{
    additionalModuleId = $addon.id
    paymentFrequencyId = $addon.paymentFrequencyId
    bookTrialPeriod    = $addon.hasOnlineTrial
  }

  $validateResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$($contract.id)/self-service/additional-modules/validate" -Method Post -Body (ConvertTo-Json $body) -ContentType 'application/json' -Headers @{ 'x-api-key' = $apiKey } -StatusCodeVariable "statusCode"
  #Write-Host "Validated addon $($addon.name): [$statusCode] $($validateResponse.validationStatus)"
  if ($validateResponse.validationStatus -ne 'ADDITIONAL_MODULE_PURCHASABLE') {
    Write-Error "Addon $($addon.name) validation failed: $($validateResponse.validationStatus)"
    exit
  }
}

# Print summary

Write-Host ""
Write-Host "-------------------------------------------"
Write-Host "Changes planned"
foreach ($addon in $addonProductsToAdd) {
  Write-Host "+ $addon" -ForegroundColor Green
}
foreach ($addon in $addonsToRemove) {
  Write-Host "- $addon" -ForegroundColor Red
}
Write-Host "-------------------------------------------"
Write-Host "Customer           : $($customer.firstName) $($customer.lastName) [$($customer.id)]"
Write-Host "Current Membership : $($contract.rateName) [$($contract.id)]"
Write-Host "-------------------------------------------"

foreach ($addon in $noChange) {
  Write-Host "  $($addon.name) $($addon.price.ToString("c")) [$($addon.id)]" -ForegroundColor Gray
}
foreach ($addon in $toRemove) {
  Write-Host "- $($addon.name) $($addon.price.ToString("c")) [$($addon.id)]" -ForegroundColor Red
}
foreach ($addon in $toAdd) {
  Write-Host "+ $($addon.name) $($addon.price.ToString("c")) [$($addon.id)] | Prorata $($addon.proRata.ToString("c"))" -ForegroundColor Green
}

Write-Host "-------------------------------------------"

$monthlyTotalDiff = $newMonthlyTotal - $oldMonthlyTotal

Write-Host "Monthly Total:"
Write-Host "  Old :  $($oldMonthlyTotal.ToString("c"))"
Write-Host "  New :  $($newMonthlyTotal.ToString("c"))"
Write-Host "  Diff: " -NoNewLine
Write-Host $($monthlyTotalDiff.ToString("+£0.00;-£0.00; £0.00")) -ForegroundColor ( $monthlyTotalDiff -ge 0 ? 'Green' : 'Red' )

Write-Host "-------------------------------------------"

Write-Host "Today's Payment: $($todayPayment.ToString("c"))"

Write-Host "-------------------------------------------"

Write-Host "API Calls:"
foreach ($addon in $toAdd) {
  $body = [ordered]@{
    additionalModuleId = $addon.id
    paymentFrequencyId = $addon.paymentFrequencyId
    bookTrialPeriod    = $addon.hasOnlineTrial
  }

  Write-Host ""
  Write-Host "# Purchase addon: $($addon.name)"
  Write-Host "POST /v1/memberships/$($contract.id)/self-service/additional-modules/purchase"
  Write-Host (ConvertTo-Json $body)
  Write-Host ""
  Write-Host "-------------------------------------------"
}

foreach ($addon in $toRemove) {
  $body = [ordered]@{
    cancelationDate     = $addon.cancellationDate.ToString("yyyy-MM-dd")
    cancelationReasonId = $cancellationReason.cancelationReasonId
  }

  Write-Host ""
  Write-Host "# Cancel addon: $($addon.name)"
  Write-Host "POST /v1/memberships/$($contract.id)/self-service/additional-module-contracts/$($addon.id)/ordinary-cancelation"
  Write-Host (ConvertTo-Json $body)
  Write-Host ""
  Write-Host "-------------------------------------------"
}

$body = [ordered]@{
  amount              = @{
    amount   = [Math]::Round($todayPayment, 2)
    currency = 'GBP'
  }
  paymentRequestToken = 'TOKEN_FROM_PAYMENT_SESSION'
}
Write-Host ""
Write-Host "# Book upfront payment"
Write-Host "POST /v1/customers/$($memberId)/account/payment"
Write-Host (ConvertTo-Json $body)
Write-Host ""

Write-Host "-------------------------------------------"

Write-Host 'Done!'
