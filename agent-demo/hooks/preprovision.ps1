<#
.SYNOPSIS
    azd preprovision hook - sanity-check the caller can reach the private
    Foundry landing zone before we let azd do anything.

.DESCRIPTION
    Runs before `azd provision`. Verifies:
      * az / azd CLI are logged in;
      * an active Azure subscription context is set;
      * (best-effort) the private Foundry account FQDN resolves and answers on 443
        from this machine (VPN / ExpressRoute path is up).

    Fails fast with actionable messages so the user does not wait several
    minutes for provision to time out.
#>

param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

Write-Host '==> preprovision: verifying prerequisites'

function Assert-Command {
    param([string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Error "Required CLI '$Name' not found on PATH. $InstallHint"
    }
}

Assert-Command 'az'  'Install with: winget install --id Microsoft.AzureCLI'
Assert-Command 'azd' 'Install with: winget install --id Microsoft.Azd'

# --- Azure CLI login state ---------------------------------------------------
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error "Not signed in to Azure CLI. Run 'az login --tenant <TENANT-ID>' first."
}
Write-Host ("    az subscription : {0} ({1})" -f $account.name, $account.id)
Write-Host ("    az tenant       : {0}" -f $account.tenantId)

# --- azd login state ---------------------------------------------------------
$azdWho = azd auth login --check-status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "azd is not signed in. Run: azd auth login --tenant-id $($account.tenantId)"
}
Write-Host "    azd auth        : ok"

# --- Private-endpoint reachability probe (best effort) -----------------------
$accountName = azd env get-value AZURE_AI_ACCOUNT_NAME 2>$null
if (-not $accountName -or $accountName -eq '') {
    Write-Warning @"
AZURE_AI_ACCOUNT_NAME is not set in the azd environment yet.
Skipping private-endpoint reachability probe. Run scripts/Bootstrap-Env.ps1
after the landing zone is applied to populate the env vars, then rerun this hook.
"@
    exit 0
}

$fqdn = "$accountName.cognitiveservices.azure.com"
Write-Host "    private-endpoint probe -> $fqdn"

try {
    $tnc = Test-NetConnection -ComputerName $fqdn -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
} catch {
    $tnc = $false
}
if (-not $tnc) {
    Write-Error @"
Cannot reach $fqdn on TCP/443 from this workstation.

The Acme AI Foundry landing zone is fully private (public network access
disabled on every resource). All CLI calls must originate from a host with
line-of-sight into the Foundry spoke VNet.

Fix:
  1. Connect to the corporate VPN (or ExpressRoute), OR
  2. RDP into a jump host inside the Foundry VNet and rerun 'azd provision'
     from there.
"@
}

Write-Host "==> preprovision: ok"
