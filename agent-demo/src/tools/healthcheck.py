"""healthcheck tool - PASS/FAIL/SKIP matrix for configured dependencies."""

from __future__ import annotations

import asyncio
import time
from typing import Any, Callable

from config import settings


class _SkippedCheck(Exception):
    pass

NAME = "healthcheck"
IS_ENABLED = settings.feature_healthcheck

SPEC = {
    "type": "function",
    "function": {
        "name": NAME,
        "description": (
            "Ping every configured dependency (Foundry, Cosmos DB, AI Search, Key "
            "Vault, Blob storage, SMB file share, ACR) and return a PASS/FAIL "
            "matrix with per-dependency latency in milliseconds. Use whenever the "
            "user asks for an environment / health / smoke check."
        ),
        "parameters": {"type": "object", "properties": {}, "additionalProperties": False},
    },
}


def _time(fn: Callable[[], Any]) -> tuple[str, int, str | None]:
    start = time.perf_counter()
    try:
        fn()
    except _SkippedCheck as ex:
        return "SKIP", int((time.perf_counter() - start) * 1000), str(ex)
    except Exception as ex:  # noqa: BLE001 - surface any error into the matrix
        return "FAIL", int((time.perf_counter() - start) * 1000), f"{type(ex).__name__}: {ex}"
    return "PASS", int((time.perf_counter() - start) * 1000), None


def _check_foundry() -> None:
    from clients import openai_client

    for attempt in range(3):
        try:
            _ = openai_client().chat.completions.create(
                model=settings.chat_deployment,
                messages=[{"role": "user", "content": "ping"}],
                max_completion_tokens=16,
            )
            return
        except Exception:  # noqa: BLE001 - retry transient control-plane authorization
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def _check_cosmos() -> None:
    if not settings.feature_memory_cosmos:
        raise _SkippedCheck("feature disabled")
    from clients import cosmos_client

    db = cosmos_client().get_database_client(settings.cosmos_database)
    _ = db.read()


def _check_search() -> None:
    if not settings.feature_kb_search:
        raise _SkippedCheck("feature disabled")
    from clients import search_index_client

    _ = search_index_client().get_service_statistics()


def _check_kv() -> None:
    if not settings.feature_kv_secret:
        raise _SkippedCheck("feature disabled")
    from clients import secret_client

    _ = secret_client().get_secret(settings.demo_secret_name)


def _check_blob() -> None:
    if not settings.feature_blob:
        raise _SkippedCheck("feature disabled")
    from clients import blob_service

    container = blob_service().get_container_client(settings.demo_blob_container)
    # list up to 1 blob just to prove data-plane access + RBAC path.
    _ = next(iter(container.list_blobs(results_per_page=1).by_page()), None)


def _check_share() -> None:
    if not settings.feature_smb_files:
        raise _SkippedCheck("feature disabled")
    from clients import share_service

    share = share_service().get_share_client(settings.demo_file_share)
    _ = list(share.list_directories_and_files())


def _check_acr() -> tuple[str, int, str | None]:
    """No data-plane call - just reports the image URI the container is running under."""
    if not settings.container_registry_name and not settings.agent_image_uri:
        return "SKIP", 0, "AZURE_CONTAINER_REGISTRY_NAME / AGENT_IMAGE_URI unset"
    return "PASS", 0, None


async def invoke(_args: dict) -> dict:
    def run_all() -> list[dict]:
        checks: list[tuple[str, Callable[[], Any]]] = [
            ("foundry", _check_foundry),
            ("cosmos", _check_cosmos),
            ("search", _check_search),
            ("keyvault", _check_kv),
            ("blob", _check_blob),
            ("files", _check_share),
        ]
        results: list[dict] = []
        for name, fn in checks:
            status, latency_ms, err = _time(fn)
            results.append({"name": name, "status": status, "latency_ms": latency_ms, "error": err})

        acr_status, acr_latency, acr_err = _check_acr()
        results.append(
            {
                "name": "acr",
                "status": acr_status,
                "latency_ms": acr_latency,
                "error": acr_err,
                "image_uri": settings.agent_image_uri,
            }
        )
        return results

    results = await asyncio.to_thread(run_all)
    summary = {
        "pass": sum(1 for r in results if r["status"] == "PASS"),
        "fail": sum(1 for r in results if r["status"] == "FAIL"),
        "skip": sum(1 for r in results if r["status"] == "SKIP"),
        "total": len(results),
    }
    return {"summary": summary, "results": results}
