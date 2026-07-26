# Python 3.11 slim base. Built server-side via `docker.remoteBuild: true`
# on the `azure.ai.agent` service target in ../azure.yaml, so `azd deploy`
# runs an ACR remote build and the dev machine never needs a Docker daemon.
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# System deps: curl is handy for the container health probe; ca-certificates
# keeps outbound TLS to Azure endpoints happy.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first so image-layer caching benefits code-only edits.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App source.
COPY . .

# Non-root user (Foundry Agent Service also runs the container unprivileged).
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser /app
USER appuser

EXPOSE 8088

# Serve traffic with `azure-ai-agentserver-responses`, which starts its own
# Kestrel/uvicorn host on port ${PORT:-8088}. This is the port the Foundry
# Agent Service platform probes (see
# https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent#port).
CMD ["python", "main.py"]
