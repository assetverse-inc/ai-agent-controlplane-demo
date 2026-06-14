"""Register (or RE-register) a backend MCP server into the gateway.

Unlike a bare POST that treats "already exists" as success, this DELETEs any
existing gateway record of the same name first, so the gateway re-discovers the
backend's current tool list (e.g. a freshly-added `convert`). Mirrors seed.py.

Usage:
    ADMIN_TOKEN=... uv run --with httpx python gateway/seed/register.py \
        <name> <url> [transport]
Example:
    register.py sales-tax http://sales-tax:8000/mcp STREAMABLEHTTP
"""

import sys
import time

from _gwapi import api, client, jget


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: register.py <name> <url> [transport]")
    name, url = sys.argv[1], sys.argv[2]
    transport = sys.argv[3] if len(sys.argv) > 3 else "STREAMABLEHTTP"

    with client() as c:
        for g in jget(c, "/gateways"):
            if g.get("name") == name and g.get("id"):
                d = api(c, "DELETE", f"/gateways/{g['id']}")
                print(f"[gw] delete existing {name}: {d.status_code}")

        body = {
            "name": name,
            "url": url,
            "transport": transport,
            "description": f"{name} MCP server",
        }
        # The gateway probes the backend during registration; a just-(re)built
        # container may not be ready yet (502). Retry a few times before failing.
        last = ""
        for attempt in range(1, 7):
            try:
                r = api(c, "POST", "/gateways", json=body)
            except Exception as e:  # transport error: backend/gateway not ready
                last = f"request error: {e}"
                print(f"[gw] register {name} attempt {attempt}/6: {last}")
                time.sleep(2)
                continue
            if r.status_code in (200, 201):
                print(f"[gw] register {name}: {r.status_code} {r.text[:160]}")
                return
            last = f"{r.status_code} {r.text[:160]}"
            print(f"[gw] register {name} attempt {attempt}/6: {last}")
            if r.status_code < 500:
                break  # a 4xx won't fix itself by retrying
            time.sleep(2)
        sys.exit(f"register {name} failed after retries: {last}")


if __name__ == "__main__":
    main()
