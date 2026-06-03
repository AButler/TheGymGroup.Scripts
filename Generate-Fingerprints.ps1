param(
  [Parameter(Mandatory = $true)]
  [string]$InputFile,
  [Parameter(Mandatory = $true)]
  [string]$OutputFile,
  [int]$DelayMilliseconds = 100
)

$ErrorActionPreference = 'Stop'

# Check input file exists
if (!(Test-Path -Path $InputFile)) {
  Write-Error "Input file '$InputFile' does not exist. Please provide a valid input file."
  exit 1
}

# Check for API key in environment variable
$apiKey = $env:STRIPE_FINGERPRINT_APIKEY
if ([string]::IsNullOrEmpty($apiKey)) {
  Write-Error "API key not found in environment variable 'STRIPE_FINGERPRINT_APIKEY'. Please set this environment variable to your Stripe API key."
  exit 1
}

# Set up authentication header for Stripe API
$baseUrl = 'https://api.stripe.com/v1/tokens'
$headers = @{
  'Authorization' = "Bearer $apiKey"
}

# Load CSV data
Write-Host "Loading data..."
$rows = Import-Csv -Path $InputFile

Write-Host "Generating fingerprints..."

# Write CSV header to output file
"SortCode,AccountNumber,Fingerprint,Success,Message" | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Progress -Activity "Generating fingerprints" -Status "0% Complete:" -PercentComplete 0

for ($i = 0; $i -lt $rows.Count; $i++) {
  $row = $rows[$i]
  $sortCode = $row.SortCode
  $accountNumber = $row.AccountNumber

  # Prepare data for Stripe API request
  $data = @{
    'bank_account[currency]'       = 'GBP'
    'bank_account[country]'        = 'GB'
    'bank_account[routing_number]' = $sortCode
    'bank_account[account_number]' = $accountNumber
  }

  try {
    # Make API request to Stripe to generate fingerprint
    $response = Invoke-RestMethod -Uri $baseUrl -Method Post -Headers $headers -Body $data -UseBasicParsing

    # Extract fingerprint from response
    $fingerprint = $response.bank_account.fingerprint

    # Write result to output file
    """$sortCode"",""$accountNumber"",""$fingerprint"",true," | Out-File -FilePath $OutputFile -Append -Encoding UTF8
  }
  catch {
    # Attempt to extract error message from Stripe API response
    try {
      $ex = ConvertFrom-Json $_
      $message = $ex.error.code ?? "Unknown error"
    }
    catch {
      $message = "Unknown error"
    }

    # Write error result to output file
    """$sortCode"",""$accountNumber"",,false,""$message""" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
  }

  $percent = [math]::Round((($i + 1) / $rows.Count) * 100, 2)
  Write-Progress -Activity "Generating fingerprints" -Status "$percent% Complete:" -PercentComplete $percent

  # Delay between requests to avoid hitting rate limits
  Start-Sleep -Milliseconds $DelayMilliseconds
}

Write-Host "Done!"