#!/usr/bin/env python3
"""Create OpenWebUI's first account (auto-admin) if it doesn't exist yet.

Idempotent by design: OpenWebUI's signup endpoint 400s on a duplicate email,
which this script treats as success rather than failure. Safe to run on
every ArgoCD PreSync.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ["WEBUI_BASE_URL"].rstrip("/")
EMAIL = os.environ["ADMIN_EMAIL"]
PASSWORD = os.environ["ADMIN_PASSWORD"]
NAME = os.environ.get("ADMIN_NAME", "bootstrap admin")


def wait_for_webui(timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(f"{BASE}/health", timeout=5)
            return
        except Exception:
            time.sleep(3)
    print("WEBUI never became healthy", file=sys.stderr)
    sys.exit(1)


def signup():
    body = json.dumps({"name": NAME, "email": EMAIL, "password": PASSWORD}).encode()
    req = urllib.request.Request(
        f"{BASE}/api/v1/auths/signup",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            print(f"admin account created: {r.status}")
            return
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        if e.code == 400:
            # OpenWebUI returns 400 for "email already registered" as well as
            # other validation errors. Confirm it's the former by attempting
            # a signin -- a real validation error should NOT be treated as
            # already-bootstrapped.
            if signin_works():
                print("admin account already exists, signin verified -- ok")
                return
            print(f"signup 400 and signin failed, not already-bootstrapped: {body}",
                  file=sys.stderr)
            sys.exit(1)
        print(f"signup failed: {e.code} {body}", file=sys.stderr)
        sys.exit(1)


def signin_works() -> bool:
    body = json.dumps({"email": EMAIL, "password": PASSWORD}).encode()
    req = urllib.request.Request(
        f"{BASE}/api/v1/auths/signin",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=15)
        return True
    except urllib.error.HTTPError:
        return False


if __name__ == "__main__":
    wait_for_webui()
    signup()
