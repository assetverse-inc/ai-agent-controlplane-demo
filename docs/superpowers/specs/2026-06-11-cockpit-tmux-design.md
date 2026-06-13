# `make cockpit` — tmux multi-window control-plane cockpit

**Date:** 2026-06-11
**Status:** Design v2 (revised after Codex review), pending spec re-review
**Author:** brainstormed with Claude; hardened against Codex `/codex review` findings

## Problem

Advanced users and presenters want to watch *everything* at once — drive Bob while seeing the gateway logs, OPA policy decisions, the MCP Inspector, and the A2A Inspector live. Today this requires opening each surface by hand in separate terminals/tabs (the TALK-PREP guide literally instructs the presenter to do so). There is no single command that lays them all out together. `make companion` gives a single read-only browser dashboard, but not the multi-pane "cockpit" view.

## Goal

A `make cockpit` target that spawns a tmux session tiling the interactive Bob session alongside the live watch surfaces, so an advanced user gets the whole control plane in one window with one command. Must work on macOS and Linux, including over SSH — the demo's standing constraint is that it runs everywhere, not just the author's Mac.

## Non-goals

- Resizing the OS terminal window to fullscreen (not portable; the user maximizes their terminal).
- A new GUI. Terminal-native (tmux) plus the browser UIs the inspectors/monitor already open.
- Replacing `make companion` or the individual targets — the cockpit composes them.
- Windows support (tmux on Windows is via WSL; out of scope).

## Approach

A thin `cockpit` Makefile target delegates to `scripts/cockpit.sh`. Each tmux pane runs an existing `make <target>`, so the cockpit is **pure orchestration and reuses all current logic** — no duplicated token-minting, UUID lookups, or log commands.

### Mechanism: tmux (chosen)

tmux gives identical behavior on macOS/Linux, works over SSH/headless, and needs no per-terminal-emulator detection. Trade-off: it's a dependency. If tmux is absent the script prints an install hint and falls back to listing the individual targets (never an ugly crash). Native OS-window spawning and browser-tabs-only were considered and rejected (fragile/SSH-hostile; no home for Bob).

### Layout (cold-start mode)

One tmux session named `cockpit`, one window:

```
┌───────────────────────┬───────────────┐
│                       │ make logs     │  gateway log tail
│  make bob             ├───────────────┤
│  (interactive,        │ make logs-opa │  OPA ALLOW/DENY decisions
│   big left pane,      ├───────────────┤
│   ~62% width)         │ make inspect-mcp │ npx inspector (opens browser)
│                       ├───────────────┤
│                       │ make inspect-a2a │ docker run, serves :8090
└───────────────────────┴───────────────┘
```

`make monitor` (Admin UI) is a one-shot URL open, not a long-running process — fired once at startup (see SSH handling below), no dedicated pane. Bob defaults to the **analyst** persona (`make bob`); `COCKPIT_PERSONA=operator make cockpit` swaps the Bob pane to `make bob-operator`.

**Exact tmux construction (so percentages are deterministic — Codex P2 #7/#8).** `split-window -p` is relative to the *target pane at split time*, so order matters:

1. `tmux new-session -d -s cockpit -x "$COLS" -y "$ROWS"` — create detached **with explicit geometry** from `tput` (a detached session otherwise defaults to 80×24; Codex P2 #8). `COLS`/`ROWS` come from the size probe below, clamped to sane minimums.
2. Pane 0 holds Bob. `split-window -h -p 38 -t cockpit:0.0` → right column is 38% width (Bob keeps ~62%).
3. In the right column (now pane 1), split downward to get four roughly-equal stacked panes: `split-window -v -p 75 -t :0.1` (→ pane 1 ≈ 25%), then `split-window -v -p 67 -t :0.2`, then `split-window -v -p 50 -t :0.3`. Yields four right-column panes of ~25% each.
4. Send each pane its command with `send-keys -t :0.<n> 'exec make <target>' Enter`.
5. `set-window-option -t cockpit remain-on-exit on` **before** sending commands — so a pane whose command exits (e.g. a missing dependency) stays visible with its error instead of silently closing (Codex P1 #4). The status line shows `Pane is dead`; the user reads the error rather than wondering where the pane went.
6. `tmux attach -t cockpit`.

### `$TMUX`-aware behavior — two distinct modes

- **Cold start (`$TMUX` unset)** → build the `cockpit` session as above, attach. Cockpit hosts Bob; you do **not** pre-start Bob.
- **Augment (`$TMUX` set)** → you're already in tmux (e.g. you launched `make bob` in a pane and run `make cockpit` **from that Bob pane**). Do **not** spawn a second Bob. Capture the *current active pane* as the anchor (`tmux display-message -p '#{pane_id}'`) and split the four watch panes off it. Record the created pane ids in a session-scoped tmux user option (`@cockpit_panes`) so teardown can target exactly them.

  **Invocation rule (Codex P1 #6):** augment tiles around the **active pane at invocation**. Run it from the Bob pane. If run from a sibling pane it will (correctly) tile around that pane — documented, not a silent surprise. We do not try to hunt for "the Bob pane"; that heuristic is fragile.

**Hard limit (confirmed by Codex P2 #12):** a Bob (or any process) running in a **plain, non-tmux** terminal cannot be retrofitted into tmux — tmux cannot adopt an external process. Detected via `$TMUX` unset + no controlling pane; in that case cold-start mode runs and launches its own Bob.

### Preflight guards (in `scripts/cockpit.sh`, before building/augmenting)

1. **tmux missing** → install hint (`brew install tmux` / `sudo apt-get install tmux`) + list the individual targets as manual fallback. Exit 0.
2. **gateway not healthy** (`curl -sf localhost:4444/health` fails) → "Stack isn't up — run `make quickstart` first." Exit 1.
3. **stack up but NOT seeded** (Codex P1 #3 — the most likely real-world failure) → after health passes, mint an admin token and check the **FinOps virtual server exists** (the same lookup `inspect-mcp`/`companion` use: `GET /servers` → a server named `FinOps`). If absent → "Gateway is up but not seeded — run `make seed` (or `make quickstart`)." Exit 1. Without this, a healthy-but-unseeded stack silently breaks the Bob, `inspect-mcp` panes.
4. **dependency probes (Codex P1 #4)** → warn (not fatal) for missing optional deps so the user knows which panes will show errors: `npx` (inspect-mcp), `docker` + `git` + buildx (inspect-a2a first run), `python3` (logs-opa), and the Bob binary (`command -v bob`). `remain-on-exit on` means a missing dep yields a readable dead pane, not a vanished one.
5. **terminal too small / no TTY** (Codex P2 #9) → guard with `[ -t 1 ]`; if no TTY (e.g. piped), error "run from an interactive terminal." If `tput cols`/`lines` succeed and are < 120×32, warn "maximize your terminal — 5 panes need room" and continue. Tolerate `tput` failure / `TERM=dumb` by falling back to a 200×50 default geometry rather than erroring.

### SSH handling (Codex P2 #10)

The cockpit itself works over SSH (tmux). But the browser-based surfaces (Admin UI, MCP Inspector, A2A Inspector) run on the *remote* host. Over SSH the script must **not** claim a tab opened. Detection: `$SSH_CONNECTION`/`$SSH_TTY` set, or `open`/`xdg-open` absent. In that case print the URLs and a port-forward hint instead:

```
Remote session detected — these UIs are on the remote host. Forward them:
  ssh -L 4444:localhost:4444 -L 6274:localhost:6274 -L 8090:localhost:8090 <host>
Then open:  http://localhost:4444/admin · MCP Inspector · http://localhost:8090
```

Local sessions keep the existing `open || xdg-open` behavior from `make monitor`.

### Teardown (Codex P1 #1, #2)

- **Cold-start session:** `make cockpit-down` → `tmux kill-session -t cockpit 2>/dev/null`. Also explicitly `docker rm -f a2a-inspector 2>/dev/null` because killing the pane kills the `docker run` *client* but does not guarantee the container is removed (`--rm` only fires on a clean stop). Belt-and-suspenders so no orphaned inspector container survives.
- **Augment session (the gap Codex caught):** `cockpit-down` must **not** `kill-session` (that would destroy the user's unrelated window). Instead it reads `@cockpit_panes` and `kill-pane` only those ids, then `docker rm -f a2a-inspector`. `Ctrl-b &` is explicitly **not** the documented teardown for augment mode.
- The script writes a one-line "to tear down: `make cockpit-down`" hint on startup in both modes.

### Re-run / session collision (Codex P2 #11)

On cold start, if a `cockpit` session already exists: detect with `tmux has-session -t cockpit` and **attach to the existing one** (don't silently fail or stack a second). Print "cockpit already running — attaching; `make cockpit-down` first for a fresh layout."

## Components

| Unit | Responsibility | Depends on |
|---|---|---|
| `scripts/cockpit.sh` (new) | Preflight (tmux, health, **seed**, deps, TTY/size); cold-start build *or* augment; SSH-aware URL/port-forward output; attach | tmux, the `make` targets, `curl`, `tput`, the mint helper |
| `cockpit` target (Makefile) | `@bash scripts/cockpit.sh` | the script |
| `cockpit-down` target (Makefile) | mode-aware teardown: kill-session *or* kill-pane the recorded ids, plus `docker rm -f a2a-inspector` | tmux, docker |
| `inspect-a2a` fix (Makefile) | **carry-along (Codex P1 #5):** add `--add-host=host.docker.internal:host-gateway` to the `docker run` so the containerized inspector can reach the host A2A agents on native Linux Docker (macOS already resolves it; Linux does not by default) | docker |
| README/RUNBOOK note | "Advanced: watch everything with `make cockpit`" + the SSH port-forward tip | — |

## Cross-platform notes

- tmux commands are identical on macOS/Linux. The only OS-specific bit is the browser open, which reuses `open || xdg-open` and is skipped (with URLs printed) over SSH.
- `inspect-a2a` gains the `host-gateway` add-host so it works on Linux, not just macOS.
- `tput` is guarded; geometry falls back to a default if unavailable.

## Testing / verification

Manual (interactive tooling):
1. **No tmux** → install hint + fallback list, exit 0.
2. **Stack down** → "run `make quickstart` first", exit 1.
3. **Up but not seeded** → "run `make seed`", exit 1. *(the key new guard)*
4. **Up + seeded, cold start** → session builds with explicit geometry, Bob ~62%, four ~25% right panes, Admin UI tab opens (local).
5. **Missing optional dep** (e.g. rename `npx`) → that pane shows a readable error and stays (remain-on-exit), others run.
6. **Already in tmux, run from a Bob pane** → four watch panes added around it, no second Bob; `@cockpit_panes` recorded.
7. **`make cockpit-down`** in each mode → cold start kills the session; augment kills only the recorded panes and leaves the rest of the window; `docker ps` shows no `a2a-inspector`.
8. **Re-run cold start with session live** → attaches, prints the "already running" hint.
9. **Over SSH** → no false "tab opened"; prints URLs + the `ssh -L` port-forward line.
10. **`COCKPIT_PERSONA=operator`** → Bob pane runs the operator persona.

The change is additive (new script + `cockpit`/`cockpit-down` targets + a one-line `inspect-a2a` flag + a doc note); it touches no existing target's behavior except adding a host alias to `inspect-a2a`, so the CI gate (`make ci`) is unaffected.

## Open question for the implementer

The `inspect-mcp` pane runs `npx @modelcontextprotocol/inspector`, which prints a localhost URL with a one-time auth token and opens a browser. In a tmux pane that's fine locally; over SSH the token URL is on the remote host and must be port-forwarded (covered by the SSH block). No change needed, but the plan should confirm the inspector's default port for the port-forward hint (currently assumed 6274 — verify against the installed inspector version).
