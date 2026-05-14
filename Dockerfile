# Patches the official Mem0 server image to add deps that are missing
# in some published versions (psycopg, langchain-neo4j). Harmless if already present.
FROM mem0/mem0-api-server:latest

RUN pip install --no-cache-dir \
    "psycopg[binary]>=3.1" \
    "langchain-neo4j>=0.1.0" \
    "neo4j>=5.0"

# Inherit CMD/ENTRYPOINT from the base image
