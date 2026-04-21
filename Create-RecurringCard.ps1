param(
  [switch]$ManualToken
)

$ErrorActionPreference = 'Stop'


$baseUrl = 'https://tgg-dev.open-api.sandbox.perfectgym.com'
$webBaseUrl = 'https://tgg-dev.web.sandbox.perfectgym.com'
$paymentBaseUrl = 'https://upc.sandbox.payment.sportalliance.com'

$apiKey = '7ad2820f-80a5-4526-903c-cea9a771485e' # London East Croydon
$termId = 1210404050 # Ultimate Monthly
$upfrontAmount = 25.0 + 15.0

function Wait-ForPaymentStatus ([string]$PaymentSessionToken, [string]$PaymentRequestToken, [string[]]$Statuses) {
  while ($true) {
    $paymentStatusResponse = Invoke-RestMethod -Uri "$paymentBaseUrl/api/v1/payments/$PaymentRequestToken" -Method Get -Headers @{ 'X-User-Payment-Session-Token' = $PaymentSessionToken }
    if ($Statuses -contains $paymentStatusResponse.status) {
      #Write-Host (ConvertTo-Json $paymentStatusResponse -Depth 10) -ForegroundColor DarkGray
      Write-Host "  - Current status: $($paymentStatusResponse.status)" -ForegroundColor Green
      return
    }
    Write-Host "  - Current status: $($paymentStatusResponse.status)" -ForegroundColor Yellow
    Start-Sleep -Seconds 1
  }
}

$paymentRequestBody = ConvertTo-Json @{
  amount                  = $upfrontAmount
  scope                   = 'ECOM'
  permittedPaymentChoices = @("CREDIT_CARD")
  referenceText           = 'Upfront Fee'
}

$sessionToken = Invoke-RestMethod -Uri "$baseUrl/v1/payments/user-session" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $paymentRequestBody -ContentType 'application/json'
Write-Host "  - Session Token: $($sessionToken.token)" -ForegroundColor Green
Write-Host "    http://localhost:3000/payment-page.html?paymentSessionToken=$($sessionToken.token)" -ForegroundColor DarkGray
$upfrontPaymentRequestToken = Read-Host -Prompt "Enter upfront payment request token"

Write-Host "FinionPay Customer ID: $($sessionToken.finionPayCustomerId)" -ForegroundColor Green

Write-Host "Creating recurring payment request token..."
$paymentRequestBody = ConvertTo-Json @{
  amount                  = 0
  scope                   = 'MEMBER_ACCOUNT'
  permittedPaymentChoices = @("CREDIT_CARD")
  referenceText           = 'Recurring Fee'
  finionPayCustomerId     = $sessionToken.finionPayCustomerId
}

# Create new session token for recurring payment
$sessionToken = Invoke-RestMethod -Uri "$baseUrl/v1/payments/user-session" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $paymentRequestBody -ContentType 'application/json'

if ($ManualToken) {
  Write-Host "  - Session Token: $($sessionToken.token)" -ForegroundColor Green
  Write-Host "    http://localhost:3000/payment-page.html?paymentSessionToken=$($sessionToken.token)" -ForegroundColor DarkGray
  $recurringPaymentRequestToken = Read-Host -Prompt "Enter recurring payment request token"
}
else {
  $paymentInstrumentToken = Read-Host -Prompt "Enter payment instrument token"

  # Get payment request token for new session
  $paymentToken = Invoke-RestMethod -Uri "$paymentBaseUrl/api/v1/payment-requests" -Method Post -Headers @{ 'X-User-Payment-Session-Token' = $sessionToken.token }

  # Select existing payment instrument
  $paymentTokenResponse = Invoke-RestMethod -Uri "$paymentBaseUrl/api/v1/payments/$($paymentToken.token)" -Method Post -Headers @{ 'X-User-Payment-Session-Token' = $sessionToken.token; 'Content-Type' = 'application/json' } -Body (ConvertTo-Json @{      paymentInstrumentToken = $paymentInstrumentToken; paymentMethod = 'CREDIT_CARD' })

  # Wait for payment request token to be ready for authentication
  Wait-ForPaymentStatus -PaymentSessionToken $sessionToken.token -PaymentRequestToken $paymentToken.token -Statuses @('CREATED', 'AUTHENTICATED')

  # Authenticate payment request token
  $paymentTokenResponse = Invoke-RestMethod -Uri "$paymentBaseUrl/api/v1/payments/$($paymentToken.token)/authenticate" -Method Put -Headers @{ 'X-User-Payment-Session-Token' = $sessionToken.token; 'Content-Type' = 'application/json' } -Body (ConvertTo-Json @{  })
  Wait-ForPaymentStatus -PaymentSessionToken $sessionToken.token -PaymentRequestToken $paymentToken.token -Statuses @('PREAUTHED')

  # New recurring payment request token is ready to use
  $recurringPaymentRequestToken = $paymentToken.token
}

$randomNumber = Get-Random -Maximum 1000000

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
  paymentRequestToken = $recurringPaymentRequestToken
}

Write-Host ($createMemberRequestBody) -ForegroundColor DarkGray

$createMemberResponse = Invoke-RestMethod -Uri "$baseUrl/v1/customers/create" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $createMemberRequestBody -ContentType 'application/json'
$memberId = $createMemberResponse.customerId

$addMembershipBody = ConvertTo-Json @{
  contractOfferTermId        = $termId
  startDate                  = (Get-Date).ToString('yyyy-MM-dd')
  initialPaymentRequestToken = $upfrontPaymentRequestToken
}

$addMembershipResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/customers/$memberId/add-membership" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body $addMembershipBody -ContentType 'application/json'

Write-Host "Member ID: $memberId" -ForegroundColor Green

Write-Host "$webBaseUrl/#/customermanagement/$memberId/overview" -ForegroundColor DarkGray