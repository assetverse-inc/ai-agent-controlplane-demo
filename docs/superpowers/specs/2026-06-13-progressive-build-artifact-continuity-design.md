# Progressive-build artifact continuity — design

**Issue:** [#9](https://github.com/manavgup/ai-agent-controlplane-demo/issues/9) — *Tighten the progressive-build showcase: carry the Bob-built server through Stages 1→2 + dev-focus the build page*
**Follow-up to:** PR #8 (merged, `c92095c`)
**Date:** 2026-06-13

## Problem

The Dev Day progressive-build track (`make stage1-build … stage4-mesh`, surfaced on
`docs/cockpit.html` → 🎓 Progressive Build) silently **swaps artifacts** mid-story:

- **Stage 1** — Bob builds `sales-tax` from scratch, runs it bare on `:8000`.
- **Stage 2** — onboards `fx-rates`, a *different* pre-existing service.
- **Stage 3** — controls fire on the expense/payments mesh (yet another set).

So the thing the developer *built* is abandoned after Stage 1 — never governed,
never used again. It reads as three disconnected demos instead of one artifact
carried build → run → govern → use. Secondary gaps: the "dev" is under-shown (only
the prompt is visible, not Bob's code, its iterate loop, or the tool actually
running), the killer "drive it from your laptop with just Bob" message lives only
in `docs/ONBOARDING.md`, and the build-page copy is presenter-framed ("the room",
"the gasp", "live-talk path") rather than dev-voiced.

## Goals

1. **Carry one artifact end-to-end.** The `sales-tax` server Bob writes in Stage 1
   is containerized and governed in Stage 2 — the payoff for building it.
2. **Keep the "extend an existing service" teaching point** as a co-equal beat:
   Bob adds a `convert` tool to `fx-rates`, re-onboards, and calls it.
3. **Show the dev.** Bob's generated code, its write→run→fix loop, and the tool
   actually returning a value.
4. **Surface BYOB on the build page** — "No Docker? drive the mesh with just Bob."
5. **Dev-voice the framing.**
6. **Never break `make up` on a fresh clone** (no `server.py` yet).

## Non-goals

No changes to the four controls, OPA policies, the A2A agents, or the Cockpit view
(beyond a note that its `<h1>` is shared). No renumbering of the four top-level
stages. No new onboarding tiers (those shipped in #8).

## Decisions (resolved during brainstorming)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Containerize sales-tax, then govern it** (vs. governing the bare host process via `host.docker.internal`). | Fully internal compose-network DNS sidesteps the container→host networking gotcha — robust on Mac/Linux/Codespaces (multi-arch constraint). Mirrors the proven `fx-rates` path. True-to-life "package to deploy" beat. |
| D2 | **fx-rates becomes a co-equal Stage 2b beat** — Bob *adds a `convert` tool* (true "extend"), not just registers it as-is. | Keeps build-from-scratch AND extend-existing both first-class, per issue. |
| D3 | **Four top-level stages, 2a/2b as sub-beats.** | Preserves the `stage1…stage4` targets and the build→govern→control→mesh mental model. |
| D4 | **Deterministic `add_tax(100)` call is the primary Stage-1 proof**; the MCP Inspector demotes to optional. | "It works — and that's the problem" lands faster than the Inspector "Via Proxy → Connect" dance. |
| D5 | **2b edits the tracked `fx-rates/server.py` live**, reverted by `reset` via `git checkout`; `server_with_convert.py` is the fallback source. | The edit *is* the "extend" beat; git restores a clean tree. |
| D6 | **"No Docker? just Bob" twisty near the top** of the build view (after *Architecture at a glance*). | People who can't run the stack should see the alternative immediately. |
| D7 | **Close the loop: register → grant → call.** Registering a backend only catalogs its tools; to make Bob *call* `add_tax`, a privileged platform step adds the tool to a minimal **`Builder`** virtual server and installs a **Builder persona**, then Bob calls it through the gateway. | Codex P1 #1: `seed.py` binds Bob's personas to virtual servers with fixed `associated_tools`; registration alone leaves the tool cataloged-but-uncallable. The grant *is* the least-privilege beat (registered ≠ callable; even the operator can't self-grant). Fully satisfies issue #9 (built → governed → **used**). |
| D8 | **Re-registration must delete-then-recreate the gateway record**, not treat "already exists" as success. | Codex P1 #2: a duplicate `POST /gateways` does not refresh the discovered tool list, so an extended `fx-rates` would never expose `convert`. Mirror `seed.py`'s `DELETE /gateways/{id}` → `POST` pattern in `salestax-register`/`fxrates-extend`. |

## The narrative spine

| Stage | What the dev does | Artifact |
|---|---|---|
| **1 — Build** | Bob writes `sales-tax` from scratch → runs it **bare** on `:8000` → **calls it** (`add_tax(100) → 108.50`, no token, no policy) | `sales-tax` (yours) |
| **2 — Govern** | **2a:** containerize that same `server.py` → Bob (operator) **registers** it at `http://sales-tax:8000/mcp` (cataloged, token-gated, *not yet callable*) → `make salestax-grant` adds `add_tax` to the `Builder` vserver + installs the Builder persona → Bob (builder) **calls** `add_tax` *through the gateway* (governed → 108.50). **2b:** Bob *extends* `fx-rates` — adds `convert` → rebuild → delete-then-recreate the gateway record → grant `convert` → `convert 1000 USD→EUR` | `sales-tax` built→governed→**used** + `fx-rates` extended |
| **3 — Control** | The four controls bite real calls (PII redaction, injection, OPA wire-block, RBAC) | the governed mesh |
| **4 — Mesh** | Full picture (== `quickstart` end-state); pick a cockpit | everything |

Stage 2a is the payoff for Stage 1 — the tool you ran wide-open is now governed
*and you still call it* through the seam, with the **grant** as the visible
least-privilege moment (registered ≠ callable). Stage 2b is the "Bob can also
extend services you didn't write" flex.

### The `Builder` virtual server + persona (closes the loop, per D7)

`seed.py` binds each Bob persona to a virtual server with a fixed `associated_tools`
list (FinOps = 8 analyst tools, Operator = 4 control-plane tools). Registering a
backend via `POST /gateways` discovers its tools into `/tools` but grants them to
no one. To make Bob *call* `add_tax`:

1. **Register** (Bob, operator persona): `POST /gateways` → `sales-tax` is in the
   catalog, token-gated, **not callable** by Bob.
2. **Grant** (`make salestax-grant`, a privileged *platform* action — the operator
   persona has no grant tool, which reinforces least-privilege): create/extend a
   minimal **`Builder`** virtual server (`POST /servers`, delete-then-recreate so
   re-runs re-associate cleanly, mirroring `seed.py`) whose `associated_tools` is
   exactly the dev's own tools — `add_tax` after 2a, `+ convert` after 2b — then
   write `.bob/mcp.json` to the Builder vserver (`make bob-install-builder`, from a
   new `bob-personas/mcp.builder.json.template`).
3. **Call** (Bob, builder persona): `Add sales tax to $100.` → governed call through
   `:4444` → `108.50`.

## Components

### New files (all committed; none gitignored)

**`mcp-servers/sales-tax/Dockerfile`** — byte-for-byte the `fx-rates` pattern:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir fastmcp==3.3.1
COPY server.py .
EXPOSE 8000
CMD ["python", "server.py"]
```

Multi-arch base, no pinned digest. It `COPY`s the *generated* `server.py`, so it
only ever builds at Stage 2 — after Bob (or the scaffold) has written the file.

**`docker-compose.salestax.yml`** — a stage-2-only override joining the base
project network:

```yaml
services:
  sales-tax:
    build: ./mcp-servers/sales-tax
    restart: unless-stopped
    ports:
      - "8001:8000"   # host:container — host 8001 avoids the Stage-1 raw :8000
```

The base `make up` never references this file, so a fresh-clone `make up` cannot
trip over the missing `server.py`. The **host port `8001`** matters for the health
gate (Codex P2): the container exposes no path on host `:8000`, so probing
`localhost:8000` would hit the *raw Stage-1 process* and false-positive. The
health gate probes `localhost:8001` (the container); the **gateway** still reaches
it by internal DNS at `http://sales-tax:8000/mcp`. 8001 also sidesteps any port
clash while the raw server is still being stopped.

**`bob-personas/mcp.builder.json.template`** — the Builder persona (mirrors the
existing `mcp.operator.json.template`): `REPLACE_BUILDER_UUID` / `REPLACE_GATEWAY_TOKEN`
placeholders, pointed at the `Builder` virtual server. Installed by
`make bob-install-builder` (see D7).

### New Makefile targets

(Compose-engine selection stays in the Makefile where `$(COMPOSE)` resolves
docker vs. podman.)

- `salestax-up` — `$(COMPOSE) -f docker-compose.yml -f docker-compose.salestax.yml up -d --build sales-tax`. Guarded: clear error if `mcp-servers/sales-tax/server.py` is absent.
- `salestax-down` — stop & remove just the `sales-tax` container (used by `reset`/`clean`).
- `salestax-register` — deterministic fallback for the 2a onboard. **Delete-then-recreate** the gateway record (Codex P1 #2): `DELETE /gateways/{id}` if present, then `POST /gateways`, so the tool list is freshly discovered. (The existing `fxrates-register` treats "already exists" as success — that's the stale-tool bug; the new targets must not.)
- `salestax-grant` — create/extend the `Builder` vserver with `add_tax` (delete-then-recreate, mirroring `seed.py`) + `make bob-install-builder`. The D7 grant step.
- `bob-install-builder` — write `.bob/mcp.json` from `bob-personas/mcp.builder.json.template` pointed at the `Builder` vserver UUID (mirrors `bob-install-operator`).
- `fxrates-extend` — deterministic fallback for 2b: copy `server_with_convert.py` → `server.py`, `$(COMPOSE) up -d --build fx-rates`, **delete-then-recreate** the fx-rates gateway record (so `convert` is discovered), then grant `convert` into the `Builder` vserver.

### `scripts/stages.sh` — `stage_govern` rewrite (replaces lines 116–146)

1. **Guard:** if `mcp-servers/sales-tax/server.py` is absent → print "run `make stage1-build` or `make stage1-scaffold` first" and exit. You cannot govern what wasn't built.
2. `make up` + `make seed` + operator persona (unchanged).
3. **2a — register → grant → call:**
   - `make salestax-up` (build + run the sales-tax container on the mesh network, host `:8001`). **Health gate** probes `localhost:8001` (the container — Codex P2), and only once it answers does `stop_raw` retire the bare host process.
   - Bob (operator) **registers** `http://sales-tax:8000/mcp` (fallback `make salestax-register`, delete-then-recreate). It's in the catalog, token-gated, **not callable yet** — the least-privilege beat.
   - `make salestax-grant` adds `add_tax` to the `Builder` vserver + installs the Builder persona.
   - Bob (builder) **calls** it: `Add sales tax to $100.` → governed result `108.50`. Payoff: the tool you ran wide-open 60 seconds ago now runs token-gated through the one seam.
4. **2b — extend an existing service:** Bob adds a `convert(amount, src_ccy, dst_ccy)` tool to `mcp-servers/fx-rates/server.py` (avoid `from`/`to` — `from` is a Python reserved word; match whatever `server_with_convert.py` already uses so the fallback stays consistent) → `$(COMPOSE) up -d --build fx-rates` → **delete-then-recreate** the fx-rates gateway record so `convert` is discovered → grant `convert` into the `Builder` vserver → Bob calls `convert 1000 USD→EUR`. Fallback `make fxrates-extend`.

### `scripts/stages.sh` — Stage-1 proof-of-life (`stage_build`)

After the bare server is healthy and **before** the optional Inspector, run a
deterministic tool call — a tiny `uv run --with fastmcp==3.3.1` client using the
**async `fastmcp.Client("http://localhost:8000/mcp")`** API (not a hand-rolled
one-shot HTTP POST — streamable-HTTP session/init is easy to get wrong; Codex
confirmed), which calls `add_tax(100)` and prints:

```
add_tax(100, 8.5) → tax=8.50, total=108.50   (no token, no policy — anyone on :8000 can call this)
```

The Inspector launch (currently the foreground blocker) moves behind an optional
prompt so the proof-of-life is the primary beat.

### `scripts/stages.sh` — `reset`

Extend to: `stop_raw`; remove generated `sales-tax/server.py`; `make salestax-down`;
`git checkout HEAD -- mcp-servers/fx-rates/server.py` (undo the 2b live edit —
explicit `HEAD` so a *staged* edit is restored from the commit, not the index;
Codex P2). Print a one-line warning that this discards local fx-rates edits. Leaves
`_solution.py` and `server_with_convert.py` (tracked fallbacks) in place.

### `docs/cockpit.html` — build view

- **Headline** (l.209) → "Build an MCP server in 2 minutes — then watch it get governed."
- **Lede** (l.210) → second-person; add the "containerize it" beat.
- **De-presenter copy:** "stalls the room" → "if a live edit wobbles"; "live-talk path" (l.211) → "all-at-once path is `make quickstart`"; Stage 3 pill "the gasp" (l.255) → "4 controls fire"; Stage 4 "the room watched it get built" (l.280) → "you built it stage by stage." Shared `<h1>` (l.176) left unchanged.
- **Stage 1:** add a collapsed **"What Bob produced"** twisty (the ~15-line `server.py` snippet from `_solution.py`); an agentic-loop line ("Bob writes, runs, and fixes its own code — paste the error back and it iterates"); the `add_tax(100) → 108.50` proof-of-life as step ②, Inspector demoted to a nested "Want to poke it by hand?" twisty.
- **Stage 2:** rewrite l.239–252 into **2a** — three labelled beats: ① containerize + register `sales-tax` (cataloged, *not callable yet* — call out the least-privilege gate); ② `make salestax-grant` (the platform grant); ③ Bob calls `Add sales tax to $100.` → `108.50` governed — and **2b** ("Bonus — Bob extends an existing service": add `convert` to `fx-rates` → re-discover → grant → call, fallback `make fxrates-extend`).
- **New twisty near the top** (after *Architecture at a glance*): **"No Docker on your laptop? Drive the whole mesh with just Bob"** → `make connect` + the Codespaces BYOB flow (`-t http` + `/mcp`), verified in #8.
- **Reset twisty** (l.291–298): keep `stage-reset`/`demo-reset`/`fxrates-reset` accurate to the new `reset` behavior.

## Testing

### Fresh-clone safety (must-not-break invariant)

- With **no** `mcp-servers/sales-tax/server.py`, `make up && make seed` brings up the
  full 10-service mesh green (base compose never references the override).
- `mcp-servers/sales-tax/server.py` remains uncommitted but **not** gitignored.
- CI `ci` aggregate (lint, bandit, compose-validate) passes; `compose-validate` runs
  against the base file only and must not choke on the override.

### Stage-flow self-test (local, pre-Codespaces)

1. `make stage-reset` → clean slate (no `server.py`).
2. `make stage1-scaffold` (stands in for Bob) → `make stage1-build` → confirm bare
   server + the `add_tax(100) → 108.50` proof-of-life.
3. `make stage2-govern` → confirm: the sales-tax **container** builds and answers on
   host `:8001`; the bare `:8000` process is stopped *after* that; it lands in the
   catalog at `http://sales-tax:8000/mcp`; `make salestax-grant` puts `add_tax` in the
   `Builder` vserver; **Bob (builder) actually calls `add_tax` through `:4444` and gets
   `108.50`** (the loop closes — Codex P1 #1). Then the 2b `convert` beat: extend →
   re-discover (the gateway record is deleted-then-recreated, so `convert` appears —
   Codex P1 #2) → grant → Bob calls `convert`.
4. `make stage3-controls` → `make verify-controls` → **16/16**.
5. `make stage-reset` + `make fxrates-reset` → `git status` clean (2b edit reverted,
   generated files gone).

### Codespaces re-test (required — item #1 changes behavior)

Re-run the BYOB proof from a Codespace: stack up, port 4444 Public, `make connect`,
then a laptop Bob (`-t http` + `/mcp`) registers and **calls the governed `sales-tax`
tool**. Same proof that passed in #8, now exercising the new artifact path. Run by
the author (needs their Codespace); an exact checklist will accompany the plan.

## Risks

- **2b live edit dirties the tree** — mitigated by `reset`'s `git checkout HEAD -- …`
  (restores from the commit even if staged) + a discard warning; `fxrates-extend` is idempotent.
- **Stage-2 container build adds a few seconds live** — acceptable; the `salestax-up`
  guard + scaffold fallback keep it from stranding the talk.
- **Override-file network join** — must share the base project name so DNS `sales-tax`
  resolves from the gateway; verified in the stage-flow self-test (and by Codex via
  `docker compose config`).
- **Grant step is admin-side, not Bob-driven** — `salestax-grant` mints the admin token
  the same way `seed`/`connect` do; if the secret drifts the grant fails loudly. This is
  intended (the operator persona has no grant tool — that's the least-privilege point).

## Codex review findings (addressed)

Independent review (`/codex review`, 2026-06-13) cross-checked this spec against the
repo. Resolutions folded in above:

| Finding | Severity | Resolution |
|---|---|---|
| Registering a backend doesn't make Bob *call* it (personas bind fixed vserver tool IDs) | P1 | D7 — `Builder` vserver + `salestax-grant` + Builder persona; register → grant → call. |
| "Already exists" re-registration leaves the tool list stale (no `convert`) | P1 | D8 — `salestax-register`/`fxrates-extend` delete-then-recreate the gateway record. |
| Health gate on `localhost:8000` false-positives on the raw process | P2 | Override maps host `:8001`; gate probes `:8001`, gateway uses internal `:8000`. |
| `git checkout -- path` is a brittle reset | P2 | `git checkout HEAD -- …` + discard warning. |
| Proof-of-life as raw HTTP POST is fragile | P2 (sound-check) | Use async `fastmcp.Client(...)`. |

Codex confirmed sound: the override network join (compose v2 + podman socket, *not*
legacy `podman-compose`), fresh-clone `make up` safety, the `http://sales-tax:8000/mcp`
registration model, and no `:8000` port conflict.
