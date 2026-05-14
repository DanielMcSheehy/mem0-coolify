# Build Mem0 REST server from source.
#
# Why not `FROM mem0/mem0-api-server:latest`?
# That image is published arm64-only on Docker Hub, which breaks amd64 hosts
# (the common Coolify case) with: "no match for platform in manifest".
# Building from source gives us a clean multi-arch image.

FROM python:3.12-slim

WORKDIR /app

# System deps: build tools, libpq for psycopg, git for source pull.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    git \
  && rm -rf /var/lib/apt/lists/*

# Pull the Mem0 server source. Sparse-checkout to just the /server subdir.
ARG MEM0_REF=main
RUN git clone --depth 1 --branch ${MEM0_REF} --filter=blob:none --sparse \
      https://github.com/mem0ai/mem0.git /tmp/mem0 \
 && cd /tmp/mem0 && git sparse-checkout set server \
 && cp -r /tmp/mem0/server/. /app/ \
 && rm -rf /tmp/mem0

# Install server requirements + the patched deps that some image versions miss.
RUN pip install --no-cache-dir -r requirements.txt \
 && pip install --no-cache-dir \
      "psycopg[binary]>=3.1" \
      "neo4j>=5.0"

EXPOSE 8000

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Run alembic migrations against mem0_app, then start the server.
# Alembic creates the users / api_keys / refresh_token_jti tables that the
# auth layer reads on every request.
CMD ["sh", "-c", "alembic upgrade head && uvicorn main:app --host 0.0.0.0 --port 8000"]
