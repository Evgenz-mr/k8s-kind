param([ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s',[ValidateSet('enabled','disabled')][string]$Postgres='disabled',[ValidateSet('enabled','disabled')][string]$MongoDB='disabled')
$ErrorActionPreference='Stop';$context="kind-$Cluster"
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update;helm repo update
if($Postgres-eq'enabled'){}
if($Postgres-eq'enabled){helm upgrade --install postgres bitnami/postgresql --kube-context $context -n database --create-namespace --set auth.username=app --set auth.password=app12345 --set auth.database=appdb --set auth.postgresPassword=postgres12345 --set primary.persistence.enabled=false;if($LASTEXITCODE-ne 0){throw 'PostgreSQL install failed.'}}
if($MongoDB-eq'enabled){helm upgrade --install mongodb bitnami/mongodb --kube-context $context -n database --create-namespace --set architecture=standalone --set auth.rootUser=root --set auth.rootPassword=mongo12345 --set auth.username=app --set auth.password=app12345 --set auth.database=appdb --set persistence.enabled=false;if($LASTEXITCODE-ne 0){throw 'MongoDB install failed.'}}
kubectl --context $context -n database get pods,svc
