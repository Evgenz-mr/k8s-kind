param([ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s')
$ErrorActionPreference='Stop';$ctx="kind-$Cluster"
foreach($cmd in @('helm','kubectl')){if(-not(Get-Command $cmd -ErrorAction SilentlyContinue)){throw "Required command '$cmd' was not found in PATH."}}

helm repo add grafana-community https://grafana-community.github.io/helm-charts --force-update
if($LASTEXITCODE-ne 0){throw 'Failed to add Grafana Community Helm repository.'}
helm repo add grafana https://grafana.github.io/helm-charts --force-update
if($LASTEXITCODE-ne 0){throw 'Failed to add Grafana Helm repository.'}
helm repo update
if($LASTEXITCODE-ne 0){throw 'Failed to update Helm repositories.'}

$lokiValues=Join-Path $env:TEMP "loki-values-$PID.yaml"
@'
deploymentMode: Monolithic
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-04-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
singleBinary:
  replicas: 1
  persistence:
    enabled: false
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
'@|Set-Content $lokiValues -Encoding utf8
helm upgrade --install loki grafana-community/loki --kube-context $ctx -n logging --create-namespace -f $lokiValues
$lokiExitCode=$LASTEXITCODE
Remove-Item $lokiValues -Force
if($lokiExitCode-ne 0){throw 'Loki installation failed.'}

$alloyValues=Join-Path $env:TEMP "alloy-values-$PID.yaml"
@'
alloy:
  configMap:
    content: |-
      discovery.kubernetes "pods" {
        role = "pod"
      }

      discovery.relabel "pods" {
        targets = discovery.kubernetes.pods.targets

        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
        }
      }

      loki.source.kubernetes "pods" {
        targets    = discovery.relabel.pods.output
        forward_to = [loki.write.default.receiver]
      }

      loki.write "default" {
        endpoint {
          url = "http://loki-gateway.logging.svc.cluster.local/loki/api/v1/push"
        }
      }
'@|Set-Content $alloyValues -Encoding utf8
helm upgrade --install alloy grafana/alloy --kube-context $ctx -n logging --create-namespace -f $alloyValues
$alloyExitCode=$LASTEXITCODE
Remove-Item $alloyValues -Force
if($alloyExitCode-ne 0){throw 'Alloy installation failed.'}

kubectl --context $ctx -n logging rollout status statefulset/loki --timeout=300s
if($LASTEXITCODE-ne 0){throw 'Loki rollout failed or timed out.'}
kubectl --context $ctx -n logging rollout status daemonset/alloy --timeout=300s
if($LASTEXITCODE-ne 0){
    Write-Host 'Alloy rollout failed. Current pods:'
    kubectl --context $ctx -n logging get pods -o wide
    throw 'Alloy rollout failed or timed out.'
}

$previousErrorActionPreference=$ErrorActionPreference
try{
    $ErrorActionPreference='Continue'
    kubectl --context $ctx get namespace monitoring 1>$null 2>$null
    $monitoringExitCode=$LASTEXITCODE
}finally{$ErrorActionPreference=$previousErrorActionPreference}
if($monitoringExitCode-eq 0){@'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-grafana-datasource
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  loki.yaml: |-
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki-gateway.logging.svc.cluster.local
        isDefault: false
'@|kubectl --context $ctx apply -f -
if($LASTEXITCODE-ne 0){throw 'Failed to configure Loki Grafana datasource.'}}
Write-Host 'Loki + Alloy ready.'
