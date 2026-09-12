param([ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s',[ValidateSet('enabled','disabled')][string]$Postgres='disabled',[ValidateSet('enabled','disabled')][string]$MongoDB='disabled')
$ErrorActionPreference='Stop';$ctx="kind-$Cluster";$root=Resolve-Path (Join-Path $PSScriptRoot '..')
if($Postgres-eq'enabled){kubectl --context $ctx apply -f (Join-Path $root 'components/postgres.yaml');if($LASTEXITCODE-ne 0){throw 'PostgreSQL apply failed.'};kubectl --context $ctx -n database rollout status deployment/postgres --timeout=300s}
if($MongoDB-eq'enabled){kubectl --context $ctx apply -f (Join-Path $root 'components/mongodb.yaml');if($LASTEXITCODE-ne 0){throw 'MongoDB apply failed.'};kubectl --context $ctx -n database rollout status deployment/mongodb --timeout=300s}
kubectl --context $ctx -n database get pods,svc
