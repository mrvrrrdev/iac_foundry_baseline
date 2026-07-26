"""Acme adjacent-services demo agent using the Foundry Responses protocol."""
from __future__ import annotations
import asyncio
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
_logger = logging.getLogger("demo-agent")
_logger.info("Acme adjacent-services demo agent starting")

# Wire Azure Monitor with an AAD credential before constructing the agentserver
# host. The host's default observability callback does not accept an Azure
# credential, while this environment requires Entra-authenticated ingestion.
# The host can still add its Foundry enrichment processors to the provider.
from telemetry import setup_telemetry  # noqa: E402
setup_telemetry()

from azure.ai.agentserver.responses import (  # noqa: E402
    CreateResponse,
    ResponseContext,
    ResponsesAgentServerHost,
    TextResponse,
)
from bootstrap import ensure_seeded  # noqa: E402
from orchestration import respond  # noqa: E402
from tools import registered_tools  # noqa: E402

app = ResponsesAgentServerHost()


@app.response_handler
async def handler(
    request: CreateResponse,
    context: ResponseContext,
    cancellation_signal: asyncio.Event,
) -> TextResponse:
    text = await context.get_input_text()
    _logger.info("received input: %r", (text or "")[:200])
    response_text = await respond(text or "", cancellation_signal)
    return TextResponse(context, request, text=response_text)


if __name__ == "__main__":
    _logger.info("enabled tools: %s", [entry["name"] for entry in registered_tools()])
    ensure_seeded()
    app.run()