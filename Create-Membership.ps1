using namespace System.Management.Automation.Host

$ErrorActionPreference = 'Stop'

$memberId = $null # 1210697492

$baseUrl = 'https://tgg-dev.open-api.sandbox.perfectgym.com'

$gymIds = @{
  '1210093500' = @{ name = 'London East Croydon'; apiKey = '7ad2820f-80a5-4526-903c-cea9a771485e' } 
  '1210133180' = @{ name = 'Holborn Circus'; apiKey = 'f4800efd-5f8a-4e84-94dc-2cf629682726' } 
  '1210131000' = @{ name = 'Hounslow'; apiKey = '3322a8ee-7198-46ab-9c59-15a8e7f1c632' } 
  '1210130080' = @{ name = 'Ilford Romford Road'; apiKey = '355a447b-f1be-4e38-a924-ab148c54266d' } 
  '1210130920' = @{ name = 'Ilford Pioneer'; apiKey = 'b2660123-a7d7-4dfe-afcd-4760c632845d' } 
}

$apiKey = $gymIds['1210093500'].apiKey

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

  $sessionToken = Invoke-RestMethod -Uri "$baseUrl/v1/payments/user-session" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $paymentRequestBody -ContentType 'application/json'
  Write-Host "  - Session Token: $($sessionToken.token)" -ForegroundColor Green
  Write-Host "    http://localhost:3000/payment-page.html?paymentSessionToken=$($sessionToken.token)" -ForegroundColor DarkGray
  $paymentRequestToken = Read-Host -Prompt "Enter payment request token"

  $createMemberRequestBody = ConvertTo-Json @{
    firstName           = 'Test'
    lastName            = "User$randomNumber"
    email               = "test.user+$randomNumber@example.com"
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

$choices = [ChoiceDescription[]] @()
$i = 1
foreach ($offer in $offers) {
  $rateCodes = ($offer.rateCodes | Select-Object -ExpandProperty name) -join ', '
  $choices += [ChoiceDescription]::new("&$i. $($offer.name) ($rateCodes)", "$($offer.name) ($rateCodes) - $($offer.description)")
  $i++
}
$choice = $host.UI.PromptForChoice('Membership Offers', 'Select a membership offer:', $choices, -1)

$selectedOffer = $offers[$choice]
Write-Host "Selected offer: $($selectedOffer.name)" -ForegroundColor Green

$choices = [ChoiceDescription[]] @()
$i = 1
foreach ($term in $selectedOffer.terms) {
  $choices += [ChoiceDescription]::new("&$i. $($term.term.value) $($term.term.unit) - $($term.paymentFrequency.price.amount)", "$($term.term.value) $($term.term.unit) - $($term.paymentFrequency.price.amount)")
  $i++
}
$choice = $host.UI.PromptForChoice('Membership Offer Term', 'Select a term:', $choices, -1)

$selectedTerm = $selectedOffer.terms[$choice]
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

$paymentRequestBody = ConvertTo-Json @{
  amount                  = $upfrontAmount
  scope                   = 'ECOM'
  permittedPaymentChoices = @("BACS", "CREDIT_CARD")
  referenceText           = 'Upfront Fee'
  customerId              = $memberId
}

$sessionToken = Invoke-RestMethod -Uri "$baseUrl/v1/payments/user-session" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $paymentRequestBody -ContentType 'application/json'
Write-Host "  - Session Token: $($sessionToken.token)" -ForegroundColor Green
Write-Host "    http://localhost:3000/payment-page.html?paymentSessionToken=$($sessionToken.token)" -ForegroundColor DarkGray
$paymentRequestToken = Read-Host -Prompt "Enter payment request token"

$addMembershipBody = ConvertTo-Json @{
  contractOfferTermId        = $selectedTerm.id
  startDate                  = (Get-Date).ToString('yyyy-MM-dd')
  voucherCode                = $voucherCode
  initialPaymentRequestToken = $paymentRequestToken
}

$previewResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/customers/$memberId/add-membership" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $addMembershipBody -ContentType 'application/json'

Write-Host 'Done!'
