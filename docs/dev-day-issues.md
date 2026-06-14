# Dev Day — running issues list

Things that bit us during dry-runs, with the fix and (where it makes sense) a
suggested code change so they can't bite us live. Newest issues at the top.

Status legend: 🔴 open · 🟡 worked-around (manual fix known) · 🟢 fixed in repo

---

## `docs/cockpit.html` — pending content updates

The prompt-card page (`docs/cockpit.html`, opened by `make dev-start`) is the
attendee-facing surface. Track on-page content it still needs here; implement in
the batch after the dry-run.

- [x] **DONE — Surfaced the four "how to attend" options on-page.** Added a "How to
  run this — 4 ways (pick your path)" table to the build view (open by default), plus
  a "Two kinds of step" legend (🗣 purple = say to Bob / ⌨ gray = run a command) and
  per-step persona "hat" badges (Builder/Operator/Analyst), so it's clear what to say
  to Bob at each step. The four tiers, for reference:
  1. **Browser only** — read-along on this page, zero install (Tier 1).
  2. **Only Bob local + Codespaces mesh** ⭐ — install Bob, run the printed
     `make connect` line against the cloud gateway; no Docker/uv/make (Tier 2).
     Note the gotcha inline: **`-t http` + `/mcp`, not SSE** (Codespaces proxies
     buffer SSE → Bob hangs on connect), and **run `bob mcp add` from an empty
     folder** (a repo clone's `.bob/mcp.json` shadows the connect config — see #2).
  3. **Watch-along** — presenter VM/Codespace, share the Companion `:7070` URL/QR (Tier 3).
  4. **Fully local** — `make quickstart`; fine the night before, risky for a whole
     room on WiFi at once (Tier 4).
  Source of truth for wording: `docs/ONBOARDING.md`.

---

## 5. 🟡 Admin UI "Add Gateway" form rejects manual registration (query-param quirk)

**Symptom:** registering sales-tax by hand in the Admin UI
(`localhost:4444/admin/#gateways`, URL `http://sales-tax:8000/mcp`, Streamable
HTTP, Auth None) fails with a red banner: *"Query parameter key must start with a
letter or underscore, followed by letters, numbers, underscores, or hyphens."*

**Diagnosis (verified in source, not guessed):** the field is
`auth_query_param_key` — part of ContextForge's "Query Parameter Authentication"
mode. The validator (`schemas.py:2867`) only rejects a **non-empty, malformed**
value (`^[a-zA-Z_][a-zA-Z0-9_\-]*$`); **empty is explicitly allowed**. The backend
reads it regardless of the chosen auth type
(`admin.py:16074: auth_query_param_key=str(form.get("auth_query_param_key","")) or None`).
So even with **Auth Type = None**, the Admin-UI SPA submits a stray, non-empty,
invalid value into that field → Pydantic rejects it. It's a **ContextForge web-form
bug** (the field isn't cleared/disabled when Auth=None), unrelated to the sales-tax
server. (Earlier note in this doc said "empty key" — that was wrong; empty passes.)

**Fix / what to do instead:** the demo never registers through this form — it
registers via the API as the operator would, which posts a clean payload with no
query-param-auth key, so the validator never trips. `make salestax-register` →
`200`/registered (verified). Or drive Bob (operator) →
`controlplane-register-mcp-server`. On stage the "register" beat is *Bob the
operator registers it*, not a hand-filled web form, so this never surfaces in the
narrated flow.

**Note:** not on the demo's critical path — informational, so reviewers don't
burn time on it.

---

## 4. 🟡 Bob's live build is non-deterministic — a 2nd generation can be broken

**Symptom:** `make stage2-govern` fails at `the sales-tax container didn't answer
on :8001`. The container shows "Running" but is actually **crash-looping**
(`docker logs` shows a repeating traceback).

**Diagnosis:** Bob's *first* `server.py` was correct (`@mcp.custom_route("/health",
methods=["GET"])` + `mcp.run(transport="http", …)`) and ran fine locally. A later
regeneration **overwrote** it with a broken variant:
  - `@mcp.get("/health")` → `AttributeError: 'FastMCP' object has no attribute 'get'`
    (no such decorator in FastMCP 3.3.1) — instant crash on container start.
  - `mcp.run(transport="sse", …)` → wrong transport (gateway expects STREAMABLEHTTP;
    SSE also buffers through proxies, see the Codespaces note).
Same prompt, different output — classic LLM non-determinism. The crash is silent
at the Docker level ("Running"/"Up Less than a second" = restart loop); only
`docker logs <container>` reveals it.

**Fix (manual):** `make stage1-scaffold` drops in the known-good `_solution.py`,
then rebuild: `docker compose -f docker-compose.yml -f docker-compose.salestax.yml
up -d --build sales-tax`. Verified healthy: `curl localhost:8001/health →
{"status":"ok","server":"sales-tax"}`. Then re-run `make stage2-govern`.

**Two lessons for stage:**
  1. **Once Bob produces a working `server.py`, stop regenerating it.** Build once,
     prove it with `make stage1-build` (→ 108.50), then leave it alone — a re-prompt
     can replace a good file with a broken one (that's what happened here).
  2. Keep `make stage1-scaffold` one keystroke away; it's the deterministic safety net.

**Suggested fixes:**
  - Tighten the Stage-1 prompt to reduce Bob's failure surface: ask explicitly for
    `transport="http"` (streamable-HTTP) and a `@mcp.custom_route("/health",
    methods=["GET"])` route, instead of the looser "served over HTTP … GET /health".
  - Make the `:8001` health-probe failure in `scripts/stages.sh` print the last few
    `docker logs sales-tax` lines inline, so the crash reason is visible without a
    separate `make logs`.

---

## 3. 🟢 ContextForge Admin UI forces an admin password change on first login

**Symptom:** opening the ContextForge UI (`localhost:4444`, e.g. via the monitor
during `make stage2-govern`) redirects to `/admin/change-password-required`
("Your password has expired and must be changed to continue"), demanding a new
≥22-char password before you can see the catalog/logs.

**Diagnosis:** not time-expiry. The pinned ContextForge v1.0.2 image defaults
`admin_require_password_change_on_bootstrap=True` (`config.py:996`), so
`bootstrap_db.py:299` sets a `password_change_required` flag on the admin at
bootstrap. The new-password rule of ≥22 chars comes from
`password_min_length_privileged=22`. The repo never disabled this, and the
bootstrap password `FinByteAdmin!2026` (17 chars) couldn't have satisfied it
anyway. Note: the data plane (register/grant/seed) uses JWTs minted from
`JWT_SECRET_KEY`, so it was never blocked — only the human Admin UI was.

**Fix (in repo):** added `PASSWORD_CHANGE_ENFORCEMENT_ENABLED=false` to `.env`
and `.env.example` (master switch, `config.py:995`; settings are no-prefix,
case-insensitive). Complexity policy (`password_policy_enabled`) stays on, so the
"Password Security" story is still real — we just don't force a rotation on stage.
Apply with `make demo-reset` (force-recreates the gateway so it re-reads `.env`
and re-bootstraps the admin without the flag). Verified: `password_change_required=0`,
login with `admin@finbyte.demo / FinByteAdmin!2026` goes straight in.

---

## 1. 🟡 `bob -y "..."` hangs silently when the SSO session has expired

**Symptom:** headless run prints `YOLO mode is enabled. All tool calls will be
automatically approved.` and then nothing — forever. No error, no output.

**Diagnosis:** `-y` (YOLO) only auto-approves *tool calls*; it does **not**
bypass SSO authentication. With no valid session, Bob blocks at the auth gate.
Tells: the process is alive but CPU time is frozen, and it holds **zero network
sockets** (`lsof -p <pid> | grep TCP` is empty) — it never even tried to reach
the model API. `~/.bob/settings.json` shows `auth.selectedType: "sso"` with an
empty `ibm_secrets: {}`.

**Fix (manual):** sign in interactively first — run `bob` with no prompt,
complete the SSO sign-in in the browser, confirm it reaches the prompt
(bottom bar shows a token budget, e.g. `Tokens left: 100%`), then `/quit`.
The session is now cached and `bob -y "..."` works.

**Suggested fix:** add an SSO-auth check to `make check` preflight so a stale
session is caught during setup, not live on stage.

---

## 2. 🟡 Bob stalls on `Initializing…` from a stale `.bob/mcp.json`

**Symptom:** interactive `bob` sits on `^ Initializing...` and churns.

**Diagnosis:** a leftover `.bob/mcp.json` (written yesterday by `make bob` /
`make bob-install`, the analyst persona) makes Bob launch the `finbyte-gateway`
MCP server on startup. With the gateway stack **down**, three things stack up,
all silent:
  1. `uvx --from mcp-contextforge-gateway …` cold-builds the wrapper package,
  2. the wrapper tries to reach `http://localhost:4444/servers/<uuid>/sse` —
     a dead endpoint — and retries to timeout,
  3. `MCP_WRAPPER_LOG_LEVEL: OFF` suppresses any diagnostic.
The vserver UUID in the file is also stale (it changes on every reseed), so even
with the stack *up* this exact config would 404 until regenerated.

Confirmed it was **not** created today: the file was dated yesterday, and
`scripts/stages.sh` (what `make stage1-build` runs) never touches `.bob/mcp.json`.
Only `make bob-install{,-operator,-builder}` (and `make bob`/`bob-operator`) write it.

**Fix (manual):** Stage ① wants **no** gateway config. Run `make clean` (it
deletes `.bob/mcp.json`) — or move it aside — before starting. Stage ②/③
regenerate it live with the correct UUID via `make bob` / `make salestax-grant`
/ `make bob-install-builder`.

**Suggested fix:** have `make stage1-build` warn (or auto-stash) if a
gateway-pointed `.bob/mcp.json` is present while the stack is down.

---

## Dry-run hygiene checklist (start of setup, before going on stage)

- [ ] `make clean` — wipes stale `.bob/mcp.json` + generated files (issue #2)
- [ ] `bob` once → complete SSO sign-in → `/quit` (issue #1)
- [ ] `make check` — Docker running, `uv`, Node ≥ 22.15
- [ ] `make stage-reset` — no stale Stage-1 server lingering
