param(
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Cluster = 'ai-k8s'
)

$ErrorActionPreference = 'Stop'
$context = "kind-$Cluster"
$root = Split-Path -Parent $PSScriptRoot
$gitops = Join-Path $root 'gitops/ai-creative'

kubectl --context $context get crd applications.argoproj.io *> $null
if ($LASTEXITCODE -ne 0) { throw 'Argo CD is not installed. Recreate/install the lab with Argo CD enabled first.' }

kubectl --context $context apply -f (Join-Path $gitops 'namespace.yaml')
kubectl --context $context apply -f (Join-Path $gitops 'backend-application.yaml')
kubectl --context $context apply -f (Join-Path $gitops 'frontend-application.yaml')

Write-Host 'Waiting for Argo CD applications...'
kubectl --context $context -n argocd get applications ai-creative-backend ai-creative-frontend
Write-Host ''
Write-Host 'AI Creative GitOps applications installed.'
Write-Host 'Site: http://ai-creative.local'
Write-Host 'Argo CD: http://argocd.local'
