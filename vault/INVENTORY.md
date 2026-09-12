# Secret inventory

For each secret: where the value came from, who put it there, when it expires.
This document becomes your Vault paths; reconstructing it from memory is the
expensive way.

| Vault path | Source | Owner | Expiry |
|---|---|---|---|
| `archi-crab/<env>/thv-jwt-signing` | generated, `openssl genrsa 2048` | | rotation invalidates all sessions |
| `archi-crab/<env>/thv-hmac` | generated, `openssl rand -base64 32` | | same |
| `archi-crab/<env>/redis-thv-auth` | generated | | |
| `archi-crab/<env>/toolhive-idp` | CERN Application Portal, `crab-mcp-gateway[-staging]` | | |
| `archi-crab/<env>/openwebui-idp` | CERN Application Portal, `archi-crab-[production\|staging]` | | |
| `archi-crab/<env>/monit-grafana` | monit-grafana.cern.ch service account | | |
| `archi-crab/<env>/robot-cert` | Puppet, `/data/certs/robot{cert,key}.pem` | | **CALENDAR THIS** |
| `archi-crab/<env>/htcondor-idtokens` | Puppet, `/data/certs/tokens.d/` | | |
| `archi-crab/<env>/litellm-keys` | providers | | |
