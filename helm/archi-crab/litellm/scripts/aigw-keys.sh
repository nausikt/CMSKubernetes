#!/usr/bin/env bash
# aigw-keys.sh — add the CERN AI gateway (AIGW) keys to each environment's Secret litellm-keys, next to the keys it
# already holds (OPENAI_API_KEY, OPENWEBUI_VIRTUAL_KEY: left as they are). Run where kubectl reaches the cluster (lxplus).
#
#   aigw-keys.sh [staging|prod|all]          default all
#
#   staging  archi-crab-staging   AIGW_SANDBOX_KEY  key archi-crab-sandbox (CERN-hosted models)
#                                 AIGW_DEV_KEY      key archi-crab-dev     (FLATIRON models)
#   prod     archi-crab           AIGW_SANDBOX_KEY  key archi-crab-sandbox
#
# Each key is read without echo and checked first against AIGW's /models: the models it may call are printed (names
# only), and a key that AIGW refuses, or that does not list what that key must list, changes nothing. The keys go to
# kubectl through pipes: never on a command line, in a file or on screen. The Secret must exist (it is never created
# here); the script prints its key names and lengths only. LiteLLM reads the Secret at start: after a change,
# restart it between runs (kubectl -n <ns> rollout restart deploy/<litellm|litellm-staging>).
set -euo pipefail
SECRET=${SECRET:-litellm-keys}
AIGW=${AIGW:-https://aigw.cern.ch/v1}
for c in kubectl curl jq base64; do command -v "$c" >/dev/null || { echo "aigw-keys: $c not found" >&2; exit 1; }; done

ask() {  # $1 prompt, $2 a model this key must list, $3 optional: the value Enter keeps. The key -> stdout.
  local v models
  read -rsp "$1: " v </dev/tty; echo >&2
  if [ -z "$v" ] && [ -n "${3:-}" ]; then printf '%s' "$3"; return; fi
  [ -n "$v" ] || { echo "aigw-keys: empty: nothing changed" >&2; return 1; }
  models=$(curl -sS -m 30 -H @<(printf 'Authorization: Bearer %s\n' "$v") "$AIGW/models" 2>/dev/null \
           | jq -r '.data[]?.id' 2>/dev/null | sort | paste -sd, -) || true
  [ -n "$models" ] || { echo "aigw-keys: AIGW refuses this key (or is unreachable from here): nothing changed" >&2; return 1; }
  echo "  AIGW: this key may call $models" >&2
  case ",$models," in *"$2"*) ;; *) echo "aigw-keys: this key lists no '$2': the wrong key? nothing changed" >&2; return 1 ;; esac
  printf '%s' "$v"
}

put() {  # namespace, then NAME=VALUE pairs: merged into the Secret's data, the other keys untouched
  local ns=$1 json="" sep="" k v
  shift
  kubectl -n "$ns" get secret "$SECRET" -o name >/dev/null 2>&1 \
    || { echo "aigw-keys: $ns has no Secret $SECRET (it holds the OpenAI keys; make it first): nothing changed" >&2; return 1; }
  for kv in "$@"; do
    k=${kv%%=*}; v=${kv#*=}
    json+="$sep\"$k\":\"$(printf '%s' "$v" | base64 | tr -d '\n')\""; sep=","
  done
  kubectl -n "$ns" patch secret "$SECRET" --type merge --patch-file <(printf '{"data":{%s}}' "$json") >/dev/null
  echo "$ns/$SECRET: $(kubectl -n "$ns" get secret "$SECRET" -o json | jq -c '.data | with_entries(.value = (.value | @base64d | length))')"
}

want=${1:-all}
case "$want" in staging|prod|all) ;; *) sed -n '2,16p' "$0" >&2; exit 2 ;; esac
S=""
if [ "$want" != prod ]; then
  echo "staging (archi-crab-staging):" >&2
  S=$(ask "  AIGW_SANDBOX_KEY = key archi-crab-sandbox" "qwen3.8-27b-fp16")
  D=$(ask "  AIGW_DEV_KEY     = key archi-crab-dev" "FLATIRON")
  put archi-crab-staging "AIGW_SANDBOX_KEY=$S" "AIGW_DEV_KEY=$D"
  unset D
fi
if [ "$want" != staging ]; then
  echo "prod (archi-crab):" >&2
  if [ -n "$S" ]; then
    PS=$(ask "  AIGW_SANDBOX_KEY = key archi-crab-sandbox (Enter: the same as staging)" "qwen3.8-27b-fp16" "$S")
  else
    PS=$(ask "  AIGW_SANDBOX_KEY = key archi-crab-sandbox" "qwen3.8-27b-fp16")
  fi
  put archi-crab "AIGW_SANDBOX_KEY=$PS"
  unset PS
fi
unset S
echo "done. LiteLLM reads these at its next start: the chart's merge restarts it once; after a later key change:" \
     "kubectl -n <ns> rollout restart deploy/<litellm|litellm-staging>, between runs" >&2
