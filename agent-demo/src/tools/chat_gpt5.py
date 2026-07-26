"""chat - direct chat completion against the Foundry gpt-5 deployment.

Rarely useful on its own (the parent agent already talks to gpt-5), but keeps
the demo's tool matrix symmetrical and gives the smoke script a "raw model"
target that doesn't require any adjacent service.
"""

from __future__ import annotations

import asyncio
from typing import Any

from config import settings

NAME = "chat"
IS_ENABLED = settings.feature_chat_gpt5

SPEC = {
    "type": "function",
    "function": {
        "name": NAME,
        "description": (
            "Direct chat completion against the Foundry gpt-5 deployment. Use "
            "for a raw model round-trip when demonstrating the underlying model."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "prompt": {"type": "string", "description": "Prompt text."},
                "maxTokens": {"type": "integer", "minimum": 1, "maximum": 4000, "default": 200},
            },
            "required": ["prompt"],
            "additionalProperties": False,
        },
    },
}


def _complete(prompt: str, max_tokens: int) -> dict[str, Any]:
    from clients import openai_client

    resp = openai_client().chat.completions.create(
        model=settings.chat_deployment,
        messages=[{"role": "user", "content": prompt}],
        max_completion_tokens=max_tokens,
    )
    choice = resp.choices[0]
    return {
        "model": settings.chat_deployment,
        "finish_reason": choice.finish_reason,
        "content": choice.message.content,
    }


async def invoke(args: dict) -> dict:
    if not IS_ENABLED:
        return {"disabled": True, "hint": "Set AGENT_FEATURE_CHAT_GPT5=true and redeploy."}
    prompt = args.get("prompt")
    if not prompt:
        return {"error": "prompt is required"}
    max_tokens = int(args.get("maxTokens") or 200)
    return await asyncio.to_thread(_complete, prompt, max_tokens)
