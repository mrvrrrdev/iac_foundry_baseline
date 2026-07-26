"""Deterministic smoke dispatch and model-driven tool orchestration."""

from __future__ import annotations

import asyncio
import json
from typing import Any

from config import settings
from tools import ToolEntry, registered_map, registered_tools

SMOKE_PREFIX = "SMOKE_RESULT:"
_MAX_TOOL_ROUNDS = 5
_SYSTEM_PROMPT = (
    "You are the Acme AI Foundry environment demo agent. Use the available tools "
    "when they can answer the request. Report tool failures clearly and never invent "
    "results."
)


def _envelope(capability: str, status: str, result: Any = None, error: str | None = None) -> str:
    payload = {
        "capability": capability,
        "status": status,
        "result": result,
        "error": error,
    }
    return SMOKE_PREFIX + json.dumps(payload, separators=(",", ":"), default=str)


async def _invoke(entry: ToolEntry, args: dict[str, Any]) -> dict[str, Any]:
    return await entry["invoke"](args)


async def run_smoke(command: str, tool_map: dict[str, ToolEntry] | None = None) -> str | None:
    normalized = command.strip().lower()
    if not normalized.startswith("smoke:"):
        return None

    capability = normalized.removeprefix("smoke:").strip()
    tools = tool_map if tool_map is not None else registered_map()
    tool_name = {
        "healthcheck": "healthcheck",
        "memory": "memory",
        "kb": "kb",
        "blob": "blob",
        "kv": "kv",
        "files": "files",
        "chat": "chat",
    }.get(capability)
    if tool_name is None:
        return _envelope(capability or "unknown", "FAIL", error="unknown smoke capability")
    if tool_name not in tools:
        return _envelope(capability, "SKIP", error="feature disabled")

    try:
        if capability == "healthcheck":
            result = await _invoke(tools[tool_name], {})
            status = "FAIL" if result.get("summary", {}).get("fail", 0) else "PASS"
            return _envelope(capability, status, result=result)

        if capability == "memory":
            await _invoke(
                tools[tool_name],
                {"action": "remember", "userId": "smoke", "key": "favoriteColor", "value": "teal"},
            )
            result = await _invoke(
                tools[tool_name],
                {"action": "recall", "userId": "smoke", "key": "favoriteColor"},
            )
            passed = any(fact.get("value") == "teal" for fact in result.get("facts", []))
        elif capability == "kb":
            result = await _invoke(tools[tool_name], {"question": "capability host", "top": 1})
            passed = bool(result.get("hits") and result["hits"][0].get("title"))
        elif capability == "blob":
            result = await _invoke(tools[tool_name], {"action": "list"})
            passed = any(item.get("name") == "welcome.txt" for item in result.get("blobs", []))
        elif capability == "kv":
            result = await _invoke(tools[tool_name], {"name": "demo-flag"})
            passed = bool(result.get("value"))
            result = {"name": result.get("name"), "value_present": passed}
        elif capability == "files":
            result = await _invoke(tools[tool_name], {"action": "list", "path": "/"})
            passed = any(item.get("name") == "hello.txt" for item in result.get("entries", []))
        else:
            result = await _invoke(
                tools[tool_name],
                {"prompt": "Respond with exactly the word pong.", "maxTokens": 200},
            )
            passed = (result.get("content") or "").strip().lower() == "pong"

        return _envelope(
            capability,
            "PASS" if passed else "FAIL",
            result=result,
            error=None if passed else "semantic smoke assertion failed",
        )
    except Exception as ex:  # noqa: BLE001 - convert dependency errors into test output
        return _envelope(capability, "FAIL", error=f"{type(ex).__name__}: {ex}")


def _complete(messages: list[dict[str, Any]], specs: list[dict[str, Any]]) -> Any:
    from clients import openai_client

    return openai_client().chat.completions.create(
        model=settings.chat_deployment,
        messages=messages,
        tools=specs or None,
    )


async def run_interactive(text: str, cancellation_signal: asyncio.Event) -> str:
    entries = registered_tools()
    tools = {entry["name"]: entry for entry in entries}
    messages: list[dict[str, Any]] = [
        {"role": "system", "content": _SYSTEM_PROMPT},
        {"role": "user", "content": text},
    ]
    specs = [entry["spec"] for entry in entries]

    for _ in range(_MAX_TOOL_ROUNDS):
        if cancellation_signal.is_set():
            return "Request cancelled."

        response = await asyncio.to_thread(_complete, messages, specs)
        message = response.choices[0].message
        tool_calls = list(message.tool_calls or [])
        messages.append(
            {
                "role": "assistant",
                "content": message.content,
                "tool_calls": [call.model_dump() for call in tool_calls] if tool_calls else None,
            }
        )
        if not tool_calls:
            return message.content or "The model returned no response."

        for call in tool_calls:
            if cancellation_signal.is_set():
                return "Request cancelled."
            try:
                args = json.loads(call.function.arguments or "{}")
                if not isinstance(args, dict):
                    raise ValueError("tool arguments must be a JSON object")
                entry = tools.get(call.function.name)
                if entry is None:
                    raise ValueError(f"unknown tool: {call.function.name}")
                result = await _invoke(entry, args)
            except Exception as ex:  # noqa: BLE001 - return tool errors to the model
                result = {"error": f"{type(ex).__name__}: {ex}"}
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": json.dumps(result, default=str),
                }
            )

    return "The request exceeded the maximum number of tool-call rounds."


async def respond(text: str, cancellation_signal: asyncio.Event) -> str:
    smoke_result = await run_smoke(text)
    if smoke_result is not None:
        return smoke_result
    return await run_interactive(text, cancellation_signal)