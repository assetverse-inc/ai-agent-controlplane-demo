#!/usr/bin/env bash
# cockpit.sh — `make cockpit`: a tmux multi-pane control-plane "cockpit".
#
# Tiles the interactive Bob session (big left pane) alongside the live watch
# surfaces (gateway logs, OPA decisions, MCP Inspector, A2A Inspector) so an
# advanced user/presenter sees the whole control plane in one window with one
# command. Pure orchestration: every pane runs an existing `make <target>`, so
# all token-minting / UUID-lookup / log logic is reused, not duplicated.
#
# Two modes, keyed on $TMUX:
#   cold start (not in tmux) → build the `cockpit` session, attach.
#   augment   (in tmux)      → split the watch panes off the ACTIVE pane (run it
#                              from your Bob pane); records created pane ids in
#                              the @cockpit_panes session option for teardown.
#
# Persona: COCKPIT_PERSONA=operator swaps the Bob pane to `make bob-operator`
# (default: analyst → `make bob`).
#
# Tear down with:  make cockpit-down
#
# Usage:  make cockpit   (or: bash scripts/cockpit.sh)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# ── colours (only when attached to a TTY) ───────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$(tput bold 2>/dev/null); D=$(tput dim 2>/dev/null); R=$(tput sgr0 2>/dev/null)
  RED=$(tput setaf 1 2>/dev/null); GRN=$(tput setaf 2 2>/dev/null)
  YEL=$(tput setaf 3 2>/dev/null); CYN=$(tput setaf 6 2>/dev/null)
else B=; D=; R=; RED=; GRN=; YEL=; CYN=; fi

ok(){   printf "  ${GRN}✔${R} %s\n" "$*"; }
warn(){ printf "  ${YEL}!${R} %s\n" "$*"; }
die(){  printf "\n${RED}${B}STOPPED:${R} %s\n" "$*" >&2; exit 1; }
hd(){   echo; printf "${B}== %s ==${R}\n" "$*"; }

GW="http://localhost:4444"
SECRET="${SECRET:-demo-only-change-me-0123456789abcdef}"
MINT_CMD=(env DATABASE_URL=sqlite:///./.tokmint.db uv run --with mcp-contextforge-gateway -- \
  python -m mcpgateway.utils.create_jwt_token)

# Bob persona → which make target hosts the Bob pane.
PERSONA="${COCKPIT_PERSONA:-analyst}"
case "$PERSONA" in
  operator) BOB_TARGET="bob-operator" ;;
  analyst)  BOB_TARGET="bob" ;;
  *) die "COCKPIT_PERSONA must be 'analyst' or 'operator' (got '$PERSONA')." ;;
esac

# Inspector ports (for the SSH port-forward hint).
MCP_INSPECTOR_PORT=6274        # @modelcontextprotocol/inspector default client UI
MCP_INSPECTOR_PROXY_PORT=6277  # its proxy/API — the 6274 UI calls this; forward both or the UI loads but can't connect
A2A_INSPECTOR_PORT=8090        # `make inspect-a2a` publishes the container on :8090

SESSION="cockpit"

# ── preflight 1: tmux present? ───────────────────────────────────────────────
if ! command -v tmux >/dev/null 2>&1; then
  hd "tmux not found"
  cat <<EOF
  The cockpit needs tmux. Install it:
    macOS:  ${CYN}brew install tmux${R}
    Linux:  ${CYN}sudo apt-get install tmux${R}  (or your distro's package manager)

  Until then, open these in separate terminals/tabs by hand:
    ${CYN}make ${BOB_TARGET}${R}       — drive Bob
    ${CYN}make logs${R}        — gateway log tail
    ${CYN}make logs-opa${R}    — OPA ALLOW/DENY decisions
    ${CYN}make inspect-mcp${R} — MCP Inspector (the 8 governed tools)
    ${CYN}make inspect-a2a${R} — A2A Inspector (the agent cards)
    ${CYN}make monitor${R}     — ContextForge Admin UI
EOF
  exit 0
fi

# ── preflight 2: gateway healthy? ────────────────────────────────────────────
if ! curl -sf "$GW/health" >/dev/null 2>&1; then
  die "Stack isn't up — run ${CYN}make quickstart${R} first."
fi
ok "gateway healthy ($GW)"

# ── preflight 3: stack SEEDED? (FinOps virtual server exists) ─────────────────
# Reuse the Makefile's MINT pattern: mint an admin token, look up the FinOps
# server by name (same lookup inspect-mcp / companion use).
ADMIN=$("${MINT_CMD[@]}" -u admin@finbyte.demo --admin -e 10080 -s "$SECRET" 2>/dev/null | tail -1)
if [ -z "$ADMIN" ]; then
  die "couldn't mint an admin token — is ${CYN}uv${R} installed? (the stack is up but token minting failed)"
fi
FINOPS=$(curl -s -H "Authorization: Bearer $ADMIN" "$GW/servers" \
  | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if isinstance(s,dict) and s.get('name')=='FinOps']" 2>/dev/null | head -1)
if [ -z "$FINOPS" ]; then
  die "Gateway is up but not seeded — run ${CYN}make seed${R} (or ${CYN}make quickstart${R})."
fi
ok "stack seeded (FinOps server $FINOPS)"

# ── preflight 4: optional dependency probes (warn, never fatal) ───────────────
# Advisory: tell the user up front which panes will fail. A failing pane shows
# its error and waits for Enter before closing (see pane_cmd), so nothing is lost.
probe(){ command -v "$1" >/dev/null 2>&1 || warn "$1 not found — the '$2' pane will error out (shows the message, closes on Enter)"; }
probe npx     "inspect-mcp"
# inspect-a2a runs on either docker OR podman (the Makefile auto-detects) — warn
# only if NEITHER is present.
command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1 \
  || warn "no container runtime (docker/podman) — the 'inspect-a2a' pane will error out (shows the message, closes on Enter)"
probe git     "inspect-a2a (first-run build)"
probe python3 "logs-opa"
# Bob is optional. When it's absent the Bob pane shows a steady note pointing at
# the Companion instead of vanishing (see bob_pane_cmd) — the rest of the cockpit
# is fully usable without it.
command -v bob >/dev/null 2>&1 \
  || warn "IBM Bob not installed — the Bob pane will show a note pointing to the Companion (:7070); the rest of the cockpit works."

# ── preflight 5: TTY + size guard ────────────────────────────────────────────
if [ ! -t 1 ]; then
  die "run from an interactive terminal (no TTY detected — the cockpit attaches a tmux session)."
fi
# tput may fail under TERM=dumb / non-terminal stdout; fall back to a roomy default.
COLS=$(tput cols 2>/dev/null); ROWS=$(tput lines 2>/dev/null)
case "$COLS" in ''|*[!0-9]*) COLS=200 ;; esac
case "$ROWS" in ''|*[!0-9]*) ROWS=50  ;; esac
[ "$COLS" -ge 1 ] 2>/dev/null || COLS=200
[ "$ROWS" -ge 1 ] 2>/dev/null || ROWS=50
if [ "$COLS" -lt 120 ] || [ "$ROWS" -lt 32 ]; then
  warn "terminal is ${COLS}x${ROWS} — maximize your terminal, 5 panes need room (>=120x32)."
fi

# ── SSH-aware URL / browser handling ─────────────────────────────────────────
# The cockpit (tmux) works over SSH, but the browser surfaces live on the REMOTE
# host. Over SSH (or with no opener) print URLs + a port-forward hint instead of
# claiming a tab opened. Locally, reuse the `open || xdg-open` pattern.
have_opener(){ command -v open >/dev/null 2>&1 || command -v xdg-open >/dev/null 2>&1; }
# The HOW-TO page is the main consumption surface — it links to every UI and
# spells out the steps. Resolve it relative to this script so it works from
# any cwd.
HOWTO="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/docs/cockpit.html"
# The Companion dashboard (:7070) is the recommended demo surface the HOW-TO
# leads with, so start it automatically — in the background (it's a browser UI,
# not a terminal-watch pane). Skip if it's already serving. `make cockpit-down`
# stops it. The stack is already verified up+seeded by the preflights above.
start_companion(){
  if curl -sf -o /dev/null "http://localhost:7070" 2>/dev/null; then
    ok "companion already running → http://localhost:7070"
  else
    nohup make companion >/tmp/cockpit-companion.log 2>&1 &
    ok "companion starting in the background → http://localhost:7070"
  fi
}

open_howto(){
  # Stamp THIS session's admin token into a gitignored JS file the page reads,
  # so the HOW-TO can show a copy-paste token for the MCP Inspector.
  printf 'window.COCKPIT_TOKEN="Bearer %s";\n' "$ADMIN" \
    > "$(dirname "$HOWTO")/assets/cockpit-token.js" 2>/dev/null || true
  start_companion
  if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ] || ! have_opener; then
    cat <<EOF

  ${B}Remote session detected${R} — the UIs live on the remote host. Forward them:
    ${CYN}ssh -L 4444:localhost:4444 -L 7070:localhost:7070 -L ${MCP_INSPECTOR_PORT}:localhost:${MCP_INSPECTOR_PORT} -L ${MCP_INSPECTOR_PROXY_PORT}:localhost:${MCP_INSPECTOR_PROXY_PORT} -L ${A2A_INSPECTOR_PORT}:localhost:${A2A_INSPECTOR_PORT} <host>${R}
  Open the how-to guide locally: ${CYN}docs/cockpit.html${R}   (it links to every UI)
  Surfaces: Companion :7070 · Admin UI :4444/admin · MCP Inspector :${MCP_INSPECTOR_PORT} · A2A Inspector :${A2A_INSPECTOR_PORT}
EOF
  else
    echo "  Opening the HOW-TO guide → docs/cockpit.html (Cockpit view)"
    # Use a file:// URL with the #cockpit fragment so an already-open tab (maybe on
    # the #build view from `make dev-start`) re-renders to the Cockpit view. A bare
    # path would let `open` treat '#cockpit' as part of the filename.
    (open "file://$HOWTO#cockpit" 2>/dev/null || xdg-open "file://$HOWTO#cockpit" 2>/dev/null || true)
  fi
}

# The four stacked watch panes, top-to-bottom.
WATCH_TARGETS=(logs logs-opa inspect-mcp inspect-a2a)

# Build the command a pane runs. On a CLEAN exit the pane closes (no lingering
# "dead" pane to kill by hand); on an ERROR it holds the message until Enter so a
# missing-dep failure stays readable. This replaces a window-wide
# `remain-on-exit on`, which turned every normal exit into a dead pane the user
# had to kill manually (and, in augment mode, polluted their real window).
pane_cmd(){ echo "make $1 || { echo; echo '[$1 exited - scroll up to read; press Enter to close]'; read _; }; exit"; }

# Bob lives in the big left pane. If IBM Bob isn't installed, `make bob` prints an
# install notice and exits 0 — which, with pane_cmd, would close that 62%-wide
# pane instantly (the || never fires on a clean exit). Instead show a steady note
# that points at the Companion and HOLD the pane, so the layout stays intact.
bob_pane_cmd(){
  if command -v bob >/dev/null 2>&1; then
    pane_cmd "$BOB_TARGET"
  else
    echo "clear; printf '\n  IBM Bob is not installed on this machine.\n\n  Every other cockpit pane works without it. The Companion dashboard\n  shows the same governed demo:  http://localhost:7070\n\n  Install IBM Bob Shell (https://bob.ibm.com/download), then re-run make cockpit.\n\n  [idle pane - press Enter to close]\n'; read _; exit"
  fi
}

teardown_hint(){ printf "\n  %sto tear down:%s %smake cockpit-down%s\n" "$D" "$R" "$CYN" "$R"; }

# ── COLD START (not in tmux): build the session, attach ──────────────────────
cold_start(){
  # Re-run collision: a cockpit session already exists → attach to it.
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    warn "cockpit already running — attaching; ${CYN}make cockpit-down${R} first for a fresh layout."
    teardown_hint
    open_howto
    exec tmux attach -t "$SESSION"
  fi

  hd "Building the cockpit (Bob + 4 watch panes)"
  # Create detached WITH explicit geometry — a detached session otherwise
  # defaults to 80x24 and the percentage splits come out wrong.
  tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS"

  # Layout. split-window -p is relative to the target pane AT SPLIT TIME, so
  # order matters. We capture each pane's id (-P -F '#{pane_id}') rather than
  # assuming index 0 — the user's tmux may set base-index/pane-base-index to 1,
  # so hardcoded :0.0 targets don't exist. The geometry is identical: Bob keeps
  # the left ~62%, the right column splits into four ~25% stacked panes.
  local bob right p2 p3 p4
  bob=$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | head -1)   # the lone initial pane = Bob
  # Use `-l N%` (size of the NEW pane), not `-p N`: tmux 3.4 (Ubuntu 24.04,
  # current Fedora, recent Homebrew) dropped `-p` and errors "size missing",
  # which collapses the cockpit to a single pane. `-l N%` works on tmux 3.1+.
  right=$(tmux split-window -h -l 38% -t "$bob"   -P -F '#{pane_id}')  # right column, 38% width
  p2=$(tmux    split-window -v -l 75% -t "$right" -P -F '#{pane_id}')  # right ≈ top 25%
  p3=$(tmux    split-window -v -l 67% -t "$p2"    -P -F '#{pane_id}')  # ≈ next 25%
  p4=$(tmux    split-window -v -l 50% -t "$p3"    -P -F '#{pane_id}')  # last two ≈ 25% each

  # Send each pane its command. Bob in the big left pane; the four watch panes
  # top-to-bottom down the right column.
  tmux send-keys -t "$bob" "$(bob_pane_cmd)" Enter
  local watch_panes=("$right" "$p2" "$p3" "$p4") i=0
  for t in "${WATCH_TARGETS[@]}"; do
    tmux send-keys -t "${watch_panes[$i]}" "$(pane_cmd "$t")" Enter
    i=$((i + 1))
  done

  ok "cockpit session built — Bob persona: $PERSONA"
  teardown_hint
  open_howto
  exec tmux attach -t "$SESSION"
}

# ── AUGMENT (already in tmux): split watch panes off the active pane ──────────
augment(){
  hd "Augmenting the current tmux window with the watch panes"
  warn "augment tiles around the ACTIVE pane — run this from your Bob pane (it does not start a second Bob)."

  local anchor created=()
  anchor=$(tmux display-message -p '#{pane_id}')

  # First split halves the anchor pane width; then stack the four watch panes
  # in that new column. pane_cmd closes each pane cleanly on exit (no dead panes
  # left in the user's real window) and holds only on error.
  local pane
  pane=$(tmux split-window -h -t "$anchor" -P -F '#{pane_id}' "$(pane_cmd "${WATCH_TARGETS[0]}")")
  created+=("$pane")
  local prev="$pane" idx
  for idx in 1 2 3; do
    pane=$(tmux split-window -v -t "$prev" -P -F '#{pane_id}' "$(pane_cmd "${WATCH_TARGETS[$idx]}")")
    created+=("$pane")
    prev="$pane"
  done

  # Even out the four stacked panes.
  tmux select-layout -E >/dev/null 2>&1 || true

  # Record exactly the panes we created so cockpit-down can kill only these.
  tmux set-option @cockpit_panes "${created[*]}" >/dev/null

  ok "added ${#created[@]} watch panes (${created[*]})"
  teardown_hint
  open_howto
}

if [ -z "${TMUX:-}" ]; then
  cold_start
else
  augment
fi
