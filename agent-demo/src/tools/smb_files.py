"""files - list / read / write on the demo-share SMB file share."""

from __future__ import annotations

import asyncio
import base64
from typing import Any

from config import settings

NAME = "files"
IS_ENABLED = settings.feature_smb_files

SPEC = {
    "type": "function",
    "function": {
        "name": NAME,
        "description": (
            "SMB file share tool over demo-share. Actions: 'list' enumerates a "
            "directory; 'read' returns a file's content as base64; 'write' "
            "creates/overwrites a file from base64 content."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": ["list", "read", "write"]},
                "path": {
                    "type": "string",
                    "description": "File or directory path. For 'list', default is '/'.",
                },
                "contentBase64": {
                    "type": "string",
                    "description": "Base64 payload for 'write'.",
                },
            },
            "required": ["action"],
            "additionalProperties": False,
        },
    },
}


def _share():
    from clients import share_service

    return share_service().get_share_client(settings.demo_file_share)


def _list(path: str) -> dict[str, Any]:
    directory = _share().get_directory_client(directory_path=path.strip("/"))
    entries = []
    for item in directory.list_directories_and_files():
        entries.append({"name": item["name"], "isDirectory": bool(item.get("is_directory"))})
    return {"share": settings.demo_file_share, "path": path, "count": len(entries), "entries": entries}


def _read(path: str) -> dict[str, Any]:
    file_client = _share().get_file_client(file_path=path.strip("/"))
    data = file_client.download_file().readall()
    return {"path": path, "bytes": len(data), "contentBase64": base64.b64encode(data).decode()}


def _write(path: str, content_b64: str) -> dict[str, Any]:
    data = base64.b64decode(content_b64)
    file_client = _share().get_file_client(file_path=path.strip("/"))
    file_client.upload_file(data)
    return {"ok": True, "path": path, "bytes": len(data)}


async def invoke(args: dict) -> dict:
    if not IS_ENABLED:
        return {"disabled": True, "hint": "Set AGENT_FEATURE_SMB_FILES=true and redeploy."}
    action = args.get("action")
    if action == "list":
        return await asyncio.to_thread(_list, args.get("path") or "/")
    if action == "read":
        path = args.get("path")
        if not path:
            return {"error": "path is required for 'read'"}
        return await asyncio.to_thread(_read, path)
    if action == "write":
        path = args.get("path")
        content_b64 = args.get("contentBase64")
        if not path or content_b64 is None:
            return {"error": "path and contentBase64 are required for 'write'"}
        return await asyncio.to_thread(_write, path, content_b64)
    return {"error": f"unknown action: {action}"}
