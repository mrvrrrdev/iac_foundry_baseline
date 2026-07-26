# Acme AI Foundry landing zone

The landing zone is a Terraform stack (root of this repo) that provisions every Azure resource the Foundry hosted agent needs, wired for **private-endpoint-only** networking and **Entra-only** authentication. There are no shared keys, no public endpoints, and no local admin logins — every data-plane call flows over a private endpoint and every principal authenticates via managed identity.

## Resources

| Layer | Module | Resource |
|-------|--------|----------|
| Foundry account + project | `avm.ai_foundry.tf`, `foundry.project.tf` | Cognitive Services account (`kind = AIServices`), project, capability host connections. |
| Container registry | `avm.container_registry.tf` | Premium ACR with admin user disabled. |
| Thread storage | `avm.cosmosdb.tf` | Cosmos DB SQL account, `demo` database + `memory` container. |
| Knowledge / RAG | `avm.ai_search.tf` | Azure AI Search, `standard` SKU. |
| Secrets | `avm.key_vault.tf` | Key Vault (RBAC auth, purge protection). |
| Blob + SMB | `avm.storage_account.tf` | Storage account with `demo-data` container and `demo-share` file share. |
| Observability | `avm.app_insights.tf`, `avm.log_analytics_workspace.tf`, `avm.monitor_workspace.tf` | Workspace-based Application Insights, Log Analytics workspace, and Azure Monitor Workspace for Prometheus metrics. |

Optional demo scaffolding (blob seed, file share seed, Cosmos containers, KV secret) is created by `demo_scaffolding.tf` when `enable_demo_scaffolding = true` (default).

## Identity model

- One **user-assigned managed identity** shared by the compute plane.
- The Foundry account and project each have their own **system-assigned managed identity**. The project SAMI is the principal that actually pulls the container image and reads capability-host resources at runtime.
- RBAC is declared in `rbac.tf`. Notable grants:
  - Project SAMI → `AcrPull` on the container registry (required on the first agent version, before any per-agent blueprint principals exist).
  - Foundry account SAMI → `Cosmos DB Operator`, `Search Index Data Contributor`, `Storage Blob Data Contributor`.
  - Deploying user → data-plane roles on Cosmos, Search, Key Vault, and Storage, so `bootstrap.py` can seed from inside the container using its identity.

## Network

Every resource has public network access disabled. Private endpoints resolve inside the Foundry spoke VNet; the demo agent's container runs on Foundry-managed compute joined to the same VNet, so the agent reaches Cosmos, Search, Key Vault, Storage, ACR, and Application Insights without leaving the private network.

## Deployment flow

1. `terraform apply` provisions the landing zone (including RBAC).
2. `azd env new` + `scripts/Bootstrap-Env.ps1` mirrors Terraform outputs into azd environment variables.
3. `azd up` runs `az acr build` server-side against `src/Dockerfile`, then publishes the image reference as a new Foundry agent version.
4. The container starts; `bootstrap.ensure_seeded()` creates the AI Search index, uploads the KB docs, and writes the `.seeded` marker so subsequent boots are no-ops.
