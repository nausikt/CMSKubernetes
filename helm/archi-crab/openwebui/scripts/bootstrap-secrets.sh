#!/usr/bin/env bash
# Hand-create the nine ARCHI-CRAB secrets, using the EXACT names the Vault
# chart will later produce. Interim measure while the Vault MR and e-group
# approval are pending.
#
#   ./scripts/bootstrap-secrets.sh archi-crab-staging
#
# Idempotent: safe to re-run. Every secret is labelled
#   archi-crab.cern.ch/provider=manual
# so the VSO migration list is one kubectl away.
#
# NEVER uses --from-literal=key=VALUE for anything secret: that form lands the
# value in your shell history AND in the process table of a shared login node
# like aiadm, where other people can read it.
set -euo pipefail
umask 077

NS="${1:?usage: $0 <namespace>}"
kubectl get ns "$NS" >/dev/null || { echo "namespace $NS not found"; exit 1; }

apply() {   # apply <name> <kubectl-create-args...>
  local name="$1"; shift
  kubectl -n "$NS" create secret generic "$name" "$@" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$NS" label secret "$name" \
    archi-crab.cern.ch/provider=manual --overwrite >/dev/null
  echo "  ok  $name"
}

echo "== generated (no input needed)"
# Per environment, never shared: a shared signing key makes a staging token
# valid in prod. thv-hmac decodes auth codes and refresh tokens -- without it
# ToolHive generates an ephemeral one and every pod restart logs everyone out.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
openssl genrsa -out "$TMP/thv.pem" 2048 2>/dev/null
apply thv-jwt-signing --from-file=private-key="$TMP/thv.pem"
apply thv-hmac        --from-literal=hmac-key="$(openssl rand -base64 32)"
apply redis-thv-auth  --from-literal=password="$(openssl rand -base64 32)"
apply openwebui-admin --from-literal=email="admin@archi-crab.cern.ch" --from-literal=password="$(openssl rand -base64 24)"

echo "== prompted (values go to stdin, never to argv)"
for spec in \
  "toolhive-idp-secret:client-secret:CERN client secret for crab-mcp-gateway[-staging]" \
  "openwebui-idp-secret:client-secret:CERN client secret for archi-crab-[production|staging]" \
  "monit-grafana:token:MONIT Grafana service-account token"
do
  name="${spec%%:*}"; rest="${spec#*:}"; key="${rest%%:*}"; prompt="${rest#*:}"
  read -rsp "  $prompt: " V; echo
  if [ -z "$V" ]; then echo "  skip $name (empty)"; continue; fi
  printf '%s' "$V" > "$TMP/v"; unset V
  apply "$name" --from-file="$key=$TMP/v"
  rm -f "$TMP/v"
done

echo "== from Puppet-provisioned host files (skipped if absent)"
if [ -r /afs/cern.ch/user/k/kphornsi/private/robot/robotcert.pem ] && [ -r /afs/cern.ch/user/k/kphornsi/private/robot/robotkey.pem ]; then
  apply crab-robot-cert \
    --from-file=robotcert.pem=/afs/cern.ch/user/k/kphornsi/private/robot/robotcert.pem \
    --from-file=robotkey.pem=/afs/cern.ch/user/k/kphornsi/private/robot/robotkey.pem
  echo -n "      expiry: "
  openssl x509 -in /afs/cern.ch/user/k/kphornsi/private/robot/robotcert.pem -noout -enddate   # CALENDAR THIS
else
  echo "  skip crab-robot-cert (/afs/cern.ch/user/k/kphornsi/private/robot/robot*.pem unreadable here)"
fi

if [ -d /data/certs/tokens.d ]; then
  apply htcondor-idtokens --from-file=/data/certs/tokens.d/
else
  echo "  skip htcondor-idtokens (/data/certs/tokens.d absent)"
fi

# Placeholder so the chart renders; replace before LiteLLM matters.
kubectl -n "$NS" get secret litellm-keys >/dev/null 2>&1 || \
  apply litellm-keys --from-literal=OPENWEBUI_VIRTUAL_KEY=placeholder

# Public CA bundle, not a credential. Needed by VSO later; harmless now.
if [ -r /etc/pki/tls/certs/CERN-bundle.pem ]; then
  apply cern-ca-bundle --from-file=ca.crt=/etc/pki/tls/certs/CERN-bundle.pem
fi

echo
echo "== result"
kubectl -n "$NS" get secret -l archi-crab.cern.ch/provider=manual \
  -o custom-columns=NAME:.metadata.name,KEYS:.data --no-headers | sed 's/^/  /'
