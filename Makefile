SHELL := /bin/bash
SECRET := demo-only-change-me-0123456789abcdef
# Mint tokens offline. Override DATABASE_URL so settings validation doesn't try
# to create the container's /data dir (read-only on the host).
MINT := DATABASE_URL=sqlite:///./.tokmint.db uv run --with mcp-contextforge-gateway -- python -m mcpgateway.utils.create_jwt_token
COMPOSE := docker compose

.PHONY: help up down seed token token-bob bob bob-operator bob-config bob-install bob-config-operator bob-install-operator companion logs logs-opa verify-controls demo-reset ps demo quickstart monitor inspect-mcp inspect-a2a fxrates-convert fxrates-reset

# `make` (no target) prints this curated, categorized help. Keep it in sync when you
# add/rename a target — the inline `## ...` comments still document each target too.
help:
	@printf "\n\033[1mIBM Bob × ContextForge — the AI agent control plane\033[0m\n"
	@printf "  make <target> — grouped below. New here? run \033[36mmake quickstart\033[0m first.\n"
	@printf "\n\033[1m🚀 START HERE\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "quickstart" "ONE command: stack → seed → configure Bob → prove 16/16 + card"
	@printf "  \033[36m%-22s\033[0m %s\n" "verify-controls" "Prove all four controls headlessly → \"16 passed, 0 failed\""
	@printf "  \033[36m%-22s\033[0m %s\n" "demo" "Stage-gated end-to-end walkthrough (pauses at each stage)"
	@printf "\n\033[1m🤖 DRIVE BOB\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob" "Launch Bob — FinOps analyst (Act 1; cwd-proof, refreshes config)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-operator" "Launch Bob — platform operator (Act 2)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-install" "Write .bob/mcp.json for the analyst persona (no launch)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-install-operator" "Write .bob/mcp.json for the operator persona (no launch)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-config" "Print the analyst MCP config (to paste elsewhere)"
	@printf "  \033[36m%-22s\033[0m %s\n" "bob-config-operator" "Print the operator MCP config"
	@printf "\n\033[1m🛰  STACK\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "up" "Build + start the stack (gateway, OPA, 6 MCP servers, 2 A2A agents)"
	@printf "  \033[36m%-22s\033[0m %s\n" "down" "Stop the stack"
	@printf "  \033[36m%-22s\033[0m %s\n" "seed" "Register servers/agents + build the FinOps/Treasury/Operator vservers"
	@printf "  \033[36m%-22s\033[0m %s\n" "demo-reset" "Recreate + reseed the gateway to a known-good state"
	@printf "  \033[36m%-22s\033[0m %s\n" "ps" "Show running services"
	@printf "\n\033[1m👀 OBSERVE\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "monitor" "Open the ContextForge Admin UI (catalog + Logs)"
	@printf "  \033[36m%-22s\033[0m %s\n" "logs" "Tail gateway logs (control firings: AUDIT [FinByteGuard])"
	@printf "  \033[36m%-22s\033[0m %s\n" "logs-opa" "Live, readable OPA decisions (ALLOW/DENY + reason)"
	@printf "  \033[36m%-22s\033[0m %s\n" "inspect-mcp" "MCP Inspector → the 8 governed tools (wire absent)"
	@printf "  \033[36m%-22s\033[0m %s\n" "inspect-a2a" "A2A Inspector → validate the Python + Rust agent cards"
	@printf "  \033[36m%-22s\033[0m %s\n" "companion" "Browser evidence dashboard on :7070"
	@printf "\n\033[1m🎬 SHOWCASE\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "fxrates-convert" "Apply the finished fx-rates (adds convert) + rebuild"
	@printf "  \033[36m%-22s\033[0m %s\n" "fxrates-reset" "Restore base fx-rates so the \"Bob builds it\" beat repeats"
	@printf "\n\033[1m🔑 TOKENS\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "token" "Print an admin JWT"
	@printf "  \033[36m%-22s\033[0m %s\n" "token-bob" "Print Bob's JWT"
	@printf "\n\033[1m✅ QUALITY / CI\033[0m\n"
	@printf "  \033[36m%-22s\033[0m %s\n" "check" "Aggregate CI gate (lint + bandit + compose-validate)"
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

monitor: ## Open the ContextForge monitor (Admin UI: catalog + observability + logs)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	echo "ContextForge Admin UI → http://localhost:4444/admin"; \
	echo "  login: admin@finbyte.demo / $$(grep -E '^PLATFORM_ADMIN_PASSWORD=' .env | cut -d= -f2-)"; \
	echo "  observability: /admin (Overview, Metrics, Logs tabs)"; \
	(open http://localhost:4444/admin 2>/dev/null || xdg-open http://localhost:4444/admin 2>/dev/null || true)

inspect-mcp: ## Launch MCP Inspector pointed at the gateway's FinOps server (shows the governed tools)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='FinOps']" 2>/dev/null | head -1); \
	if [ -z "$$UUID" ]; then echo "FinOps server not found — run 'make seed' first" >&2; exit 1; fi; \
	echo "MCP Inspector opening… In the UI, connect with:"; \
	echo "  Transport      : Streamable HTTP"; \
	echo "  URL            : http://localhost:4444/servers/$$UUID/mcp"; \
	echo "  Auth header    : Authorization: Bearer $$ADMIN"; \
	echo "(you should see 8 tools — note erp-payments-wire is ABSENT: least-privilege)"; \
	npx -y @modelcontextprotocol/inspector

inspect-a2a: ## Launch the A2A Inspector (clone+build first time) to validate the agent cards
	@echo "A2A Inspector (a2aproject/a2a-inspector) on http://localhost:8090"; \
	echo "  point it at:  http://host.docker.internal:9001  (Python Auditor)  ·  :3000 (Rust Payments)"; \
	if ! docker image inspect a2a-inspector >/dev/null 2>&1; then \
	  echo "building a2a-inspector image (first run, ~1-2 min)…"; \
	  tmp=$$(mktemp -d); git clone --depth 1 https://github.com/a2aproject/a2a-inspector "$$tmp/ai" >/dev/null 2>&1 \
	    && docker buildx build --load -t a2a-inspector "$$tmp/ai" >/dev/null 2>&1 || { echo "build failed — see the a2a-inspector README"; exit 1; }; \
	fi; \
	docker rm -f a2a-inspector >/dev/null 2>&1 || true; \
	docker run --rm --name a2a-inspector -p 8090:8080 a2a-inspector

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
	@bash scripts/watch-decisions.sh

ps: ## Show running services
	$(COMPOSE) ps

down: ## Stop the stack
	$(COMPOSE) down

# ── Quality / security / CI (adapted from IBM/mcp-context-forge v1.0.2) ──
# Divergence notes: upstream uses detect-secrets (not gitleaks) and osv-scan/dockle
# (not trivy). `secrets-baseline`/`trivy` reflect that; pick what fits before publishing.
.PHONY: format lint lint-rust test bandit pip-audit secrets-baseline sbom hadolint compose-validate smoke trivy check
PY_DIRS := mcp-servers a2a-agents/auditor companion gateway/seed scripts
IMAGES  ?= ai-agent-controlplane-demo-auditor ai-agent-controlplane-demo-payments

format: ## Auto-fix Python (ruff --fix + black)
	uvx ruff check --fix $(PY_DIRS); uvx black $(PY_DIRS)
lint: ## Lint Python (ruff + black --check)
	uvx ruff check $(PY_DIRS); uvx black --check $(PY_DIRS)
lint-rust: ## Lint the Rust agent (fmt + clippy)
	cd a2a-agents/payments && cargo fmt --check && cargo clippy -- -D warnings
test: ## Run pytest (tolerates "no tests collected")
	@uv run --with pytest pytest -q $(PY_DIRS) || { c=$$?; [ $$c -eq 5 ] || exit $$c; }
bandit: ## Python source security scan
	uvx bandit -r $(PY_DIRS) -ll
pip-audit: ## Dependency CVE scan
	uvx pip-audit || true
secrets-baseline: ## Secret scan (detect-secrets — upstream-faithful)
	uvx --from detect-secrets detect-secrets scan --update .secrets.baseline
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
check: lint bandit compose-validate ## Aggregate gate for CI
	@echo "check passed"
