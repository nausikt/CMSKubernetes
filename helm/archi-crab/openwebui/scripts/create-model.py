"""Upsert the assistant model from MODEL_JSON and make it the default.

Idempotent by id: create if absent, update otherwise. Tool servers are matched
against /api/v1/tools ids (substring, case-insensitive) so the exact
"server:<id>" naming OpenWebUI uses never has to be hardcoded here. Setting
the default model uses /api/v1/configs/models; if that endpoint moves in a
future OpenWebUI, the script prints the manual step instead of failing the sync.
"""
import json
import os
from _webui import call, die, signin, wait_for_webui

spec = json.loads(os.environ.get("MODEL_JSON", "{}"))
if not spec:
    print("MODEL_JSON empty -- nothing to do")
    raise SystemExit(0)

wait_for_webui()
token = signin() or die("admin signin failed -- run create-admin.py first")

tools = call("GET", "/api/v1/tools/", token=token) or []
matches = [m.lower() for m in spec.get("toolMatch", [])]
tool_ids = sorted({t["id"] for t in tools
                   for m in matches if m in t.get("id", "").lower()})
missing = [m for m in matches if not any(m in i.lower() for i in tool_ids)]
if missing:
    print(f"WARNING: no registered tool id matched {missing} -- "
          f"available: {[t.get('id') for t in tools]}")

body = {
    "id": spec["id"],
    "name": spec["name"],
    "base_model_id": spec["base"],
    "params": {"system": spec.get("prompt", ""), "function_calling": "native"},
    "meta": {"profile_image_url": "/static/favicon.png",
             "description": "CRAB operations assistant",
             "toolIds": tool_ids},
    "is_active": True,
}
existing = {m.get("id") for m in (call("GET", "/api/v1/models/", token=token) or [])}
if spec["id"] in existing:
    call("POST", f"/api/v1/models/model/update?id={spec['id']}", body, token=token)
    print(f"updated model {spec['id']} (tools: {tool_ids or '-'})")
else:
    call("POST", "/api/v1/models/create", body, token=token)
    print(f"created model {spec['id']} (tools: {tool_ids or '-'})")

if spec.get("default"):
    try:
        call("POST", "/api/v1/configs/models",
             {"DEFAULT_MODELS": spec["id"], "MODEL_ORDER_LIST": [spec["id"]]},
             token=token)
        print(f"default model -> {spec['id']}")
    except Exception:
        print("could not set default via /api/v1/configs/models -- set it once "
              "in Admin Panel > Settings > Models > Default Model")
