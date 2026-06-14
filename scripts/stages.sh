#!/usr/bin/env bash
# stages.sh — the Dev Day "progressive build" track. Walks a room from a bare,
# ungoverned MCP server up to the full governed mesh, ONE stage at a time, so
# attendees see *why* ContextForge earns its place instead of meeting the
# finished stack all at once (that top-down path is `make quickstart`).
#
#   make stage1-build      Bob builds a tool → run it RAW, inspect it UNGOVERNED
#   make stage2-govern     put that same tool behind ContextForge (catalog + token)
#   make stage3-controls   seed the mesh → the four controls start biting
#   make stage4-mesh        the full governed picture (== quickstart end-state)
#
# Each stage is a *scene-setter*: it prepares state, opens the right window, and
# prints the exact thing to tell Bob — then you drive Bob live. Every stage has a
# deterministic fallback so a wobbly live edit never strands the talk.
#
# Usage:  bash scripts/stages.sh {build|govern|controls|mesh|reset}
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$(tput bold 2>/dev/null); D=$(tput dim 2>/dev/null); R=$(tput sgr0 2>/dev/null)
  GRN=$(tput setaf 2 2>/dev/null); YEL=$(tput setaf 3 2>/dev/null)
  BLU=$(tput setaf 4 2>/dev/null); CYN=$(tput setaf 6 2>/dev/null)
else B=; D=; R=; GRN=; YEL=; BLU=; CYN=; fi

hd(){ echo; printf "${B}${BLU}━━ %s ━━${R}\n" "$*"; }
ok(){ printf "  ${GRN}✔${R} %s\n" "$*"; }
no(){ printf "  ${YEL}!${R} %s\n" "$*"; }
say(){ printf "%s\n" "$*"; }
bob(){ printf "     ${CYN}▸ %s${R}\n" "$*"; }   # an exact line to type at Bob

RAW_PORT=8000
RAW_PIDFILE=/tmp/finbyte-stage1-raw.pid
RAW_LOG=/tmp/finbyte-stage1-raw.log
# Stage 1: Bob writes this MCP server FROM SCRATCH (generated, NOT committed — and
# deliberately NOT gitignored, since Bob refuses to write ignored paths); _solution.py
# is the tracked fallback (make stage1-scaffold). In Stage 2 this same server is
# containerised (docker-compose.salestax.yml) and onboarded as the dev's own tool.
SCRATCH_DIR=mcp-servers/sales-tax
SCRATCH_SRC=$SCRATCH_DIR/server.py
HOWTO=docs/build.html

stop_raw(){
  [ -f "$RAW_PIDFILE" ] && { kill "$(cat "$RAW_PIDFILE")" 2>/dev/null || true; rm -f "$RAW_PIDFILE"; }
  pkill -f "$SCRATCH_SRC" 2>/dev/null || true
}

start_raw(){
  stop_raw
  # Run the server bare on the host — no container, no gateway, no policy. This
  # IS the "ungoverned" baseline. fastmcp pinned to match the repo's Dockerfiles.
  ( uv run --with fastmcp==3.3.1 python "$SCRATCH_SRC" >"$RAW_LOG" 2>&1 & echo $! >"$RAW_PIDFILE" )
  for _ in $(seq 1 40); do
    curl -sf "localhost:$RAW_PORT/health" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

wait_salestax_container(){  # the CONTAINER answers on host :8001 (raw still owns :8000)
  for _ in $(seq 1 40); do
    curl -sf "localhost:8001/health" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

open_build_guide(){ # open the follow-along build guide — SSH-aware, never fatal
  if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ] || ! { command -v open >/dev/null 2>&1 || command -v xdg-open >/dev/null 2>&1; }; then
    say "  ${D}Follow-along guide (copy-paste Bob prompts):${R} open ${CYN}$HOWTO${R}."
  else
    ( open "$HOWTO" 2>/dev/null || xdg-open "$HOWTO" 2>/dev/null || true )
    say "  ${D}Opened the follow-along guide → $HOWTO.${R}"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
stage_build(){
  hd "STAGE 1/4 — Bob builds an MCP server FROM SCRATCH (no governance)"
  say "The starting point every developer recognises: a plain MCP server on your"
  say "laptop. No gateway, no policy, no auth. Whoever reaches the port runs any tool."
  echo
  say "${B}① Tell Bob to build it${R} (the copy-paste prompt is on the prompt-card):"
  bob "Create a new MCP server with fastmcp at $SCRATCH_SRC: a tool add_tax(amount, rate_pct=8.5) returning {amount, rate_pct, tax, total}, plus a GET /health route, served over HTTP on 0.0.0.0:8000."
  say "  ${D}Fallback if Bob's file won't run:${R} ${CYN}make stage1-scaffold${R}  ${D}(drops in the finished server)${R}"
  echo

  if [ ! -f "$SCRATCH_SRC" ]; then
    no "$SCRATCH_SRC doesn't exist yet."
    say "  Have Bob create it (prompt above), or run ${CYN}make stage1-scaffold${R} — then re-run ${CYN}make stage1-build${R}."
    open_build_guide
    exit 0
  fi

  command -v uv >/dev/null 2>&1 || { no "uv not found — needed to run the bare server. See https://docs.astral.sh/uv/"; exit 1; }
  say "${B}② Running Bob's server bare on :$RAW_PORT${R} (no gateway, no policy, no auth)…"
  if start_raw; then
    ok "live & UNGOVERNED at http://localhost:$RAW_PORT/mcp  (the server Bob just wrote)"
  else
    no "the server didn't answer on :$RAW_PORT — last log lines:"; tail -8 "$RAW_LOG" 2>/dev/null | sed 's/^/    /'
    say "  If Bob's file has a bug, drop in the known-good one: ${CYN}make stage1-scaffold${R}, then re-run."
    exit 1
  fi
  echo
  say "${B}③ Call it — proof it works (and that's the problem):${R}"
  if uv run --with fastmcp==3.3.1 python scripts/salestax_smoke.py; then
    ok "called add_tax over MCP — no token, no policy, no audit. Anyone on the network could."
  else
    no "smoke call failed — if Bob's server has a bug, drop in the known-good one: ${CYN}make stage1-scaffold${R}, then re-run."
  fi
  echo
  say "Want to poke it by hand too? Open the MCP Inspector (no token field):"
  echo
  command -v npx >/dev/null 2>&1 || { no "npx not found (Node ≥18) — skipping the Inspector; the bare server is still up on :$RAW_PORT."; \
    say "  When you're ready to govern it:  ${CYN}make stage2-govern${R}"; open_build_guide; exit 0; }

  rm -f /tmp/mcp-raw-*.json 2>/dev/null || true
  CFG=$(mktemp /tmp/mcp-raw-XXXXXX); mv "$CFG" "$CFG.json"; CFG="$CFG.json"
  printf '{"mcpServers":{"sales-tax-RAW":{"type":"streamable-http","url":"http://localhost:%s/mcp"}}}\n' "$RAW_PORT" > "$CFG"
  say "  In the Inspector:  Connection Type → ${B}Via Proxy${R}, then ${B}Connect${R} (no auth needed)."
  say "  ${D}When you're ready to govern it:  ${R}${CYN}make stage2-govern${R}${D} (stops this bare server).${R}"
  open_build_guide
  echo
  DANGEROUSLY_OMIT_AUTH=true npx -y @modelcontextprotocol/inspector --config "$CFG" --server sales-tax-RAW
  echo
  ok "Inspector closed. The bare server is still up on :$RAW_PORT (stop it: make stage2-govern, or: bash scripts/stages.sh reset)."
}

# ──────────────────────────────────────────────────────────────────────────────
stage_govern(){
  hd "STAGE 2/4 — govern the tool you just built (register → grant → call)"
  say "Same code — now it goes into the mesh: containerised, in the catalog, and"
  say "reachable only through the one governed seam with a token."
  echo

  if [ ! -f "$SCRATCH_SRC" ]; then
    no "$SCRATCH_SRC doesn't exist — you can't govern what wasn't built."
    say "  Run ${CYN}make stage1-build${R} (have Bob write it) or ${CYN}make stage1-scaffold${R}, then re-run ${CYN}make stage2-govern${R}."
    exit 0
  fi

  say "Bringing up the gateway + OPA + backends (idempotent)…"
  make up   || { no "stack failed to start — see: make logs"; exit 1; }
  make seed || { no "seed failed — retry 'make seed'"; exit 1; }
  ok "mesh seeded — catalog + Operator virtual server built"
  make -s bob-install-operator >/dev/null 2>&1 && ok "Bob set to the OPERATOR persona (can register)" \
    || no "couldn't set operator persona — run 'make bob-install-operator'"
  echo

  say "${B}②a Containerise the tool you built${R} (on the mesh network):"
  make salestax-up || { no "couldn't build/run the sales-tax container — see 'make logs'"; exit 1; }
  if wait_salestax_container; then
    ok "sales-tax container healthy on :8001"
    stop_raw && ok "retired the bare Stage-1 process on :8000 (the container takes over)"
  else
    no "the sales-tax container didn't answer on :8001 — check 'make logs'"; exit 1
  fi
  echo

  say "${B}②b Register it${R} — drive Bob (operator):"
  bob "Register the sales-tax service at http://sales-tax:8000/mcp."
  bob "List everything ContextForge is governing."
  say "  ${D}Fallback:${R} ${CYN}make salestax-register${R}"
  say "  ${D}It's now in the catalog, token-gated — but Bob still ${B}can't call it${R}.${D}"
  say "  Exposing a tool to an agent is a separate grant. That gate ${B}is${R}${D} least-privilege.${R}"
  echo

  say "${B}②c Grant it + call it${R} — make the tool you built usable by your agent:"
  say "  ${CYN}make salestax-grant${R}   ${D}(adds add_tax to a 'Builder' vserver + switches Bob to the builder persona)${R}"
  bob "Add sales tax to \$100."
  say "  ${D}→ governed call through :4444 → 108.50. Built → governed → ${B}used${R}.${D} The loop closes.${R}"
  echo

  say "${B}②d Bonus — have Bob extend an EXISTING service${R} (fx-rates):"
  bob "Add a convert(amount, base, quote) tool to the fx-rates service at mcp-servers/fx-rates/server.py, then rebuild it."
  bob "Re-register fx-rates and convert 1000 USD to EUR."
  say "  ${D}Fallback (does all of it):${R} ${CYN}make fxrates-extend${R}"
  say "  ${D}build-from-scratch (sales-tax) AND extend-existing (fx-rates), both governed.${R}"
  echo

  ( open http://localhost:4444/admin 2>/dev/null || xdg-open http://localhost:4444/admin 2>/dev/null || true )
  say "Watch both land in the catalog → ${CYN}make monitor${R} (Admin UI). Next: ${CYN}make stage3-controls${R}"
}

# ──────────────────────────────────────────────────────────────────────────────
stage_controls(){
  hd "STAGE 3/4 — turn the four controls on"
  say "Being in the catalog only buys auth + a single seam. The *interesting* controls"
  say "live in the FinOps mesh — watch each one bite a real call Bob makes."
  echo
  make seed >/dev/null 2>&1 || { no "seed failed — retry 'make seed' (is the stack up? 'make stage2-govern')"; exit 1; }
  ok "FinOps mesh ready (seeded in Stage 2; re-checked here so this stage stands alone)"
  make -s bob-install >/dev/null 2>&1 && ok "Bob set back to the ANALYST persona (8 tools, no wire)" || true
  echo
  say "${B}Open a second pane for the live decision stream:${R}  ${CYN}make logs-opa${R}"
  echo
  say "${B}Drive Bob (analyst) — one prompt hits all four controls:${R}"
  bob "Process today's pending expenses end to end. For each: read it, check its receipt, approve and reimburse anything clean, and flag anything that needs a wire."
  echo
  say "  ${D}What the room should see fire:${R}"
  say "     exp_pii        → ${B}PII/secret redacted${R}     (***-**-6789, [SECRET_REDACTED])"
  say "     exp_injection  → ${B}injection neutralized${R}   ([INJECTION_BLOCKED])"
  say "     exp_big \$50k    → ${B}OPA blocks the wire${R}     (cross-language Python→Rust)"
  say "     (Bob itself has ${B}no wire tool${R} — least-privilege / RBAC)"
  echo
  say "  ${D}Reset fixtures between runs:${R} ${CYN}make demo-reset${R}"
  say "  ${D}Headless proof of all four anytime:${R} ${CYN}make verify-controls${R}  → 16/16"
  say "Next: ${CYN}make stage4-mesh${R}"
}

# ──────────────────────────────────────────────────────────────────────────────
stage_mesh(){
  hd "STAGE 4/4 — the full governed mesh"
  say "This is where ${CYN}make quickstart${R} would have dropped you in one shot — but now"
  say "the room watched it get built. Prove the whole thing, then pick a cockpit."
  echo
  make verify-controls || no "some checks failed — 'make demo-reset' then retry"
  echo
  say "${B}Drive it from here:${R}"
  say "  • ${CYN}make cockpit${R}      tmux: Bob + logs + OPA + both inspectors in one window"
  say "  • ${CYN}make companion${R}    browser evidence dashboard → http://localhost:7070"
  say "  • ${CYN}make monitor${R}      ContextForge Admin UI (catalog + Logs)"
  say "  • ${CYN}make bob-operator${R} Act 2 — Bob operates the control plane"
  echo
  ok "Progressive build complete: bare tool → governed → controlled → full mesh."
}

case "${1:-}" in
  build)    stage_build ;;
  govern)   stage_govern ;;
  controls) stage_controls ;;
  mesh)     stage_mesh ;;
  reset)
    stop_raw
    rm -f "$SCRATCH_SRC"
    make -s salestax-down >/dev/null 2>&1 || true
    if ! git diff --quiet -- mcp-servers/fx-rates/server.py 2>/dev/null; then
      echo "note: discarding local edits to mcp-servers/fx-rates/server.py (restoring committed version)."
    fi
    git checkout HEAD -- mcp-servers/fx-rates/server.py 2>/dev/null || true
    echo "reset: stopped the bare server, removed $SCRATCH_SRC, stopped the sales-tax container, restored base fx-rates ( _solution.py / server_with_convert.py kept )."
    ;;
  *) echo "usage: bash scripts/stages.sh {build|govern|controls|mesh|reset}" >&2; exit 2 ;;
esac
