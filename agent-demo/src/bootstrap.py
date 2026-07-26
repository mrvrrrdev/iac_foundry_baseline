"""In-container first-run bootstrap.

Runs on FastAPI startup (see main.py) when ``AGENT_SEED_ON_STARTUP=true``.
Idempotent: writes a marker blob (``demo-data/.seeded``) after a successful
pass, and subsequent boots see the marker and no-op quickly.

What it seeds (each step is guarded by its feature flag, so disabling a
capability also disables its seeding):

* AI Search index ``demo-kb`` (vector-enabled schema, 3072 dims) + upload of
  every bundled markdown file under ``seed/kb_docs/``. Each doc becomes one
  document in the index (small demo - no chunking).
* Blob ``demo-data/welcome.txt`` with a short greeting.
* File ``demo-share/hello.txt`` with the same greeting.

Runs under the Foundry-assigned managed identity, which already has:

* Search Index Data Contributor + Search Service Contributor
* Storage Blob Data Contributor + Storage File Data Privileged Contributor

...so no additional RBAC is required.
"""

from __future__ import annotations

import logging
import pathlib
from typing import Iterable

from config import settings

_logger = logging.getLogger("demo-agent.bootstrap")

_MARKER_BLOB = ".seeded"
_GREETING = (
    "Hello from the Acme AI Foundry demo agent. This file was written by "
    "src/bootstrap.py on the container's first boot to prove that "
    "passwordless data-plane access is working end to end.\n"
)


# --------------------------------------------------------------------------- #
# helpers                                                                     #
# --------------------------------------------------------------------------- #

def _seeded_marker_exists() -> bool:
    """Return True when the seed marker blob exists (fast path for repeat boots)."""
    if not settings.feature_blob or not settings.storage_blob_endpoint:
        return False
    from clients import blob_service

    try:
        container = blob_service().get_container_client(settings.demo_blob_container)
        return container.get_blob_client(_MARKER_BLOB).exists()
    except Exception as ex:  # noqa: BLE001
        _logger.warning("Could not read seed marker (will attempt seeding): %s", ex)
        return False


def _write_seeded_marker() -> None:
    from clients import blob_service

    container = blob_service().get_container_client(settings.demo_blob_container)
    container.upload_blob(name=_MARKER_BLOB, data=b"", overwrite=True)


# --------------------------------------------------------------------------- #
# AI Search index seeding                                                     #
# --------------------------------------------------------------------------- #

def _create_search_index_if_missing() -> bool:
    from azure.core.exceptions import ResourceNotFoundError
    from azure.search.documents.indexes.models import (
        HnswAlgorithmConfiguration,
        HnswParameters,
        SearchField,
        SearchFieldDataType,
        SearchIndex,
        VectorSearch,
        VectorSearchAlgorithmKind,
        VectorSearchProfile,
    )

    from clients import search_index_client

    client = search_index_client()
    try:
        client.get_index(settings.search_index)
        _logger.info("AI Search index %r already exists", settings.search_index)
        return False
    except ResourceNotFoundError:
        pass

    fields = [
        SearchField(name="id", type=SearchFieldDataType.String, key=True),
        SearchField(name="title", type=SearchFieldDataType.String, searchable=True),
        SearchField(name="content", type=SearchFieldDataType.String, searchable=True),
        SearchField(name="source", type=SearchFieldDataType.String, filterable=True),
        SearchField(
            name="contentVector",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=3072,  # text-embedding-3-large default
            vector_search_profile_name="default-vector-profile",
        ),
    ]
    vector_search = VectorSearch(
        algorithms=[
            HnswAlgorithmConfiguration(
                name="default-hnsw",
                kind=VectorSearchAlgorithmKind.HNSW,
                parameters=HnswParameters(m=4, ef_construction=400, ef_search=500),
            )
        ],
        profiles=[VectorSearchProfile(name="default-vector-profile", algorithm_configuration_name="default-hnsw")],
    )
    client.create_index(
        SearchIndex(name=settings.search_index, fields=fields, vector_search=vector_search)
    )
    _logger.info("Created AI Search index %r", settings.search_index)
    return True


def _kb_docs() -> Iterable[pathlib.Path]:
    root = pathlib.Path(__file__).parent / "seed" / "kb_docs"
    if not root.exists():
        return []
    return sorted(root.glob("*.md"))


def _seed_kb_documents() -> int:
    from clients import openai_client, search_client

    docs = list(_kb_docs())
    if not docs:
        _logger.warning("No KB documents found under seed/kb_docs/; nothing to embed")
        return 0

    client = openai_client()
    payload = []
    for doc in docs:
        content = doc.read_text(encoding="utf-8")
        title = content.splitlines()[0].lstrip("# ").strip() if content else doc.stem
        embedding = client.embeddings.create(
            model=settings.embedding_deployment, input=[content]
        ).data[0].embedding
        payload.append(
            {
                "id": doc.stem,
                "title": title,
                "content": content,
                "source": doc.name,
                "contentVector": embedding,
            }
        )

    search_client().upload_documents(documents=payload)
    _logger.info("Uploaded %d KB documents to AI Search", len(payload))
    return len(payload)


# --------------------------------------------------------------------------- #
# Blob + share seeding                                                        #
# --------------------------------------------------------------------------- #

def _seed_blob() -> None:
    from clients import blob_service

    container = blob_service().get_container_client(settings.demo_blob_container)
    container.upload_blob(name="welcome.txt", data=_GREETING.encode("utf-8"), overwrite=True)
    _logger.info("Uploaded welcome.txt to blob container %r", settings.demo_blob_container)


def _seed_share() -> None:
    from clients import share_service

    share = share_service().get_share_client(settings.demo_file_share)
    file_client = share.get_file_client(file_path="hello.txt")
    file_client.upload_file(_GREETING.encode("utf-8"))
    _logger.info("Wrote hello.txt to file share %r", settings.demo_file_share)


# --------------------------------------------------------------------------- #
# Entrypoint                                                                  #
# --------------------------------------------------------------------------- #

def ensure_seeded() -> dict:
    """Idempotent seed. Returns a small summary for the startup log."""

    if not settings.seed_on_startup:
        _logger.info("Seeding disabled (AGENT_SEED_ON_STARTUP=false)")
        return {"skipped": True, "reason": "AGENT_SEED_ON_STARTUP=false"}

    if _seeded_marker_exists():
        _logger.info("Seed marker present; skipping bootstrap")
        return {"skipped": True, "reason": "marker exists"}

    summary: dict = {"kb_index_created": False, "kb_docs_uploaded": 0, "blob": False, "share": False}

    if settings.feature_kb_search and settings.search_endpoint:
        try:
            summary["kb_index_created"] = _create_search_index_if_missing()
            summary["kb_docs_uploaded"] = _seed_kb_documents()
        except Exception as ex:  # noqa: BLE001
            _logger.exception("KB seed failed: %s", ex)
            summary["kb_error"] = f"{type(ex).__name__}: {ex}"

    if settings.feature_blob and settings.storage_blob_endpoint:
        try:
            _seed_blob()
            summary["blob"] = True
        except Exception as ex:  # noqa: BLE001
            _logger.exception("Blob seed failed: %s", ex)
            summary["blob_error"] = f"{type(ex).__name__}: {ex}"

    if settings.feature_smb_files and settings.storage_file_endpoint:
        try:
            _seed_share()
            summary["share"] = True
        except Exception as ex:  # noqa: BLE001
            _logger.exception("File share seed failed: %s", ex)
            summary["share_error"] = f"{type(ex).__name__}: {ex}"

    # Only write the marker when at least the blob path worked - otherwise the
    # marker itself would fail to write and repeated boots would keep retrying.
    if summary.get("blob"):
        try:
            _write_seeded_marker()
            summary["marker_written"] = True
        except Exception as ex:  # noqa: BLE001
            _logger.warning("Could not write seed marker: %s", ex)

    _logger.info("Bootstrap summary: %s", summary)
    return summary
