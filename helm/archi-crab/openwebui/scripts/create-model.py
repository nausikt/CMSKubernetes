"""Upsert the assistant model from MODEL_JSON and make it the default.

Idempotent by id: create if absent, update otherwise.

Tools: MCP tool servers registered in admin settings are addressed as
`server:mcp:<info.id>` (docs.openwebui.com/reference/server-side-tool-calling).
They do NOT appear in /api/v1/tools/ (that list is Python workspace tools), so
the v9 substring matcher found nothing. MODEL_JSON.tools lists info.ids; this
script verifies each is registered before attaching, and fails loudly if not.
"""
import json
import os
from _webui import call, die, signin, wait_for_webui

spec = json.loads(os.environ.get("MODEL_JSON", "{}"))
if not spec:
    die("MODEL_JSON empty -- the model job has no spec (chart wiring bug)")

wait_for_webui()
token = signin() or die("admin signin failed -- run create-admin.py first")

registered = (call("GET", "/api/v1/configs/tool_servers", token=token) or {}) \
    .get("TOOL_SERVER_CONNECTIONS", [])
reg_ids = {t.get("info", {}).get("id") for t in registered if isinstance(t, dict)}
wanted = spec.get("tools", [])
missing = [t for t in wanted if t not in reg_ids]
if missing:
    die(f"tool server(s) {missing} not registered (have {sorted(i for i in reg_ids if i)}) "
        "-- the tools job must run first")
tool_ids = [f"server:mcp:{t}" for t in wanted]

# MERGE, don't overwrite: keep every meta/params field the UI or OpenWebUI set
# (capabilities, knowledge, ...), then apply only what Git manages. A plain
# overwrite reset "Builtin Tools" to on at every sync -> 134 tools > 128 limit.
listed = ((call("GET", "/api/v1/models/list", token=token) or {}).get("items") or [])
current = next((m for m in listed if m.get("id") == spec["id"]), None)
meta = dict((current or {}).get("meta") or {})
params = dict((current or {}).get("params") or {})
meta.update({"profile_image_url": meta.get("profile_image_url", "/static/favicon.png"),
             "description": spec.get("description", ""),
             "toolIds": tool_ids})
caps = dict(meta.get("capabilities") or {})
caps.update(spec.get("capabilities") or {})   # e.g. builtin_tools: false
meta["capabilities"] = caps
params.update({"system": spec.get("prompt", ""), "function_calling": "native"})
body = {
    "id": spec["id"],
    "name": spec["name"],
    "base_model_id": spec["base"],
    "params": params,
    "meta": meta,
    "access_control": None,          # public: every signed-in user sees it
    "is_active": True,
}
if current:
    call("POST", f"/api/v1/models/model/update?id={spec['id']}", body, token=token)
    print(f"updated model {spec['id']} tools={tool_ids} capabilities={caps}")
else:
    call("POST", "/api/v1/models/create", body, token=token)
    print(f"created model {spec['id']} tools={tool_ids} capabilities={caps}")

if spec.get("default"):
    try:
        cfg = call("GET", "/api/v1/configs/models", token=token) or {}
        order = [m for m in (cfg.get("MODEL_ORDER_LIST") or []) if m != spec["id"]]
        cfg.update({"DEFAULT_MODELS": spec["id"], "MODEL_ORDER_LIST": [spec["id"]] + order})
        call("POST", "/api/v1/configs/models", cfg, token=token)   # read-modify-write
        print(f"default model -> {spec['id']}")
    except Exception:
        print("could not set default via /api/v1/configs/models -- set it once "
              "in Admin Panel > Settings > Models > Default Model")
