<#
.SYNOPSIS
    azd postdeploy hook - grant Monitoring Metrics Publisher on App Insights
    to the Foundry hosted agent's identities (blueprint + per-version
    instance SAMI). Idempotent and mandatory when tracing is enabled.

.DESCRIPTION
    Foundry hosted agents run in a container whose primary IMDS identity is
    a per-agent-version system-assigned MI ("instance SAMI"). Because App
    Insights has local_authentication_disabled=true, the auto-instrumented
    OTEL exporters inside the container need Monitoring Metrics Publisher
    on the component. The instance SAMI does not exist at Terraform plan
    time - it is created when the agent version is provisioned. So we
    resolve it AFTER 'azd deploy' and grant the role idempotently.

    The blueprint SAMI (persistent across agent versions) is also re-granted
    for defence in depth, in case a future Foundry runtime starts returning
    it as the primary IMDS identity.

    Required azd env vars (populated by scripts/Bootstrap-Env.ps1 and by
    'azd deploy'):
      * AZURE_FOUNDRY_APPINSIGHTS_ID   - App Insights resource ID
      * AZURE_AI_PROJECT_ENDPOINT      - Foundry project data-plane endpoint
      * AGENT_DEMO_AGENT_NAME          - written by 'azd deploy demo-agent'
      * AGENT_DEMO_AGENT_VERSION       - written by 'azd deploy demo-agent'

    When AGENT_FEATURE_TRACING is true (the default), this hook fails if it
    cannot discover the current version identity or verify its role assignment.
    Re-run the hook by hand after resolving the reported problem:
    pwsh ./hooks/postdeploy-demo-agent.ps1
#>

param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

Write-Host '==> postdeploy: granting Monitoring Metrics Publisher on App Insights to agent identities'

function Assert-Command {
    param([string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Error "Required CLI '$Name' not found on PATH. $InstallHint"
    }
}

Assert-Command 'az'  'Install with: winget install --id Microsoft.AzureCLI'
Assert-Command 'azd' 'Install with: winget install --id Microsoft.Azd'

function Get-AzdEnvValue {
    param([Parameter(Mandatory)][string]$Name)
    $v = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v.Trim()
}

$tracingValue = Get-AzdEnvValue 'AGENT_FEATURE_TRACING'
$tracingEnabled = [string]::IsNullOrWhiteSpace($tracingValue) -or $tracingValue -notmatch '^(?i:false|0|no|off)$'
if (-not $tracingEnabled) {
    Write-Host '==> postdeploy: tracing is disabled; skipping Application Insights RBAC'
    exit 0
}

$appiId       = Get-AzdEnvValue 'AZURE_FOUNDRY_APPINSIGHTS_ID'
$projectEp    = Get-AzdEnvValue 'AZURE_AI_PROJECT_ENDPOINT'
$agentName    = Get-AzdEnvValue 'AGENT_DEMO_AGENT_NAME'
$agentVersion = Get-AzdEnvValue 'AGENT_DEMO_AGENT_VERSION'

if (-not $appiId) {
    throw 'AZURE_FOUNDRY_APPINSIGHTS_ID is not set. Run scripts/Bootstrap-Env.ps1 first.'
}
if (-not $projectEp) {
    throw 'AZURE_AI_PROJECT_ENDPOINT is not set. Run scripts/Bootstrap-Env.ps1 first.'
}
if (-not $agentName) {
    throw "AGENT_DEMO_AGENT_NAME is not set. Run 'azd deploy demo-agent' first."
}
if (-not $agentVersion) {
    throw "AGENT_DEMO_AGENT_VERSION is not set. Run 'azd deploy demo-agent' first."
}

Write-Host ("    App Insights   : {0}" -f $appiId)
Write-Host ("    Foundry project: {0}" -f $projectEp)
Write-Host ("    Agent          : {0} (version {1})" -f $agentName, $agentVersion)

# --- Bearer token for the Foundry data plane --------------------------------
$token = az account get-access-token --resource 'https://ai.azure.com' --query accessToken -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'az account get-access-token for https://ai.azure.com failed. Sign in with az login and retry.'
}
$headers = @{ Authorization = "Bearer $token" }
$apiVer  = '2025-05-15-preview'

# --- Resolve identities from the authoritative Foundry response fields ------
function Get-PrincipalIdFromUrl {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$IdentityPropertyNames,
        [int]$MaxAttempts = 1
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri $Url -Headers $headers -Method GET -ErrorAction Stop
            foreach ($identityPropertyName in $IdentityPropertyNames) {
                $identity = $response.PSObject.Properties[$identityPropertyName].Value
                if ($null -eq $identity) {
                    continue
                }

                foreach ($principalPropertyName in @('principal_id', 'principalId')) {
                    $principalId = $identity.PSObject.Properties[$principalPropertyName].Value
                    $guid = [guid]::Empty
                    if ([guid]::TryParse("$principalId", [ref]$guid)) {
                        $resolved = $guid.ToString()
                        Write-Host ("    found          : {0} principalId = {1}" -f $Label, $resolved)
                        return $resolved
                    }
                }
            }
            Write-Warning ("No {0} principal ID found in the expected response fields (attempt {1}/{2})." -f $Label, $attempt, $MaxAttempts)
        } catch {
            Write-Warning ("GET {0} ({1}) failed on attempt {2}/{3}: {4}" -f $Url, $Label, $attempt, $MaxAttempts, $_.Exception.Message)
        }

        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds ([Math]::Min(5 * $attempt, 20))
        }
    }

    return $null
}

$escapedAgentName = [uri]::EscapeDataString($agentName)
$escapedVersion = [uri]::EscapeDataString($agentVersion)
$blueprintPrincipal = Get-PrincipalIdFromUrl `
    -Url ("{0}/agents/{1}?api-version={2}" -f $projectEp.TrimEnd('/'), $escapedAgentName, $apiVer) `
    -Label 'blueprint' `
    -IdentityPropertyNames @('blueprint')

$instancePrincipal = Get-PrincipalIdFromUrl `
    -Url ("{0}/agents/{1}/versions/{2}?api-version={3}" -f $projectEp.TrimEnd('/'), $escapedAgentName, $escapedVersion, $apiVer) `
    -Label 'instance' `
    -IdentityPropertyNames @('instance_identity', 'instanceIdentity') `
    -MaxAttempts 6

if (-not $instancePrincipal) {
    throw "No principal ID was found for $agentName version $agentVersion after bounded retries. Telemetry RBAC cannot be established."
}

# --- Grant Monitoring Metrics Publisher on App Insights ---------------------
$roleName = 'Monitoring Metrics Publisher'
$roleId = '3913510d-42f4-4e42-8a64-420c390055eb'
$granted = 0
$existed = 0
$failed  = 0

function Test-DirectRoleAssignment {
    param([Parameter(Mandatory)][string]$ObjectId)

    $assignmentId = az role assignment list `
        --scope $appiId `
        --role $roleId `
        --query "[?principalId=='$ObjectId'].id | [0]" `
        --output tsv `
        --only-show-errors 2>$null
    return $LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace("$assignmentId")
}

function Grant-AndVerifyRoleAssignment {
    param(
        [Parameter(Mandatory)][string]$ObjectId,
        [Parameter(Mandatory)][string]$Label,
        [int]$MaxAttempts = 6
    )

    if (Test-DirectRoleAssignment -ObjectId $ObjectId) {
        Write-Host ("    exists         : {0} {1} already has '{2}'" -f $Label, $ObjectId, $roleName)
        $script:existed++
        return $true
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $output = az role assignment create `
            --role $roleId `
            --assignee-object-id $ObjectId `
            --assignee-principal-type ServicePrincipal `
            --scope $appiId `
            --only-show-errors 2>&1

        if ($LASTEXITCODE -eq 0 -or "$output" -match 'RoleAssignmentExists|already exists') {
            for ($verifyAttempt = 1; $verifyAttempt -le 6; $verifyAttempt++) {
                if (Test-DirectRoleAssignment -ObjectId $ObjectId) {
                    Write-Host ("    verified       : {0} {1} has '{2}'" -f $Label, $ObjectId, $roleName)
                    $script:granted++
                    return $true
                }
                Start-Sleep -Seconds 5
            }
        } else {
            Write-Warning ("Role grant for {0} {1} failed on attempt {2}/{3}: {4}" -f $Label, $ObjectId, $attempt, $MaxAttempts, "$output")
        }

        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds ([Math]::Min(5 * $attempt, 20))
        }
    }

    $script:failed++
    return $false
}

if ($blueprintPrincipal) {
    if (-not (Grant-AndVerifyRoleAssignment -ObjectId $blueprintPrincipal -Label 'blueprint')) {
        Write-Warning "The supplementary blueprint grant failed for $blueprintPrincipal."
    }
}

$instanceVerified = Grant-AndVerifyRoleAssignment -ObjectId $instancePrincipal -Label 'instance'

if (-not $instanceVerified) {
    throw "The current-version principal $instancePrincipal lacks a verified '$roleName' assignment on App Insights."
}

# --- Grant the hosted runtime identity access to enabled adjacent services ---
function Test-FeatureEnabled {
    param([Parameter(Mandatory)][string]$Name)
    $value = Get-AzdEnvValue $Name
    return [string]::IsNullOrWhiteSpace($value) -or $value -notmatch '^(?i:false|0|no|off)$'
}

function Grant-AndVerifyAzureRole {
    param(
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Label,
        [int]$MaxAttempts = 6
    )

    $created = $false
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $assignmentId = az role assignment list `
            --scope $Scope `
            --role $Role `
            --query "[?principalId=='$instancePrincipal'].id | [0]" `
            --output tsv `
            --only-show-errors 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace("$assignmentId")) {
            if ($created) {
                Write-Host ("    verified       : instance has '{0}' on {1}" -f $Role, $Label)
                $script:granted++
            } else {
                Write-Host ("    exists         : instance has '{0}' on {1}" -f $Role, $Label)
                $script:existed++
            }
            return
        }

        $output = az role assignment create `
            --role $Role `
            --assignee-object-id $instancePrincipal `
            --assignee-principal-type ServicePrincipal `
            --scope $Scope `
            --only-show-errors 2>&1
        if ($LASTEXITCODE -eq 0 -or "$output" -match 'RoleAssignmentExists|already exists') {
            $created = $true
            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds 5
            }
            continue
        }

        Write-Warning ("Role grant '{0}' on {1} failed on attempt {2}/{3}: {4}" -f $Role, $Label, $attempt, $MaxAttempts, "$output")
        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds ([Math]::Min(5 * $attempt, 20))
        }
    }

    $script:failed++
    throw "The current-version principal $instancePrincipal lacks '$Role' on $Label."
}

function Grant-AndVerifyCosmosDataRole {
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$AccountName,
        [int]$MaxAttempts = 6
    )

    $cosmosRoleId = '00000000-0000-0000-0000-000000000002'
    $created = $false
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $assignmentId = az cosmosdb sql role assignment list `
            --resource-group $ResourceGroup `
            --account-name $AccountName `
            --query "[?principalId=='$instancePrincipal' && contains(roleDefinitionId, '$cosmosRoleId')].id | [0]" `
            --output tsv `
            --only-show-errors 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace("$assignmentId")) {
            if ($created) {
                Write-Host '    verified       : instance has Cosmos DB Built-in Data Contributor'
                $script:granted++
            } else {
                Write-Host '    exists         : instance has Cosmos DB Built-in Data Contributor'
                $script:existed++
            }
            return
        }

        $output = az cosmosdb sql role assignment create `
            --resource-group $ResourceGroup `
            --account-name $AccountName `
            --role-definition-id $cosmosRoleId `
            --scope '/' `
            --principal-id $instancePrincipal `
            --only-show-errors 2>&1
        if ($LASTEXITCODE -eq 0 -or "$output" -match 'already exists|Conflict') {
            $created = $true
            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds 5
            }
            continue
        }

        Write-Warning ("Cosmos data role grant failed on attempt {0}/{1}: {2}" -f $attempt, $MaxAttempts, "$output")
        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds ([Math]::Min(5 * $attempt, 20))
        }
    }

    $script:failed++
    throw "The current-version principal $instancePrincipal lacks Cosmos DB Built-in Data Contributor."
}

$accountId = Get-AzdEnvValue 'AZURE_AI_ACCOUNT_ID'
if (-not $accountId) { throw 'AZURE_AI_ACCOUNT_ID is not set. Re-run scripts/Bootstrap-Env.ps1.' }
Grant-AndVerifyAzureRole -Scope $accountId -Role 'Cognitive Services OpenAI User' -Label 'Foundry account'

if (Test-FeatureEnabled 'AGENT_FEATURE_MEMORY_COSMOS') {
    $resourceGroup = Get-AzdEnvValue 'AZURE_RESOURCE_GROUP'
    $cosmosEndpoint = Get-AzdEnvValue 'AZURE_COSMOS_ENDPOINT'
    if (-not $resourceGroup -or -not $cosmosEndpoint) { throw 'Cosmos RBAC inputs are missing. Re-run scripts/Bootstrap-Env.ps1.' }
    $cosmosAccount = ([uri]$cosmosEndpoint).Host.Split('.')[0]
    Grant-AndVerifyCosmosDataRole -ResourceGroup $resourceGroup -AccountName $cosmosAccount
}

if (Test-FeatureEnabled 'AGENT_FEATURE_KB_SEARCH') {
    $searchId = Get-AzdEnvValue 'AZURE_SEARCH_ID'
    if (-not $searchId) { throw 'AZURE_SEARCH_ID is not set. Re-run scripts/Bootstrap-Env.ps1.' }
    Grant-AndVerifyAzureRole -Scope $searchId -Role 'Search Service Contributor' -Label 'AI Search'
    Grant-AndVerifyAzureRole -Scope $searchId -Role 'Search Index Data Contributor' -Label 'AI Search'
}

if (Test-FeatureEnabled 'AGENT_FEATURE_KV_SECRET') {
    $keyVaultId = Get-AzdEnvValue 'AZURE_KEY_VAULT_ID'
    if (-not $keyVaultId) { throw 'AZURE_KEY_VAULT_ID is not set. Re-run scripts/Bootstrap-Env.ps1.' }
    Grant-AndVerifyAzureRole -Scope $keyVaultId -Role 'Key Vault Secrets User' -Label 'Key Vault'
}

$storageId = Get-AzdEnvValue 'AZURE_STORAGE_ACCOUNT_ID'
if ((Test-FeatureEnabled 'AGENT_FEATURE_BLOB') -or (Test-FeatureEnabled 'AGENT_FEATURE_SMB_FILES')) {
    if (-not $storageId) { throw 'AZURE_STORAGE_ACCOUNT_ID is not set. Re-run scripts/Bootstrap-Env.ps1.' }
}
if (Test-FeatureEnabled 'AGENT_FEATURE_BLOB') {
    Grant-AndVerifyAzureRole -Scope $storageId -Role 'Storage Blob Data Contributor' -Label 'Storage account'
}
if (Test-FeatureEnabled 'AGENT_FEATURE_SMB_FILES') {
    Grant-AndVerifyAzureRole -Scope $storageId -Role 'Storage File Data Privileged Contributor' -Label 'Storage account'
}

Write-Host ''
Write-Host ("==> postdeploy: {0} granted, {1} pre-existing, {2} failed" -f $granted, $existed, $failed)

exit 0
