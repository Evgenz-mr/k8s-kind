param(
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Name = 'ai-k8s'
)

$ErrorActionPreference = 'Stop'

Write-Host 'Kind clusters:'
kind get clusters

Write-Host "`nKubernetes nodes for '$Name':"
kubectl --context "kind-$Name" get nodes -o wide

Write-Host "`nPods in all namespaces:"
kubectl --context "kind-$Name" get pods -A
