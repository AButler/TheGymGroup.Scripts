param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("dev", "sit", "pat")]
  [string]$Environment,
  [string]$RoleToCheck = "admin",
  [switch]$Apply
)

$ErrorActionPreference = "Stop"

if (!$Apply) {
  Write-Host ""
  Write-Host "** Checking only - run with -Apply to perform updates **" -ForegroundColor Yellow
  Write-Host ""
}

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

# State data
$orgUnitIds = @()

Write-Host "Exporting organization units..."
$orgUnitsResponse = Invoke-RestMethod -Uri "$BaseUrl/rest-api/organizationunit/studiopicker" -Method Get -WebSession $session
foreach ($orgUnit in $orgUnitsResponse) {
  Write-Host "  * [$($orgUnit.databaseId)] $($orgUnit.name)"
  $orgUnitIds += $orgUnit.databaseId
}
$allOrgUnits = [string]::Join(",", $orgUnitIds)

Write-Host "Getting users..."
$usersResponse = Invoke-RestMethod -Uri "$BaseUrl/rest-api/employee/wrapped/paged?facilityIds=$([uri]::EscapeDataString($allOrgUnits))&maxResults=100&offset=0&search=" -Method Get -WebSession $session
foreach ($user in $usersResponse.data) {
  if ($null -eq $user.useraccount) {
    continue
  }

  if ($user.useraccount.listRoleDetails.length -eq 0) {
    continue
  }

  Write-Host "  * [$($user.databaseId)] $($user.firstname) $($user.lastname) [$($user.useraccount.username)]... " -NoNewLine

  $hasAnyAdminRole = $false
  $adminOfOrg = @()
  $missingAdmin = @()
  $roleId = 0

  foreach ($role in $user.useraccount.listRoleDetails) {
    if ($role.roleName -ne $RoleToCheck) {
      continue
    }

    $roleId = $role.roleId

    if (!$hasAnyAdminRole) {
      $hasAnyAdminRole = $true
    }

    $adminOfOrg += $role.organizationUnitId
  }

  if (!$hasAnyAdminRole) {
    Write-Host "not $RoleToCheck" -ForegroundColor Yellow
    continue
  }

  $hasAllAdminRoles = $true
  foreach ($orgUnitId in $orgUnitIds) {
    if ($adminOfOrg -notcontains $orgUnitId) {
      $hasAllAdminRoles = $false
      $missingAdmin += $orgUnitId
    }
  }

  if ($hasAllAdminRoles) {
    Write-Host "OK" -ForegroundColor Green
  }
  else {
    if ($Apply) {
      Write-Host "updating... " -ForegroundColor Yellow -NoNewLine
    }
    else {
      $missingAdminIds = [string]::Join(", ", $missingAdmin)
      Write-Host "needs updating" -ForegroundColor Yellow
    }
  }

  if ($hasAllAdminRoles) {
    continue
  }

  if (!$Apply) {
    continue
  }

  $updateBody = ConvertTo-Json @{
    userRoleId     = $roleId
    previousRoleId = $roleId
    facilities     = $orgUnitsResponse
  } -Depth 10

  try {
    $updateUserResponse = Invoke-RestMethod -Uri "$BaseUrl/rest-api/useraccount/$($user.userAccount.databaseId)/roletofacilities" -Method PUT -ContentType "application/json" -Body $updateBody -WebSession $session

    Write-Host "done" -ForegroundColor Green
  }
  catch {
    Write-Host "failed: $($_.Exception.Message)" -ForegroundColor Red
  }
}

Write-Host "Done!"