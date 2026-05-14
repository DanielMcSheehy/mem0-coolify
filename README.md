# Mem0 on Coolify

Self-hosted Mem0 (AI memory backend) for use as a shared knowledge store across
Hermes, spacebot.sh, Claude Code, OpenClaw, and local dev.

## Stack

| Service  | Image                       | Purpose                                  |
| -------- | --------------------------- | ---------------------------------------- |
| mem0     | `mem0/mem0-api-server` + patches | REST API on port 8000               |
| postgres | `ankane/pgvector`           | Vector + metadata store                  |
| neo4j    | `neo4j:5-community`         | Graph relationships between memories     |

Total RAM footprint: ~3 GB. Fits comfortably on a small Coolify VPS.

## Deploy on Coolify

1. **Create a new resource** → **Docker Compose**.
2. Point it at this repo (or paste the `docker-compose.yaml` + `Dockerfile` directly).
3. In Coolify's **Environment Variables** tab, paste the contents of `.env.example`
   and replace every `REPLACE_ME` with real values:
   ```bash
   # generate secrets locally
   openssl rand -base64 32   # use for MEM0_API_KEY
   openssl rand -base64 32   # use for POSTGRES_PASSWORD
   openssl rand -base64 32   # use for NEO4J_PASSWORD
   ```
4. In Coolify's **Domains** tab, attach a domain to the `mem0` service on port `8000`.
   Coolify's Traefik handles TLS via Let's Encrypt automatically.
5. **Deploy**. First boot takes 2–5 min (image pulls + dependency install + Neo4j warmup).

## Smoke test

```bash
export MEM0_URL="https://mem0.your-domain.com"
export MEM0_KEY="<your MEM0_API_KEY>"

# Add a memory
curl -X POST "$MEM0_URL/add" \
  -H "Authorization: Bearer $MEM0_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Daniel prefers concise, technical answers."}],
    "user_id": "daniel",
    "agent_id": "hermes"
  }'

# Search
curl -X POST "$MEM0_URL/search" \
  -H "Authorization: Bearer $MEM0_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "communication style", "user_id": "daniel"}'

# List
curl "$MEM0_URL/memories?user_id=daniel" \
  -H "Authorization: Bearer $MEM0_KEY"
```

## Scoping convention (the whole point of this setup)

One Mem0 instance, every agent writes under its own `agent_id` but shares `user_id="daniel"`:

| Caller            | `user_id`  | `agent_id`     |
| ----------------- | ---------- | -------------- |
| Hermes            | `daniel`   | `hermes`       |
| spacebot.sh       | `daniel`   | `spacebot`     |
| Claude Code       | `daniel`   | `claude-code`  |
| OpenClaw          | `daniel`   | `openclaw`     |
| local dev / REPL  | `daniel`   | `local-dev`    |

Search across all agents: omit `agent_id`. Search a specific agent's memory only: include it.

## Wiring Claude Code (MCP)

Add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "mem0": {
      "command": "npx",
      "args": ["-y", "@mem0/mcp-server"],
      "env": {
        "MEM0_API_KEY": "<your MEM0_API_KEY>",
        "MEM0_BASE_URL": "https://mem0.your-domain.com",
        "MEM0_USER_ID": "daniel",
        "MEM0_AGENT_ID": "claude-code"
      }
    }
  }
}
```

Claude Code now has `add_memory` / `search_memory` tools pointed at your Coolify instance.

## Backups

Volumes are named (`postgres_data`, `neo4j_data`) — Coolify's backup feature picks them up.
For ad-hoc dumps:

```bash
# Postgres
docker compose exec postgres pg_dump -U mem0 mem0 > mem0-pg-$(date +%F).sql

# Neo4j (community edition requires stopping the container)
docker compose stop neo4j
docker run --rm -v mem0-coolify_neo4j_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/mem0-neo4j-$(date +%F).tar.gz /data
docker compose start neo4j
```

## Security notes

- **Auth is enforced by `MEM0_API_KEY`** — set it, and only callers with the Bearer token can write/read.
- **Postgres and Neo4j are NOT exposed** publicly. They're reachable only on Coolify's internal Docker network.
- **CORS is `*`** by default in the upstream image. Restrict at the Coolify/Traefik layer if you're embedding this in a browser app.

## API quick reference

| Method | Path                  | Notes                                    |
| ------ | --------------------- | ---------------------------------------- |
| POST   | `/add`                | Add memory. Body: `{messages, user_id, agent_id?, metadata?}` |
| POST   | `/search`             | Body: `{query, user_id, agent_id?, limit?}` |
| GET    | `/memories?user_id=…` | List all memories for a user             |
| DELETE | `/memories/{id}`      | Delete by memory ID                      |
| GET    | `/docs`               | Swagger UI                               |
