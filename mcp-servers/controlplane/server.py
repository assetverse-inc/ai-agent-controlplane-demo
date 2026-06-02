# controlplane — FastMCP v3 MCP server: the "operator" surface.
#
# This is the meta layer of the demo: it exposes ContextForge's OWN management
# and observability through MCP tools, so Bob (as a privileged *platform
# operator* persona — distinct from the least-privilege FinOps analyst) can
# operate and inspect the very control plane that governs the other agents:
#   - register a NEW MCP server into the gateway      (extend the plane)
#   - list everything the gateway is governing        (the federated catalog)
#   - read the audit trail of blocked invocations     (what got stopped)
#   - interrogate the OPA policy engine live           (why — would X be allowed?)
#
# It talks to the gateway admin API (with an admin token) and to OPA directly,
# both reachable by Compose service name on the private network.
import os
import re

import httpx
from fastmcp import FastMCP

GW = os.environ.get("GATEWAY_URL", "http://gateway:4444")
TOKEN = os.environ.get("GATEWAY_TOKEN", "")
OPA = os.environ.get("OPA_URL", "http://opa:8181")
H = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}

mcp = FastMCP("controlplane")


@mcp.tool
def register_mcp_server(name: str, url: str, description: str = "") -> dict:
    """Register a NEW MCP server into the ContextForge gateway so its tools join
    the governed catalog. `url` is the server's MCP endpoint, reachable from the
    gateway (e.g. 'http://my-service:8000/mcp')."""
    try:
        r = httpx.post(f"{GW}/gateways", headers=H, timeout=30, json={
            "name": name, "url": url, "transport": "STREAMABLEHTTP",
            "description": description or f"{name} (registered via operator)",
        })
    except Exception as e:  # noqa: BLE001
        return {"registered": False, "error": str(e), "name": name, "url": url}
    ok = 200 <= r.status_code < 300
    out = {"registered": ok, "status_code": r.status_code, "name": name, "url": url}
    try:
        out["gateway_response"] = r.json()
    except Exception:  # noqa: BLE001
        out["gateway_response"] = r.text[:300]
    return out


@mcp.tool
def list_control_plane() -> dict:
    """List everything ContextForge is governing: federated MCP servers, A2A
    agents, and the virtual servers (each a least-privilege tool scope)."""
    def get(path):
        try:
            return httpx.get(f"{GW}{path}", headers=H, timeout=15).json()
        except Exception:  # noqa: BLE001
            return []

    gateways = get("/gateways")
    agents = get("/a2a")
    servers = get("/servers")
    vservers = []
    for s in servers if isinstance(servers, list) else []:
        try:
            tools = httpx.get(f"{GW}/servers/{s['id']}/tools", headers=H, timeout=15).json()
            names = sorted(t.get("name", "") for t in tools) if isinstance(tools, list) else []
        except Exception:  # noqa: BLE001
            names = []
        vservers.append({"name": s.get("name"), "id": s.get("id"),
                         "tool_count": len(names), "tools": names})
    return {
        "mcp_servers": [{"name": x.get("name"), "url": x.get("url")}
                        for x in gateways] if isinstance(gateways, list) else [],
        "a2a_agents": [x.get("name") for x in agents] if isinstance(agents, list) else [],
        "virtual_servers": vservers,
    }


@mcp.tool
def recent_blocks(limit: int = 10) -> list[dict]:
    """The audit trail of recent tool invocations the control plane BLOCKED
    (policy violations / errors), newest first — what was stopped and when."""
    try:
        d = httpx.get(f"{GW}/admin/logs", headers=H, timeout=15,
                      params={"level": "ERROR", "limit": limit}).json()
    except Exception as e:  # noqa: BLE001
        return [{"error": f"could not read audit log: {e}"}]
    rows = []
    for e in (d.get("logs", []) if isinstance(d, dict) else []):
        msg = str(e.get("message", ""))
        m = re.search(r"Tool '([^']+)' invocation failed", msg)
        if not m:
            continue
        rows.append({
            "time": str(e.get("timestamp", ""))[:19],
            "tool": m.group(1),
            "outcome": "blocked",
            "request_id": e.get("request_id"),
        })
    return rows


@mcp.tool
def evaluate_policy(amount: float, approval: bool = False,
                    tool: str = "erp-payments-wire") -> dict:
    """Ask the OPA policy engine directly whether a payment of `amount` (with or
    without `approval`) WOULD be allowed — interrogating the policy live, without
    actually attempting the payment. Returns allow + any deny reasons."""
    payload = {"input": {
        "action": f"tools.invoke.{tool}",
        "resource": {"id": tool, "type": "tool"},
        "context": {"tool_args": {"amount": amount, "approval": approval,
                                  "payee": "(policy probe)"}},
    }}
    try:
        res = httpx.post(f"{OPA}/v1/data/mcpgateway", json=payload, timeout=15).json().get("result", {})
    except Exception as e:  # noqa: BLE001
        return {"error": f"OPA unreachable: {e}"}
    return {
        "tool": tool, "amount": amount, "approval": approval,
        "allow": res.get("allow"),
        "deny": res.get("deny", []),
    }


@mcp.custom_route("/health", methods=["GET"])
async def health(request):
    """Plain REST health probe (for the gateway's connectivity test + containers)."""
    from starlette.responses import JSONResponse
    return JSONResponse({"status": "ok", "server": "controlplane"})


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)
