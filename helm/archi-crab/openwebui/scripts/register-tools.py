#!/usr/bin/env python3
"""Converge OpenWebUI's global tool servers on TOOL_SERVERS_JSON.

Endpoint verified from routers/configs.py: GET and POST /api/v1/configs/
tool_servers, both behind get_admin_user. POST takes the WHOLE list
(ToolServersConfigForm.TOOL_SERVER_CONNECTIONS) and replaces it; there is no
PATCH and no per-id route. So: GET, merge by info.id, POST the merged list.
Entries not in Git but already present are kept -- this reconciles what Git
declares, it does not prune what admins added by hand.

Payload shape (ToolServerConnection, extra='allow'):
  url, path, type, auth_type, key, config, info{id, enabled}, headers
  - key and config have NO default: they must be PRESENT, and config MUST be
    {} not null -- main.py does c.get('config', {}) which returns None for an
    explicit null, then crashes on `'access_control' in None` at startup.
    A bad registration bricks the app; see the comment in values.yaml.
"""
import json
import os
import sys
sys.path.insert(0, "/scripts")
from _webui import call, die, signin, wait_for_webui  # noqa: E402

ENDPOINT = "/api/v1/configs/tool_servers"
KEY = "TOOL_SERVER_CONNECTIONS"

desired = json.loads(os.environ.get("TOOL_SERVERS_JSON", "[]"))
if not desired:
    print("TOOL_SERVERS_JSON empty -- nothing to do")
    sys.exit(0)

for t in desired:
    if t.get("config") is None:
        die(f"tool server {t.get('info', {}).get('id')!r} has config: null -- "
            "must be {} (an explicit null crashes OpenWebUI at startup)")
    if "key" not in t:
        die(f"tool server {t.get('info', {}).get('id')!r} is missing `key` "
            "(required-but-nullable; set key: null)")

wait_for_webui()
token = signin() or die("admin signin failed -- run create-admin.py first")

current = (call("GET", ENDPOINT, token=token) or {}).get(KEY, [])
by_id = {t.get("info", {}).get("id"): t for t in current if isinstance(t, dict)}
before = set(by_id)
for t in desired:
    by_id[t["info"]["id"]] = t

call("POST", ENDPOINT, {KEY: list(by_id.values())}, token=token)
added = set(by_id) - before
print(f"reconciled {len(desired)} from Git ({len(added)} new: {sorted(added) or '-'}); "
      f"{len(by_id)} registered in total")
