"""Grant tools to Bob by (re)building a virtual server that contains them.

Registering a backend only catalogs its tools; Bob can only CALL a tool that is
in the associated_tools of the virtual server his persona points at. This
ensures a named virtual server exists whose tool set is the UNION of its current
tools and the requested ones, then prints its UUID.

Usage:
    ADMIN_TOKEN=... uv run --with httpx python gateway/seed/grant.py \
        <vserver-name> <tool-name> [<tool-name> ...]
Example:
    grant.py Builder add_tax
"""

import sys

from _gwapi import api, client, jget, match_tool_ids


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: grant.py <vserver-name> <tool-name> [<tool-name> ...]")
    vname, want_names = sys.argv[1], sys.argv[2:]

    with client() as c:
        tools = jget(c, "/tools")
        want_ids = match_tool_ids(tools, want_names)
        if not want_ids:
            sys.exit(
                f"none of {want_names} found in /tools — is the backend registered?"
            )

        servers = jget(c, "/servers")
        existing = next((s for s in servers if s.get("name") == vname), None)
        keep_ids = []
        if existing:
            # preserve whatever this vserver already exposed, then union.
            # GET /servers returns `associatedTools` (camelCase) as tool NAMES;
            # re-resolve them to ids so the union survives a delete+recreate.
            assoc = existing.get("associatedTools")
            if assoc is None:
                assoc = existing.get("associated_tools", [])
            existing_names = [
                t.get("name") if isinstance(t, dict) else t for t in assoc
            ]
            keep_ids = match_tool_ids(tools, [n for n in existing_names if n])
            d = api(c, "DELETE", f"/servers/{existing['id']}")
            print(f"[server] delete existing {vname}: {d.status_code}")

        tids = list(dict.fromkeys([*keep_ids, *want_ids]))  # ordered union
        r = api(
            c,
            "POST",
            "/servers",
            json={
                "server": {
                    "name": vname,
                    "description": f"{vname} virtual server (dev-owned tools)",
                    "associated_tools": tids,
                }
            },
        )
        print(f"[server] create {vname} ({len(tids)} tools): {r.status_code}")
        if r.status_code not in (200, 201):
            sys.exit(1)

        uuid = next(
            (s.get("id") for s in jget(c, "/servers") if s.get("name") == vname), ""
        )
        if not uuid:
            sys.exit(f"could not read back the {vname} UUID")
        print(uuid)  # LAST line = UUID (Makefile captures this)


if __name__ == "__main__":
    main()
