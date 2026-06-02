# erp-payments — FastMCP v3 MCP server (money operations)
# `wire` is the dangerous one: OPA blocks amount >= 10000 without approval=true.
# `wire` is hidden from Bob's FinOps virtual server; only the Treasury-scoped
# Payments agent may reach it (and OPA still gates it).
from fastmcp import FastMCP

mcp = FastMCP("erp-payments")


@mcp.tool
def approve(expense_id: str) -> dict:
    """Mark an expense as approved for reimbursement."""
    return {"status": "approved", "expense_id": expense_id}


@mcp.tool
def reimburse(expense_id: str, amount: float = 0.0) -> dict:
    """Reimburse an approved expense (low-risk)."""
    return {"status": "reimbursed", "expense_id": expense_id, "amount": amount}


@mcp.tool
def wire(payee: str, amount: float, approval: bool = False) -> dict:
    """Wire funds to a payee. High-risk: large wires require approval=true
    (enforced by the gateway's OPA policy, not here)."""
    return {"status": "wired", "payee": payee, "amount": amount, "approval": approval}


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)
