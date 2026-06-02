# M0 live-instance findings (verified against a running gateway, 2026-06-02)

Gateway run for verification: `uvx --from mcp-contextforge-gateway mcpgateway mcpgateway.main:app --host 127.0.0.1 --port 4444` (SQLite). `/health` → 200. 451 OpenAPI paths.

## Auth
- **Tokens require an `exp` claim** (`REQUIRE_TOKEN_EXPIRATION=true` default). Mint with a non-zero expiry: `python -m mcpgateway.utils.create_jwt_token -u <email> --admin -e 10080 -s "$JWT_SECRET_KEY"` (`-e` is MINUTES; `-e 0` makes an exp-less token that is REJECTED). `--admin` is a bare flag (no value).
- All API endpoints need `Authorization: Bearer <jwt>`. `/openapi.json` itself is auth-gated.

## Registration API (verified schemas)
- `POST /gateways` body = **GatewayCreate**: required `name`, `url`; optional `transport`, `description`, `authType`/`authToken`/`authHeaderKey`/`authHeaderValue`, `tags`, `visibility`. Registering a backend MCP server here makes the gateway introspect it and create tool records (with ids) visible at `GET /tools`.
- `POST /servers` body = **`{ "server": ServerCreate, "team_id"?, "visibility"? }`**. ServerCreate: required `name`; tool/agent association via **`associated_tools: [tool_id,...]`**, **`associated_a2a_agents: [agent_id,...]`**, plus `associated_resources`, `associated_prompts`, `tags`, `visibility`.
- `POST /a2a` body = **`{ "agent": A2AAgentCreate, "team_id"?, "visibility"? }`**. A2AAgentCreate: required `name`, `endpoint_url`; `agent_type` (e.g. `"jsonrpc"`), `auth_type`/`auth_value`, `tags`, `protocol_version`, `capabilities`, `config`. Creates a tool `a2a_<name>`.
- `POST /tokens` body = **TokenCreateRequest**: required `name`; `expires_in_days`, `scope` (TokenScopeRequest — for server-scoping), `team_id`, `user_email`, `is_active`. (For demo role/team tokens the `create_jwt_token` CLI with `--teams`/`--scopes` is simpler.)
- A2A invoke: `POST /a2a/{agent_name}/invoke` (params) or via `/rpc` `tools/call` (`arguments`).

## Client (Bob) transport — IMPORTANT
- This gateway build exposes virtual-server client transports as **SSE**: `GET /servers/{server_id}/sse` (event stream) + `POST /servers/{server_id}/message`. There is **no `/servers/{id}/mcp` streamable-HTTP path** in this build (the `/_internal/mcp/*` paths are internal, not the client transport). Global `/sse` + `/message` also exist.
- ⇒ **Bob `.bob/mcp.json` should use the SSE notation**: `"url": "http://<gateway>:4444/servers/<FINOPS_UUID>/sse"` + `"headers": {"Authorization": "Bearer <token>"}`. (Bob supports SSE `url` + headers; the verbatim Bearer example in Bob docs uses exactly `url`+`headers`.) Keep the `httpURL`/`type:streamable-http` variants as commented alternatives in the template; the user confirms which their Bob build prefers, but SSE is what this gateway serves.

## OPA / unified_pdp
- Native PDP cannot do numeric amount caps → **OPA sidecar required** (confirmed in M0 reference §5). OPA engine POSTs `{"input": ...}` to **`/v1/data/{policy_path}`** (default `mcpgateway`); reads `result.allow` + `result.deny[]`; tool args land at `input.context.tool_args.*`. Verify the exact query suffix against gateway logs when wiring M1.6.

## Plugins / hooks (from reference §1, to confirm when plugins load)
- `UnifiedPDPPlugin` → `tool_pre_invoke`. `PIIFilterPlugin` (has `detect_api_keys`) + `SecretsDetection` + `CodeSafetyLinterPlugin` → `tool_post_invoke` (can block). `DenyListPlugin` is prompt-only (don't use for tool-output injection).

## Misc
- Non-fatal boot warning about UAID cross-gateway routing — irrelevant for a single gateway.
- `SSRF_*` default false → must set `SSRF_ALLOW_PRIVATE_NETWORKS=true` for Compose service-name calls.

## Still needs the user (GA Bob)
- Which `.bob/mcp.json` notation the installed GA Bob parses, and the on-real-Bob run. The gateway side (SSE endpoint + bearer) is confirmed here.
