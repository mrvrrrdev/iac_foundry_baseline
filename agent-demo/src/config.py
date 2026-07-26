"""Env-driven configuration for the Acme AI Foundry demo agent.

Every setting is optional at import time so the app can boot even when a
capability is intentionally disabled or its env var is missing. Individual
tool modules check ``settings.feature_<name>`` before importing / using their
resource endpoints.

The single global ``settings`` instance is imported everywhere - do not
construct additional Settings copies.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Optional

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


def _envbool(default: bool = True):
    """Return a Field factory for `AGENT_FEATURE_*` toggles that default true."""
    return Field(default=default)


class Settings(BaseSettings):
    """All environment inputs. Instantiated once as the module-global ``settings``."""

    model_config = SettingsConfigDict(env_file=None, case_sensitive=False, extra="ignore")

    # ---- Feature toggles (default on) --------------------------------------
    feature_tracing: bool = Field(
        default=True,
        validation_alias=AliasChoices("ACME_FEATURE_TRACING", "AGENT_FEATURE_TRACING"),
    )
    feature_healthcheck: bool = Field(
        default=True,
        validation_alias=AliasChoices("ACME_FEATURE_HEALTHCHECK", "AGENT_FEATURE_HEALTHCHECK"),
    )
    feature_memory_cosmos: bool = Field(
        default=True,
        validation_alias=AliasChoices("ACME_FEATURE_MEMORY_COSMOS", "AGENT_FEATURE_MEMORY_COSMOS"),
    )
    feature_kb_search: bool = Field(
        default=True,
        validation_alias=AliasChoices("ACME_FEATURE_KB_SEARCH", "AGENT_FEATURE_KB_SEARCH"),
    )
    feature_blob: bool = Field(
        default=True,
        validation_alias=AliasChoices("ACME_FEATURE_BLOB", "AGENT_FEATURE_BLOB"),
    )
    feature_kv_secret: bool = Field(
        default=True,
        validation_alias=AliasChoices("ACME_FEATURE_KV_SECRET", "AGENT_FEATURE_KV_SECRET"),
    )
    feature_smb_files: bool = Field(
        default=True,
        validation_alias=AliasChoices("ACME_FEATURE_SMB_FILES", "AGENT_FEATURE_SMB_FILES"),
    )
    feature_chat_gpt5: bool = Field(
        default=True,
        validation_alias=AliasChoices("ACME_FEATURE_CHAT_GPT5", "AGENT_FEATURE_CHAT_GPT5"),
    )

    seed_on_startup: bool = Field(
        default=True,
        validation_alias=AliasChoices("ACME_SEED_ON_STARTUP", "AGENT_SEED_ON_STARTUP"),
    )

    # ---- Azure identity / context ------------------------------------------
    subscription_id: Optional[str] = Field(default=None, alias="AZURE_SUBSCRIPTION_ID")
    tenant_id: Optional[str] = Field(default=None, alias="AZURE_TENANT_ID")
    location: Optional[str] = Field(default=None, alias="AZURE_LOCATION")
    resource_group: Optional[str] = Field(default=None, alias="AZURE_RESOURCE_GROUP")

    # ---- Foundry -----------------------------------------------------------
    ai_account_name: Optional[str] = Field(default=None, alias="AZURE_AI_ACCOUNT_NAME")
    ai_project_name: Optional[str] = Field(default=None, alias="AZURE_AI_PROJECT_NAME")
    ai_project_endpoint: Optional[str] = Field(default=None, alias="AZURE_AI_PROJECT_ENDPOINT")
    ai_account_endpoint: Optional[str] = Field(default=None, alias="AZURE_AI_ACCOUNT_ENDPOINT")
    chat_deployment: str = Field(default="gpt-5", alias="AZURE_AI_CHAT_DEPLOYMENT")
    embedding_deployment: str = Field(
        default="text-embedding-3-large", alias="AZURE_AI_EMBEDDING_DEPLOYMENT"
    )

    # ---- ACR ---------------------------------------------------------------
    container_registry_name: Optional[str] = Field(
        default=None, alias="AZURE_CONTAINER_REGISTRY_NAME"
    )
    agent_image_uri: Optional[str] = Field(default=None, alias="AGENT_IMAGE_URI")

    # ---- Cosmos DB ---------------------------------------------------------
    cosmos_endpoint: Optional[str] = Field(default=None, alias="AZURE_COSMOS_ENDPOINT")
    cosmos_database: str = Field(default="demo", alias="AZURE_COSMOS_DATABASE")
    cosmos_memory_container: str = Field(default="memory", alias="AZURE_COSMOS_MEMORY_CONTAINER")

    # ---- AI Search ---------------------------------------------------------
    search_endpoint: Optional[str] = Field(default=None, alias="AZURE_SEARCH_ENDPOINT")
    search_index: str = Field(default="demo-kb", alias="AZURE_SEARCH_INDEX")

    # ---- Storage -----------------------------------------------------------
    storage_account_name: Optional[str] = Field(default=None, alias="AZURE_STORAGE_ACCOUNT_NAME")
    storage_blob_endpoint: Optional[str] = Field(default=None, alias="AZURE_STORAGE_BLOB_ENDPOINT")
    storage_file_endpoint: Optional[str] = Field(default=None, alias="AZURE_STORAGE_FILE_ENDPOINT")
    demo_blob_container: str = Field(default="demo-data", alias="AZURE_STORAGE_DEMO_CONTAINER")
    demo_file_share: str = Field(default="demo-share", alias="AZURE_STORAGE_DEMO_SHARE")

    # ---- Key Vault ---------------------------------------------------------
    key_vault_uri: Optional[str] = Field(default=None, alias="AZURE_KEY_VAULT_URI")
    demo_secret_name: str = Field(default="demo-flag", alias="AZURE_KV_DEMO_SECRET_NAME")

    # ---- Telemetry ---------------------------------------------------------
    applicationinsights_connection_string: Optional[str] = Field(
        default=None, alias="APPLICATIONINSIGHTS_CONNECTION_STRING"
    )


@lru_cache(maxsize=1)
def _load() -> Settings:
    return Settings()  # type: ignore[call-arg]


settings: Settings = _load()
