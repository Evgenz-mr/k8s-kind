param(
    [ValidatePattern('^[a-z0-9-]+$')][string]$Cluster = 'ai-k8s',
    [ValidateSet('enabled','disabled')][string]$Redis = 'disabled',
    [ValidateSet('enabled','disabled')][string]$Kafka = 'disabled',
    [ValidateSet('enabled','disabled')][string]$MinIO = 'disabled',
    [ValidateSet('enabled','disabled')][string]$Kyverno = 'disabled'
)

$ErrorActionPreference = 'Stop'
$ctx = "kind-$Cluster"
$root = Resolve-Path (Join-Path $PSScriptRoot '..')

$components = @(
    @{ Name = 'Redis'; Enabled = $Redis; Resource = 'redis' },
    @{ Name = 'Kafka'; Enabled = $Kafka; Resource = 'kafka' },
    @{ Name = 'MinIO'; Enabled = $MinIO; Resource = 'minio' }
)

foreach ($item in $components) {
    if ($item.Enabled -eq 'enabled') {
        $manifest = Join-Path $root ("components/{0}.yaml" -f $item.Resource)
        kubectl --context $ctx apply -f $manifest
        if ($LASTEXITCODE -ne 0) { throw ("{0} apply failed." -f $item.Name) }
        kubectl --context $ctx -n data rollout status ("deployment/{0}" -f $item.Resource) --timeout=300s
        if ($LASTEXITCODE -ne 0) { throw ("{0} rollout failed." -f $item.Name) }
    }
}

if ($Kyverno -eq 'enabled') {
    helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
    helm repo update
    helm upgrade --install kyverno kyverno/kyverno --kube-context $ctx -n kyverno --create-namespace
    if ($LASTEXITCODE -ne 0) { throw 'Kyverno install failed.' }
    kubectl --context $ctx -n kyverno rollout status deployment/kyverno-admission-controller --timeout=300s
    if ($LASTEXITCODE -ne 0) { throw 'Kyverno rollout failed.' }
}

kubectl --context $ctx get pods -A
