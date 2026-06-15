# sales-tax (SOLUTION / FALLBACK) — the finished server Bob is asked to BUILD
# FROM SCRATCH in the Dev Day Stage 1 beat ("use Bob to create an MCP server").
#
# The repo ships NO mcp-servers/sales-tax/server.py — that's the whole point:
# on stage, Bob writes it live. If Bob's live build wobbles, `make stage1-scaffold`
# copies THIS file to server.py so the beat keeps moving. `make stage-reset`
# removes the generated server.py so the beat repeats cleanly.
#
# Kept deliberately tiny and pure-compute (no network, no state) so Bob one-shots
# it reliably and the room can read the whole thing. Mirrors the fx-rates shape
# (fastmcp http transport + a /health route on :8000) so it runs bare via:
#   uv run --with fastmcp==3.3.1 python server.py
from fastmcp import FastMCP

mcp = FastMCP("sales-tax")


@mcp.tool
def add_tax(amount: float, rate_pct: float = 8.5) -> dict:
    """Add sales tax to an amount. `rate_pct` is a percentage, e.g. 8.5 for 8.5%."""
    tax = round(amount * rate_pct / 100, 2)
    return {
        "amount": amount,
        "rate_pct": rate_pct,
        "tax": tax,
        "total": round(amount + tax, 2),
    }


@mcp.custom_route("/health", methods=["GET"])
async def health(request):
    """Plain REST health probe (so `make stage1-build` can wait for readiness)."""
    from starlette.responses import JSONResponse

    return JSONResponse({"status": "ok", "server": "sales-tax"})


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)
