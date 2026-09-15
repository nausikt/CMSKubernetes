#!/usr/bin/env python3
"""Ensure the bootstrap admin account exists.

OpenWebUI's FIRST account becomes admin automatically. Once any account
exists, /api/v1/auths/signup is closed and returns 403 -- so the only
idempotent check is "can this account sign in". Signin first, signup only if
that fails. Safe to re-run on every PostSync.
"""
import sys
sys.path.insert(0, "/scripts")
from _webui import EMAIL, PASSWORD, call, die, signin, wait_for_webui  # noqa: E402

wait_for_webui()

if signin():
    print("admin account present -- nothing to do")
    sys.exit(0)

try:
    call("POST", "/api/v1/auths/signup",
         {"name": "archi-crab bootstrap admin", "email": EMAIL, "password": PASSWORD})
except Exception:
    die("signup refused AND signin failed: the account exists with a different "
        "password, or signup is closed on a database with no matching account. "
        "Either reset the openwebui-admin secret to the stored password, or "
        "delete the PVC for a clean start.")

if not signin():
    die("account created but signin still fails -- check ENABLE_LOGIN_FORM")
print("admin account created")
