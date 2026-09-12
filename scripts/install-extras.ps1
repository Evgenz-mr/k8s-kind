param(
 [ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s',
 [ValidateSet('enabled','disabled')][string]$Redis='disabled',
 [ValidateSet('enabled','disabled')][string]$Kafka='disabled',
 [ValidateSet('enabled','disabled')][string]$MinIO='disabled',
 [ValidateSet('enabled','disabled')][string]$Kyverno='disabled'
)
$ErrorActionPreference='Stop';$context="kind-$Cluster"
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update
helm repo update
if($Redis-eq'enabled){helm upgrade --install redis bitnami/redis --kube-context $context -n data --create-namespace --set architecture=standalone --set auth.enabled=false --set master.persistence.enabled=false;if($LASTEXITCODE-ne 0){throw 'Redis install failed.'}}
if($Kafka-eq'enabled){helm upgrade --install kafka bitnami/kafka --kube-context $context -n data --create-namespace --set controller.replicaCount=1 --set broker.replicaCount=0 --set persistence.enabled=false;if($LASTEXITCODE-ne 0){throw 'Kafka install failed.'}}
if($MinIO-eq'enabled){helm upgrade --install minio bitnami/minio --kube-context $context -n data --create-namespace --set auth.rootUser=admin --set auth.rootPassword=adminadmin --set defaultBuckets=app --set persistence.enabled=false;if($LASTEXITCODE-ne 0){throw 'MinIO install failed.'}}
if($Kyverno-eq'enabled){helm upgrade --install kyverno kyverno/kyverno --kube-context $context -n kyverno --create-namespace;if($LASTEXITCODE-ne 0){throw 'Kyverno install failed.'}}
kubectl --context $context get pods -A
