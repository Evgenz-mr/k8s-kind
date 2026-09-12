param(
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Cluster = 'ai-k8s'
)
$ErrorActionPreference = 'Stop'
$context = "kind-$Cluster"
foreach ($cmd in @('helm','kubectl')) { if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Required command '$cmd' was not found in PATH." } }

helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update

# Single-binary Loki is appropriate for this disposable local lab.
helm upgrade --install loki grafana/loki --kube-context $context --namespace logging --create-namespace `
  --set deploymentMode=SingleBinary `
  --set singleBinary.replicas=1 `
  --set backend.replicas=0 `
  --set read.replicas=0 `
  --set write.replicas=0 `
  --set chunksCache.enabled=false `
  --set resultsCache.enabled=false `
  --set loki.auth_enabled=false `
  --set loki.commonConfig.replication_factor=1 `
  --set loki.storage.type=filesystem `
  --set singleBinary.persistence.enabled=false
if ($LASTEXITCODE -ne 0) { throw 'Loki installation failed.' }

$alloyValues = Join-Path $env:TEMP "alloy-values-$PID.yaml"
@'
alloy:
  configMap:
    content: |-
      logging {
        level = "info"
      }
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
          url = "http://loki.logging.svc.cluster.local:3100/loki/api/v1/push"
        }
      }
'@ | Set-Content -Path $alloyValues -Encoding utf8
helm upgrade --install alloy grafana/alloy --kube-context $context --namespace logging -f $alloyValues
Remove-Item $alloyValues -Force
if ($LASTEXITCODE -ne 0) { throw 'Alloy installation failed.' }

kubectl --context $context -n logging get pods
Write-Host 'Loki + Alloy logging stack installed.'
Write-Host 'Loki endpoint: http://loki.logging.svc.cluster.local:3100'
