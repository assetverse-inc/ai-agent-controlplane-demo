# sales-tax — the "Bob builds an MCP server from scratch" beat (Dev Day Stage 1)

This folder is intentionally **almost empty**. On stage, IBM Bob *writes*
`server.py` live — that's the whole point of Stage 1: show the room how easy it
is to stand up an MCP server (an "agent"), and how completely **ungoverned** it
is until ContextForge wraps it (Stage 2).

| File | Role |
|---|---|
| `_solution.py` | The finished reference / fallback. `make stage1-scaffold` copies it to `server.py` if Bob's live build wobbles. |
| `server.py` | **Generated** — written by Bob (or the scaffold). Not committed (but *not* gitignored: Bob honors `.gitignore` and would refuse to write an ignored path). `make stage-reset` deletes it so the beat repeats clean. |

## The beat

```bash
make stage1-build      # prints the prompt; once server.py exists, runs it bare on :8000 + opens the Inspector
```

Tell Bob (verbatim is fine):

> Create a new MCP server with fastmcp at `mcp-servers/sales-tax/server.py`: a tool
> `add_tax(amount, rate_pct=8.5)` returning `{amount, rate_pct, tax, total}`, plus a
> GET `/health` route, served over HTTP on `0.0.0.0:8000`.

Then re-run `make stage1-build`. The MCP Inspector opens with **no token field** —
anyone on the network can call any tool, no redaction, no policy, no audit. That
exposure is exactly what Stage 2 (`make stage2-govern`) fixes by putting a tool
behind ContextForge.

Fallback: `make stage1-scaffold` (drops in `_solution.py`). Repeat clean: `make stage-reset`.
