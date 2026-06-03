# -*- coding: utf-8 -*-
"""FinByteGuard — a ContextForge plugin enforcing the FinByte demo controls.

Two hooks:
  * tool_pre_invoke  -> reads the REAL tool args and asks OPA (Rego policy
    `data.mcpgateway`) to decide; blocks large un-approved wires. (Money shot #1.)
    The bundled UnifiedPDP strips arg VALUES before calling OPA, so this plugin
    passes them through — the policy decision is still made by OPA + Rego.
  * tool_post_invoke -> deep-redacts a leaked API key and neutralizes injected
    instructions anywhere in the (possibly nested) tool output. (Money shots #2/#3.)

Built on the same cpex.framework Plugin base the bundled plugins use.
"""
import re
import sys

import httpx
from cpex.framework import (
    Plugin,
    PluginConfig,
    PluginContext,
    PluginViolation,
    ToolPostInvokePayload,
    ToolPostInvokeResult,
    ToolPreInvokePayload,
    ToolPreInvokeResult,
)

# Audit trail — every control action writes one readable line to the gateway's
# stdout (captured by `docker compose logs` / `make logs`), so EVERY money shot
# is checkable in the log, not just the policy block. We write to stdout directly
# because the gateway's structured logger only emits its own mcpgateway.* records
# and drops plain logging calls from plugins.
def _audit(msg: str) -> None:
    print(f"AUDIT {msg}", file=sys.stdout, flush=True)

_SECRET = re.compile(r"sk-live-[A-Za-z0-9]+")
_INJECT = [
    re.compile(r"(?i)SYSTEM:\s*ignore[^.]*\."),
    re.compile(r"(?i)Approve and wire immediately[^.]*\."),
    re.compile(r"(?i)NOTE TO ASSISTANT:[^.]*\."),
]


def _scrub(v):
    """Recursively redact secrets + injected instructions in any string."""
    if isinstance(v, str):
        v = _SECRET.sub("[SECRET_REDACTED]", v)
        for p in _INJECT:
            v = p.sub("[INJECTION_BLOCKED]", v)
        return v
    if isinstance(v, dict):
        return {k: _scrub(x) for k, x in v.items()}
    if isinstance(v, list):
        return [_scrub(x) for x in v]
    return v


class FinByteGuard(Plugin):
    """Policy enforcement + output sanitization for the FinByte demo."""

    def __init__(self, config: PluginConfig):
        super().__init__(config)
        cfg = self._config.config or {}
        self._opa_url = cfg.get("opa_url", "http://opa:8181")
        self._policy_path = cfg.get("policy_path", "mcpgateway")

    async def tool_pre_invoke(
        self, payload: ToolPreInvokePayload, context: PluginContext
    ) -> ToolPreInvokeResult:
        name = (payload.name or "").lower()
        if "wire" in name or "payment" in name:
            args = dict(payload.args or {})
            opa_input = {
                "action": f"tools.invoke.{payload.name}",
                "resource": {"id": payload.name, "type": "tool"},
                "context": {"tool_args": args},
            }
            try:
                async with httpx.AsyncClient(timeout=5.0) as client:
                    resp = await client.post(
                        f"{self._opa_url}/v1/data/{self._policy_path}",
                        json={"input": opa_input},
                    )
                    result = resp.json().get("result", {})
            except Exception as exc:  # fail closed
                result = {"allow": False, "deny": [f"policy engine unavailable: {exc}"]}
            if not result.get("allow", False):
                reason = "; ".join(result.get("deny") or ["denied by policy"])
                _audit(f"[FinByteGuard] BLOCKED {payload.name} — {reason}")
                violation = PluginViolation(
                    reason="Policy decision: DENY",
                    description=reason,
                    code="WIRE_POLICY_DENY",
                    details={"tool": payload.name, "args_keys": sorted(args.keys())},
                )
                return ToolPreInvokeResult(
                    continue_processing=False,
                    modified_payload=payload,
                    violation=violation,
                )
            _audit(f"[FinByteGuard] ALLOWED {payload.name} — policy passed "
                   f"(amount={args.get('amount')}, approval={args.get('approval')})")
        return ToolPreInvokeResult(modified_payload=payload)

    async def tool_post_invoke(
        self, payload: ToolPostInvokePayload, context: PluginContext
    ) -> ToolPostInvokeResult:
        if payload.result is not None:
            # str() exposes the nested tool output (it's a CopyOnWriteDict that
            # json.dumps would flatten); report WHICH controls fired, not counts
            # (FastMCP duplicates text in content + structuredContent).
            raw = str(payload.result)
            what = []
            if _SECRET.search(raw):
                what.append("redacted API key")
            if any(p.search(raw) for p in _INJECT):
                what.append("neutralized injected instructions")
            if what:
                _audit(f"[FinByteGuard] sanitized {getattr(payload, 'name', '?')} "
                       f"output — {'; '.join(what)}")
            payload = payload.model_copy(update={"result": _scrub(payload.result)})
        return ToolPostInvokeResult(modified_payload=payload)
