"""memory - persist / recall per-user facts in the demo Cosmos container."""

from __future__ import annotations

import asyncio
import time
import uuid
from typing import Any

from azure.cosmos import PartitionKey
from azure.cosmos.exceptions import CosmosResourceNotFoundError

from config import settings

NAME = "memory"
IS_ENABLED = settings.feature_memory_cosmos

SPEC = {
    "type": "function",
    "function": {
        "name": NAME,
        "description": (
            "Persistent memory for a user in Cosmos DB. Actions: 'remember' stores "
            "a fact (key/value) for a user; 'recall' returns matching facts. Use "
            "when the user says 'remember X' / 'what did I tell you about Y'."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": ["remember", "recall", "forget"]},
                "userId": {"type": "string", "description": "Stable user identifier."},
                "key": {"type": "string", "description": "Fact label (e.g. 'favoriteColor')."},
                "value": {
                    "type": "string",
                    "description": "Fact value, required for 'remember'.",
                },
            },
            "required": ["action", "userId"],
            "additionalProperties": False,
        },
    },
}


def _container():
    from clients import cosmos_client

    db = cosmos_client().get_database_client(settings.cosmos_database)
    return db.create_container_if_not_exists(
        id=settings.cosmos_memory_container,
        partition_key=PartitionKey(path="/userId"),
    )


def _remember(user_id: str, key: str, value: str) -> dict[str, Any]:
    doc = {
        "id": f"{key}::{uuid.uuid4()}",
        "userId": user_id,
        "kind": "fact",
        "key": key,
        "value": value,
        "createdAt": int(time.time()),
    }
    _container().upsert_item(doc)
    return {"ok": True, "id": doc["id"], "key": key, "value": value}


def _recall(user_id: str, key: str | None) -> dict[str, Any]:
    query = (
        'SELECT c.key, c["value"] AS factValue, c.createdAt '
        "FROM c WHERE c.userId = @u AND c.kind = 'fact'"
    )
    params: list[dict[str, Any]] = [{"name": "@u", "value": user_id}]
    if key:
        query += " AND c.key = @k"
        params.append({"name": "@k", "value": key})
    query += " ORDER BY c.createdAt DESC"
    items = list(
        _container().query_items(
            query=query,
            parameters=params,
            partition_key=user_id,
            max_item_count=50,
        )
    )
    facts = [
        {
            "key": item.get("key"),
            "value": item.get("factValue"),
            "createdAt": item.get("createdAt"),
        }
        for item in items
    ]
    return {"count": len(facts), "facts": facts}


def _forget(user_id: str, key: str) -> dict[str, Any]:
    # Best-effort: query & delete all matching docs.
    query = "SELECT c.id FROM c WHERE c.userId = @u AND c.key = @k"
    params = [{"name": "@u", "value": user_id}, {"name": "@k", "value": key}]
    ids = [
        item["id"]
        for item in _container().query_items(
            query=query, parameters=params, partition_key=user_id
        )
    ]
    for doc_id in ids:
        try:
            _container().delete_item(item=doc_id, partition_key=user_id)
        except CosmosResourceNotFoundError:
            pass
    return {"ok": True, "deleted": len(ids)}


async def invoke(args: dict) -> dict:
    if not IS_ENABLED:
        return {"disabled": True, "hint": "Set AGENT_FEATURE_MEMORY_COSMOS=true and redeploy."}
    action = args.get("action")
    user_id = args.get("userId")
    if not action or not user_id:
        return {"error": "action and userId are required"}

    if action == "remember":
        key = args.get("key")
        value = args.get("value")
        if not key or value is None:
            return {"error": "key and value are required for 'remember'"}
        return await asyncio.to_thread(_remember, user_id, key, value)

    if action == "recall":
        return await asyncio.to_thread(_recall, user_id, args.get("key"))

    if action == "forget":
        key = args.get("key")
        if not key:
            return {"error": "key is required for 'forget'"}
        return await asyncio.to_thread(_forget, user_id, key)

    return {"error": f"unknown action: {action}"}
