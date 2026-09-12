#!/usr/bin/env bash
set -euo pipefail

CLUSTER="${1:-ai-k8s}"
CONTEXT="kind-${CLUSTER}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITOPS_DIR="${ROOT_DIR}/gitops/ai-creative"

kubectl --context "${CONTEXT}" get crd applications.argoproj.io >/dev/null

kubectl --context "${CONTEXT}" apply -f "${GITOPS_DIR}/namespace.yaml"
kubectl --context "${CONTEXT}" apply -f "${GITOPS_DIR}/backend-application.yaml"
kubectl --context "${CONTEXT}" apply -f "${GITOPS_DIR}/frontend-application.yaml"

echo "Waiting for Argo CD applications..."
kubectl --context "${CONTEXT}" -n argocd get applications ai-creative-backend ai-creative-frontend

echo
echo "AI Creative GitOps applications installed."
echo "Site: http://ai-creative.local"
echo "Argo CD: http://argocd.local"
