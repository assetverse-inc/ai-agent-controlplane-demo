# Presenter RUNBOOK

## Prerequisites
A fresh machine needs these before step 1 (see the [README Prerequisites table](../README.md#prerequisites) for links):
- **Docker** — Docker Desktop on macOS/Windows, **OR** Docker Engine on Linux. The demo runs on a clean Linux box / VM, not only Docker Desktop; the OPA image is multi-arch so arm64 (Apple silicon / arm64 Linux) and amd64 both run natively, no emulation.
- **uv**, **git**, **make**.
- **Only to DRIVE / inspect Bob:** IBM Bob Shell plus **Node ≥ 22.15** (Bob Shell is a cross-platform Node app; Node also runs the MCP Inspector via `npx`). Install Bob on macOS/Linux with `curl -fsSL https://bob.ibm.com/download/bobshell.sh | bash` (it checks Node ≥22.15 first). On a bleeding-edge distro, use `nvm install 22` to satisfy the Node version. Bob and Node are **not** needed to bring up the stack or prove the controls headlessly (see step 2).

## Before the talk
1. `cp .env.example .env && make up && make seed` — wait for "gateway healthy" + the FinOps/Treasury UUIDs.
   - On a **fresh Linux VM**, set the Docker daemon DNS *before* the first build (see the build-time-DNS row in the failure matrix below). Image pulls can succeed while in-build `RUN` steps (cargo/pip) fail to resolve hosts; `{"dns":["8.8.8.8","1.1.1.1"]}` in `/etc/docker/daemon.json` + `sudo systemctl restart docker` fixes it.
2. `make verify-controls` → confirm **16 passed, 0 failed**. (This is your safety net: if live Bob misbehaves on stage, run this instead — it proves every control. `make quickstart` / `make verify-controls` reach 16/16 **without Bob installed** — a headless Linux VM or CI runner proves every control with no Bob needed; Bob is only required to DRIVE the demo.)
3. **`make bob`** → launches Bob as the FinOps analyst. **Driving Bob requires Node ≥ 22.15** (IBM Bob Shell is a cross-platform Node app; install via `curl -fsSL https://bob.ibm.com/download/bobshell.sh | bash`, and `nvm install 22` on a bleeding-edge distro). On a headless / Linux box the first run needs an IBMid device-code/URL login. `make bob` first (re)writes `.bob/mcp.json` (the project config Bob reads, relative to its cwd) with the current FinOps UUID + admin token, then starts Bob **from the repo root**. This is cwd-proof: launching `bob` by hand from the `bob-personas/` subfolder — or any other dir — makes Bob look for a non-existent `.bob/mcp.json` and print "No MCP servers configured" (then it asks you for the UUID/token). `make bob` also kills the **stale-UUID** failure (the #1 "Bob can't connect" cause) because it refreshes the config on every launch. (`bob mcp list` shows "Disconnected" until a live session — that status line is static, not a failure. `make bob-install` still exists if you only want to write the config without launching. If `bob` isn't installed, `make bob` / `make bob-operator` fail gracefully — they still write `.bob/mcp.json`, print an install hint, and exit 0.)
   - Bob connects through the `mcpgateway.wrapper` stdio bridge (`uvx --from mcp-contextforge-gateway python -m mcpgateway.wrapper`). The wrapper **must** have `DATABASE_URL` set to a writable path (the template uses `sqlite:////tmp/mcpwrapper.db`) or it crashes on startup importing `mcpgateway.config` (`OSError: Read-only file system: '/data'`). `make bob-config` bakes this in — that startup crash, not auth, was the old "Bob won't connect" bug.
4. Open three windows: (a) Bob, (b) `make logs` (gateway), (c) a terminal for `verify-controls` / curl.
5. Record a screen capture of each money shot as a backup.

## Live-room delivery (everyone runs it live)

This section is for the case where a **room of attendees** runs the demo on their own laptops, live, at the same time — not just the presenter. It complements (does not replace) the "Before the talk" checklist above and the "Recovery" table below.

### (a) Setup buffer / pre-flight
The realities of a live room:
- **Attendees should run `make quickstart` BEFORE the session** (or during a ~10-minute setup window at the start). The pinned ContextForge gateway image **pulls once** and **7 images build** from source the first time; on conference wifi the network is the risk, not the laptop.
- **Bob and npx are optional**: `make quickstart` warns in preflight if they're absent and still ends with **16/16**, so a headless Linux VM / CI runner proves every control with no Bob installed. Bob is needed only to DRIVE the demo.
- Cold start once images are cached: **~38 seconds** end-to-end (measured: `make down && make quickstart` → "16 passed, 0 failed"; slowest phase is the stack bring-up + gateway-health wait). **That number is build-only** — the **first-ever** run on a clean machine additionally pays the one-time ContextForge image pull + 7 source builds, so budget several minutes on first run / conference wifi.
- **Presenter pre-flight (do all of this before the room arrives):**
  1. Pre-run `make quickstart` and confirm it ends with the "Ready." card.
  2. Confirm `make verify-controls` = **16/16** (this is the headless safety net — it passes with no Bob installed).
  3. Know the two launch commands: **`make bob`** (FinOps analyst persona, Act 1) and **`make bob-operator`** (operator persona, Act 2). Both refresh the config and launch from the repo root — quit Bob before switching.
  4. Open the two panes you'll drive from: **Bob** (`make bob`) and **`make monitor`** (the ContextForge Admin UI — catalog + logs).
  5. **Record a screen capture of each beat** (each money shot + the operator beats) as a backup, so any single live failure is a fall-back to video, not a dead demo.

### (b) Failure → fallback matrix

| Symptom | Likely cause | In-the-moment fallback | Prevent it |
|---|---|---|---|
| "Docker daemon not responding" | Docker not started — Docker Desktop on Mac/Windows, OR the Docker Engine service (`dockerd`) on Linux | Start Docker Desktop, or on Linux `sudo systemctl start docker`; then re-run `make quickstart` | Start Docker (Desktop or the Linux Engine service) before the session |
| Build `RUN` steps fail with "Could not resolve host: index.crates.io" (or a pip/apt host) even though image **pulls** succeed | Fresh Docker Engine install whose build container inherits a dead systemd-resolved stub (`127.0.0.53`) | Create `/etc/docker/daemon.json` with `{"dns":["8.8.8.8","1.1.1.1"]}`, then `sudo systemctl restart docker`, then re-run `make quickstart` (idempotent) | On a fresh Linux VM, set the daemon DNS before the first build |
| "preflight: `<tool>` MISSING" | a REQUIRED tool (`docker` / `uv` / `curl` / `python3`) is missing | Install per the preflight hint, then re-run | Install the required tools beforehand |
| "preflight: `bob` / `npx` not found" (yellow `!`, not a hard MISSING) | Bob / Node are OPTIONAL — only needed to DRIVE / inspect the demo | Nothing to fix: quickstart still finishes `16 passed, 0 failed`. Install IBM Bob Shell (needs Node ≥22.15) to drive Bob | Only needed on the machine that drives Bob |
| "`make up` hangs / gateway never healthy" | Slow or blocked image pull (conference wifi / proxy / `ghcr.io`) | Switch to a phone hotspot; or just watch the presenter and take the repo home | Pre-pull with `docker compose pull` beforehand |
| "Port already in use" | One of 4444 (gateway), 8090 (A2A inspector), 6274/6277 (MCP inspector), 7070 (companion), 3000/9001 (agents) is taken | Stop the conflicting app or free the port | Check those ports are free before |
| "Bob shows no tools / 'Disconnected'" | The FinOps/Operator UUID changed on reseed (stale UUID in `.bob/mcp.json`) | Quit Bob and re-launch with `make bob` (or `make bob-operator`) — they refresh the UUID before launching. `bob mcp list` "Disconnected" is a static status line until a live session — not a failure | Always launch via `make bob` / `make bob-operator` (they refresh on every run) |
| "Bob says 'No MCP servers configured' / asks for the UUID & token" | `bob` was launched from the wrong directory (e.g. the `bob-personas/` subfolder); Bob reads `.bob/mcp.json` relative to its cwd | Quit it and run `make bob` — it launches from the repo root where `.bob/mcp.json` lives | Use `make bob` / `make bob-operator`, never a hand-launched `bob` from a subfolder |
| "Bob describes a result instead of doing it" | Bob read the repo source and narrated the answer instead of calling a tool | Tell it to **USE the finbyte-gateway tool**; confirm in the monitor's Logs (no gateway log line = it narrated, didn't call) | Prompt "use the finbyte-gateway tool", and keep `make monitor` visible |
| "401 from the gateway / wrapper exits at start" | Token isn't a registered user, or the wrapper is missing `DATABASE_URL` | Run `make bob-install` (uses the admin token + bakes `DATABASE_URL=sqlite:////tmp/mcpwrapper.db`) | Always configure Bob via `make bob-install` |
| "MCP Inspector shows no tools" | Pointed at a backend (not host-exposed) instead of at the gateway | Point it at the gateway `/servers/<uuid>/mcp` + bearer — exactly what `make inspect-mcp` prints | Use `make inspect-mcp` |
| "A2A Inspector slow / won't start" | First run clones + builds the image (~1–2 min) | Presenter leads the A2A Inspector; attendees use the lighter MCP Inspector | Pre-build it before the talk |
| "A control didn't fire / 16/16 fails" | Accumulated bad state | `make demo-reset`, then `make verify-controls` | Reset between runs |

### (c) Fallback ladder (if live Bob misbehaves on stage)
Work down this ladder — the point is that **the demo can never fully fail, because the controls are independently provable** even if the live agent acts up:
1. **`make verify-controls`** — proves all 16 controls headlessly and deterministically (block/allow), no agent in the loop. (Runs with no Bob installed.)
2. **`make demo`** — the stage-gated walkthrough (cold start → register → scenarios → proof) that pauses at each stage.
3. **The recorded screen captures** of each beat (from pre-flight step 5).
4. **The take-home repo + `QUICKSTART.md`** — attendees run it later on their own.

## On-stage run order (45 min)
- **Architecture** (5 min): show `make ps` (10 services), `curl` both agent cards to prove Python vs Rust:
  - Python Auditor: `docker compose exec auditor python -c "import urllib.request,json;print(json.load(urllib.request.urlopen('http://localhost:9001/.well-known/agent-card.json'))['name'])"`
  - Rust Payments serves the same well-known path on :3000 (advertised in its agent card).
- **Baseline** (3 min): in Bob — *"Process expense exp_clean and reimburse it."* → succeeds.
- **Money shots** (~5 min each), each visible in `make logs` — exact prompt→log-line map in [`LOG-CHEATSHEET.md`](LOG-CHEATSHEET.md):
  1. *Policy*: *"Wire $50,000 to Acme LLC for expense exp_big."* → **blocked** with the T&E reason. Then *"…approve and wire $50,000 with dual approval"* → allowed. (Also: the Auditor→Rust `a2a-payments` $50k is blocked the same way — agent-mesh governance.)
  2. *Data protection*: *"Show me the receipt for expense exp_pii."* → SSN/card masked, key `[SECRET_REDACTED]`.
  3. *Injection*: *"Process expense exp_injection."* → the embedded "SYSTEM: ignore…" is `[INJECTION_BLOCKED]`.
  4. *Least-privilege*: *"Wire funds directly."* → Bob has no `wire` tool (FinOps excludes it).
- **Act 2 — Bob operates the control plane** (~5 min): switch Bob to the privileged operator persona — quit Bob, then `make bob-operator` (the analyst persona deliberately has no operator tools — RBAC made concrete). Then, in Bob:
  1. *"List everything ContextForge is governing."* → `list_control_plane` (federated servers, A2A agents, virtual-server tool scopes).
  2. *"Would a $50,000 wire be allowed? What about with dual approval?"* → `evaluate_policy` (Bob interrogates OPA live: deny + reason, then allow).
  3. *"Finance just shipped an fx-rates service at http://fx-rates:8000/mcp — register it."* → `register_mcp_server`; fx-rates joins the catalog and its tools are now governed (re-run `list_control_plane` to show it).
  4. *"Show me what got blocked today."* → `recent_blocks` (the audit trail).
  Reset between runs: `make seed` un-registers fx-rates so the register beat repeats.
- **Proof** (5 min): `make verify-controls` → 16/16 green. Hand off the repo + `make bob`.
- **Q&A** (5 min).

## Reset between runs
- `make demo-reset` — restarts the gateway + expense-db (restores fixtures).
- Tokens expired? Just re-launch with `make bob` (tokens last 7 days; `make bob` mints a fresh one and rewrites `.bob/mcp.json` every time). The same refresh covers the UUID change after a reseed.

## Recovery
| Symptom | Fix |
|---|---|
| Bob lists no tools | re-launch with `make bob` (refreshes the FinOps UUID from the repo root), confirm `curl -s localhost:4444/health` = 200 |
| Bob server "Disconnected" / wrapper exits | ensure `.bob/mcp.json` has `DATABASE_URL` in `env` (writable path); stale FinOps UUID → `make bob` |
| Bob "No MCP servers configured" / asks for UUID+token | launched from the wrong dir (cwd has no `.bob/mcp.json`) → use `make bob` (launches from the repo root) |
| `bob` not found / won't launch | `bob` isn't installed — `make bob` writes the config + prints an install hint and exits 0. Install IBM Bob Shell (`curl -fsSL https://bob.ibm.com/download/bobshell.sh \| bash`, needs **Node ≥ 22.15**); the stack + `make verify-controls` still prove 16/16 without it |
| Docker build fails: "Could not resolve host" (cargo/pip/apt) but pulls work | fresh Docker Engine inherited a dead resolver — add `{"dns":["8.8.8.8","1.1.1.1"]}` to `/etc/docker/daemon.json`, `sudo systemctl restart docker`, re-run `make quickstart` (idempotent) |
| `make seed` warns "tool not found" | backends still starting; wait 5s and re-run `make seed` (idempotent) |
| Port 4444 in use | another gateway running: `make down`, or `pkill -f mcpgateway.main` (a host instance) |
| OPA shot not blocking | `docker compose ps opa` up (not crash-looping)? `make demo-reset`. The Rego is **baked into the opa image** (`gateway/Dockerfile.opa`, `COPY policies /policies`) — there's no host bind-mount to check |
| Live Bob flaky | fall back to `make verify-controls` + the recorded captures |

## Notes
- **RBAC 403** (vs the least-privilege shown here) needs a bootstrapped non-admin role — out of scope for the lite demo.
- **Not in this release:** rate limiting and a heavier Postgres/Redis/nginx/Phoenix-OTEL "full" profile. The demo ships one SQLite-backed lite stack; both are upstream-supported follow-ups if you want to add them.
