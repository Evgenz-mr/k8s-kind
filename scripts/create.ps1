param(
 [ValidateRange(0,10)][int]$Workers=2,[ValidatePattern('^[a-z0-9-]+$')][string]$Name='ai-k8s',
 [ValidateSet('nginx','haproxy','none')][string]$Ingress='nginx',[ValidateSet('headlamp','none')][string]$Dashboard='headlamp',
 [ValidateSet('enabled','disabled')][string]$ArgoCD='disabled',[ValidateSet('enabled','disabled')][string]$CertManager='disabled',
 [ValidateSet('enabled','disabled')][string]$Metrics='disabled',[ValidateSet('enabled','disabled')][string]$Monitoring='disabled',
 [ValidateSet('enabled','disabled')][string]$Vault='disabled',[ValidateSet('loki','none')][string]$Logging='none',
 [ValidateSet('enabled','disabled')][string]$Postgres='disabled',[ValidateSet('enabled','disabled')][string]$MongoDB='disabled',
 [ValidateSet('enabled','disabled')][string]$Redis='disabled',[ValidateSet('enabled','disabled')][string]$Kafka='disabled',
 [ValidateSet('enabled','disabled')][string]$MinIO='disabled',[ValidateSet('enabled','disabled')][string]$Kyverno='disabled',
 [ValidateSet('default','cilium')][string]$Network='default'
)
$ErrorActionPreference='Stop'
foreach($cmd in @('docker','kind','kubectl','helm')){if(-not(Get-Command $cmd -ErrorAction SilentlyContinue)){throw "Required command '$cmd' was not found in PATH."}}
docker info *> $null;if($LASTEXITCODE-ne 0){throw 'Docker engine is not running.'};if((kind get clusters)-contains $Name){throw "Kind cluster '$Name' already exists."}
if(($Dashboard-eq'headlamp'-or $ArgoCD-eq'enabled'-or $Monitoring-eq'enabled')-and $Ingress-eq'none'){throw 'Dashboard, Argo CD and Monitoring require Ingress.'}
$dir=Join-Path $PSScriptRoot '..\generated';New-Item -ItemType Directory -Force $dir|Out-Null;$cfg=Join-Path $dir "$Name.yaml"
$lines=@('kind: Cluster','apiVersion: kind.x-k8s.io/v1alpha4',"name: $Name");if($Network-eq'cilium'){$lines+=@('networking:','  disableDefaultCNI: true','  kubeProxyMode: none')};$lines+=@('nodes:','  - role: control-plane','    extraPortMappings:','      - containerPort: 80','        hostPort: 8080','        protocol: TCP','      - containerPort: 443','        hostPort: 8443','        protocol: TCP');for($i=1;$i-le$Workers;$i++){$lines+='  - role: worker'};$lines|Set-Content $cfg -Encoding utf8
kind create cluster --name $Name --config $cfg;if($LASTEXITCODE-ne 0){throw 'kind create cluster failed.'};$context="kind-$Name"
if($Network-eq'cilium'){helm repo add cilium https://helm.cilium.io/ --force-update;helm repo update;helm upgrade --install cilium cilium/cilium --kube-context $context -n kube-system --set kubeProxyReplacement=true --set k8sServiceHost="$Name-control-plane" --set k8sServicePort=6443;if($LASTEXITCODE-ne 0){throw 'Cilium installation failed.'};kubectl --context $context -n kube-system rollout status ds/cilium --timeout=300s}
kubectl --context $context wait --for=condition=Ready nodes --all --timeout=300s
if($Ingress-ne'none'){& "$PSScriptRoot\install-ingress.ps1" -Controller $Ingress -Cluster $Name}
if($CertManager-eq'enabled'){& "$PSScriptRoot\install-cert-manager.ps1" -Cluster $Name}
if($Metrics-eq'enabled'){& "$PSScriptRoot\install-metrics.ps1" -Cluster $Name}
if($Monitoring-eq'enabled'){& "$PSScriptRoot\install-monitoring.ps1" -Cluster $Name -Ingress $Ingress}
if($Logging-eq'loki'){& "$PSScriptRoot\install-logging.ps1" -Cluster $Name}
if($Vault-eq'enabled'){& "$PSScriptRoot\install-vault.ps1" -Cluster $Name}
if($Postgres-eq'enabled -or $MongoDB-eq'enabled){& "$PSScriptRoot\install-databases.ps1" -Cluster $Name -Postgres $Postgres -MongoDB $MongoDB}
if($Redis-eq'enabled -or $Kafka-eq'enabled -or $MinIO-eq'enabled -or $Kyverno-eq'enabled){& "$PSScriptRoot\install-extras.ps1" -Cluster $Name -Redis $Redis -Kafka $Kafka -MinIO $MinIO -Kyverno $Kyverno}
if($Dashboard-eq'headlamp'){& "$PSScriptRoot\install-dashboard.ps1" -Dashboard headlamp -Ingress $Ingress -Cluster $Name -Username admin -Password admin}
if($ArgoCD-eq'enabled'){& "$PSScriptRoot\install-argocd.ps1" -Cluster $Name -Ingress $Ingress -Username admin -Password admin}
Write-Host "`nCluster '$Name' created. HTTP: localhost:8080 HTTPS: localhost:8443";kubectl --context $context get pods -A
