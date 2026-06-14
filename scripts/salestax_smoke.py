"""Stage-1 proof-of-life: call add_tax(100) on the BARE sales-tax server.

Uses the async fastmcp.Client (not a hand-rolled HTTP POST — streamable-HTTP
session/init is easy to get wrong). Run via:
    uv run --with fastmcp==3.3.1 python scripts/salestax_smoke.py
Prints a single human line; exits non-zero on failure.
"""

import asyncio
import sys

from fastmcp import Client

URL = "http://localhost:8000/mcp"


async def main():
    async with Client(URL) as c:
        res = await c.call_tool("add_tax", {"amount": 100})
    # fastmcp 3.x: prefer structured .data, fall back to text content
    data = getattr(res, "data", None)
    if not isinstance(data, dict):
        sc = getattr(res, "structured_content", None)
        data = sc if isinstance(sc, dict) else {}
    tax = data.get("tax")
    total = data.get("total")
    rate = data.get("rate_pct", 8.5)
    if tax is None or total is None:
        print(f"add_tax(100) returned unexpected shape: {data!r}", file=sys.stderr)
        return 1
    print(
        f"add_tax(100, {rate}) -> tax={tax:.2f}, total={total:.2f}   "
        "(no token, no policy - anyone on :8000 can call this)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
