#!/usr/bin/env bash
set -euo pipefail

NS=${1:-monitoring}
DEPLOY=prometheus-server
KUBECTL_ARGS=(--request-timeout=10s)
TIMEOUT=${TIMEOUT:-1800}
SLEEP=${SLEEP:-5}

ensure_prefixed_probes() {
  # Ensure probe paths match the route prefix to avoid 404s
  local ns="$1" dep="$2"
  if ! kubectl "${KUBECTL_ARGS[@]}" -n "$ns" get deploy "$dep" >/dev/null 2>&1; then
    return 0
  fi
  local lpath rpath
  lpath=$(kubectl "${KUBECTL_ARGS[@]}" -n "$ns" get deploy "$dep" -o jsonpath='{.spec.template.spec.containers[?(@.name=="prometheus-server")].livenessProbe.httpGet.path}' 2>/dev/null || true)
  rpath=$(kubectl "${KUBECTL_ARGS[@]}" -n "$ns" get deploy "$dep" -o jsonpath='{.spec.template.spec.containers[?(@.name=="prometheus-server")].readinessProbe.httpGet.path}' 2>/dev/null || true)
  if [[ "$lpath" != "/prometheus/-/healthy" || "$rpath" != "/prometheus/-/ready" ]]; then
    echo "[wait-prometheus] Patching ${ns}/${dep} probes to use /prometheus prefix..."
    kubectl -n "$ns" patch deploy "$dep" --type='json' \
      -p='[{"op":"replace","path":"/spec/template/spec/containers/1/livenessProbe/httpGet/path","value":"/prometheus/-/healthy"},{"op":"replace","path":"/spec/template/spec/containers/1/readinessProbe/httpGet/path","value":"/prometheus/-/ready"}]' || true
  fi
}

ensure_prefixed_probes "$NS" "$DEPLOY"

echo "[wait-prometheus] Waiting for Deployment ${NS}/${DEPLOY} to be Available..."
start=$(date +%s)
while true; do
  if kubectl "${KUBECTL_ARGS[@]}" -n "$NS" get deploy "$DEPLOY" >/dev/null 2>&1; then
    avail=$(kubectl "${KUBECTL_ARGS[@]}" -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
    repl=$(kubectl "${KUBECTL_ARGS[@]}" -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.status.replicas}' 2>/dev/null || echo 0)
    echo "  available/desired: ${avail:-0}/${repl:-0}"
    if [[ ${repl:-0} -gt 0 && ${avail:-0} -eq ${repl:-0} ]]; then
      break
    fi
  fi
  now=$(date +%s)
  if (( now - start > TIMEOUT )); then
    echo "[wait-prometheus] Timeout waiting for ${NS}/${DEPLOY}" >&2
    exit 1
  fi
  sleep "$SLEEP"
done

echo "[wait-prometheus] Ensuring Service endpoints exist..."
start=$(date +%s)
while true; do
  eps=$(kubectl "${KUBECTL_ARGS[@]}" -n "$NS" get endpoints prometheus-server -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
  if [[ -n "${eps:-}" ]]; then
    echo "  endpoints: ${eps}"
    break
  fi
  now=$(date +%s)
  if (( now - start > TIMEOUT )); then
    echo "[wait-prometheus] Timeout waiting for Service endpoints" >&2
    exit 1
  fi
  sleep "$SLEEP"
done

echo "[wait-prometheus] Prometheus is ready."
