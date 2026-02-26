param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("dev", "sit", "pat")]
  [string]$Environment,
  [switch]$FreezeMember
)
$ErrorActionPreference = 'Stop'

switch ($Environment) {
  "dev" {
    $BaseUrl = "https://tgg-dev.web.sandbox.perfectgym.com"
    $Username = $env:PG_DEV_USER ?? $env:PG_USERNAME
    $Password = $env:PG_DEV_PASSWORD ?? $env:PG_PASSWORD
    Write-Host "Using DEV environment - $BaseUrl"
  }
  "sit" {
    $BaseUrl = "https://tgg-sit.web.sandbox.perfectgym.com"
    $Username = $env:PG_SIT_USER ?? $env:PG_USERNAME
    $Password = $env:PG_SIT_PASSWORD ?? $env:PG_PASSWORD
    Write-Host "Using SIT environment - $BaseUrl"
  }
  "pat" {
    $BaseUrl = "https://tgg-pat.web.sandbox.perfectgym.com"
    $Username = $env:PG_PAT_USER ?? $env:PG_USERNAME
    $Password = $env:PG_PAT_PASSWORD ?? $env:PG_PASSWORD
    Write-Host "Using PAT environment - $BaseUrl"
  }
}

if ($Username -eq $null -or $Password -eq $null) {
  Write-Error "Environment variables for the selected environment are not set."
  exit 1
}

Write-Host "Logging in..."

$loginUrl = "$BaseUrl/login"
$loginBody = @{
  client   = "webclient"
  username = $Username
  password = $Password
}
$response = Invoke-WebRequest -Uri $loginUrl -Method Post -Body $loginBody -ContentType "application/x-www-form-urlencoded" -SessionVariable session
if ($response.StatusCode -ne 200) {
  Write-Error "Login failed with status code $($response.StatusCode)."
  exit 1
}

Write-Host "Querying data..."

$orgUnits = Invoke-RestMethod -Uri "$BaseUrl/rest-api/organizationunit/studiopicker" -Method Get -WebSession $session
$studioId = ($orgUnits | Select-Object -First 1).databaseId
$employee = Invoke-RestMethod -Uri "$BaseUrl/rest-api/me/info" -Method Get -WebSession $session

$rates = Invoke-RestMethod -Uri "$BaseUrl/rest-api/contract/rateNames?organizationUnitId=$studioId" -Method Get -WebSession $session
$standardRate = $rates | Where-Object { $_.rateName -eq "Standard Monthly" }

if ($null -eq $standardRate) {
  Write-Error "Could not find Standard Monthly rate for studio $studioId."
  exit 1
}

$rateDetails = Invoke-RestMethod -Uri "$BaseUrl/rest-api/rate/$($standardRate.databaseId)/ratedetail?organizationUnitId=$studioId" -Method Get -WebSession $session
$standardRateDetail = $rateDetails | Select-Object -First 1

if ($null -eq $standardRateDetail) {
  Write-Error "Could not find Standard Monthly rate detail for studio $studioId."
  exit 1
}

$paymentFrequencies = Invoke-RestMethod -Uri "$BaseUrl/rest-api/ratedetail/$($standardRateDetail.databaseId)/paymentfrequency?organizationUnitId=$studioId" -Method Get -WebSession $session
$standardRatePaymentFrequency = $paymentFrequencies | Select-Object -First 1

if ($null -eq $standardRatePaymentFrequency) {
  Write-Error "Could not find Standard Monthly rate payment frequency for studio $studioId."
  exit 1
}

$addons = Invoke-RestMethod -Uri "$BaseUrl/rest-api/modulerate/bookable?organizationUnitId=$studioId" -Method Get -WebSession $session
$guestPassAddon = $addons | Where-Object { $_.name -eq "Guest Pass" }
$yangaAddOn = $addons | Where-Object { $_.name -eq "Yanga Sports Water" }

if ($null -eq $guestPassAddon) {
  Write-Error "Could not find Guest Pass addon for studio $studioId."
  exit 1
}

$guestPassAddonPaymentFrequency = $guestPassAddon.rateDetailPaymentFrequencyDtos | Where-Object { $_.type -ne "FREE" } | Select-Object -First 1

if ($null -eq $guestPassAddonPaymentFrequency) {
  Write-Error "Could not find payment frequency for Guest Pass addon for studio $studioId."
  exit 1
}

if ($null -eq $yangaAddOn) {
  Write-Error "Could not find Yanga Sports Water addon for studio $studioId."
  exit 1
}

$yangaAddOnPaymentFrequency = $yangaAddOn.rateDetailPaymentFrequencyDtos | Where-Object { $_.type -ne "FREE" } | Select-Object -First 1

if ($null -eq $yangaAddOnPaymentFrequency) {
  Write-Error "Could not find payment frequency for Yanga Sports Water addon for studio $studioId."
  exit 1
}

Write-Host "Creating member..."

$lastName = "Member$(Get-Date -Format 'yyyyMMddHHmmss')"
$today = Get-Date
$startDate = $today.AddMonths(-1)
$employeeId = $employee.employeeId
$rateId = $standardRate.databaseId
$rateDetailId = $standardRateDetail.databaseId
$rateDetailPaymentFrequencyId = $standardRatePaymentFrequency.databaseId

$createMemberPayload = @{
  identityCardProvided = $true
  masterData           = @{
    customerTitle              = 0
    note                       = ""
    telPrivate                 = ""
    telBusiness                = ""
    telPrivateMobile           = ""
    telBusinessMobile          = ""
    firstname                  = "Past"
    identityCardProvided       = $false
    gender                     = 0
    dateOfBirth                = "2000-02-01"
    lastname                   = $lastName
    email                      = ""
    info                       = ""
    birthInformation           = @{
      dateOfBirth  = "2000-02-01"
      placeOfBirth = ""
      databaseId   = $null
      optlock      = 0
    }
    medicalCertificate         = @{
      certificateStatus = ""
      status            = $null
      databaseId        = $null
      optlock           = 0
    }
    sportFederationCertificate = @{
      sportFederation = $null
      databaseId      = $null
      optlock         = 0
      status          = $null
    }
    secondFirstname            = ""
    secondLastname             = ""
    fax                        = ""
    documentIdentification     = @{
      documentNumber = ""
    }
  }
  voucher              = @{
    optlock = 0
  }
  address              = @{
    optlock     = 0
    addition    = ""
    city        = "1"
    street      = "1"
    houseNumber = ""
    zip         = "1"
    country     = "GB"
    details     = @{
      additionalInformation = ""
      block                 = ""
      door                  = ""
      floor                 = ""
      portal                = ""
      province              = ""
      stairway              = ""
      streetType            = ""
      secondStreet          = ""
      provinceCode          = ""
      buildingName          = ""
      cityPart              = ""
      district              = ""
    }
  }
  listCustomerTagFks   = @()
  fkOrganizationUnit   = $studioId
  cardNumber           = ""
  contract             = @{
    startDate                                               = $startDate.ToString("yyyy-MM-dd")
    paymentDay                                              = $startDate.Day
    contractPaymentFrequency                                = $standardRatePaymentFrequency
    term                                                    = 1
    termUnit                                                = 2
    termExtension                                           = 14
    termExtensionUnit                                       = 0
    cancelationPeriod                                       = 14
    cancelationPeriodUnit                                   = 0
    starterPackagePrice                                     = 12
    endDate                                                 = $startDate.AddMonths(1).AddDays(-1).ToString("yyyy-MM-dd")
    fkOrganizationUnit                                      = $studioId
    fkEmployee                                              = $employeeId
    fkSubsequentRateDetailPaymentFrequency                  = $rateDetailPaymentFrequencyId
    fkSubsequentRateDetail                                  = $rateDetailId
    fkSubsequentRate                                        = $rateId
    fkRateDetailPaymentFrequency                            = $rateDetailPaymentFrequencyId
    fkRate                                                  = $rateId
    fkRateDetail                                            = $rateDetailId
    firstBookingDate                                        = $today.ToString("yyyy-MM-dd")
    firstBookingType                                        = "CONTRACT_START_DATE"
    startDateCurrentTerm                                    = $startDate.ToString("yyyy-MM-dd")
    preuseType                                              = 0
    nextCancelationDate                                     = $startDate.AddMonths(1).AddDays(-1).AddDays(-14).ToString("yyyy-MM-dd")
    extensionCancelationPeriod                              = @{
      term     = 14
      termUnit = 0
    }
    cancelationStrategy                                     = "RECEIPT_DATE"
    extensionType                                           = "TERM_EXTENSION"
    isReversed                                              = $false
    imported                                                = $false
    moduleContracts                                         = @()
    flatFeeContracts                                        = @()
    bonusPeriods                                            = @()
    contractIdlePeriods                                     = @()
    subsequentContractHasSubsequentContract                 = $false
    allowReferenceDateRecurringPaymentFrequencyAtEndOfMonth = $false
    extensionPeriodCounter                                  = 0
    rateDetailExtensionType                                 = "TERM_EXTENSION"
    conclusionDate                                          = $today.ToString("yyyy-MM-dd")
  }
  image                = @{
    imageUrl      = ""
    type          = "CUSTOMER"
    isPlaceholder = $true
  }
  paymentMethod        = 0
  payer                = @{
    payerVariant              = "SELF"
    bankAccount               = $null
    payingCustomer            = $null
    payingPerson              = $null
    customerId                = 0
    databaseId                = $null
    optlock                   = 0
    useAsDefaultPaymentMethod = $false
  }
}

Write-Host "Creating member with last name $lastName..."
$createMemberResponse = Invoke-RestMethod -Uri "$BaseUrl/rest-api/customer/member/create?userEventDecisionType=DIRECT_TRANSMISSION&sendEmailVerification=false" -Method Post -WebSession $session -Body (ConvertTo-Json $createMemberPayload -Depth 10) -ContentType 'application/json'
$memberId = $createMemberResponse.databaseId
$contractId = $createMemberResponse.contractId

Write-Host "Member ID: $memberId" -ForegroundColor Green
Write-Host "Contract ID: $contractId" -ForegroundColor Green

Write-Host "Adding Guest Pass addon..."

$createAddonPayload = @{
  type                                      = "RECURRING"
  value                                     = $guestPassAddonPaymentFrequency.value
  unit                                      = $guestPassAddonPaymentFrequency.unit
  price                                     = $guestPassAddonPaymentFrequency.price
  money                                     = $guestPassAddonPaymentFrequency.money
  paidTimePeriodCalculationType             = "REFERENCE_DATE"
  recurring                                 = $false
  firstChargeMode                           = "DEFAULT"
  monthDays                                 = @()
  ageBasedAdjustmentDtos                    = @()
  fkRateDetail                              = -1
  firstEncashment                           = "IMMEDIATELY"
  paymentFrequencyDynamicAdjustmentRuleDtos = @()
  priceAdjustment                           = @{
    adjustmentEntries = @()
  }
  fkOrganizationUnit                        = $studioId
  paymentDay                                = $startDate.Day
  firstBookingType                          = "CONTRACT_START_DATE"
  alignSubContractDueDatesToMainContract    = $true
  fkContract                                = $contractId
  fkRateDetailPaymentFrequency              = $guestPassAddonPaymentFrequency.databaseId
  startDate                                 = $startDate.ToString("yyyy-MM-dd")
  retroactive                               = $false
  employeeId                                = $employeeId
  paymentFrequencyUnit                      = $guestPassAddonPaymentFrequency.unit
  salesSource                               = "WEBCLIENT"
  fkModuleRate                              = $guestPassAddon.databaseId
  startDateOfUse                            = $startDate.AddMonths(1).ToString("yyyy-MM-dd")
  discountAdjustmentRules                   = @()
  orgUnit                                   = $studioId
  editMode                                  = $false
  bonusPeriods                              = @()
}

$guestPassAddonResponse = Invoke-RestMethod -Uri "$BaseUrl/rest-api/modulecontract" -Method Post -WebSession $session -Body (ConvertTo-Json $createAddonPayload -Depth 10) -ContentType 'application/json'
Write-Host "Guest Pass Addon ID: $($guestPassAddonResponse.databaseId)" -ForegroundColor Green

Write-Host "Adding Yanga addon..."

$createAddonPayload = @{
  type                                      = "RECURRING"
  value                                     = $yangaAddonPaymentFrequency.value
  unit                                      = $yangaAddonPaymentFrequency.unit
  price                                     = $yangaAddonPaymentFrequency.price
  money                                     = $yangaAddonPaymentFrequency.money
  paidTimePeriodCalculationType             = "REFERENCE_DATE"
  recurring                                 = $false
  firstChargeMode                           = "DEFAULT"
  monthDays                                 = @()
  ageBasedAdjustmentDtos                    = @()
  fkRateDetail                              = -1
  firstEncashment                           = "IMMEDIATELY"
  paymentFrequencyDynamicAdjustmentRuleDtos = @()
  priceAdjustment                           = @{
    adjustmentEntries = @()
  }
  fkOrganizationUnit                        = $studioId
  paymentDay                                = $startDate.Day
  firstBookingType                          = "CONTRACT_START_DATE"
  alignSubContractDueDatesToMainContract    = $true
  fkContract                                = $contractId
  fkRateDetailPaymentFrequency              = $yangaAddonPaymentFrequency.databaseId
  startDate                                 = $startDate.ToString("yyyy-MM-dd")
  retroactive                               = $false
  employeeId                                = $employeeId
  paymentFrequencyUnit                      = $yangaAddonPaymentFrequency.unit
  salesSource                               = "WEBCLIENT"
  fkModuleRate                              = $yangaAddon.databaseId
  startDateOfUse                            = $startDate.AddMonths(1).ToString("yyyy-MM-dd")
  discountAdjustmentRules                   = @()
  orgUnit                                   = $studioId
  editMode                                  = $false
  bonusPeriods                              = @()
}

$yangaAddonResponse = Invoke-RestMethod -Uri "$BaseUrl/rest-api/modulecontract" -Method Post -WebSession $session -Body (ConvertTo-Json $createAddonPayload -Depth 10) -ContentType 'application/json'
Write-Host "Yanga Addon ID: $($yangaAddonResponse.databaseId)" -ForegroundColor Green

if ($FreezeMember) {
  Write-Host "Freezing member..."

  $idlePeriodConfigurationId = 1210782620
  $idlePeriodReasonId = 1210005510

  $freezePayload = @{
    startDate                           = $startDate.ToString("yyyy-MM-dd")
    entranceLock                        = $true
    idlePeriodAmount                    = 0
    idlePeriodReason                    = @{
      databaseId = $idlePeriodReasonId
    }
    includeAllModuleContracts           = $true
    includeAllFlatFeeContracts          = $true
    type                                = "CHARGE_FREE_WITHOUT_EXTENSION"
    applyOnExtraordinaryCancelationDate = $false
    unlimited                           = $true
    idlePeriodConfigurationId           = $idlePeriodConfigurationId
    mainContractId                      = $contractId
  }

  $idlePeriodResponse = Invoke-RestMethod -Uri "$BaseUrl/rest-api/contractidleperiod?userEventDecisionType=NONE&basedOnConfiguration=true" -Method Post -WebSession $session -Body (ConvertTo-Json $freezePayload -Depth 10) -ContentType 'application/json'

  Write-Host "Idle Period ID: $($idlePeriodResponse.databaseId)" -ForegroundColor Green
  
}

Write-Host "$BaseUrl/#/customermanagement/$memberId/overview" -ForegroundColor DarkGray