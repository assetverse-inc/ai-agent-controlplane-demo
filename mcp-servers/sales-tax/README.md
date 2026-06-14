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

Then re-run `make stage1-build`. It serves the server bare on `:8000` and **calls
the tool** to prove it works — `add_tax(100, 8.5) → tax=8.50, total=108.50`, with no
token, no policy, no audit: anyone on the network could do the same. (It also opens
the MCP Inspector as an optional "poke it by hand" view.) That exposure is exactly
the problem Stage 2 fixes.

## Stage 2 — the same server gets governed (`register → grant → call`)

`make stage2-govern` doesn't switch to a different service — it **carries this one**:

1. **Containerise** (`make salestax-up`) — builds `server.py` into an image
   (`Dockerfile` here) and runs it on the compose mesh network via the stage-2-only
   `docker-compose.salestax.yml` override (host `:8001`; the gateway reaches it at
   `sales-tax:8000`). The base `make up` never references this, so a fresh clone with
   no `server.py` is unaffected.
2. **Register** (`make salestax-register`, or Bob as operator) — it joins the catalog,
   token-gated, but **not yet callable** by Bob.
3. **Grant + call** (`make salestax-grant`) — adds `add_tax` to a minimal `Builder`
   virtual server + builder persona, so Bob **calls the tool it built, governed** →
   `108.50`. Built → governed → **used**.

Fallback: `make stage1-scaffold` (drops in `_solution.py`). Repeat clean:
`make stage-reset` (stops the bare server + container, removes `server.py`).
