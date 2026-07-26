"""blob - list / upload / download in the demo-data container."""

from __future__ import annotations

import asyncio
import base64
from typing import Any

from config import settings

NAME = "blob"
IS_ENABLED = settings.feature_blob

SPEC = {
    "type": "function",
    "function": {
        "name": NAME,
        "description": (
            "Object storage tool over the demo-data blob container. Actions: "
            "'list' returns blob names; 'upload' writes a blob from base64 "
            "content; 'download' returns a blob's content as base64."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": ["list", "upload", "download"]},
                "name": {"type": "string", "description": "Blob name for upload/download."},
                "contentBase64": {
                    "type": "string",
                    "description": "Base64-encoded content for 'upload'.",
                },
                "contentType": {
                    "type": "string",
                    "description": "Content-Type for 'upload' (default text/plain).",
                },
            },
            "required": ["action"],
            "additionalProperties": False,
        },
    },
}


def _container():
    from clients import blob_service

    return blob_service().get_container_client(settings.demo_blob_container)


def _list() -> dict[str, Any]:
    blobs = [{"name": b.name, "size": b.size} for b in _container().list_blobs()]
    return {"container": settings.demo_blob_container, "count": len(blobs), "blobs": blobs}


def _upload(name: str, content_b64: str, content_type: str) -> dict[str, Any]:
    from azure.storage.blob import ContentSettings

    data = base64.b64decode(content_b64)
    _container().upload_blob(
        name=name,
        data=data,
        overwrite=True,
        content_settings=ContentSettings(content_type=content_type),
    )
    return {"ok": True, "name": name, "bytes": len(data)}


def _download(name: str) -> dict[str, Any]:
    downloader = _container().download_blob(name)
    data = downloader.readall()
    return {"name": name, "bytes": len(data), "contentBase64": base64.b64encode(data).decode()}


async def invoke(args: dict) -> dict:
    if not IS_ENABLED:
        return {"disabled": True, "hint": "Set AGENT_FEATURE_BLOB=true and redeploy."}
    action = args.get("action")
    if action == "list":
        return await asyncio.to_thread(_list)
    if action == "upload":
        name = args.get("name")
        content_b64 = args.get("contentBase64")
        if not name or content_b64 is None:
            return {"error": "name and contentBase64 are required for 'upload'"}
        content_type = args.get("contentType") or "text/plain"
        return await asyncio.to_thread(_upload, name, content_b64, content_type)
    if action == "download":
        name = args.get("name")
        if not name:
            return {"error": "name is required for 'download'"}
        return await asyncio.to_thread(_download, name)
    return {"error": f"unknown action: {action}"}
