using namespace System.Management.Automation.Host

$ErrorActionPreference = 'Stop'

$memberId = 1210365931

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
$currentTier = ($primaryContract.rateCodes | Where-Object { $_.name -like 'Tier: *' } | Select-Object -First 1).name

Write-Host "Primary Contract: [$($primaryContract.id)] $($primaryContract.rateName) [$currentTier] - $($primaryContract.price.ToString("C")) - $($primaryContract.startDate) - $($primaryContract.endDate)"

$switchOptions = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$memberId/membership-switch/configs" -Headers @{ "x-api-key" = $apiKey }

$switchOption = $switchOptions | Where-Object { $_.name -like '* Change Membership' } | Select-Object -First 1

$switchConfig = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$memberId/membership-switch/configs/$($switchOption.id)" -Headers @{ "x-api-key" = $apiKey }

$destinations = @()

foreach ($offer in $switchConfig.destinationMembershipOffers) {
  foreach ($term in $offer.terms) {
    if ($term.term.value -eq $primaryContract.term.periodValue -and $term.term.unit -eq $primaryContract.term.periodUnit) {
      $destinationTier = ($offer.rateCodes | Where-Object { $_.name -like 'Tier: *' } | Select-Object -First 1).name

      $destinations += @{
        offerId    = $offer.id
        termId     = $term.id
        name       = $offer.name
        tier       = $destinationTier
        price      = $term.paymentFrequency.price.amount
        adminFeeId = ($term.optionalModules | Where-Object { $_.name -eq 'Admin Fee' } | Select-Object -First 1).id
      }
    }
  }
}

if ($destinations.count -eq 0) {
  Write-Host "No switch destinations found for member's current contract."
  exit 1
}

$destination = $destinations | Select-Object -First 1
if ($destinations.count -gt 1) {
  $choices = [ChoiceDescription[]] @()

  $i = 1
  foreach ($destination in $destinations) {
    $choices += [ChoiceDescription]::new("&$i. [$($destination.termId)] $($destination.name) - $($destination.price.ToString("C")) [$($destination.tier)]")
    $i++
  }

  $choice = $host.UI.PromptForChoice('Member', 'Select upgrade/downgrade offer?', $choices, 0)

  $destination = $destinations[$choice]
}

Write-Host "Switching to offer [$($destination.termId)] $($destination.name) [$($destination.tier)]..."

$previewBody = @{
  configId                  = $($switchOption.id)
  membershipOfferTermId     = $destination.termId
  sourceContractId          = $primaryContract.id
  startDate                 = (Get-Date).ToString('yyyy-MM-dd')
  selectedOptionalModuleIds = @()
}

if ($primaryContract.price -gt $destination.price) {
  Write-Host "This is a downgrade since the destination price ($($destination.price.ToString("C"))) is lower than the current price ($($primaryContract.price.ToString("C")))."
  $previewBody.selectedOptionalModuleIds += $destination.adminFeeId
}

Write-Host (ConvertTo-Json $previewBody -Depth 10)

$previewResponse = Invoke-RestMethod -Uri "$baseUrl/v1/memberships/$memberId/membership-switch/preview" -Method Post -Headers @{ 'x-api-key' = $apiKey } -Body (ConvertTo-Json $previewBody) -ContentType 'application/json'

Write-Host (ConvertTo-Json $previewResponse -Depth 10)

$dueOnSigningAmount = $previewResponse.paymentPreview.dueOnSigningAmount.amount

Write-Host "Payment Schedule:"
foreach ($payment in $previewResponse.paymentPreview.paymentSchedule) {
  Write-Host "  [$($payment.dueDate)] $($payment.amount.amount.ToString("C")) - $($payment.description)"
}

Write-Host "Due today: $($dueOnSigningAmount.ToString("C"))"