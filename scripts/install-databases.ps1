param(
    [ValidatePattern('^[a-z0-9-]+$')][string]$Cluster = 'ai-k8s',
    [ValidateSet('enabled','disabled')][string]$Postgres = 'disabled',
    [ValidateSet('enabled','disabled')][string]$MongoDB = 'disabled'
)
$ErrorActionPreference = 'Stop'
$ctx = "kind-$Cluster"
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
if ($Postgres -eq 'enabled') {
    $postgresManifest = Join-Path $root 'components/postgres.yaml'
    kubectl --context $ctx apply -f $postgresManifest
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL apply failed.' }
    kubectl --context $ctx -n database rollout status deployment/postgres --timeout=300s
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL rollout failed.' }
}
if ($MongoDB -eq 'enabled') {
    $mongoManifest = Join-Path $root 'components/mongodb.yaml'
    kubectl --context $ctx apply -f $mongoManifest
    if ($LASTEXITCODE -ne 0) { throw 'MongoDB apply failed.' }
    kubectl --context $ctx -n database rollout status deployment/mongodb --timeout=300s
    if ($LASTEXITCODE -ne 0) { throw 'MongoDB rollout failed.' }
}
if ($Postgres -eq 'enabled' -or $MongoDB -eq 'enabled') { kubectl --context $ctx -n database get pods,svc }
