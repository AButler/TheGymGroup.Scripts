using namespace System.Management.Automation.Host

$ErrorActionPreference = 'Stop'

$memberId = $null

$tenant = 'dev'
$baseUrl = "https://tgg-$tenant.open-api.sandbox.perfectgym.com"

$gymIds = (ConvertFrom-Json (Get-Content (Join-Path $PSScriptRoot 'api-keys.json') -Raw) -AsHashtable)[$tenant]

$apiKey = $gymIds['CrossStudio'].apiKey

$choices = [ChoiceDescription[]] @(
  [ChoiceDescription]::new("&Yes (Create Member)", "Create a member"),
  [ChoiceDescription]::new("&No (Use Existing Member)", "Use an existing member")
)

$choice = $host.UI.PromptForChoice('Member', 'Do you want to create a member?', $choices, 1)

if ($choice -eq 1) {
  $memberId = Read-Host 'Enter existing Member ID'
}
else {
  Write-Host 'Creating member...'

  $randomNumber = Get-Random -Maximum 1000000

  $paymentRequestBody = ConvertTo-Json @{
    amount                  = 0
    scope                   = 'MEMBER_ACCOUNT'
    permittedPaymentChoices = @("BACS", "CREDIT_CARD")
    referenceText           = 'Recurring Charge'
  }

  $sessionToken = Invoke-RestMethod -Uri "$baseUrl/v1/payments/user-session" -Method Post -Headers @{ 'X-Api-Key' = $apiKey } -Body $paymentRequestBody -ContentType 'application/json'
  Write-Host "  - Session Token: $($sessionToken.token)" -ForegroundColor Green
  Write-Host "    http://localhost:3000/payment-page.html?paymentSessionToken=$($sessionToken.token)" -ForegroundColor DarkGray
  $paymentRequestToken = Read-Host -Prompt "Enter payment request token"

  $createMemberRequestBody = ConvertTo-Json @{
    firstName           = 'Test'
    lastName            = "User$randomNumber"
    email               = "andrew.butler+$randomNumber@thegymgroup.com"
    phone               = '01234567890'
    dateOfBirth         = '2000-01-01'
    street              = '1 Test Street'
    city                = 'Test City'
    zipCode             = 'TE5 7ST'
    countryCode         = 'GB'
    language            = @{ languageCode = 'en'; countryCode = 'GB' }
    paymentRequestToken = $paymentRequestToken
  }

  $createMemberResponse = Invoke-RestMethod -Uri "$baseUrl/v1/customers/create" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $createMemberRequestBody -ContentType 'application/json'
  $memberId = $createMemberResponse.customerId
}

Write-Host "Member ID: $memberId" -ForegroundColor Green
$member = Invoke-RestMethod -Uri "$baseUrl/v1/cross-studio/customers/$memberId" -Method Get -Headers @{ 'x-api-key' = $apiKey }
Write-Host "Member Name: $($member.firstName) $($member.lastName)" -ForegroundColor Green
$apiKey = $gymIds[$member.studioId.ToString()].apiKey

$offers = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/membership-offers" -Method Get -Headers @{ 'x-api-key' = $apiKey }

$i = 1
Write-Host "Select a membership offer:"
foreach ($offer in $offers) {
  $rateCodes = ($offer.rateCodes | Select-Object -ExpandProperty name) -join ', '
  Write-Host "$i. $($offer.name) ($rateCodes)"
  $i++
}
$choice = Read-Host "Enter choice (1-$($offers.Count))"

$selectedOffer = $offers[$choice - 1]
Write-Host "Selected offer: $($selectedOffer.name)" -ForegroundColor Green

if ($selectedOffer.terms.Count -eq 1) {
  $selectedTerm = $selectedOffer.terms[0]
}
else {
  $choices = [ChoiceDescription[]] @()
  $i = 1
  foreach ($term in $selectedOffer.terms) {
    $choices += [ChoiceDescription]::new("&$i. $($term.term.value) $($term.term.unit) - $($term.paymentFrequency.price.amount)", "$($term.term.value) $($term.term.unit) - $($term.paymentFrequency.price.amount)")
    $i++
  }
  $choice = $host.UI.PromptForChoice('Membership Offer Term', 'Select a term:', $choices, -1)

  $selectedTerm = $selectedOffer.terms[$choice]
}
Write-Host "Selected term: $($selectedTerm.term.value) $($selectedTerm.term.unit) - $($selectedTerm.paymentFrequency.price.amount)" -ForegroundColor Green
Write-Host ""

$voucherCode = Read-Host -Prompt "Voucher code"
if ([string]::IsNullOrWhiteSpace($voucherCode)) {
  $voucherCode = $null
}

$previewBody = ConvertTo-Json @{
  contractOfferTermId = $selectedTerm.id
  startDate           = (Get-Date).ToString('yyyy-MM-dd')
  voucherCode         = $voucherCode
}

$previewResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/customers/$memberId/add-membership/preview" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $previewBody -ContentType 'application/json'
$upfrontAmount = $previewResponse.paymentPreview.dueOnSigningAmount.amount

Write-Host ""
Write-Host "Upfront Amount Due: $upfrontAmount" -ForegroundColor Green
Write-Host ""

$accountBalance = Invoke-RestMethod -Uri "$baseUrl/v1/customers/$memberId/account/balances" -Method Get -Headers @{ 'x-api-key' = $apiKey }
if ($accountBalance.accountBalance.amount -gt 0) {
  Write-Host "Member has an account balance of $($accountBalance.accountBalance.amount) $($accountBalance.accountBalance.currency). This will be applied to the upfront amount." -ForegroundColor Yellow
  $upfrontAmount = [Math]::Max(0, $upfrontAmount - $accountBalance.accountBalance.amount)
  Write-Host ""
  Write-Host "New Upfront Amount Due: $upfrontAmount" -ForegroundColor Green
  Write-Host ""
}
else {
  Write-Host "Member has no account balance." -ForegroundColor Green
}

if ($upfrontAmount -gt 0) {
  $paymentRequestBody = ConvertTo-Json @{
    amount                  = $upfrontAmount
    scope                   = 'ECOM'
    permittedPaymentChoices = @("PAYPAL", "CREDIT_CARD")
    referenceText           = 'Upfront Fee'
    customerId              = $memberId
  }

  $sessionToken = Invoke-RestMethod -Uri "$baseUrl/v1/payments/user-session" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $paymentRequestBody -ContentType 'application/json'
  Write-Host "  - Session Token: $($sessionToken.token)" -ForegroundColor Green
  Write-Host "    http://localhost:3000/payment-page.html?paymentSessionToken=$($sessionToken.token)" -ForegroundColor DarkGray
  $paymentRequestToken = Read-Host -Prompt "Enter payment request token"
}
else {
  $paymentRequestToken = $null
}

$addMembershipBody = ConvertTo-Json @{
  contractOfferTermId        = $selectedTerm.id
  startDate                  = (Get-Date).ToString('yyyy-MM-dd')
  voucherCode                = $voucherCode
  initialPaymentRequestToken = $paymentRequestToken
}

Write-Host "Adding membership..." -ForegroundColor Green

$previewResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/customers/$memberId/add-membership" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $addMembershipBody -ContentType 'application/json'

$webBaseUrl = $baseUrl -replace '.open-api.', '.web.'
Write-Host "$webBaseUrl/#/customermanagement/$memberId/overview" -ForegroundColor DarkGray
Write-Host 'Done!'
