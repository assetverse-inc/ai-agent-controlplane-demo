# Presenter RUNBOOK

## Before the talk
1. `cp .env.example .env && make up && make seed` — wait for "gateway healthy" + the FinOps/Treasury UUIDs.
2. `make verify-controls` → confirm **16 passed, 0 failed**. (This is your safety net: if live Bob misbehaves on stage, run this instead — it proves every control.)
3. `make bob-install` → writes `.bob/mcp.json` (the project config Bob reads from this dir) with the current FinOps UUID + Bob token. **Re-run after every `make seed`/`make demo-reset` — the FinOps UUID changes on each reseed, and a stale UUID is the #1 cause of "Bob can't connect".** Start Bob from the repo dir; ask it to list its tools. (`bob mcp list` shows "Disconnected" until a live session — that status line is static, not a failure.)
   - Bob connects through the `mcpgateway.wrapper` stdio bridge (`uvx --from mcp-contextforge-gateway python -m mcpgateway.wrapper`). The wrapper **must** have `DATABASE_URL` set to a writable path (the template uses `sqlite:////tmp/mcpwrapper.db`) or it crashes on startup importing `mcpgateway.config` (`OSError: Read-only file system: '/data'`). `make bob-config` bakes this in — that startup crash, not auth, was the old "Bob won't connect" bug.
4. Open three windows: (a) Bob, (b) `make logs` (gateway), (c) a terminal for `verify-controls` / curl.
5. Record a screen capture of each money shot as a backup.

## Live-room delivery (everyone runs it live)

This section is for the case where a **room of attendees** runs the demo on their own laptops, live, at the same time — not just the presenter. It complements (does not replace) the "Before the talk" checklist above and the "Recovery" table below.

### (a) Setup buffer / pre-flight
The realities of a live room:
- **Attendees should run `make quickstart` BEFORE the session** (or during a ~10-minute setup window at the start). The pinned ContextForge gateway image **pulls once** and **7 images build** from source the first time; on conference wifi the network is the risk, not the laptop.
- Cold start once images are cached: **~38 seconds** end-to-end (measured: `make down && make quickstart` → "16 passed, 0 failed"; slowest phase is the stack bring-up + gateway-health wait). **That number is build-only** — the **first-ever** run on a clean machine additionally pays the one-time ContextForge image pull + 7 source builds, so budget several minutes on first run / conference wifi.
- **Presenter pre-flight (do all of this before the room arrives):**
  1. Pre-run `make quickstart` and confirm it ends with the "Ready." card.
  2. Confirm `make verify-controls` = **16/16** (this is the headless safety net).
  3. Run **both** `make bob-install` (FinOps analyst persona) and have `make bob-install-operator` ready to switch for Act 2.
  4. Open the two panes you'll drive from: **Bob** (in the repo dir) and **`make monitor`** (the ContextForge Admin UI — catalog + logs).
  5. **Record a screen capture of each beat** (each money shot + the operator beats) as a backup, so any single live failure is a fall-back to video, not a dead demo.

### (b) Failure → fallback matrix

| Symptom | Likely cause | In-the-moment fallback | Prevent it |
|---|---|---|---|
| "Docker daemon not responding" | Docker Desktop not started | Start it, then re-run `make quickstart` | Start Docker before the session |
| "preflight: `<tool>` MISSING" | `uv` / `bob` / `npx` / `node` not installed | Install per the preflight hint, then re-run | Install all four beforehand |
| "`make up` hangs / gateway never healthy" | Slow or blocked image pull (conference wifi / proxy / `ghcr.io`) | Switch to a phone hotspot; or just watch the presenter and take the repo home | Pre-pull with `docker compose pull` beforehand |
| "Port already in use" | One of 4444 (gateway), 8090 (A2A inspector), 6274/6277 (MCP inspector), 7070 (companion), 3000/9001 (agents) is taken | Stop the conflicting app or free the port | Check those ports are free before |
| "Bob shows no tools / 'Disconnected'" | The FinOps/Operator UUID changed on reseed (stale UUID in `.bob/mcp.json`) | Re-run `make bob-install` (or `bob-install-operator`), restart Bob. `bob mcp list` "Disconnected" is a static status line until a live session — not a failure | Re-run `bob-install` after any `make seed` / `make demo-reset` |
| "Bob describes a result instead of doing it" | Bob read the repo source and narrated the answer instead of calling a tool | Tell it to **USE the finbyte-gateway tool**; confirm in the monitor's Logs (no gateway log line = it narrated, didn't call) | Prompt "use the finbyte-gateway tool", and keep `make monitor` visible |
| "401 from the gateway / wrapper exits at start" | Token isn't a registered user, or the wrapper is missing `DATABASE_URL` | Run `make bob-install` (uses the admin token + bakes `DATABASE_URL=sqlite:////tmp/mcpwrapper.db`) | Always configure Bob via `make bob-install` |
| "MCP Inspector shows no tools" | Pointed at a backend (not host-exposed) instead of at the gateway | Point it at the gateway `/servers/<uuid>/mcp` + bearer — exactly what `make inspect-mcp` prints | Use `make inspect-mcp` |
| "A2A Inspector slow / won't start" | First run clones + builds the image (~1–2 min) | Presenter leads the A2A Inspector; attendees use the lighter MCP Inspector | Pre-build it before the talk |
| "A control didn't fire / 16/16 fails" | Accumulated bad state | `make demo-reset`, then `make verify-controls` | Reset between runs |

### (c) Fallback ladder (if live Bob misbehaves on stage)
Work down this ladder — the point is that **the demo can never fully fail, because the controls are independently provable** even if the live agent acts up:
1. **`make verify-controls`** — proves all 16 controls headlessly and deterministically (block/allow), no agent in the loop.
2. **`make demo`** — the stage-gated walkthrough (cold start → register → scenarios → proof) that pauses at each stage.
3. **The recorded screen captures** of each beat (from pre-flight step 5).
4. **The take-home repo + `QUICKSTART.md`** — attendees run it later on their own.

## On-stage run order (45 min)
- **Architecture** (5 min): show `make ps` (8 services), `curl` both agent cards to prove Python vs Rust:
  - Python Auditor: `docker compose exec auditor python -c "import urllib.request,json;print(json.load(urllib.request.urlopen('http://localhost:9001/.well-known/agent-card.json'))['name'])"`
  - Rust Payments serves the same well-known path on :3000 (advertised in its agent card).
- **Baseline** (3 min): in Bob — *"Process expense exp_clean and reimburse it."* → succeeds.
- **Money shots** (~5 min each), each visible in `make logs`:
  1. *Policy*: *"Wire $50,000 to Acme LLC for expense exp_big."* → **blocked** with the T&E reason. Then *"…approve and wire $50,000 with dual approval"* → allowed. (Also: the Auditor→Rust `a2a-payments` $50k is blocked the same way — agent-mesh governance.)
  2. *Data protection*: *"Show me the receipt for expense exp_pii."* → SSN/card masked, key `[SECRET_REDACTED]`.
  3. *Injection*: *"Process expense exp_injection."* → the embedded "SYSTEM: ignore…" is `[INJECTION_BLOCKED]`.
  4. *Least-privilege*: *"Wire funds directly."* → Bob has no `wire` tool (FinOps excludes it).
- **Act 2 — Bob operates the control plane** (~5 min): switch Bob to the privileged operator persona — `make bob-install-operator`, restart Bob (the analyst persona deliberately has no operator tools — RBAC made concrete). Then, in Bob:
  1. *"List everything ContextForge is governing."* → `list_control_plane` (federated servers, A2A agents, virtual-server tool scopes).
  2. *"Would a $50,000 wire be allowed? What about with dual approval?"* → `evaluate_policy` (Bob interrogates OPA live: deny + reason, then allow).
  3. *"Finance just shipped an fx-rates service at http://fx-rates:8000/mcp — register it."* → `register_mcp_server`; fx-rates joins the catalog and its tools are now governed (re-run `list_control_plane` to show it).
  4. *"Show me what got blocked today."* → `recent_blocks` (the audit trail).
  Reset between runs: `make seed` un-registers fx-rates so the register beat repeats.
- **Proof** (5 min): `make verify-controls` → 16/16 green. Hand off the repo + `make bob-install`.
- **Q&A** (5 min).

## Reset between runs
- `make demo-reset` — restarts the gateway + expense-db (clears rate-limit lockouts, restores fixtures).
- Tokens expired? `make token` / `make bob-install` again (tokens last 7 days). Always re-run `make bob-install` after a reseed (UUID changes).

## Recovery
| Symptom | Fix |
|---|---|
| Bob lists no tools | re-run `make bob-install` (refreshes the FinOps UUID), restart Bob; confirm `curl -s localhost:4444/health` = 200 |
| Bob server "Disconnected" / wrapper exits | ensure `.bob/mcp.json` has `DATABASE_URL` in `env` (writable path); stale FinOps UUID → `make bob-install` |
| `make seed` warns "tool not found" | backends still starting; wait 5s and re-run `make seed` (idempotent) |
| Port 4444 in use | another gateway running: `make down`, or `pkill -f mcpgateway.main` (a host instance) |
| OPA shot not blocking | `docker compose ps opa` up? `make demo-reset`; check `gateway/policies/finops.rego` mounted |
| Live Bob flaky | fall back to `make verify-controls` + the recorded captures |

## Notes
- **Rate-limit live 429**: the limiter is enabled (in-memory). For a visible 429 on stage, lower
  `TOOL_RATE_LIMIT` in `.env` (e.g. `15`) and recreate the gateway, then hammer a tool ~20×.
- **Full profile** (`make up-full`) adds Phoenix for an OTEL trace of the governed call path.
- **RBAC 403** (vs the least-privilege shown here) needs a bootstrapped non-admin role — out of scope for the lite demo.
