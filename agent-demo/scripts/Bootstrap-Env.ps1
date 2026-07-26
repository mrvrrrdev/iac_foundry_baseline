<#
.SYNOPSIS
    Populate the azd environment from Terraform outputs.

.DESCRIPTION
    Reads `terraform output -json` from the repo root and mirrors the values
    into the current azd environment via `azd env set`. Also seeds the eight
    AGENT_FEATURE_* toggles to 'true' when they are not already set, so a
    fresh environment exercises the whole platform.

    Safe to re-run - values are overwritten in place.

.PARAMETER TerraformDir
    Path to the Terraform root. Defaults to the repository root (one level up
    from the script's parent directory).

.PARAMETER Force
    Overwrite existing AGENT_FEATURE_* flags too. Off by default.
#>

param(
    [string]$TerraformDir = (Join-Path $PSScriptRoot '..\..' | Resolve-Path),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

Write-Host "==> Bootstrap-Env: reading terraform outputs from $TerraformDir"

Push-Location $TerraformDir
try {
    $json = terraform output -json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        Write-Error "'terraform output -json' failed in $TerraformDir. Have you run 'terraform apply'?"
    }
    $outputs = $json | ConvertFrom-Json
} finally {
    Pop-Location
}

# Map: terraform output name -> azd environment variable
$map = @{
    'resource_group_name'                    = 'AZURE_RESOURCE_GROUP'
    'ai_foundry_account_id'                  = 'AZURE_AI_ACCOUNT_ID'
    'container_registry_name'                = 'AZURE_CONTAINER_REGISTRY_NAME'
    'container_registry_login_server'        = 'AZURE_CONTAINER_REGISTRY_ENDPOINT'
    'ai_foundry_account_name'                = 'AZURE_AI_ACCOUNT_NAME'
    'ai_foundry_project_name'                = 'AZURE_AI_PROJECT_NAME'
    'ai_foundry_project_id'                  = 'AZURE_AI_PROJECT_ID'
    'ai_foundry_project_endpoint'            = 'AZURE_AI_PROJECT_ENDPOINT'
    'ai_foundry_account_endpoint'            = 'AZURE_AI_ACCOUNT_ENDPOINT'
    'ai_foundry_chat_model_deployment'       = 'AZURE_AI_CHAT_DEPLOYMENT'
    'ai_foundry_embedding_model_deployment'  = 'AZURE_AI_EMBEDDING_DEPLOYMENT'
    'cosmos_endpoint'                        = 'AZURE_COSMOS_ENDPOINT'
    'cosmosdb_id'                            = 'AZURE_COSMOS_ID'
    'cosmos_demo_database'                   = 'AZURE_COSMOS_DATABASE'
    'cosmos_demo_memory_container'           = 'AZURE_COSMOS_MEMORY_CONTAINER'
    'search_endpoint'                        = 'AZURE_SEARCH_ENDPOINT'
    'ai_search_id'                           = 'AZURE_SEARCH_ID'
    'key_vault_uri'                          = 'AZURE_KEY_VAULT_URI'
    'key_vault_id'                           = 'AZURE_KEY_VAULT_ID'
    'storage_account_name'                   = 'AZURE_STORAGE_ACCOUNT_NAME'
    'storage_account_id'                     = 'AZURE_STORAGE_ACCOUNT_ID'
    'storage_blob_endpoint'                  = 'AZURE_STORAGE_BLOB_ENDPOINT'
    'storage_file_endpoint'                  = 'AZURE_STORAGE_FILE_ENDPOINT'
    'demo_blob_container_name'               = 'AZURE_STORAGE_DEMO_CONTAINER'
    'demo_file_share_name'                   = 'AZURE_STORAGE_DEMO_SHARE'
    'demo_kv_secret_name'                    = 'AZURE_KV_DEMO_SECRET_NAME'
    'application_insights_connection_string' = 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    'application_insights_id'                = 'AZURE_FOUNDRY_APPINSIGHTS_ID'
    'foundry_managed_identity_client_id'     = 'AZURE_FOUNDRY_UAMI_CLIENT_ID'
}

# --- Azure context from az CLI (not exposed as TF outputs) -------------------
$account = az account show --output json | ConvertFrom-Json
if (-not $account) {
    Write-Error "az account show returned nothing. Run 'az login' first."
}
azd env set AZURE_SUBSCRIPTION_ID $account.id | Out-Null
azd env set AZURE_TENANT_ID       $account.tenantId | Out-Null

# --- Mirror TF outputs -------------------------------------------------------
$set = 0
$skipped = 0
foreach ($tfName in $map.Keys) {
    $azdName = $map[$tfName]
    $prop    = $outputs.PSObject.Properties[$tfName]
    if (-not $prop) {
        Write-Warning "terraform output '$tfName' not found; skipping"
        $skipped++
        continue
    }
    $value = $prop.Value.value
    if ($null -eq $value -or $value -eq '') {
        Write-Host ("    (null)   {0,-40} <- {1}" -f $azdName, $tfName)
        $skipped++
        continue
    }
    azd env set $azdName "$value" | Out-Null
    Write-Host ("    set      {0,-40} <- {1}" -f $azdName, $tfName)
    $set++
}

# --- Aliases: azd's built-in service targets expect specific names ----------
# `azure.ai.agent` (hosted agent) reads FOUNDRY_PROJECT_ENDPOINT, not our
# AZURE_AI_PROJECT_ENDPOINT. Mirror the value under both names.
$foundryEp = $outputs.PSObject.Properties['ai_foundry_project_endpoint']
if ($foundryEp -and $foundryEp.Value.value) {
    azd env set FOUNDRY_PROJECT_ENDPOINT "$($foundryEp.Value.value)" | Out-Null
    Write-Host ("    alias    {0,-40} <- {1}" -f 'FOUNDRY_PROJECT_ENDPOINT', 'ai_foundry_project_endpoint')
    $set++
}

# --- Feature toggles: default to true when not present -----------------------
$features = @(
    'AGENT_FEATURE_TRACING',
    'AGENT_FEATURE_HEALTHCHECK',
    'AGENT_FEATURE_MEMORY_COSMOS',
    'AGENT_FEATURE_KB_SEARCH',
    'AGENT_FEATURE_BLOB',
    'AGENT_FEATURE_KV_SECRET',
    'AGENT_FEATURE_SMB_FILES',
    'AGENT_FEATURE_CHAT_GPT5',
    'AGENT_SEED_ON_STARTUP'
)
# `azd env get-value <key>` returns a non-empty error string when the key is
# missing, which fools a "-not $existing" check. Parse `azd env get-values`
# (dumps everything) once instead and look up in the resulting hashtable.
$existingMap = @{}
$dumped = azd env get-values 2>$null
foreach ($line in $dumped) {
    if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*"?(.*?)"?\s*$') {
        $existingMap[$matches[1]] = $matches[2]
    }
}

foreach ($f in $features) {
    $existing = $existingMap[$f]
    if ($Force -or [string]::IsNullOrEmpty($existing)) {
        azd env set $f 'true' | Out-Null
        Write-Host ("    feature  {0,-40} = true" -f $f)
    } else {
        Write-Host ("    keep     {0,-40} = $existing" -f $f)
    }
}

Write-Host ""
Write-Host ("==> Bootstrap-Env: {0} value(s) set, {1} skipped" -f $set, $skipped)
Write-Host "Next: azd up   (or, staged: azd provision  then  azd deploy)"
