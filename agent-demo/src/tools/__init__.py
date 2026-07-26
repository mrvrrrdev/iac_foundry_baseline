"""Tool registry.

Each tool module defines:

* ``NAME``       - short function name exposed to the agent
* ``IS_ENABLED`` - bool, read from ``config.settings`` at import time
* ``SPEC``       - JSON-schema-ish OpenAI function-calling spec
* ``async def invoke(args: dict) -> dict``

``registered_tools()`` returns only the currently-enabled tools so the
FastAPI app can register them at startup and expose their SPECs to Foundry.
"""

from __future__ import annotations

from typing import Awaitable, Callable, Dict, List, TypedDict

from . import blob_files, chat_gpt5, healthcheck, kb_search, kv_secret, memory_cosmos, smb_files


class ToolEntry(TypedDict):
    name: str
    spec: dict
    invoke: Callable[[dict], Awaitable[dict]]


_ALL = [healthcheck, memory_cosmos, kb_search, blob_files, kv_secret, smb_files, chat_gpt5]


def registered_tools() -> List[ToolEntry]:
    """Return the enabled tools, in stable registration order."""
    entries: List[ToolEntry] = []
    for mod in _ALL:
        if getattr(mod, "IS_ENABLED", False):
            entries.append(
                ToolEntry(name=mod.NAME, spec=mod.SPEC, invoke=mod.invoke)  # type: ignore[arg-type]
            )
    return entries


def registered_map() -> Dict[str, ToolEntry]:
    return {t["name"]: t for t in registered_tools()}
