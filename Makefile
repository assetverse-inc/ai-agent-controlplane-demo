SHELL := /bin/bash
SECRET := demo-only-change-me-0123456789abcdef
# Mint tokens offline. Override DATABASE_URL so settings validation doesn't try
# to create the container's /data dir (read-only on the host).
MINT := DATABASE_URL=sqlite:///./.tokmint.db uv run --with mcp-contextforge-gateway -- python -m mcpgateway.utils.create_jwt_token
COMPOSE := docker compose

.PHONY: help up up-full down seed token token-bob bob-config bob-install bob-config-operator bob-install-operator companion logs verify-controls demo-reset ps demo

help:
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

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

up-full: .env ## Start the full presenter stack (postgres/redis/nginx/phoenix)
	@echo "AUDITOR_TOKEN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET))" > .env.tokens
	$(COMPOSE) --env-file .env.tokens -f docker-compose.yml -f docker-compose.full.yml up -d --build

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
	sed -e "s|REPLACE_FINOPS_UUID|$$UUID|" -e "s|REPLACE_GATEWAY_TOKEN|$$ADMIN|" bob/mcp.json.template

bob-install: ## Write .bob/mcp.json for the FinOps ANALYST persona (least-privilege)
	@mkdir -p .bob; \
	$(MAKE) -s bob-config > .bob/mcp.json && \
	echo "wrote .bob/mcp.json — FinOps analyst persona (8 tools, no wire). Restart Bob."; \
	echo "Note: 'bob mcp list' shows 'Disconnected' until a live session — that is just static status."

bob-config-operator: ## Print the Bob MCP config for the OPERATOR persona (Operator vserver + admin token)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='Operator']" 2>/dev/null | head -1); \
	if [ -z "$$UUID" ]; then echo "Operator server not found — run 'make seed' first" >&2; exit 1; fi; \
	sed -e "s|REPLACE_OPERATOR_UUID|$$UUID|" -e "s|REPLACE_GATEWAY_TOKEN|$$ADMIN|" bob/mcp.operator.json.template

bob-install-operator: ## Write .bob/mcp.json for the OPERATOR persona (register servers, audit, policy)
	@mkdir -p .bob; \
	$(MAKE) -s bob-config-operator > .bob/mcp.json && \
	echo "wrote .bob/mcp.json — platform OPERATOR persona (register/list/audit/evaluate). Restart Bob."; \
	echo "Switch back to the analyst with: make bob-install"

companion: ## Run the browser companion dashboard on :7070 (watch the control plane while using Bob)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if isinstance(s,dict) and s.get('name')=='FinOps']" 2>/dev/null | head -1); \
	echo "Companion → http://localhost:7070  (FinOps $$UUID)"; \
	GATEWAY_TOKEN=$$ADMIN FINOPS_UUID=$$UUID uv run --with flask --with httpx python companion/app.py

demo: ## Stage-gated end-to-end demo (cold start → register → scenarios → proof), pauses each stage
	@bash scripts/demo.sh

verify-controls: ## Run the money-shot proof suite (assert block/allow)
	@bash scripts/money-shots/run-all.sh

demo-reset: ## Clean-reset the gateway to a known-good state (recreate + reseed)
	$(COMPOSE) up -d --force-recreate gateway
	@for i in $$(seq 1 30); do curl -sf localhost:4444/health >/dev/null 2>&1 && break || sleep 2; done
	@$(MAKE) seed
	@echo "reset done — run 'make verify-controls' to confirm 16/16"

logs: ## Tail gateway logs
	$(COMPOSE) logs -f gateway

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
