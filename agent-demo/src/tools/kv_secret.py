"""kv - read demo Key Vault secrets. Read-only, allowlisted."""

from __future__ import annotations

import asyncio
import re
from typing import Any

from config import settings

NAME = "kv"
IS_ENABLED = settings.feature_kv_secret

# Only demo-prefixed secrets are readable via this tool to prevent the model
# from reading production secrets (defense-in-depth in addition to KV RBAC).
_ALLOWED_SECRET_RE = re.compile(r"^demo-[a-zA-Z0-9-]+$")

SPEC = {
    "type": "function",
    "function": {
        "name": NAME,
        "description": (
            "Read a demo Key Vault secret. Only names matching 'demo-*' are "
            "allowed. Returns the secret value on success."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "Secret name (must match 'demo-*'). Default: demo-flag.",
                },
            },
            "additionalProperties": False,
        },
    },
}


def _read(name: str) -> dict[str, Any]:
    from clients import secret_client

    secret = secret_client().get_secret(name)
    return {"name": name, "value": secret.value}


async def invoke(args: dict) -> dict:
    if not IS_ENABLED:
        return {"disabled": True, "hint": "Set AGENT_FEATURE_KV_SECRET=true and redeploy."}
    name = args.get("name") or settings.demo_secret_name
    if not _ALLOWED_SECRET_RE.match(name):
        return {"error": f"secret name '{name}' is not allowlisted (must match 'demo-*')"}
    return await asyncio.to_thread(_read, name)
