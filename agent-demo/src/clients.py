"""Shared singletons - credential and cached SDK clients.

Each accessor is guarded so the module imports cleanly even when the
corresponding endpoint env var is unset (a capability is off). Callers should
check the feature flag on ``config.settings`` before invoking.

``DefaultAzureCredential`` picks up the Foundry-assigned managed identity
in-container automatically. Locally it falls back to ``az login``.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Optional

from azure.identity import DefaultAzureCredential


@lru_cache(maxsize=1)
def credential() -> DefaultAzureCredential:
    # In-container the Foundry-assigned managed identity is picked up
    # automatically. Locally, DefaultAzureCredential falls back to `az login`.
    return DefaultAzureCredential()


@lru_cache(maxsize=1)
def cosmos_client():
    from azure.cosmos import CosmosClient
    from config import settings

    if not settings.cosmos_endpoint:
        raise RuntimeError("AZURE_COSMOS_ENDPOINT is not set")
    return CosmosClient(url=settings.cosmos_endpoint, credential=credential())


@lru_cache(maxsize=1)
def blob_service():
    from azure.storage.blob import BlobServiceClient
    from config import settings

    if not settings.storage_blob_endpoint:
        raise RuntimeError("AZURE_STORAGE_BLOB_ENDPOINT is not set")
    return BlobServiceClient(account_url=settings.storage_blob_endpoint, credential=credential())


@lru_cache(maxsize=1)
def share_service():
    from azure.storage.fileshare import ShareServiceClient
    from config import settings

    if not settings.storage_file_endpoint:
        raise RuntimeError("AZURE_STORAGE_FILE_ENDPOINT is not set")
    # NB: SMB file shares over AAD require token_intent="backup"; the module
    # accepts a positional credential and negotiates automatically for
    # ShareServiceClient.
    return ShareServiceClient(
        account_url=settings.storage_file_endpoint,
        credential=credential(),
        token_intent="backup",
    )


@lru_cache(maxsize=1)
def secret_client():
    from azure.keyvault.secrets import SecretClient
    from config import settings

    if not settings.key_vault_uri:
        raise RuntimeError("AZURE_KEY_VAULT_URI is not set")
    return SecretClient(vault_url=settings.key_vault_uri, credential=credential())


@lru_cache(maxsize=1)
def search_index_client():
    from azure.search.documents.indexes import SearchIndexClient
    from config import settings

    if not settings.search_endpoint:
        raise RuntimeError("AZURE_SEARCH_ENDPOINT is not set")
    return SearchIndexClient(endpoint=settings.search_endpoint, credential=credential())


@lru_cache(maxsize=1)
def search_client():
    from azure.search.documents import SearchClient
    from config import settings

    if not settings.search_endpoint:
        raise RuntimeError("AZURE_SEARCH_ENDPOINT is not set")
    return SearchClient(
        endpoint=settings.search_endpoint,
        index_name=settings.search_index,
        credential=credential(),
    )


@lru_cache(maxsize=1)
def openai_client():
    """Foundry-hosted OpenAI-compatible client for embeddings / chat completions.

    Uses the account-scoped endpoint (``AZURE_AI_ACCOUNT_ENDPOINT``) with a
    bearer token from the shared credential. Falls back to the project
    endpoint if only that one is set.
    """
    from openai import AzureOpenAI
    from azure.identity import get_bearer_token_provider
    from config import settings

    endpoint: Optional[str] = settings.ai_account_endpoint or settings.ai_project_endpoint
    if not endpoint:
        raise RuntimeError(
            "Neither AZURE_AI_ACCOUNT_ENDPOINT nor AZURE_AI_PROJECT_ENDPOINT is set"
        )
    token_provider = get_bearer_token_provider(
        credential(), "https://cognitiveservices.azure.com/.default"
    )
    return AzureOpenAI(
        azure_endpoint=endpoint.rstrip("/"),
        api_version="2024-10-21",
        azure_ad_token_provider=token_provider,
    )
