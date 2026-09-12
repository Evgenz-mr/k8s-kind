#!/usr/bin/env bash
set -Eeuo pipefail
NAME=ai-k8s; WORKERS=2; INGRESS=nginx; DASHBOARD=headlamp; ARGOCD=disabled; CERT_MANAGER=disabled; METRICS=disabled; MONITORING=disabled; VAULT=disabled; LOGGING=none; REDIS=disabled; KAFKA=disabled; MINIO=disabled; KYVERNO=disabled; NETWORK=default
while [[ $# -gt 0 ]]; do case "$1" in
 --name) NAME="$2"; shift 2;; --workers) WORKERS="$2"; shift 2;; --ingress) INGRESS="$2"; shift 2;; --dashboard) DASHBOARD="$2"; shift 2;; --argocd) ARGOCD="$2"; shift 2;; --cert-manager) CERT_MANAGER="$2"; shift 2;; --metrics) METRICS="$2"; shift 2;; --monitoring) MONITORING="$2"; shift 2;; --vault) VAULT="$2"; shift 2;; --logging) LOGGING="$2"; shift 2;; --redis) REDIS="$2"; shift 2;; --kafka) KAFKA="$2"; shift 2;; --minio) MINIO="$2"; shift 2;; --kyverno) KYVERNO="$2"; shift 2;; --network) NETWORK="$2"; shift 2;; *) echo "Unknown option: $1" >&2; exit 2;; esac; done
for c in docker kind kubectl helm; do command -v "$c" >/dev/null || { echo "Required command '$c' not found" >&2; exit 1; }; done
docker info >/dev/null 2>&1 || { echo 'Docker engine is not running.' >&2; exit 1; }
kind get clusters | grep -Fxq "$NAME" && { echo "Kind cluster '$NAME' already exists." >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; mkdir -p "$ROOT/generated"; CFG="$ROOT/generated/$NAME.yaml"
{
 echo 'kind: Cluster'; echo 'apiVersion: kind.x-k8s.io/v1alpha4'; echo "name: $NAME"
 if [[ "$NETWORK" == cilium ]]; then echo 'networking:'; echo '  disableDefaultCNI: true'; echo '  kubeProxyMode: none'; fi
 echo 'nodes:'; echo '  - role: control-plane'; echo '    extraPortMappings:'; echo '      - containerPort: 80'; echo '        hostPort: 8080'; echo '        protocol: TCP'; echo '      - containerPort: 443'; echo '        hostPort: 8443'; echo '        protocol: TCP'
 for ((i=1;i<=WORKERS;i++)); do echo '  - role: worker'; done
} > "$CFG"
kind create cluster --name "$NAME" --config "$CFG"; CTX="kind-$NAME"
if [[ "$NETWORK" == cilium ]]; then helm repo add cilium https://helm.cilium.io/ --force-update; helm repo update; helm upgrade --install cilium cilium/cilium --kube-context "$CTX" -n kube-system --set kubeProxyReplacement=true --set k8sServiceHost="$NAME-control-plane" --set k8sServicePort=6443; kubectl --context "$CTX" -n kube-system rollout status ds/cilium --timeout=300s; fi
install_chart(){ helm upgrade --install "$1" "$2" --kube-context "$CTX" -n "$3" --create-namespace "${@:4}"; }
if [[ "$INGRESS" == nginx ]]; then helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update; helm repo update; install_chart ingress-nginx ingress-nginx/ingress-nginx ingress-nginx --set controller.hostPort.enabled=true --set controller.service.type=ClusterIP; elif [[ "$INGRESS" == haproxy ]]; then helm repo add haproxytech https://haproxytech.github.io/helm-charts --force-update; helm repo update; install_chart haproxy haproxytech/kubernetes-ingress haproxy --set controller.hostNetwork=true; fi
if [[ "$CERT_MANAGER" == enabled ]]; then install_chart cert-manager oci://quay.io/jetstack/charts/cert-manager cert-manager --set crds.enabled=true; fi
if [[ "$METRICS" == enabled ]]; then helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update; helm repo update; install_chart metrics-server metrics-server/metrics-server kube-system --set 'args={--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}' ; fi
if [[ "$MONITORING" == enabled ]]; then helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update; helm repo update; install_chart monitoring prometheus-community/kube-prometheus-stack monitoring --set grafana.adminUser=admin --set grafana.adminPassword=admin; fi
if [[ "$LOGGING" == loki ]]; then echo 'Use scripts/install-logging.ps1 under pwsh until shared Helm values migration is complete.' >&2; exit 1; fi
if [[ "$VAULT" == enabled ]]; then helm repo add hashicorp https://helm.releases.hashicorp.com --force-update; helm repo update; install_chart vault hashicorp/vault vault --set server.dev.enabled=true --set server.dev.devRootToken=root --set injector.enabled=true; fi
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update; helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update; helm repo update
[[ "$REDIS" == enabled ]] && install_chart redis bitnami/redis data --set architecture=standalone --set auth.enabled=false --set master.persistence.enabled=false
[[ "$KAFKA" == enabled ]] && install_chart kafka bitnami/kafka data --set controller.replicaCount=1 --set broker.replicaCount=0 --set persistence.enabled=false
[[ "$MINIO" == enabled ]] && install_chart minio bitnami/minio data --set auth.rootUser=admin --set auth.rootPassword=adminadmin --set persistence.enabled=false
[[ "$KYVERNO" == enabled ]] && install_chart kyverno kyverno/kyverno kyverno
kubectl --context "$CTX" get nodes -o wide; kubectl --context "$CTX" get pods -A
echo "Cluster $NAME ready. Host ingress ports: http=8080 https=8443"
