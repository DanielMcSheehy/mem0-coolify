# Mem0 on Coolify

Self-hosted Mem0 (AI memory backend) as a shared knowledge store across
Hermes, spacebot.sh, Claude Code, OpenClaw, and local dev.

## Stack

| Service  | Image                              | Purpose                                |
| -------- | ---------------------------------- | -------------------------------------- |
| mem0     | Built from `mem0ai/mem0` source    | REST API on port 8000 (multi-arch)     |
| postgres | `ankane/pgvector`                  | Vector + metadata store                |

Total RAM footprint: ~1 GB. Fits comfortably on a small Coolify VPS.

> **Why no Neo4j?** Earlier guides (including Mem0's own blog) describe a
> three-container stack with Neo4j for graph memory. The current upstream
> `mem0ai/mem0/server` source only configures `pgvector` — there's no
> `graph_store` in `DEFAULT_CONFIG`. Running Neo4j adds 2 GB RAM and a
> known startup-validation footgun for zero benefit on this server.

## Deploy on Coolify

1. **Create a new resource** → **Public Repository** → paste this repo's URL.
2. Build pack: **Docker Compose**.
3. In Coolify's **Environment Variables** tab, set each variable from `.env.example`:
   ```bash
   # generate secrets locally
   openssl rand -base64 32   # use for ADMIN_API_KEY
   openssl rand -base64 48   # use for JWT_SECRET
   openssl rand -base64 32   # use for POSTGRES_PASSWORD
   ```
4. In Coolify's **Domains** tab, attach a domain to the `mem0` service on port `8000`.
   Coolify's Traefik handles TLS via Let's Encrypt automatically.
5. **Deploy**. First boot takes 3–5 min (Mem0 image builds from source). Subsequent
   deploys hit the build cache.

> **Why build from source?** The official `mem0/mem0-api-server:latest` image
> on Docker Hub is published arm64-only, which fails on amd64 Coolify hosts with
> `no match for platform in manifest`. Building from source produces a working
> image on whichever architecture your host runs.

## Smoke test

```bash
export MEM0_URL="https://mem0.your-domain.com"
export MEM0_KEY="<your ADMIN_API_KEY>"

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

## Scoping convention

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
        "MEM0_API_KEY": "<your ADMIN_API_KEY>",
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

The `postgres_data` volume holds everything. Coolify's backup feature picks it up,
or run an ad-hoc dump:

```bash
docker compose exec postgres pg_dump -U mem0 mem0 > mem0-$(date +%F).sql
```

## Security notes

- **Auth is enforced by `ADMIN_API_KEY`** — only callers with the Bearer token can read/write.
- **Postgres is NOT exposed publicly.** It's reachable only on Coolify's internal Docker network.
- **CORS is `*`** by default in the upstream image. Restrict at the Coolify/Traefik layer if you embed this in a browser app.

## API quick reference

| Method | Path                  | Notes                                                          |
| ------ | --------------------- | -------------------------------------------------------------- |
| POST   | `/add`                | Add memory. Body: `{messages, user_id, agent_id?, metadata?}`  |
| POST   | `/search`             | Body: `{query, user_id, agent_id?, limit?}`                    |
| GET    | `/memories?user_id=…` | List memories for a user                                       |
| DELETE | `/memories/{id}`      | Delete by memory ID                                            |
| GET    | `/docs`               | Swagger UI                                                     |
