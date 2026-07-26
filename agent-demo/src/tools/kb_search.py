"""kb - vector search against the demo-kb AI Search index."""

from __future__ import annotations

import asyncio
from typing import Any

from config import settings

NAME = "kb"
IS_ENABLED = settings.feature_kb_search

SPEC = {
    "type": "function",
    "function": {
        "name": NAME,
        "description": (
            "Query the demo knowledge base (an AI Search index seeded from short "
            "markdown docs bundled with the agent). Returns the top matching "
            "chunks with source doc id. Use for 'what do you know about X' / "
            "'what does the KB say about Y'."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "question": {"type": "string", "description": "Free-text question."},
                "top": {"type": "integer", "minimum": 1, "maximum": 20, "default": 5},
            },
            "required": ["question"],
            "additionalProperties": False,
        },
    },
}


def _embed(text: str) -> list[float]:
    from clients import openai_client

    resp = openai_client().embeddings.create(
        model=settings.embedding_deployment,
        input=[text],
    )
    return resp.data[0].embedding


def _search(question: str, top: int) -> dict[str, Any]:
    from azure.search.documents.models import VectorizedQuery

    from clients import search_client

    vector = _embed(question)
    results = search_client().search(
        search_text=None,
        vector_queries=[
            VectorizedQuery(vector=vector, k_nearest_neighbors=top, fields="contentVector")
        ],
        select=["id", "title", "content", "source"],
        top=top,
    )
    hits: list[dict[str, Any]] = []
    for r in results:
        hits.append(
            {
                "id": r.get("id"),
                "title": r.get("title"),
                "source": r.get("source"),
                "snippet": (r.get("content") or "")[:400],
                "score": r["@search.score"],
            }
        )
    return {"count": len(hits), "hits": hits}


async def invoke(args: dict) -> dict:
    if not IS_ENABLED:
        return {"disabled": True, "hint": "Set AGENT_FEATURE_KB_SEARCH=true and redeploy."}
    question = args.get("question")
    if not question:
        return {"error": "question is required"}
    top = int(args.get("top") or 5)
    return await asyncio.to_thread(_search, question, top)
