# Agent Service capability host

The Foundry Agent Service **capability host** is the Bring-Your-Own (BYO) data plane behind hosted agents. When an agent is provisioned in Microsoft Foundry, the capability host wires three tenant-owned Azure resources into the Foundry account so that agent runs use *your* isolation boundary, quotas, and RBAC rather than Foundry's shared multi-tenant defaults.

## The three BYO resources

| Capability | Azure resource | Purpose |
|------------|----------------|---------|
| Thread storage | Azure Cosmos DB (SQL API) | Persists agent threads, messages, and run metadata. |
| Knowledge / files | Azure AI Search | Vector + keyword index for `File Search` and RAG tools. |
| Blob attachments | Azure Storage account | Uploaded files, images, and tool outputs referenced by threads. |

Each is attached to the Foundry account via a `connection` resource and referenced from the project's `capabilityHost` object. The Foundry control plane creates its own Cosmos containers, Search indexes, and blob containers inside the resources you provide — you never write to those internal artifacts directly.

## How the Acme landing zone wires it up

In this repository the capability host is declared in `foundry.project.tf` and points at the three resources provisioned by the AVM modules:

- **Cosmos DB** — `avm.cosmosdb.tf`.
- **AI Search** — `avm.ai_search.tf`, SKU `standard`.
- **Storage** — `avm.storage_account.tf`.

All three are private-endpoint-only. The Foundry account's system-assigned managed identity is granted the required data-plane roles by `rbac.tf` (`Cosmos DB Operator`, `Search Index Data Contributor`, `Storage Blob Data Contributor`).

## What the demo agent stores where

This demo agent uses the capability host resources *and* a parallel set of "demo" artifacts inside the same accounts:

- **Cosmos DB** — Foundry threads live in an auto-created `agents` database; the `demo` database + `memory` container (partition key `/userId`) are used by the `memory` tool.
- **AI Search** — Foundry may create its own indexes; the `demo-kb` index (created by `bootstrap.py`) is used by the `kb` tool.
- **Storage** — Foundry manages its own containers; the `demo-data` blob container and `demo-share` SMB file share are used by the `blob` and `files` tools.

Separating "Foundry-owned" from "demo-owned" artifacts inside the same accounts keeps the RBAC surface tight while still exercising every landing-zone service end to end.
