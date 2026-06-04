# Architecture

```
   IBM Bob  (MCP client; .bob/mcp.json -> SSE url + bearer JWT)
       │  MCP over SSE  (/servers/<FinOps-UUID>/sse)
       ▼
 ┌─────────────────────────────────────────────────────────────┐
 │           ContextForge / MCP Gateway  (v1.0.2, :4444)         │
 │                                                              │
 │  AuthN (JWT) · Virtual servers: FinOps (Bob) / Treasury      │
 │  Plugin pipeline @ tool hooks:                               │
 │    tool_pre_invoke  → FinByteGuard → OPA (Rego amount cap)   │
 │    tool_post_invoke → FinByteGuard (secret/injection) +      │
 │                       PIIFilter (SSN/card)                   │
 │  Built-in: RBAC, rate limiter, audit log                     │
 └───┬───────────────┬───────────────┬───────────────┬─────────┘
   MCP│             MCP│             MCP│             A2A│ (bridged as a2a_<name> MCP tools)
     ▼               ▼               ▼               ▼
 expense-db      erp-payments     policy-docs     a2a_auditor (Python, a2a-sdk)
 (FastMCP,Py)    (wire/approve/   + notify              │ delegates payment
 PII+injection    reimburse)      (FastMCP,Py)          ▼
 +$50k fixtures                                   a2a_payments (Rust, a2a-lf/a2a-server-lf)
                                                  + OPA sidecar :8181 (Rego policy)
```

## The enforcement point
ContextForge bridges each registered A2A agent into an MCP tool named `a2a_<name>`. So a
call to `a2a_payments` (the Auditor delegating a payment to the Rust agent) is an MCP tool
invocation and runs through the gateway's `tool_pre_invoke` / `tool_post_invoke` hooks —
exactly where the controls fire. **The control plane governs agent→tool *and* agent→agent
calls at the same seam.**

## Why FinByteGuard exists
The bundled `UnifiedPDP` plugin strips tool-argument *values* before calling OPA (it sends
only `resource.args_keys`), so a pure-OPA amount cap can't see the amount. `FinByteGuard`
(a small plugin on the same `cpex.framework` base) passes the real args to OPA, so the
Rego policy (`gateway/policies/finops.rego`) still makes the decision — and it also
deep-redacts secrets/injection in nested tool output (which the example `SearchReplace`
plugin only does at the top level).

## Components
| Component | Tech | Role |
|---|---|---|
| gateway | ContextForge v1.0.2 (pinned digest) | control plane / MCP+A2A proxy |
| opa | Open Policy Agent 0.70 | Rego policy decision point |
| expense-db, erp-payments, policy-docs, notify, controlplane, fx-rates | Python / FastMCP v3 | MCP tool servers (fx-rates ships unregistered, for the live-register beat) |
| auditor | Python / `a2a-sdk` 1.1.0 | A2A agent: validates + delegates payment |
| payments | Rust / `a2a-lf` 0.3 + `a2a-server-lf` 0.4 | A2A agent: executes payment |

This release ships a single SQLite-backed profile (the table above). A heavier
Postgres/Redis/nginx/Phoenix-OTEL profile is future work — not included here.
