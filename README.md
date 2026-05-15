# Hindsight on Coolify

Self-hosted [Hindsight](https://hindsight.vectorize.io) (AI agent memory) as a
shared knowledge store across Hermes, spacebot.sh, Claude Code, OpenClaw, and
local dev.

> This repo previously hosted a Mem0 setup. Mem0's self-host story had too many
> sharp edges (two-DB Postgres init, alembic, arm64-only image, env var
> collisions). Switched to Hindsight — single container, multi-arch, embedded
> Postgres, MCP built in. See `docker-compose.mem0.yaml.deprecated` for the old
> stack if you want to compare.

## Stack

| Service   | Image                                  | Notes                                |
| --------- | -------------------------------------- | ------------------------------------ |
| hindsight | `ghcr.io/vectorize-io/hindsight:latest`| API on 8888 (+ MCP) and UI on 9999. Embedded Postgres with pgvector. |

One container. Multi-arch (amd64 + arm64). Bundled local embedder so OpenAI is
only used for fact extraction and reflect reasoning. Total RAM footprint:
~2–3 GB idle.

## Deploy on Coolify

1. **Create a new resource** → **Public Repository** → paste this repo's URL.
2. Build pack: **Docker Compose**.
3. In Coolify's **Environment Variables** tab, set each variable from `.env.example`:
   ```bash
   # generate the Hindsight bearer token
   openssl rand -hex 32
   ```
4. In Coolify's **Domains** tab:
   - Attach a primary domain to the `hindsight` service on port **8888** (API + MCP)
   - Optionally attach a second domain on port **9999** (Control Plane UI)
5. **Deploy.** First boot pulls a ~4 GB image and runs DB migrations — takes 2–4 min.

## Smoke test

```bash
export HS_URL="https://hindsight.your-domain.com"
export HS_KEY="<your HINDSIGHT_API_KEY>"

# Create a bank for Daniel
curl -X POST "$HS_URL/banks" \
  -H "Authorization: Bearer $HS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"id": "daniel-global", "name": "Daniel global memory"}'

# Retain a memory
curl -X POST "$HS_URL/banks/daniel-global/retain" \
  -H "Authorization: Bearer $HS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"content": "Daniel prefers concise, technical answers and self-hosts everything on Coolify."}'

# Recall
curl -X POST "$HS_URL/banks/daniel-global/recall" \
  -H "Authorization: Bearer $HS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "communication style"}'
```

The Control Plane UI at `https://hindsight-ui.your-domain.com` gives you a
visual browser for banks, memories, and the retain/recall/reflect operations.

## Memory bank topology

Unlike Mem0's `user_id` / `agent_id` model, Hindsight uses **banks** — named
collections of memories. Pick one of two strategies:

### A — One global bank, every agent reads/writes the same store

| Caller            | Bank ID         |
| ----------------- | --------------- |
| Hermes            | `daniel-global` |
| spacebot.sh       | `daniel-global` |
| Claude Code       | `daniel-global` |
| OpenClaw          | `daniel-global` |

Pros: Fully shared knowledge. Cons: No per-agent scoping.

### B — Per-agent banks + a shared bank for things everyone should know

| Caller            | Bank ID         |
| ----------------- | --------------- |
| Hermes            | `hermes`        |
| spacebot.sh       | `spacebot`      |
| Claude Code       | `claude-code`   |
| OpenClaw          | `openclaw`      |
| Anyone, anything  | `daniel-shared` |

Pros: Isolated agent histories + a shared "global facts" pool. Cons: More banks
to manage; cross-bank recall requires multiple API calls.

Recommend **(B)** for production-grade isolation, **(A)** for max simplicity.

## Wiring Claude Code (MCP — built into Hindsight)

Hindsight serves an MCP endpoint at `/mcp/{bank_id}/`. Add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "hindsight": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "https://hindsight.your-domain.com/mcp/claude-code/",
        "--header",
        "Authorization:${HS_AUTH}"
      ],
      "env": {
        "HS_AUTH": "Bearer <your HINDSIGHT_API_KEY>"
      }
    }
  }
}
```

Claude Code now has `retain` / `recall` / `reflect` tools scoped to the
`claude-code` bank. Change the bank ID in the URL path to point at a different
bank.

## Wiring Hermes and OpenClaw

Both have first-class Hindsight plugins:

- **Hermes:** `hermes memory setup hindsight` (per `get-hermes.ai/memory`)
- **OpenClaw:** `hindsight-openclaw` plugin (see Hindsight's blog post "One
  Memory for Every AI Tool I Use")

Point each at `https://hindsight.your-domain.com` with the Bearer token.

## Backups

The `hindsight_data` named volume holds everything. Coolify backups pick it up,
or run an ad-hoc dump from the Coolify host:

```bash
# Volume contents (embedded postgres) — tar the whole directory
docker run --rm \
  -v $(docker volume ls -q | grep hindsight_data):/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/hindsight-$(date +%F).tar.gz /data
```

## Security notes

- **Auth is enforced by `HINDSIGHT_API_KEY`** — only callers with the Bearer
  token can read/write. Applies to both REST and MCP endpoints.
- **No host port exposure.** Coolify's Traefik handles ingress + TLS.
- **CORS is permissive by default** — tighten at the Coolify/Traefik layer if
  you embed this in a browser app.

## Why Hindsight over Mem0

| Concern                       | Mem0                              | Hindsight                            |
| ----------------------------- | --------------------------------- | ------------------------------------ |
| Self-host complexity          | High (2 DBs + alembic + init.sh)  | Low (single container)               |
| Multi-arch image              | arm64-only on Docker Hub          | amd64 + arm64 on GHCR                |
| MCP server                    | Separate `@mem0/mcp-server` pkg   | Built into the API container         |
| Embedded DB option            | No (requires external Postgres)   | Yes (`/home/hindsight/.pg0`)         |
| Auth                          | DIY (env var routing)             | Built-in tenant extension            |
| Time to working deploy        | Many hours                        | Minutes                              |
