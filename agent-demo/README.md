# Acme AI Foundry — demo hosted agent

A **containerised Foundry hosted agent** that exercises every service in the
Acme AI Foundry landing zone (Foundry itself, Cosmos DB, AI Search, Key
Vault, Blob + SMB storage, ACR, App Insights) end to end. Deploy it with
`azd` from a **Windows PowerShell 7** workstation — **no Python, no Docker,
no WSL required** locally. The image is built server-side by `az acr build`
inside the Foundry VNet.

Use it as a **smoke test** for the landing zone (does everything work?) and
as a **capability demo** (here is how a hosted agent talks to each service).

---

## What gets deployed

* One **Foundry hosted agent** named `acme-demo-agent`, model `gpt-5`. The
  agent manifest (`kind`, `name`, `protocols`, description) is inlined on
  the `demo-agent` service in [`azure.yaml`](./azure.yaml); the older
  on-disk `src/agent.yaml` shape is deprecated.
* A container image `demo-agent:<git-sha>` pushed to the adjacent ACR.
* Additional demo scaffolding (also created by Terraform when
  `enable_demo_scaffolding = true`, `false` is the default):
    * `demo-data` blob container + a seed `welcome.txt` blob.
    * `demo-share` SMB file share (100 GiB quota) + seed `hello.txt`.
    * `demo` Cosmos SQL database + `memory` container (`/userId` partition).
    * `demo-flag` Key Vault secret with a hello-world value.
    * `demo-kb` AI Search vector index seeded with the markdown docs under
      `src/seed/kb_docs/`.

Initial seeding runs **inside the container** (see `src/bootstrap.py`), so no
out-of-VNet data-plane calls are required from your workstation. When
`AGENT_SEED_ON_STARTUP=true`, `bootstrap.ensure_seeded()` runs synchronously
before the Responses server starts; `/readiness` is unavailable until its
marker check and any required seeding finish. After the initial seed succeeds,
disable startup seeding and redeploy to reduce hosted-session cold-start risk.

---

## Tools the agent exposes

Each tool is behind an `AGENT_FEATURE_*` flag (see the table below). All
default to `true`; disable a flag with `azd env set AGENT_FEATURE_<NAME> false`
and redeploy.

| Tool name       | Purpose                                                                    | Feature flag                 |
|-----------------|----------------------------------------------------------------------------|------------------------------|
| `healthcheck`   | PASS/FAIL matrix + latency for every dependency.                           | `AGENT_FEATURE_HEALTHCHECK`  |
| `memory`        | `remember` / `recall` / `forget` per-user facts in Cosmos DB.              | `AGENT_FEATURE_MEMORY_COSMOS`|
| `kb`            | Vector search over the `demo-kb` AI Search index.                          | `AGENT_FEATURE_KB_SEARCH`    |
| `blob`          | `list` / `upload` / `download` on the `demo-data` blob container.          | `AGENT_FEATURE_BLOB`         |
| `kv`            | Read allow-listed `demo-*` secrets from Key Vault.                         | `AGENT_FEATURE_KV_SECRET`    |
| `files`         | `list` / `read` / `write` on the `demo-share` SMB file share.              | `AGENT_FEATURE_SMB_FILES`    |
| `chat`          | Direct chat completion against the `gpt-5` deployment.                     | `AGENT_FEATURE_CHAT_GPT5`    |

Extra toggles:

| Variable                    | Effect                                                                          |
|-----------------------------|---------------------------------------------------------------------------------|
| `AGENT_FEATURE_TRACING`     | Emit OpenTelemetry traces to Application Insights via `azure-monitor-opentelemetry`. |
| `AGENT_SEED_ON_STARTUP`     | Run synchronous, idempotent seeding before the Responses server starts. Keep enabled for the initial seed, then disable. |

---

## Deploying from Windows PowerShell (no Python, no Docker, no WSL)


### 1. One-time prerequisites
```powershell
winget install --id Microsoft.PowerShell     # PowerShell 7
winget install --id Microsoft.AzureCLI       # az
winget install --id Microsoft.Azd            # azd
winget install --id Hashicorp.Terraform      # for the landing zone
winget install --id Git.Git                  # for the git SHA tag
```

Nothing else is required. In particular there is **no local Python install
and no local Docker** — the container is built server-side by `az acr build`
and runs on Foundry's managed compute.

### 2. Connect to the Foundry network

The Acme landing zone is **fully private** (public network access disabled,
Entra-only auth, private endpoints only). Every step below must run from a
host with line-of-sight into the Foundry spoke VNet: usually the **corporate
VPN**, ExpressRoute, or a jump host / Azure Bastion VM. `preprovision.ps1`
sanity-checks this and fails fast with a useful message if the private
endpoint FQDN is unreachable.

### 3. Sign in

```powershell
az login  --tenant <TENANT-ID>
azd auth login --tenant-id <TENANT-ID>
az account set --subscription <SUBSCRIPTION-ID>
```

### 4. Apply the landing zone (from the repo root)

Skip this step if the landing zone is already applied.

```powershell
terraform init
terraform apply
```

This provisions the Foundry account, the demo scaffolding (blob container,
file share, Cosmos database + container, Key Vault secret), and every
associated RBAC assignment. The **AI Search index** is NOT created by
Terraform — it is created by the container the first time it boots
(`src/bootstrap.py`), because index creation is a data-plane call that
requires VNet line-of-sight.

### 5. Bootstrap the azd environment

```powershell
cd agent-demo
azd env new acme-dev-demo
./scripts/Bootstrap-Env.ps1
```

`Bootstrap-Env.ps1` reads every relevant `terraform output` from the repo
root and mirrors the values into the new azd environment (endpoints,
resource names, App Insights connection string, subscription/tenant, and
default `AGENT_FEATURE_*=true`). Re-run any time you want to refresh.

### 6. Deploy

```powershell
# Open the ACR public endpoint AND flip default-action to Allow for the
# ~2-minute server-side build, then revert both in a finally block so an
# aborted deploy cannot leave the registry exposed. Terraform's steady state
# asserts default-action = Deny; without flipping it here the ACR Tasks
# fleet is still blocked even with the public endpoint on (its egress IPs
# are not covered by the AzureServices trusted-services bypass). Entra token
# auth (AcrPush/AcrPull) still gates every call — admin_enabled and
# anonymous_pull_enabled are false.
$acr = azd env get-value AZURE_CONTAINER_REGISTRY_NAME
try {
    az acr update -n $acr --public-network-enabled true  --default-action Allow | Out-Null
    azd up
}
finally {
    az acr update -n $acr --public-network-enabled false --default-action Deny  | Out-Null
}
```

Under the hood:

1. `hooks/preprovision.ps1` verifies az/azd login and pings the Foundry
   private endpoint on TCP/443.
2. `azd provision` runs `infra/main.bicep` — an intentionally empty
   resource-group deployment (zero real Azure resources, just a nested
   no-op deployment). All infrastructure is provisioned by the outer
   Terraform stack in step 4 of the deployment flow; this template exists
   only to satisfy azd's default Bicep provider so `azd provision` is a
   fast no-op.
3. `azd deploy` (invoked by `azd up`) uses the `azure.ai.agent` service
   target with `docker.remoteBuild: true` (see `azure.yaml`) to run an
   **ACR remote build** against `src/Dockerfile` — the image is built
   inside ACR, so no local Docker daemon is needed. The build runs on
   the ACR Tasks shared fleet, whose egress IPs are not covered by
   Container Registry's `AzureServices` trusted-services bypass, so the
   registry's public endpoint must be reachable AND the network rule
   set's `default-action` must be `Allow` for the ~2-minute build
   window — that is why the wrapper above toggles BOTH
   `--public-network-enabled` and `--default-action` around the call.
   The resulting image tag is written back to the azd env as
   `AGENT_IMAGE_URI` and registered as a new **agent version** on the
   Foundry project.
4. `hooks/postdeploy-demo-agent.ps1` discovers the new version's instance
   managed identity and grants it `Monitoring Metrics Publisher` on Application
   Insights. When tracing is enabled, a missing identity or unverified role
   assignment fails postdeploy instead of leaving the agent with broken tracing.
5. Before starting the Responses server, `main.py` synchronously runs
   `bootstrap.ensure_seeded()` when `AGENT_SEED_ON_STARTUP=true`. It creates
   the AI Search index and uploads the seed KB docs / blob / file. A marker
   blob makes repeat runs idempotent, but `/readiness` cannot return HTTP 200
   until the marker lookup and any required seeding finish. After the initial
   seed succeeds, disable startup seeding and deploy a new agent version.


### 7. Smoke test
```powershell
./scripts/Invoke-Smoke.ps1 -VerboseLatency
```

The script asks the agent to run the environment health check, asserts
every dependency PASS, then invokes each enabled feature with a canned
prompt. Non-zero exit on any failure.

---

## Configuring which features are on

Feature flags live on the azd environment. Turn one off:

```powershell
azd env set AGENT_FEATURE_KB_SEARCH false
azd up
```

The container will re-register with only the enabled tools; the agent's
system prompt tells the model to report the disabled capability instead of
attempting to use it.

After the first successful seed, disable synchronous startup seeding to keep
`/readiness` off the Blob, Search, embedding, and File data-plane paths:

```powershell
azd env set AGENT_SEED_ON_STARTUP false
$acr = azd env get-value AZURE_CONTAINER_REGISTRY_NAME
try {
    az acr update -n $acr --public-network-enabled true  --default-action Allow | Out-Null
    azd up
}
finally {
    az acr update -n $acr --public-network-enabled false --default-action Deny  | Out-Null
}
./scripts/Invoke-Smoke.ps1 -VerboseLatency
```

Do not disable seeding on a new environment before its initial successful run.
Confirm the smoke test passes and, if necessary, confirm `.seeded` exists in
the `demo-data` container. Otherwise the `demo-kb` index and documents,
`welcome.txt`, or `hello.txt` may not exist.

> **Observed mitigation (Sweden Central):** agent version 1 intermittently
> returned HTTP 424 `session_not_ready` with startup seeding enabled. After
> the data had been seeded, version 2 was deployed with startup seeding
> disabled and passed all seven dependency checks plus all six capability
> checks. The redeploy also refreshed hosted compute, so this is evidence of
> a successful mitigation, not proof that seeding was the sole cause.

---

## Redeploying from scratch

Two scopes, pick one.

**A. Rebuild just the agent** (landing zone intact). Publishes a fresh
container image + new agent version against the existing Foundry project:

```powershell
azd env select acme-dev-demo
azd down --purge --force   # deletes the agent + azd-managed artifacts
# Same open-then-close wrap as step 6 — see there for the security rationale.
$acr = azd env get-value AZURE_CONTAINER_REGISTRY_NAME
try {
    az acr update -n $acr --public-network-enabled true  --default-action Allow | Out-Null
    azd up                 # provision (no-op) + deploy (remote build + new version)
}
finally {
    az acr update -n $acr --public-network-enabled false --default-action Deny  | Out-Null
}
```

**B. Rebuild the entire stack** (landing zone + demo). Follows the
Cognitive Services soft-delete purge recipe from the root
[`README.md`](../README.md#111-soft-delete-collision-on-redeploy):

```powershell
# 1. Tear down the demo azd project
cd agent-demo
azd env select acme-dev-demo
azd down --purge --force
cd ..

# 2. Destroy the Terraform stack
terraform destroy

# 3. Purge the soft-deleted Foundry account (name/subdomain is reserved otherwise)
az cognitiveservices account list-deleted -o table
az cognitiveservices account purge `
    --location swedencentral `
    --resource-group acme-dev-rg-foundry-01 `
    --name acme-dev-aif-01

# 4. Rebuild — same open-then-close wrap as step 6.
terraform apply
cd agent-demo
./scripts/Bootstrap-Env.ps1
$acr = azd env get-value AZURE_CONTAINER_REGISTRY_NAME
try {
    az acr update -n $acr --public-network-enabled true  --default-action Allow | Out-Null
    azd up
}
finally {
    az acr update -n $acr --public-network-enabled false --default-action Deny  | Out-Null
}
```

---

## Troubleshooting

| Symptom                                                                 | What to check                                                                                                                                       |
|-------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| `preprovision` fails: cannot reach `<account>.cognitiveservices…:443`   | Corporate VPN / ExpressRoute is not up, or DNS is not resolving the private endpoint. Try `Resolve-DnsName <fqdn>` — it should return a 10.x/172.x address. |
| `azd deploy` fails during ACR remote build with 403                     | Your Entra principal needs `AcrPush` on the registry. The landing zone grants `AcrPull` to the Foundry MI; humans running `azd deploy` need `AcrPush` separately. |
| Agent version stuck in `Creating` / fails with `ProvisioningError`, `container_protocol_versions: []` | Container is not answering the platform probes. Inspect the version via data plane: `GET {AZURE_AI_PROJECT_ENDPOINT}/agents/{name}/versions/{n}?api-version=2025-05-15-preview` (Bearer token, audience `https://ai.azure.com`) and look at `error.code` + `container_protocol_versions`. Container-side traces: `az monitor app-insights query --app <appId> --analytics-query "traces \| order by timestamp desc \| take 50"`. Common causes: wrong port (must be 8088), wrong probe path (`GET /readiness`), image not `linux/amd64`, or ACR pull RBAC missing. If all customer-side checks are green, capture the request-id and open an Azure support ticket — hosted-agent provisioning has had platform-side incidents (e.g. Sweden Central, 2025-11). |
| Invocation fails with HTTP 424 `session_not_ready` | The fresh session did not become ready before Foundry's timeout, so the request may not have reached the agent handler. After confirming initial seeding completed, set `AGENT_SEED_ON_STARTUP=false`, redeploy with the ACR wrapper from the configuration section, and rerun the smoke test. If it persists, inspect Application Insights for container startup traces and `/readiness` requests. No telemetry for a failed session suggests a Foundry scheduler or regional issue; retain the request ID for Azure Support. |
| Exporter or QuickPulse logs `Unauthorized` and `The Agent/SDK does not have permissions to send telemetry to this resource.` | The current version's instance identity lacks `Monitoring Metrics Publisher` on Application Insights. From `agent-demo`, select the deployment's azd environment and run `pwsh ./hooks/postdeploy-demo-agent.ps1`. The hook retries identity propagation, creates the assignment idempotently, verifies it directly, and exits nonzero if tracing is still unauthorized. Do not enable local authentication as a workaround. |
| Container starts, `healthcheck` reports Cosmos FAIL with 401            | The Foundry MI Cosmos data-plane role assignment (`00000000-…-002`) has not propagated yet. Wait a minute and re-invoke.                            |
| Bootstrap didn't seem to run                                                | The marker blob (`.seeded` in `demo-data`) is present. Delete it and restart the agent to re-seed, or set `AGENT_SEED_ON_STARTUP=false` and seed manually. |
| `kb` returns 0 hits                                                     | Check the container logs for a "KB seed failed" line. AI Search embeddings need the `text-embedding-3-large` deployment to be reachable from the container's identity. |
| `azd ai agent invoke` reports `agent service "demo-agent" does not appear to have been deployed` right after a successful `azd deploy` | The `azure.ai.agents` extension changed its per-service env-var naming (previously `AGENT_<SVC>NAME`/`_VERSION` with dashes stripped; now `AGENT_<SVC>_NAME`/`_VERSION` with dashes → underscore). Check `azd env get-values \| Select-String AGENT_DEMO_AGENT_` — if only the old-style keys are populated, re-run `azd deploy` under the current extension so it writes the new keys. Also confirm the manifest `name:` matches the agent actually on Foundry; renaming (e.g. `sko-demo-agent` → `acme-demo-agent`) leaves the previous agent orphaned. Delete the stale one with `DELETE {AZURE_AI_PROJECT_ENDPOINT}/agents/<old-name>?api-version=2025-05-15-preview` (Bearer token, audience `https://ai.azure.com`). |

---

## Cross-platform note

The workflow above is PowerShell 7 based and is validated on **Windows**.
It should run on **Linux and macOS** with `pwsh` installed — `az`, `azd`
and `terraform` are cross-platform — but the private-endpoint reachability
probe in `hooks/preprovision.ps1` uses `Test-NetConnection`, which is
Windows-only. On non-Windows hosts either substitute an equivalent check
(e.g. `Test-Connection -TargetName <fqdn> -TcpPort 443`) or skip the
preprovision hook. WSL2 is not required — the point of the ACR remote
build (`docker.remoteBuild: true` in `azure.yaml`) is that you never need
a local Linux container runtime.
