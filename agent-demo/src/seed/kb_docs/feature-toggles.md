# Agent feature toggles

The Acme demo hosted agent registers one tool per landing-zone capability. Every tool is guarded by an `AGENT_FEATURE_*` flag on the azd environment, so operators can shrink the agent's surface area without rebuilding the image.

## Tool flags

| Flag | Tool | What it exposes |
|------|------|-----------------|
| `AGENT_FEATURE_HEALTHCHECK` | `healthcheck` | PASS/FAIL matrix and latency for every dependency. The smoke test relies on this, so leave it on. |
| `AGENT_FEATURE_MEMORY_COSMOS` | `memory` | `remember` / `recall` / `forget` per-user facts in Cosmos DB `demo.memory` (partition key `/userId`). |
| `AGENT_FEATURE_KB_SEARCH` | `kb` | Vector search over the `demo-kb` AI Search index. Seeded from the markdown files under `src/seed/kb_docs/`. |
| `AGENT_FEATURE_BLOB` | `blob` | `list` / `upload` / `download` on the `demo-data` blob container. |
| `AGENT_FEATURE_KV_SECRET` | `kv` | Read allow-listed `demo-*` secrets from Key Vault. Write is never enabled. |
| `AGENT_FEATURE_SMB_FILES` | `files` | `list` / `read` / `write` on the `demo-share` SMB file share. |
| `AGENT_FEATURE_CHAT_GPT5` | `chat` | Direct chat completion against the `gpt-5` model deployment. |

## Platform flags

| Flag | Effect |
|------|--------|
| `AGENT_FEATURE_TRACING` | Emit OpenTelemetry traces to Application Insights via `azure-monitor-opentelemetry`. |
| `AGENT_SEED_ON_STARTUP` | Run `bootstrap.ensure_seeded()` on the container's first boot. Idempotent — writes a `.seeded` marker blob to `demo-data`. |

All flags default to `true`.

## Changing a flag

```powershell
azd env set AGENT_FEATURE_KB_SEARCH false
azd up
```

The container re-registers with only the enabled tools; the agent's system prompt tells the model to report the disabled capability instead of attempting to call it. Disabling a flag also short-circuits that capability's block in `bootstrap.py`, so a freshly-provisioned environment stays consistent with the flag set.

## Re-seeding after content changes

The marker blob at `demo-data/.seeded` short-circuits subsequent boots. To re-run seeding after adding or editing a KB doc, delete the marker and restart the agent. Alternatively set `AGENT_SEED_ON_STARTUP=false`, seed manually, then flip it back to `true`.
