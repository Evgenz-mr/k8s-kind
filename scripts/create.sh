#!/usr/bin/env bash
set -Eeuo pipefail
NAME=ai-k8s; WORKERS=2; INGRESS=nginx; DASHBOARD=headlamp; ARGOCD=disabled; CERT_MANAGER=disabled; METRICS=disabled; MONITORING=disabled; VAULT=disabled; LOGGING=none; POSTGRES=disabled; MONGODB=disabled; REDIS=disabled; KAFKA=disabled; MINIO=disabled; KYVERNO=disabled; NETWORK=default
while [[ $# -gt 0 ]]; do case "$1" in --name) NAME="$2";;--workers) WORKERS="$2";;--ingress) INGRESS="$2";;--dashboard) DASHBOARD="$2";;--argocd) ARGOCD="$2";;--cert-manager) CERT_MANAGER="$2";;--metrics) METRICS="$2";;--monitoring) MONITORING="$2";;--vault) VAULT="$2";;--logging) LOGGING="$2";;--postgres) POSTGRES="$2";;--mongodb) MONGODB="$2";;--redis) REDIS="$2";;--kafka) KAFKA="$2";;--minio) MINIO="$2";;--kyverno) KYVERNO="$2";;--network) NETWORK="$2";;*) echo "Unknown option: $1" >&2;exit 2;;esac;shift 2;done
for c in docker kind kubectl helm;do command -v "$c" >/dev/null||{ echo "Missing $c" >&2;exit 1;};done
docker info >/dev/null 2>&1||{ echo 'Docker engine is not running' >&2;exit 1;};kind get clusters|grep -Fxq "$NAME"&&{ echo "Cluster $NAME already exists" >&2;exit 1;}
[[ "$INGRESS" == none && ( "$DASHBOARD" == headlamp || "$ARGOCD" == enabled || "$MONITORING" == enabled ) ]]&&{ echo 'UI components require ingress' >&2;exit 1;}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."&&pwd)";mkdir -p "$ROOT/generated";CFG="$ROOT/generated/$NAME.yaml"
{ echo 'kind: Cluster';echo 'apiVersion: kind.x-k8s.io/v1alpha4';echo "name: $NAME";[[ "$NETWORK" == cilium ]]&&{ echo 'networking:';echo '  disableDefaultCNI: true';};echo 'nodes:';echo '  - role: control-plane';echo '    extraPortMappings:';echo '      - containerPort: 80';echo '        hostPort: 8080';echo '        protocol: TCP';echo '      - containerPort: 443';echo '        hostPort: 8443';echo '        protocol: TCP';for((i=1;i<=WORKERS;i++));do echo '  - role: worker';done;} >"$CFG"
kind create cluster --name "$NAME" --config "$CFG";CTX="kind-$NAME"
if [[ "$NETWORK" == cilium ]];then helm repo add cilium https://helm.cilium.io/ --force-update;helm repo update;helm upgrade --install cilium cilium/cilium --kube-context "$CTX" -n kube-system --set ipam.mode=kubernetes --set image.pullPolicy=IfNotPresent;kubectl --context "$CTX" -n kube-system rollout status ds/cilium --timeout=300s;fi
kubectl --context "$CTX" wait --for=condition=Ready nodes --all --timeout=300s
if [[ "$INGRESS" != none ]];then kubectl --context "$CTX" label node "$NAME-control-plane" ingress-ready=true --overwrite; if [[ "$INGRESS" == nginx ]];then helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update;helm repo update;helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --kube-context "$CTX" -n ingress-nginx --create-namespace --set controller.service.type=ClusterIP --set controller.hostPort.enabled=true --set-string controller.nodeSelector.ingress-ready=true;kubectl --context "$CTX" -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s;else helm repo add haproxytech https://haproxytech.github.io/helm-charts --force-update;helm repo update;helm upgrade --install haproxy-kubernetes-ingress haproxytech/kubernetes-ingress --kube-context "$CTX" -n haproxy-controller --create-namespace --set controller.hostNetwork=true --set-string controller.nodeSelector.ingress-ready=true;kubectl --context "$CTX" -n haproxy-controller rollout status deploy/haproxy-kubernetes-ingress --timeout=300s;fi;fi
if [[ "$CERT_MANAGER" == enabled ]];then helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --kube-context "$CTX" -n cert-manager --create-namespace --set crds.enabled=true;kubectl --context "$CTX" -n cert-manager rollout status deploy/cert-manager --timeout=300s;fi
if [[ "$METRICS" == enabled ]];then helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update;helm repo update;helm upgrade --install metrics-server metrics-server/metrics-server --kube-context "$CTX" -n kube-system --set 'args={--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}' ;kubectl --context "$CTX" -n kube-system rollout status deploy/metrics-server --timeout=300s;fi
if [[ "$MONITORING" == enabled ]];then helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update;helm repo update;helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --kube-context "$CTX" -n monitoring --create-namespace --set grafana.adminUser=admin --set grafana.adminPassword=admin;kubectl --context "$CTX" -n monitoring rollout status deploy/monitoring-grafana --timeout=300s;fi
if [[ "$LOGGING" == loki ]];then helm repo add grafana-community https://grafana-community.github.io/helm-charts --force-update;helm repo add grafana https://grafana.github.io/helm-charts --force-update;helm repo update;LV=$(mktemp);cat >"$LV" <<'YAML'
deploymentMode: Monolithic
loki:
  auth_enabled: false
  commonConfig: {replication_factor: 1}
  storage: {type: filesystem}
  schemaConfig:
    configs:
      - from: "2024-04-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index: {prefix: loki_index_, period: 24h}
singleBinary: {replicas: 1, persistence: {enabled: false}}
backend: {replicas: 0}
read: {replicas: 0}
write: {replicas: 0}
ingester: {replicas: 0}
querier: {replicas: 0}
queryFrontend: {replicas: 0}
queryScheduler: {replicas: 0}
distributor: {replicas: 0}
compactor: {replicas: 0}
indexGateway: {replicas: 0}
bloomPlanner: {replicas: 0}
bloomBuilder: {replicas: 0}
bloomGateway: {replicas: 0}
chunksCache: {enabled: false}
resultsCache: {enabled: false}
YAML
helm upgrade --install loki grafana-community/loki --kube-context "$CTX" -n logging --create-namespace -f "$LV";rm -f "$LV";kubectl --context "$CTX" -n logging rollout status statefulset/loki --timeout=300s;fi
if [[ "$VAULT" == enabled ]];then helm repo add hashicorp https://helm.releases.hashicorp.com --force-update;helm repo update;helm upgrade --install vault hashicorp/vault --kube-context "$CTX" -n vault --create-namespace --set server.dev.enabled=true --set server.dev.devRootToken=root --set injector.enabled=true;kubectl --context "$CTX" -n vault wait --for=condition=Ready pod/vault-0 --timeout=300s;fi
[[ "$POSTGRES" == enabled ]]&&{ kubectl --context "$CTX" apply -f "$ROOT/components/postgres.yaml";kubectl --context "$CTX" -n database rollout status deploy/postgres --timeout=300s;};[[ "$MONGODB" == enabled ]]&&{ kubectl --context "$CTX" apply -f "$ROOT/components/mongodb.yaml";kubectl --context "$CTX" -n database rollout status deploy/mongodb --timeout=300s;};[[ "$REDIS" == enabled ]]&&{ kubectl --context "$CTX" apply -f "$ROOT/components/redis.yaml";kubectl --context "$CTX" -n data rollout status deploy/redis --timeout=300s;};[[ "$KAFKA" == enabled ]]&&{ kubectl --context "$CTX" apply -f "$ROOT/components/kafka.yaml";kubectl --context "$CTX" -n data rollout status deploy/kafka --timeout=300s;};[[ "$MINIO" == enabled ]]&&{ kubectl --context "$CTX" apply -f "$ROOT/components/minio.yaml";kubectl --context "$CTX" -n data rollout status deploy/minio --timeout=300s;}
if [[ "$KYVERNO" == enabled ]];then helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update;helm repo update;helm upgrade --install kyverno kyverno/kyverno --kube-context "$CTX" -n kyverno --create-namespace;kubectl --context "$CTX" -n kyverno rollout status deploy/kyverno-admission-controller --timeout=300s;fi
CLASS="$INGRESS"
if [[ "$DASHBOARD" == headlamp ]];then helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ --force-update;helm repo update;helm upgrade --install headlamp headlamp/headlamp --kube-context "$CTX" -n headlamp --create-namespace;kubectl --context "$CTX" -n headlamp create sa headlamp-admin --dry-run=client -o yaml|kubectl --context "$CTX" apply -f -;kubectl --context "$CTX" create clusterrolebinding headlamp-admin --clusterrole=cluster-admin --serviceaccount=headlamp:headlamp-admin --dry-run=client -o yaml|kubectl --context "$CTX" apply -f -;cat <<YAML|kubectl --context "$CTX" apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: headlamp, namespace: headlamp}
spec: {ingressClassName: $CLASS, rules: [{host: dashboard.localhost, http: {paths: [{path: /, pathType: Prefix, backend: {service: {name: headlamp, port: {number: 80}}}}]}}]}
YAML
 echo 'Headlamp token:';kubectl --context "$CTX" -n headlamp create token headlamp-admin --duration=24h;fi
if [[ "$ARGOCD" == enabled ]];then helm repo add argo https://argoproj.github.io/argo-helm --force-update;helm repo update;helm upgrade --install argocd argo/argo-cd --kube-context "$CTX" -n argocd --create-namespace --set configs.params.server\.insecure=true;kubectl --context "$CTX" -n argocd rollout status deploy/argocd-server --timeout=300s;fi
"$ROOT/scripts/smoke-test.sh" "$NAME";echo "Ready: http://dashboard.localhost:8080 (when Headlamp enabled)"
