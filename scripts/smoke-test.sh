#!/usr/bin/env bash
set -uo pipefail
CLUSTER=${1:-ai-k8s}; CTX="kind-$CLUSTER"; FAIL=0
run(){ printf '[TEST] %s\n' "$1"; shift; if "$@"; then echo '[PASS]'; else echo '[FAIL]'; FAIL=1; fi; }
run 'Nodes Ready' kubectl --context "$CTX" wait --for=condition=Ready nodes --all --timeout=60s
run 'CoreDNS Ready' kubectl --context "$CTX" -n kube-system rollout status deployment/coredns --timeout=60s
run 'API discovery' kubectl --context "$CTX" api-resources
if kubectl --context "$CTX" get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1; then run 'Metrics API' kubectl --context "$CTX" top nodes; fi
BAD=$(kubectl --context "$CTX" get pods -A --field-selector=status.phase=Failed -o name 2>/dev/null || true); if [[ -n "$BAD" ]]; then echo "[FAIL] Failed pods: $BAD"; FAIL=1; else echo '[PASS] No failed pods'; fi
kubectl --context "$CTX" get pods -A
(( FAIL == 0 )) || { echo 'SMOKE TESTS FAILED'; exit 1; }; echo 'ALL SMOKE TESTS PASSED.'
