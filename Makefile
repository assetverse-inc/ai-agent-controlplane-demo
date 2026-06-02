SHELL := /bin/bash
SECRET := demo-only-change-me-0123456789abcdef
# Mint tokens offline. Override DATABASE_URL so settings validation doesn't try
# to create the container's /data dir (read-only on the host).
MINT := DATABASE_URL=sqlite:///./.tokmint.db uv run --with mcp-contextforge-gateway -- python -m mcpgateway.utils.create_jwt_token
COMPOSE := docker compose

.PHONY: help up up-full down seed token token-bob bob-config companion logs verify-controls demo-reset ps

help:
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

.env:
	cp .env.example .env

token: ## Print an admin JWT
	@$(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET)

token-bob: ## Print Bob's JWT (paste into .bob/mcp.json)
	@$(MINT) -u bob@finbyte.demo --admin -e 10080 -s $(SECRET)

up: .env ## Build + start the lite stack
	@echo "AUDITOR_TOKEN=$$($(MINT) -u auditor@finbyte.demo --admin -e 10080 -s $(SECRET))" > .env.tokens
	$(COMPOSE) --env-file .env.tokens up -d --build
	@echo "waiting for gateway health..."; \
	for i in $$(seq 1 40); do curl -sf localhost:4444/health >/dev/null 2>&1 && { echo "gateway healthy"; break; } || sleep 2; done

up-full: .env ## Start the full presenter stack (postgres/redis/nginx/phoenix)
	@echo "AUDITOR_TOKEN=$$($(MINT) -u auditor@finbyte.demo --admin -e 10080 -s $(SECRET))" > .env.tokens
	$(COMPOSE) --env-file .env.tokens -f docker-compose.yml -f docker-compose.full.yml up -d --build

seed: ## Register servers/agents + build FinOps/Treasury virtual servers
	@ADMIN_TOKEN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET)) \
	  uv run --with httpx python gateway/seed/seed.py

bob-config: ## Print the .bob/mcp.json to paste into IBM Bob (live FinOps UUID + token)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	BOB=$$($(MINT) -u bob@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if s.get('name')=='FinOps']" 2>/dev/null | head -1); \
	if [ -z "$$UUID" ]; then echo "FinOps server not found — run 'make seed' first" >&2; exit 1; fi; \
	sed -e "s|REPLACE_FINOPS_UUID|$$UUID|" -e "s|REPLACE_BOB_TOKEN|$$BOB|" bob/mcp.json.template

companion: ## Run the browser companion dashboard on :7070 (watch the control plane while using Bob)
	@ADMIN=$$($(MINT) -u admin@finbyte.demo --admin -e 10080 -s $(SECRET) 2>/dev/null | tail -1); \
	UUID=$$(curl -s -H "Authorization: Bearer $$ADMIN" localhost:4444/servers | python3 -c "import sys,json;[print(s['id']) for s in json.load(sys.stdin) if isinstance(s,dict) and s.get('name')=='FinOps']" 2>/dev/null | head -1); \
	echo "Companion → http://localhost:7070  (FinOps $$UUID)"; \
	GATEWAY_TOKEN=$$ADMIN FINOPS_UUID=$$UUID uv run --with flask --with httpx python companion/app.py

verify-controls: ## Run the money-shot proof suite (assert block/allow)
	@bash scripts/money-shots/run-all.sh

demo-reset: ## Reset fixtures + clear rate-limit lockouts between runs
	$(COMPOSE) restart gateway expense-db
	@echo "reset done"

logs: ## Tail gateway logs
	$(COMPOSE) logs -f gateway

ps: ## Show running services
	$(COMPOSE) ps

down: ## Stop the stack
	$(COMPOSE) down
