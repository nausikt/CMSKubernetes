#!/usr/bin/env python3
"""Reconcile OpenWebUI's global tool servers to match TOOL_SERVERS_JSON.

GET the existing list, then PATCH entries that exist (matched by id/url) and
POST entries that don't. Idempotent: running twice with the same input
converges rather than duplicating.

NOTE: the exact endpoint path and payload shape below are best-effort from
the OpenWebUI admin config API and HAVE NOT BEEN VERIFIED against a live
/openapi.json (the deployed image did not serve one at the paths tried).
Confirm before relying on this in anything but staging:
  kubectl -n <ns> exec deploy/<openwebui> -- \
    python3 -c "import urllib.request,json; \
      d=json.load(urllib.request.urlopen('http://localhost:8080/docs/openapi.json')); \
      print('\n'.join(p for p in d['paths'] if 'tool' in p.lower()))"
and adjust ENDPOINT / the payload keys to match.
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ["WEBUI_BASE_URL"].rstrip("/")
EMAIL = os.environ["ADMIN_EMAIL"]
PASSWORD = os.environ["ADMIN_PASSWORD"]
DESIRED = json.loads(os.environ.get("TOOL_SERVERS_JSON", "[]"))

# BEST GUESS -- verify against the real OpenAPI spec before trusting this path.
ENDPOINT = "/api/v1/configs/tool_servers"


def signin() -> str:
    body = json.dumps({"email": EMAIL, "password": PASSWORD}).encode()
    req = urllib.request.Request(
        f"{BASE}/api/v1/auths/signin",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        data = json.load(r)
    token = data.get("token") or data.get("access_token")
    if not token:
        print(f"signin succeeded but no token in response: {data}", file=sys.stderr)
        sys.exit(1)
    return token


def call(method, path, token, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{BASE}{path}",
        data=data,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
        method=method,
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def main():
    if not DESIRED:
        print("TOOL_SERVERS_JSON empty, nothing to do")
        return

    token = signin()

    try:
        existing = call("GET", ENDPOINT, token) or []
    except urllib.error.HTTPError as e:
        print(f"GET {ENDPOINT} failed: {e.code} {e.read().decode(errors='replace')}",
              file=sys.stderr)
        print("The endpoint path is likely wrong for this OpenWebUI version -- "
              "see the module docstring.", file=sys.stderr)
        sys.exit(1)

    try:
        existing = call("GET", ENDPOINT, token) or {}
    except urllib.error.HTTPError as e:
        print(f"GET {ENDPOINT} failed: {e.code} "
              f"{e.read().decode(errors='replace')}", file=sys.stderr)
        sys.exit(1)

    current = existing.get("TOOL_SERVER_CONNECTIONS", [])
    by_id = {t.get("info", {}).get("id"): t for t in current if isinstance(t, dict)}
        for spec in DESIRED:
            by_id[spec["info"]["id"]] = spec
        call("POST", ENDPOINT, token, {"TOOL_SERVER_CONNECTIONS": list(by_id.values())})

    print(f"reconciled {len(DESIRED)} tool server(s); "
          f"{len(by_id)} total registered")

if __name__ == "__main__":
    main()
