"""Shared helpers for the OpenWebUI bootstrap Jobs. Stdlib only -- these run
in python:3.12-alpine with nothing installed."""
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ["WEBUI_BASE_URL"].rstrip("/")
EMAIL = os.environ["ADMIN_EMAIL"]
PASSWORD = os.environ["ADMIN_PASSWORD"]


def die(msg: str, code: int = 1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def call(method: str, path: str, body=None, token: str | None = None, timeout: int = 15):
    """One HTTP call. On an HTTP error, print the RESPONSE BODY before
    re-raising -- FastAPI's 422 names the exact field, and a bare traceback
    hides it (which cost three sync cycles the first time round)."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        f"{BASE}{path}",
        data=json.dumps(body).encode() if body is not None else None,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        print(f"{method} {path} -> {e.code}\n{e.read().decode(errors='replace')}", file=sys.stderr)
        raise


def wait_for_webui(timeout: int = 180):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(f"{BASE}/health", timeout=5)
            return
        except Exception:
            time.sleep(3)
    die(f"OpenWebUI at {BASE} never became healthy in {timeout}s")


def signin() -> str | None:
    """Return a bearer token, or None if the credentials are refused."""
    try:
        data = call("POST", "/api/v1/auths/signin", {"email": EMAIL, "password": PASSWORD})
    except urllib.error.HTTPError as e:
        if e.code in (400, 401, 403):
            return None
        raise
    return data.get("token") or data.get("access_token")
