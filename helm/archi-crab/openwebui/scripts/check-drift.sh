#!/usr/bin/env bash
# Detect whether cern-magnum has reverted manual patches, and whether the
# Gateway is still reachable -- on EITHER ingress path.
#
#   ./scripts/check-drift.sh --save     baseline (after any deliberate change)
#   ./scripts/check-drift.sh            compare
#
# WHY THIS EXISTS: Cilium is a cern-magnum addon, so its DaemonSets and
# ConfigMap are owned by Helm. Our patches are drift: they survive until the
# next cluster update and then vanish silently. The symptom is "the gateway
# stopped working and nobody changed anything".
#
# TWO INGRESS PATHS, both handled:
#   nodeport      Octavia LB quota is 0. Envoy binds an unprivileged NodePort;
#                 LanDB aliases point at the worker node IPs.
#   loadbalancer  quota granted. Octavia allocates a VIP; aliases point there.
# The script detects which is live and tests that one, so it survives the
# switch without edits.
set -uo pipefail

DIR="${DRIFT_DIR:-$HOME/archi-crab-drift}"
GW_NS="${GW_NS:-archi-crab-gw}"
GW_SVC="${GW_SVC:-cilium-gateway-archi-crab}"
EXPECT_NODEPORT="${EXPECT_NODEPORT:-31393}"
mkdir -p "$DIR"

snap() {
  kubectl -n kube-system get ds cilium-envoy -o json \
    | jq -cS '.spec.template.spec.containers[0].securityContext.capabilities' > "$DIR/envoy-caps.json"
  kubectl -n kube-system get ds cilium -o json \
    | jq -cS '.spec.template.spec.containers[0].securityContext.capabilities' > "$DIR/agent-caps.json"
  kubectl -n kube-system get cm cilium-config -o json \
    | jq -S '.data | with_entries(select(.key|test("gateway-api|netbindservice")))' > "$DIR/cilium-gwapi.json"
  kubectl -n "$GW_NS" get svc "$GW_SVC" -o json \
    | jq -cS '{type: .spec.type, nodePort: .spec.ports[0].nodePort, lbIP: (.status.loadBalancer.ingress[0].ip // null)}' \
    > "$DIR/gw-svc.json"
}

if [[ "${1:-}" == "--save" ]]; then
  snap; date -Is > "$DIR/taken-at.txt"
  echo "baseline saved to $DIR ($(cat "$DIR/taken-at.txt"))"
  cat "$DIR/gw-svc.json"
  exit 0
fi

rc=0
chk() {
  if [[ "$2" == *"$3"* ]]; then echo "  ok       $1"
  else echo "  MISMATCH $1 (have '${2:-<empty>}', want '$3')"; rc=1; fi
}

echo "== cilium patches (drift from cern-magnum)"
caps_envoy=$(kubectl -n kube-system get ds cilium-envoy -o json \
  | jq -r '.spec.template.spec.containers[0].securityContext.capabilities.add[]?' | paste -sd, -)
caps_agent=$(kubectl -n kube-system get ds cilium -o json \
  | jq -r '.spec.template.spec.containers[0].securityContext.capabilities.add[]?' | paste -sd, -)
# Kept even on the NodePort path: harmless, and required the moment host-network
# is retried. Losing them silently is exactly what we are watching for.
chk "cilium-envoy NET_BIND_SERVICE" "$caps_envoy" NET_BIND_SERVICE
chk "cilium agent NET_BIND_SERVICE" "$caps_agent" NET_BIND_SERVICE

echo
echo "== ingress path"
SVC_TYPE=$(kubectl -n "$GW_NS" get svc "$GW_SVC" -o jsonpath='{.spec.type}' 2>/dev/null)
NODEPORT=$(kubectl -n "$GW_NS" get svc "$GW_SVC" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
LB_IP=$(kubectl -n "$GW_NS" get svc "$GW_SVC" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
HN=$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.gateway-api-hostnetwork-enabled}' 2>/dev/null)

if [[ -n "$LB_IP" ]]; then
  MODE=loadbalancer; PORT=443; TARGETS="$LB_IP"
  echo "  LOADBALANCER -- Octavia VIP $LB_IP, port 443"
  echo "  ACTION: LanDB aliases must point HERE, not at the node IPs."
  echo "  ACTION: drop :$NODEPORT from every URL -- redirect URIs, vmcp.host,"
  echo "          authServer.issuer, OpenWebUI callbacks."
elif [[ "$SVC_TYPE" == "LoadBalancer" ]]; then
  MODE=nodeport; PORT="$NODEPORT"
  TARGETS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
  echo "  NODEPORT (LB pending) -- type=LoadBalancer, no VIP yet: quota or provisioning"
  echo "    kubectl -n $GW_NS describe svc $GW_SVC | sed -n '/Events/,\$p'"
else
  MODE=nodeport; PORT="$NODEPORT"
  TARGETS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
  echo "  NODEPORT -- type=$SVC_TYPE, port $NODEPORT"
fi

# Pinned because every OAuth redirect URI and resourceUrl carries it. A
# reassigned port invalidates all of them at once.
[[ "$MODE" == nodeport ]] && chk "nodePort pinned" "$NODEPORT" "$EXPECT_NODEPORT"
echo "  host-network mode: ${HN:-<unset>}  (expected false while on NodePort)"

echo
echo "== reachability (the check that actually matters)"
# Gateway status is unreliable on Cilium 1.18.x in host-network mode
# (cilium/cilium#42786): Programmed stays False while traffic works. Test the
# port, never the condition.
for t in $TARGETS; do
  printf '  %-18s :%-6s ' "$t" "$PORT"
  nc -z -w2 "$t" "$PORT" && echo bound || { echo "NOT BOUND"; rc=1; }
done

echo
echo "== diff against baseline"
if [[ -f "$DIR/envoy-caps.json" ]]; then
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  save="$DIR"; DIR="$tmp"; snap; DIR="$save"
  for f in envoy-caps.json agent-caps.json cilium-gwapi.json gw-svc.json; do
    if diff -q "$DIR/$f" "$tmp/$f" >/dev/null 2>&1; then echo "  same     $f"
    else echo "  CHANGED  $f"; diff "$DIR/$f" "$tmp/$f" | sed 's/^/           /'; rc=1; fi
  done
  echo "  baseline taken $(cat "$DIR/taken-at.txt" 2>/dev/null)"
else
  echo "  no baseline -- run with --save first"
fi

exit $rc
