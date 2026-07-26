<#
.SYNOPSIS
    Post-deploy smoke test - invoke the demo agent and validate the
    environment health check + per-feature capabilities.

.DESCRIPTION
    Uses deterministic SMOKE:* commands over `azd ai agent invoke`. Each
    response contains one compact SMOKE_RESULT JSON envelope.

    The test flow:
      1. Ask the agent to run the environment health check. Parse the JSON
         result and assert every dependency PASS (or explicit SKIP).
      2. Iterate the enabled AGENT_FEATURE_* toggles and issue a per-feature
         canned prompt. Prompts for disabled features are skipped.

    Exits non-zero if any dependency FAIL or any per-feature invoke errors.

.PARAMETER VerboseLatency
    Print per-dependency latency (ms) from the health check.
#>

param(
    [switch]$VerboseLatency
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3
$env:AZURE_DEV_USER_AGENT = 'microsoft_foundry_skill'

$azdCommand = Get-Command azd -ErrorAction SilentlyContinue
if ($azdCommand) {
    $script:Azd = $azdCommand.Source
} else {
    $knownAzd = Join-Path $env:LOCALAPPDATA 'Programs\Azure Dev CLI\azd.exe'
    if (-not (Test-Path $knownAzd)) {
        throw "azd was not found on PATH or at '$knownAzd'. Install Azure Developer CLI and retry."
    }
    $script:Azd = $knownAzd
}
$azdDirectory = Split-Path -Parent $script:Azd
if (($env:PATH -split ';') -notcontains $azdDirectory) {
    $env:PATH = "$azdDirectory;$env:PATH"
}

function Get-EnabledFeatures {
    $vals = & $script:Azd env get-values 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'azd env get-values failed. Select the acme-dev-demo environment and retry.'
    }
    $map = @{}
    foreach ($line in $vals) {
        if ($line -match '^AGENT_FEATURE_([A-Z_0-9]+)=(.+)$') {
            $name = $matches[1]
            $val  = $matches[2].Trim('"')
            $map[$name] = ($val -eq 'true')
        }
    }
    return $map
}

function Invoke-Agent {
    param([string]$Prompt)
    Write-Host ("---- prompt: {0}" -f $Prompt) -ForegroundColor Cyan
    $out = & $script:Azd ai agent invoke --new-session --new-conversation $Prompt 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error ("azd ai agent invoke failed (exit {0}): {1}" -f $LASTEXITCODE, ($out -join "`n"))
    }
    return ($out -join "`n")
}

function ConvertFrom-SmokeOutput {
    param(
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][string]$Capability
    )

    $marker = 'SMOKE_RESULT:'
    $payloads = @(
        foreach ($line in ($Output -split "`r?`n")) {
            $index = $line.IndexOf($marker, [StringComparison]::Ordinal)
            if ($index -ge 0) {
                $line.Substring($index + $marker.Length).Trim()
            }
        }
    )
    if ($payloads.Count -ne 1) {
        throw "Expected exactly one SMOKE_RESULT marker for '$Capability'; found $($payloads.Count). Raw output:`n$Output"
    }

    try {
        $result = $payloads[0] | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Invalid SMOKE_RESULT JSON for '$Capability': $($_.Exception.Message). Raw output:`n$Output"
    }
    if ($result.capability -ne $Capability) {
        throw "Smoke capability mismatch: expected '$Capability', received '$($result.capability)'."
    }
    return $result
}

function Invoke-SmokeCapability {
    param([Parameter(Mandatory)][string]$Capability)

    $output = Invoke-Agent ("SMOKE:{0}" -f $Capability)
    $result = ConvertFrom-SmokeOutput -Output $output -Capability $Capability
    if ($result.status -eq 'FAIL') {
        $details = $null
        $nestedResults = $result.result.PSObject.Properties['results']
        if ($nestedResults) {
            $details = @(
                $nestedResults.Value |
                    Where-Object { $_.status -eq 'FAIL' } |
                    ForEach-Object { "{0}: {1}" -f $_.name, $_.error }
            ) -join '; '
        }
        if ([string]::IsNullOrWhiteSpace($details)) {
            $details = $result.error
        }
        throw "Smoke capability '$Capability' failed: $details"
    }
    if ($result.status -notin @('PASS', 'SKIP')) {
        throw "Smoke capability '$Capability' returned invalid status '$($result.status)'."
    }
    return $result
}

Write-Host "==> Invoke-Smoke: environment health check"
$healthEnvelope = Invoke-SmokeCapability 'healthcheck'
$health = $healthEnvelope.result

$fails = @($health.results | Where-Object { $_.status -eq 'FAIL' })
if ($fails.Count -gt 0) {
    foreach ($f in $fails) {
        Write-Host ("    FAIL {0}: {1}" -f $f.name, $f.error) -ForegroundColor Red
    }
    Write-Error ("Healthcheck reported {0} failure(s)" -f $fails.Count)
}

if ($VerboseLatency) {
    Write-Host "    dependency latency (ms):"
    foreach ($r in $health.results) {
        Write-Host ("      {0,-10} {1,-6} {2,6} ms" -f $r.name, $r.status, $r.latency_ms)
    }
}
Write-Host ("    healthcheck ok ({0}/{1} pass)" -f $health.summary.pass, $health.summary.total)

# --- Per-feature canned invokes ---------------------------------------------
$features = Get-EnabledFeatures
$prompts  = @(
    @{ Name = 'MEMORY_COSMOS'; Capability = 'memory' },
    @{ Name = 'KB_SEARCH';     Capability = 'kb' },
    @{ Name = 'BLOB';          Capability = 'blob' },
    @{ Name = 'KV_SECRET';     Capability = 'kv' },
    @{ Name = 'SMB_FILES';     Capability = 'files' },
    @{ Name = 'CHAT_GPT5';     Capability = 'chat' }
)

$failures = 0
foreach ($p in $prompts) {
    if (-not $features.ContainsKey($p.Name) -or -not $features[$p.Name]) {
        Write-Host ("---- skip {0} (feature disabled)" -f $p.Name) -ForegroundColor DarkGray
        continue
    }
    try {
        $result = Invoke-SmokeCapability $p.Capability
        Write-Host ("    {0}: {1}" -f $p.Name, $result.status) -ForegroundColor Green
    } catch {
        Write-Host ("    {0}: FAIL - {1}" -f $p.Name, $_.Exception.Message) -ForegroundColor Red
        $failures++
    }
}

if ($failures -gt 0) {
    Write-Error ("{0} per-feature invocation(s) failed" -f $failures)
}
Write-Host "==> Invoke-Smoke: all ok"
