SHELL := /bin/bash
SECRET := demo-only-change-me-0123456789abcdef
# Mint tokens offline. Override DATABASE_URL so settings validation doesn't try
# to create the container's /data dir (read-only on the host).
MINT := DATABASE_URL=sqlite:///./.tokmint.db uv run --with mcp-contextforge-gateway -- python -m mcpgateway.utils.create_jwt_token
# Container runtime + compose command. Prefer docker; fall back to podman so the
# demo runs everywhere (the standing constraint), not just on a Docker machine.
# Both auto-detect once; override either explicitly, e.g.:
#   make up CONTAINER=podman COMPOSE="podman compose"
DETECTED_CONTAINER := $(shell command -v docker >/dev/null 2>&1 && echo docker || echo podman)
# Prefer Docker Compose v2 (`docker compose` or the standalone `docker-compose`
# binary) — it handles this 10-service stack correctly. The legacy python
# `podman-compose` mishandles long-form env_file, shared build contexts, and
# depends_on, so on Podman the documented path is docker-compose v2 against the
# Podman socket (see RUNBOOK "Run on Podman"); `podman compose` is the fallback.
DETECTED_COMPOSE := $(shell \
	if command -v docker >/dev/null 2>&1; then echo "docker compose"; \
	elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"; \
	elif command -v podman >/dev/null 2>&1; then echo "podman compose"; \
	else echo "docker compose"; fi)
CONTAINER ?= $(DETECTED_CONTAINER)
COMPOSE ?= $(DETECTED_COMPOSE)
# On Podman, drive the stack through docker-compose against the rootless Podman
# API socket, and use the classic (buildah) builder — Compose v2's buildkit
# driver collides on parallel builds over the Podman socket. Both are defaults
# (?=), so an explicit env override still wins. Requires the socket to be live:
#   systemctl --user enable --now podman.socket   (scripts/test-fresh-host.sh does this)
ifeq ($(CONTAINER),podman)
DOCKER_HOST ?= unix:///run/user/$(shell id -u)/podman/podman.sock
DOCKER_BUILDKIT ?= 0
export DOCKER_HOST DOCKER_BUILDKIT
endif

.PHONY: help check clean up down seed token token-bob bob bob-operator bob-config bob-install bob-config-operator bob-install-operator bob-config-builder bob-install-builder connect companion logs logs-opa verify-controls demo-reset ps demo quickstart monitor inspect-mcp inspect-a2a cockpit cockpit-down fxrates-convert fxrates-reset fxrates-register dev-start stage1-build stage1-scaffold stage2-govern stage3-controls stage4-mesh stage-reset salestax-up salestax-down salestax-register salestax-grant fxrates-extend

# `make` (no target) prints this curated, categorized help. Keep it in sync when you
# add/rename a target — the inline `## ...` comments still document each target too.
help:
	@printf "\n\033[1mIBM Bob × ContextForge — the AI agent control plane\033[0m\n"
	@printf "  make <target> — grouped below. New here? run \033[36mmake quickstart\033[0m first.\n"
	@printf "\n\033[1m🚀 START HERE\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "quickstart" "ONE command: stack → seed → configure Bob → prove 16/16 + card"
	@printf "  \033[36m%-22s\033[0m %s\n" "verify-controls" "Prove all four controls headlessly → \"16 passed, 0 failed\""
	@printf "  \033[36m%-22s\033[0m %s\n" "demo" "Stage-gated end-to-end walkthrough (pauses at each stage)"
	@printf "  \033[36m%-22s\033[0m %s\n" "check" "Verify ALL prerequisites are installed + live stack status"
	@printf "\n\033[1m🎓 DEV DAY — PROGRESSIVE BUILD (bare tool → governed mesh)\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "dev-start" "Open the prompt-card page (start here — copy-paste Bob prompts per stage)"
	@printf "  \033[36m%-22s\033[0m %s\n" "stage1-build" "Bob builds an MCP server from scratch → run RAW + inspect UNGOVERNED"
	@printf "  \033[36m%-22s\033[0m %s\n" "stage2-govern" "Put that tool behind ContextForge (seed catalog + token + Bob registers it)"
	@printf "  \033[36m%-22s\033[0m %s\n" "stage3-controls" "Exercise the four controls (Bob's analyst queue + logs-opa)"
	@printf "  \033[36m%-22s\033[0m %s\n" "stage4-mesh" "The full governed picture (== quickstart end-state)"
	@printf "\n\033[1m🤖 DRIVE BOB\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob" "Launch Bob — FinOps analyst (Act 1; cwd-proof, refreshes config)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-operator" "Launch Bob — platform operator (Act 2)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-install" "Write .bob/mcp.json for the analyst persona (no launch)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-install-operator" "Write .bob/mcp.json for the operator persona (no launch)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-config" "Print the analyst MCP config (to paste elsewhere)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-config-operator" "Print the operator MCP config"
	@printf "  \033[36m%-22s\033[0m %s\n" "connect" "Print the 1 command to point a REMOTE/LOCAL Bob at this gateway (Codespaces/BYOB)"
	@printf "\n\033[1m🛰  STACK\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "up" "Build + start the stack (gateway, OPA, 6 MCP servers, 2 A2A agents)"
	@printf "  \033[36m%-22s\033[0m %s\n" "down" "Stop the stack"
	@printf "  \033[36m%-22s\033[0m %s\n" "seed" "Register servers/agents + build the FinOps/Treasury/Operator vservers"
	@printf "  \033[36m%-22s\033[0m %s\n" "demo-reset" "Recreate + reseed the gateway to a known-good state"
	@printf "  \033[36m%-22s\033[0m %s\n" "ps" "Show running services"
	@printf "  \033[36m%-22s\033[0m %s\n" "clean" "Stop everything + remove generated/temp files (keeps images, .env, evidence)"
	@printf "\n\033[1m👀 OBSERVE\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "monitor" "Open the ContextForge Admin UI (catalog + Logs)"
	@printf "  \033[36m%-22s\033[0m %s\n" "logs" "Tail gateway logs (control firings: AUDIT [FinByteGuard])"
	@printf "  \033[36m%-22s\033[0m %s\n" "logs-opa" "Live, readable OPA decisions (ALLOW/DENY + reason)"
	@printf "  \033[36m%-22s\033[0m %s\n" "inspect-mcp" "MCP Inspector → the 8 governed tools (wire absent)"
	@printf "  \033[36m%-22s\033[0m %s\n" "inspect-a2a" "A2A Inspector → validate the Python + Rust agent cards"
	@printf "  \033[36m%-22s\033[0m %s\n" "companion" "Browser evidence dashboard on :7070"
	@printf "  \033[36m%-22s\033[0m %s\n" "cockpit" "tmux cockpit: Bob + logs + OPA + both inspectors in one window"
	@printf "  \033[36m%-22s\033[0m %s\n" "cockpit-down" "Tear down the cockpit (kill session/panes + a2a-inspector)"
	@printf "\n\033[1m🎬 SHOWCASE\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "fxrates-convert" "Apply the finished fx-rates (adds convert) + rebuild"
	@printf "  \033[36m%-22s\033[0m %s\n" "fxrates-reset" "Restore base fx-rates so the \"Bob builds it\" beat repeats"
	@printf "\n\033[1m🔑 TOKENS\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "token" "Print an admin JWT"
	@printf "  \033[36m%-22s\033[0m %s\n" "token-bob" "Print Bob's JWT"
	@printf "\n\033[1m✅ QUALITY / CI\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "ci" "Aggregate CI gate (lint + bandit + compose-validate)"
	@printf "  \033[36m%-22s\033[0m %s\n" "format" "Auto-fix Python (ruff --fix + black)"
	@printf "  \033[36m%-22s\033[0m %s\n" "lint" "Lint Python (ruff + black --check)"
	@printf "  \033[36m%-22s\033[0m %s\n" "lint-rust" "fmt + clippy the Rust agent"
	@printf "  \033[36m%-22s\033[0m %s\n" "test" "Run pytest"
	@printf "  \033[36m%-22s\033[0m %s\n" "bandit" "Python source security scan"
	@printf "  \033[36m%-22s\033[0m %s\n" "pip-audit" "Dependency CVE scan"
	@printf "  \033[36m%-22s\033[0m %s\n" "secrets-baseline" "Secret scan (detect-secrets)"
	@printf "  \033[36m%-22s\033[0m %s\n" "sbom" "Generate CycloneDX SBOM"
	@printf "  \033[36m%-22s\033[0m %s\n" "hadolint" "Lint Dockerfiles"
	@printf "  \033[36m%-22s\033[0m %s\n" "compose-validate" "Validate docker-compose.yml"
	@printf "  \033[36m%-22s\033[0m %s\n" "smoke" "Post-up gateway health probe"
	@printf "  \033[36m%-22s\033[0m %s\n" "trivy" "Image CVE scan"
	@printf "\n"

.env:
	cp .env.example .env

check: ## Verify ALL prerequisites (required + optional) + live stack status; exits 1 if a required tool is missing
	@bash scripts/check.sh

# Stop every demo process and delete generated/ephemeral files so the next run
# starts clean. KEEPS: built images (slow to rebuild), .env (your config), and
# docs/evidence (the captured catalog). For a full wipe incl. the gateway DB
# volume + images, the last line prints the one-shot command.
clean: ## Stop everything + remove generated/temp files (keeps images, .env, evidence)
	-@bash scripts/stages.sh reset >/dev/null 2>&1 || true
	-@$(MAKE) -s cockpit-down >/dev/null 2>&1 || true
	-@$(COMPOSE) down --remove-orphans >/dev/null 2>&1 || true
	@rm -f .env.tokens .tokmint.db .bob/mcp.json docs/assets/cockpit-token.js 2>/dev/null || true
	@rm -f /tmp/mcp-finops-*.json /tmp/mcp-raw-*.json /tmp/_qs_verify.out /tmp/finbyte-* /tmp/cockpit-* /tmp/stage1.* 2>/dev/null || true
	@echo "✔ cleaned: stack stopped · generated/temp files removed · sales-tax/server.py dropped"
	@echo "  kept: built images, .env, docs/evidence/"
	@printf '  full wipe (also volumes + local images):  %s down -v --rmi local\n' "$(COMPOSE)"

token: ## Print an admin JWT
	@$(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET)

token-bob: ## Print Bob's JWT (paste into .bob/mcp.json)
	@$(MINT) -u bob@finbyte.demo --admin -e 10080 -s $(SECRET)

up: .env ## Build + start the lite stack
	@echo "AUDITOR_TOKEN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET))" > .env.tokens
	$(COMPOSE) --env-file .env.tokens up -d --build
	@echo "waiting for gateway health..."; \
	for i in $$(seq 1 40); do curl -sf localhost:4444/health >/dev/null 2>&1 && { echo "gateway healthy"; break; } || sleep 2; done

seed: ## Register servers/agents + build FinOps/Treasury virtual servers
	@ADMIN_TOKEN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET)) \
	  uv run --with httpx python gateway/seed/seed.py

# NOTE: the token must be for a REGISTERED gateway user. admin@finbyte.demo is
# the seeded platform admin; a bob@finbyte.demo token is signed correctly but the
# gateway 401s it (no such user). Least-privilege is enforced by the FinOps
# virtual server (the UUID in MCP_SERVER_URL exposes 8 tools, hides wire), not by
# the token identity — so the admin-subject token is the right choice here.
bob-config: ## Print the Bob MCP config (mcpgateway.wrapper, live FinOps UUID + admin token)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='FinOps']" 2>/dev/null | head -1); \
	if [ -z "$$UUID" ]; then echo "FinOps server not found — run 'make seed' first" >&2; exit 1; fi; \
	sed -e "s|REPLACE_FINOPS_UUID|$$UUID|" -e "s|REPLACE_GATEWAY_TOKEN|$$ADMIN|" bob-personas/mcp.json.template

bob-install: ## Write .bob/mcp.json for the FinOps ANALYST persona (least-privilege)
	@mkdir -p .bob; \
	$(MAKE) -s bob-config > .bob/mcp.json && \
	echo "wrote .bob/mcp.json — FinOps analyst persona (8 tools, no wire). Restart Bob."; \
	echo "Note: 'bob mcp list' shows 'Disconnected' until a live session — that is just static status."

bob-config-operator: ## Print the Bob MCP config for the OPERATOR persona (Operator vserver + admin token)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='Operator']" 2>/dev/null | head -1); \
	if [ -z "$$UUID" ]; then echo "Operator server not found — run 'make seed' first" >&2; exit 1; fi; \
	sed -e "s|REPLACE_OPERATOR_UUID|$$UUID|" -e "s|REPLACE_GATEWAY_TOKEN|$$ADMIN|" bob-personas/mcp.operator.json.template

bob-install-operator: ## Write .bob/mcp.json for the OPERATOR persona (register servers, audit, policy)
	@mkdir -p .bob; \
	$(MAKE) -s bob-config-operator > .bob/mcp.json && \
	echo "wrote .bob/mcp.json — platform OPERATOR persona (register/list/audit/evaluate). Restart Bob."; \
	echo "Switch back to the analyst with: make bob-install"

bob-config-builder: ## Print the Bob MCP config for the BUILDER persona (Builder vserver + admin token)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='Builder']" 2>/dev/null | head -1); \
	if [ -z "$$UUID" ]; then echo "Builder server not found — run 'make salestax-grant' first" >&2; exit 1; fi; \
	sed -e "s|REPLACE_BUILDER_UUID|$$UUID|" -e "s|REPLACE_GATEWAY_TOKEN|$$ADMIN|" bob-personas/mcp.builder.json.template

bob-install-builder: ## Write .bob/mcp.json for the BUILDER persona (calls the dev's own granted tools)
	@mkdir -p .bob; \
	$(MAKE) -s bob-config-builder > .bob/mcp.json && \
	echo "wrote .bob/mcp.json — BUILDER persona (calls your granted tools: add_tax, convert). Restart Bob."; \
	echo "Switch back to the analyst with: make bob-install"

connect: ## Print the ONE 'bob mcp add' command for a LOCAL/REMOTE Bob to drive THIS gateway (no Docker/uv/make on the attendee's laptop). Set GATEWAY_URL=... for a VM, or run inside a Codespace for auto-detect.
	@bash scripts/connect.sh

# Launch Bob FROM THE REPO ROOT so it always reads THIS dir's .bob/mcp.json.
# Running `bob` from the bob-personas/ subfolder (or any other dir) is the #1
# "No MCP servers configured" trap — Bob looks for .bob/mcp.json relative to its
# cwd. `make bob` is cwd-proof AND refreshes the persona config first, so it also
# kills the stale-UUID failure after a reseed. The persona is chosen by the target.
bob: bob-install ## Launch Bob as the FinOps ANALYST (cwd-proof; refreshes config first)
	@echo; printf "▶ Launching Bob — FinOps analyst — from %s\n" "$$(pwd)"; \
	echo "  (reads ./.bob/mcp.json → finbyte-gateway: 8 tools, no wire)"; echo
	@command -v bob >/dev/null 2>&1 || { printf "  IBM Bob (bob) isn't on your PATH — install IBM Bob Shell to drive the demo.\n  .bob/mcp.json was still written; install IBM Bob Shell (https://bob.ibm.com/download), then 'make bob' will launch it.\n  The stack is fully provable WITHOUT Bob:  make verify-controls  (-> 16/16).\n"; exit 0; }
	@bob

bob-operator: bob-install-operator ## Launch Bob as the platform OPERATOR (cwd-proof; refreshes config first)
	@echo; printf "▶ Launching Bob — platform operator — from %s\n" "$$(pwd)"; \
	echo "  (reads ./.bob/mcp.json → register / list / audit / evaluate)"; echo
	@command -v bob >/dev/null 2>&1 || { printf "  IBM Bob (bob) isn't on your PATH — install IBM Bob Shell to drive the demo.\n  .bob/mcp.json (operator persona) was still written; install IBM Bob Shell (https://bob.ibm.com/download), then 'make bob-operator' will launch it.\n  The stack is fully provable WITHOUT Bob:  make verify-controls  (-> 16/16).\n"; exit 0; }
	@bob

companion: ## Run the browser companion dashboard on :7070 (watch the control plane while using Bob)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if isinstance(s,dict) and s.get('name')=='FinOps']" 2>/dev/null | head -1); \
	echo "Companion → http://localhost:7070  (FinOps $$UUID)"; \
	GATEWAY_TOKEN=$$ADMIN FINOPS_UUID=$$UUID uv run --with flask --with httpx python companion/app.py

quickstart: .env ## ONE command: preflight → stack → seed → Bob → verify → walkthrough card
	@bash scripts/quickstart.sh

demo: ## Stage-gated end-to-end demo (cold start → register → scenarios → proof), pauses each stage
	@bash scripts/demo.sh

fxrates-convert: ## Showcase fallback: apply the finished fx-rates (with convert) + rebuild
	cp mcp-servers/fx-rates/server_with_convert.py mcp-servers/fx-rates/server.py
	$(COMPOSE) up -d --build fx-rates
	@echo "fx-rates now has 'convert' — re-register via Bob's operator persona to govern it"

fxrates-reset: ## Restore the base fx-rates (no convert) so the 'Bob builds it' beat repeats
	git checkout mcp-servers/fx-rates/server.py
	$(COMPOSE) up -d --build fx-rates
	@echo "fx-rates restored to base (get_fx_rate + list_currencies)"

# ── Dev Day: progressive build (bare tool → governed mesh) ──────────────────
# Scene-setters that walk a room up the stack one beat at a time, the inverse of
# quickstart's "whole mesh at once". Each prints the exact Bob prompt + a
# deterministic fallback; see scripts/stages.sh and docs/SHOWCASE-BOB.md.
dev-start: ## Dev Day ⏵: open the progressive-build prompt-card page (docs/cockpit.html → 🎓 Progressive Build)
	@url="file://$(CURDIR)/docs/cockpit.html#build"; \
	echo "▶ Opening the Dev Day prompt-card → docs/cockpit.html (🎓 Progressive Build tab)"; \
	echo "  copy each stage's Bob prompt straight from the page."; \
	(open "$$url" 2>/dev/null || xdg-open "$$url" 2>/dev/null \
	  || echo "  (no browser opener — open docs/cockpit.html yourself and click 🎓 Progressive Build)"); \
	echo; echo "  Then walk the stages:  make stage1-build → stage2-govern → stage3-controls → stage4-mesh"

stage1-build: ## Dev Day ①: Bob builds an MCP server from scratch → run RAW + inspect UNGOVERNED (:8000)
	@bash scripts/stages.sh build
stage1-scaffold: ## Dev Day ① fallback: drop in the finished sales-tax server if Bob's live build wobbles
	@cp mcp-servers/sales-tax/_solution.py mcp-servers/sales-tax/server.py && \
	echo "wrote mcp-servers/sales-tax/server.py from _solution.py — now run 'make stage1-build'"
stage2-govern: ## Dev Day ②: put that tool behind ContextForge (catalog + token)
	@bash scripts/stages.sh govern
stage3-controls: ## Dev Day ③: seed the mesh → the four controls start biting
	@bash scripts/stages.sh controls
stage4-mesh: ## Dev Day ④: the full governed mesh (== quickstart end-state)
	@bash scripts/stages.sh mesh
stage-reset: ## Stop the bare Stage-1 fx-rates server (if running)
	@bash scripts/stages.sh reset

SALESTAX_COMPOSE := $(COMPOSE) -f docker-compose.yml -f docker-compose.salestax.yml

salestax-up: ## (Stage 2) build + run the Bob-built sales-tax server as a container on the mesh network
	@if [ ! -f mcp-servers/sales-tax/server.py ]; then \
	  echo "mcp-servers/sales-tax/server.py is missing — run 'make stage1-build' or 'make stage1-scaffold' first" >&2; exit 1; fi
	$(SALESTAX_COMPOSE) up -d --build sales-tax
	@echo "sales-tax container up — host :8001 (health probe), gateway reaches it at http://sales-tax:8000/mcp"

salestax-down: ## Stop + remove just the ad-hoc sales-tax container
	@$(SALESTAX_COMPOSE) rm -sf sales-tax 2>/dev/null || true
	@echo "sales-tax container stopped + removed"

salestax-register: ## (Stage 2 fallback) register/refresh sales-tax in the gateway (delete-then-recreate)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	ADMIN_TOKEN=$$ADMIN uv run --with httpx python gateway/seed/register.py sales-tax http://sales-tax:8000/mcp STREAMABLEHTTP

salestax-grant: ## (Stage 2) grant add_tax into the Builder vserver + install the Builder persona so Bob can CALL it
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	ADMIN_TOKEN=$$ADMIN uv run --with httpx python gateway/seed/grant.py Builder add_tax >/dev/null && \
	$(MAKE) -s bob-install-builder

fxrates-extend: ## (Stage 2b fallback) give fx-rates a convert tool, rebuild, refresh in the gateway, grant it to Bob
	cp mcp-servers/fx-rates/server_with_convert.py mcp-servers/fx-rates/server.py
	$(COMPOSE) up -d --build fx-rates
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	ADMIN_TOKEN=$$ADMIN uv run --with httpx python gateway/seed/register.py fx-rates http://fx-rates:8000/mcp STREAMABLEHTTP && \
	ADMIN_TOKEN=$$ADMIN uv run --with httpx python gateway/seed/grant.py Builder convert add_tax >/dev/null && \
	$(MAKE) -s bob-install-builder
	@echo "fx-rates extended with 'convert', re-discovered, and granted to Bob's Builder persona"

fxrates-register: ## (Stage 2 fallback) register fx-rates into the gateway via API, as Bob's operator would
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	code=$$(curl -s -o /tmp/_fxreg.out -w '%{http_code}' -X POST localhost:4444/gateways \
	  -H "Authorization: Bearer $$ADMIN" -H 'Content-Type: application/json' \
	  -d '{"name":"fx-rates","url":"http://fx-rates:8000/mcp","transport":"STREAMABLEHTTP","description":"fx-rates MCP server"}'); \
	if [ "$$code" = "200" ] || [ "$$code" = "201" ]; then echo "✓ fx-rates registered into ContextForge (HTTP $$code)"; \
	elif grep -qi 'already\|exists\|conflict\|duplicate' /tmp/_fxreg.out 2>/dev/null; then echo "✓ fx-rates already registered"; \
	else echo "registration returned HTTP $$code: $$(cat /tmp/_fxreg.out 2>/dev/null)"; fi

monitor: ## Open the ContextForge monitor (Admin UI: catalog + observability + logs)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	echo "ContextForge Admin UI → http://localhost:4444/admin"; \
	echo "  login: admin@finbyte.demo / $$(grep -E '^PLATFORM_ADMIN_PASSWORD=' .env | cut -d= -f2-)"; \
	echo "  observability: /admin (Overview, Metrics, Logs tabs)"; \
	(open http://localhost:4444/admin 2>/dev/null || xdg-open http://localhost:4444/admin 2>/dev/null || true)

inspect-mcp: ## Launch MCP Inspector pre-pointed at the gateway's FinOps server (shows the governed tools)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	if [ -z "$$ADMIN" ]; then echo "could not mint the admin token (is the stack up? try 'make quickstart')" >&2; exit 1; fi; \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='FinOps']" 2>/dev/null | head -1); \
	if [ -z "$$UUID" ]; then echo "FinOps server not found — is the stack up and seeded? try 'make quickstart'" >&2; exit 1; fi; \
	rm -f /tmp/mcp-finops-* 2>/dev/null || true; \
	URL="http://localhost:4444/servers/$$UUID/mcp"; \
	CFG=$$(mktemp /tmp/mcp-finops-XXXXXX); mv "$$CFG" "$$CFG.json"; CFG="$$CFG.json"; \
	printf '{"mcpServers":{"FinByte-FinOps":{"type":"streamable-http","url":"%s","headers":{"Authorization":"Bearer %s"}}}}\n' "$$URL" "$$ADMIN" > "$$CFG"; \
	echo "MCP Inspector opens pre-pointed at the FinOps virtual server on ContextForge"; \
	echo "(Streamable HTTP + the right URL — this is the gateway's governed slice, NOT a"; \
	echo " backend MCP server; everything goes through the one governed seam)."; \
	echo; \
	echo "Final step — add the gateway token (inspector v0.22 won't load it from config):"; \
	echo "  1) Connection Type   →  Via Proxy   (NOT Direct — Direct gets CORS-blocked)"; \
	echo "  2) Authentication ▸ Custom Headers ▸ + Add :"; \
	echo "       Header Name  =  Authorization"; \
	echo "       Header Value =  paste the line below  (make sure the row toggle is ON)"; \
	echo "  3) Connect  →  you should see 8 tools"; \
	echo; \
	echo "  Bearer $$ADMIN"; \
	echo; \
	BEARER="Bearer $$ADMIN"; \
	if command -v pbcopy >/dev/null 2>&1; then printf '%s' "$$BEARER" | pbcopy; echo "  ✓ (also copied to your clipboard — just Cmd-V into Header Value)"; \
	elif command -v wl-copy >/dev/null 2>&1; then printf '%s' "$$BEARER" | wl-copy; echo "  ✓ (also copied to clipboard via wl-copy)"; \
	elif command -v xclip >/dev/null 2>&1; then printf '%s' "$$BEARER" | xclip -selection clipboard; echo "  ✓ (also copied to clipboard via xclip)"; \
	elif command -v xsel >/dev/null 2>&1; then printf '%s' "$$BEARER" | xsel --clipboard; echo "  ✓ (also copied to clipboard via xsel)"; \
	fi; \
	echo; \
	echo "You should then see 8 tools — note erp-payments-wire is ABSENT (least-privilege)."; \
	echo "(proxy auth is disabled for this local demo; temp config at $$CFG)"; \
	DANGEROUSLY_OMIT_AUTH=true npx -y @modelcontextprotocol/inspector --config "$$CFG" --server FinByte-FinOps

inspect-a2a: ## Launch the A2A Inspector (clone+build first time) to validate the agent cards
	@echo "A2A Inspector (a2aproject/a2a-inspector) on http://localhost:8090  (runtime: $(CONTAINER))"; \
	echo "  point it at:  http://host.docker.internal:9001  (Python Auditor)  ·  :3000 (Rust Payments)"; \
	if [ "$(CONTAINER)" = "docker" ]; then BUILD="docker buildx build --load"; else BUILD="$(CONTAINER) build --network=host"; fi; \
	if ! $(CONTAINER) image inspect a2a-inspector >/dev/null 2>&1; then \
	  echo "building a2a-inspector image (first run, ~1-2 min)…"; \
	  tmp=$$(mktemp -d); git clone --depth 1 https://github.com/a2aproject/a2a-inspector "$$tmp/ai" >/dev/null 2>&1 \
	    && $$BUILD -t a2a-inspector "$$tmp/ai" >/dev/null 2>&1 || { echo "build failed — see the a2a-inspector README"; exit 1; }; \
	fi; \
	$(CONTAINER) rm -f a2a-inspector >/dev/null 2>&1 || true; \
	addhost=""; if [ "$(CONTAINER)" = "podman" ] || [ "$$(uname -s)" = "Linux" ]; then addhost="--add-host=host.docker.internal:host-gateway"; fi; \
	$(CONTAINER) run --rm --name a2a-inspector $$addhost -p 8090:8080 a2a-inspector

cockpit: ## tmux cockpit: Bob + logs + OPA + both inspectors in one window (COCKPIT_PERSONA=operator for Act 2)
	@bash scripts/cockpit.sh

# Mode-aware teardown. Cold-start built a `cockpit` session → kill it. Augment
# recorded the panes it created in the @cockpit_panes session option → kill ONLY
# those (never the user's whole window). Both also force-remove the a2a-inspector
# container: killing the pane stops the `docker run` client but `--rm` only fires
# on a clean stop, so an orphan can survive.
cockpit-down: ## Tear down the cockpit (kill session/panes + remove a2a-inspector)
	@if command -v tmux >/dev/null 2>&1 && tmux has-session -t cockpit 2>/dev/null; then \
	  tmux kill-session -t cockpit 2>/dev/null && echo "cockpit session killed"; \
	elif command -v tmux >/dev/null 2>&1 && [ -n "$$TMUX" ]; then \
	  panes=$$(tmux show-option -qv @cockpit_panes 2>/dev/null); \
	  if [ -n "$$panes" ]; then \
	    for p in $$panes; do \
	      tmux set-option -p -t "$$p" remain-on-exit off 2>/dev/null || true; \
	      tmux kill-pane -t "$$p" 2>/dev/null || true; \
	    done; \
	    tmux set-option -u @cockpit_panes 2>/dev/null || true; \
	    echo "augment panes killed ($$panes)"; \
	  else echo "no cockpit panes recorded in this session (nothing to kill)"; fi; \
	else echo "no cockpit session found"; fi
	@$(CONTAINER) rm -f a2a-inspector >/dev/null 2>&1 || true; echo "a2a-inspector removed (if present)"
	@pkill -f "modelcontextprotocol/inspector" >/dev/null 2>&1 && echo "MCP Inspector proxy stopped" || true
	@pkill -f "companion/app.py" >/dev/null 2>&1 && echo "companion stopped" || true

verify-controls: ## Run the money-shot proof suite (assert block/allow)
	@bash scripts/money-shots/run-all.sh

demo-reset: ## Clean-reset the gateway to a known-good state (recreate + reseed)
	$(COMPOSE) up -d --force-recreate gateway
	@for i in $$(seq 1 30); do curl -sf localhost:4444/health >/dev/null 2>&1 && break || sleep 2; done
	@$(MAKE) seed
	@echo "reset done — run 'make verify-controls' to confirm 16/16"

logs: ## Tail gateway logs (raw; blocked calls show as ERROR 'invocation failed')
	$(COMPOSE) logs -f gateway

logs-opa: ## Live, readable OPA policy decisions (ALLOW/DENY + args + reason)
	@COMPOSE="$(COMPOSE)" bash scripts/watch-decisions.sh

ps: ## Show running services
	$(COMPOSE) ps

down: ## Stop the stack
	$(COMPOSE) down

# ── Quality / security / CI (adapted from IBM/mcp-context-forge v1.0.2) ──
# Divergence notes: upstream uses detect-secrets (not gitleaks) and osv-scan/dockle
# (not trivy). `secrets-baseline`/`trivy` reflect that; pick what fits before publishing.
.PHONY: format lint lint-rust test bandit pip-audit secrets-baseline sbom hadolint compose-validate smoke trivy ci
PY_DIRS := mcp-servers a2a-agents/auditor companion gateway/seed scripts
IMAGES  ?= ai-agent-controlplane-demo-auditor ai-agent-controlplane-demo-payments

format: ## Auto-fix Python (ruff --fix + black)
	uvx ruff check --fix $(PY_DIRS); uvx black $(PY_DIRS)
lint: ## Lint Python (ruff + black --check)
	uvx ruff check $(PY_DIRS); uvx black --check $(PY_DIRS)
lint-rust: ## Lint the Rust agent (fmt + clippy)
	cd a2a-agents/payments && cargo fmt --check && cargo clippy -- -D warnings
test: ## Run pytest (tolerates "no tests collected")
	@uv run --with pytest --with httpx pytest -q $(PY_DIRS) || { c=$$?; [ $$c -eq 5 ] || exit $$c; }
bandit: ## Python source security scan
	uvx bandit -c .bandit.yaml -r $(PY_DIRS) -ll
pip-audit: ## Dependency CVE scan
	uvx pip-audit || true
secrets-baseline: ## Secret scan (detect-secrets — upstream-faithful)
	uvx --from detect-secrets detect-secrets scan > .secrets.baseline
sbom: ## Generate CycloneDX SBOM
	uvx --from cyclonedx-bom cyclonedx-py environment --output-format JSON --output-file docs/sbom.json --no-validate $$(command -v python3)
hadolint: ## Lint Dockerfiles
	@find . -name Dockerfile -not -path '*/target/*' -exec hadolint {} +
compose-validate: ## Validate docker-compose.yml
	$(COMPOSE) config --quiet && echo OK
smoke: ## Post-up gateway health probe
	@curl -sf localhost:4444/health && echo OK || exit 1
trivy: ## Image CVE scan (divergence: upstream uses osv/dockle)
	@for i in $(IMAGES); do trivy image --severity HIGH,CRITICAL --ignore-unfixed $$i || true; done
ci: lint bandit compose-validate ## Aggregate gate for CI (lint + bandit + compose-validate)
	@echo "ci checks passed"
