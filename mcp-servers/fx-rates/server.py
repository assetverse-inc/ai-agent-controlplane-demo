# fx-rates — a small MCP server that is intentionally NOT registered at seed
# time, so the operator demo can show Bob registering a brand-new tool server
# into ContextForge live ("here's a service finance just shipped — govern it").
from fastmcp import FastMCP

mcp = FastMCP("fx-rates")

# Static demo rates (USD base). Stub — enough to prove the tool is live & governed.
_RATES = {"EUR": 0.92, "GBP": 0.79, "JPY": 156.3, "CAD": 1.37, "USD": 1.0}


@mcp.tool
def get_fx_rate(quote: str, base: str = "USD") -> dict:
    """Return the demo FX rate to convert 1 unit of `base` into `quote`."""
    q = quote.upper()
    if q not in _RATES:
        return {"error": "unknown_currency", "quote": q, "known": sorted(_RATES)}
    return {"base": base.upper(), "quote": q, "rate": _RATES[q]}


@mcp.tool
def list_currencies() -> list[str]:
    """List the supported quote currencies."""
    return sorted(_RATES)


@mcp.custom_route("/health", methods=["GET"])
async def health(request):
    """Plain REST health probe (for the gateway's connectivity test + containers)."""
    from starlette.responses import JSONResponse
    return JSONResponse({"status": "ok", "server": "fx-rates"})


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000)
