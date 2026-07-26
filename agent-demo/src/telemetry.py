"""Azure Monitor / OpenTelemetry wiring for the demo agent.

Wraps ``azure.monitor.opentelemetry.configure_azure_monitor`` so callers can
call ``setup_telemetry()`` once at startup with no arguments. Safe to call
even when tracing is disabled or the connection string is unset - it
becomes a no-op that logs the reason to stdout.
"""

from __future__ import annotations

import logging
import os

from config import settings

_logger = logging.getLogger("demo-agent.telemetry")


def setup_telemetry() -> bool:
    """Configure App Insights export. Returns True if telemetry is live."""

    if not settings.feature_tracing:
        _logger.info("Telemetry disabled by AGENT_FEATURE_TRACING=false")
        return False

    if not settings.applicationinsights_connection_string:
        _logger.warning(
            "APPLICATIONINSIGHTS_CONNECTION_STRING is unset; telemetry not configured. "
            "The Foundry Agent Service normally injects this from the appinsightsconn "
            "project connection - if it's missing, the agent is running outside Foundry."
        )
        return False

    # Imported lazily so pytest / smoke runs don't pay the module cost when
    # tracing is turned off.
    from azure.identity import DefaultAzureCredential
    from azure.monitor.opentelemetry import configure_azure_monitor
    from opentelemetry.sdk.resources import SERVICE_NAME, Resource

    # The App Insights resource is provisioned with local_authentication_disabled=true,
    # so the ingestion endpoint rejects instrumentation-key auth (401 Unauthorized).
    # We MUST hand configure_azure_monitor an AAD token credential; without one it
    # silently falls back to key-based auth and every export attempt fails.
    #
    # In the hosted container, DefaultAzureCredential resolves the App Service
    # managed identity materialized for the current agent version. Terraform
    # cannot grant that post-created identity, so the azd postdeploy hook grants
    # and verifies Monitoring Metrics Publisher on the App Insights component.
    credential = DefaultAzureCredential()
    service_name = os.getenv("FOUNDRY_AGENT_NAME", "acme-demo-agent")

    configure_azure_monitor(
        connection_string=settings.applicationinsights_connection_string,
        credential=credential,
        resource=Resource.create({SERVICE_NAME: service_name}),
    )
    _logger.info(
        "Azure Monitor telemetry configured with AAD credential (service.name=%s)",
        service_name,
    )
    return True
