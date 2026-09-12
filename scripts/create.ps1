param(
 [ValidateRange(0,10)][int]$Workers=2,
 [ValidatePattern('^[a-z0-9-]+$')][string]$Name='ai-k8s',
 [ValidateSet('auto','windows','linux')][string]$HostOS='auto',
 [ValidateSet('nginx','haproxy','none')][string]$Ingress='nginx',
 [ValidateSet('headlamp','none')][string]$Dashboard='headlamp',
 [ValidateSet('enabled','disabled')][string]$ArgoCD='disabled',
 [ValidateSet('enabled','disabled')][string]$CertManager='disabled',
 [ValidateSet('enabled','disabled')][string]$Metrics='disabled',
 [ValidateSet('enabled','disabled')][string]$Monitoring='disabled',
 [ValidateSet('enabled','disabled')][string]$Vault='disabled',
 [ValidateSet('loki','none')][string]$Logging='none',
 [ValidateSet('enabled','disabled')][string]$Redis='disabled',
 [ValidateSet('enabled','disabled')][string]$Kafka='disabled',
 [ValidateSet('enabled','disabled')][string]$MinIO='disabled',
 [ValidateSet('enabled','disabled')][string]$Kyverno='disabled',
 [ValidateSet('default','cilium')][string]$Network='default'
)
$ErrorActionPreference='Stop'
if($HostOS-eq'auto'){$HostOS=if($IsWindows-or $env:OS-eq'Windows_NT'){'windows'}else{'linux'}}
Write-Host "Host OS: $HostOS"
foreach($cmd in @('docker','kind','kubectl')){if(-not(Get-Command $cmd -ErrorAction SilentlyContinue)){throw "Required command '$cmd' was not found in PATH."}}
if(($Ingress-ne'none'-or $Dashboard-ne'none'-or $ArgoCD-eq'enabled'-or $CertManager-eq'enabled'-or $Metrics-eq'enabled'-or $Monitoring-eq'enabled'-or $Vault-eq'enabled'-or $Logging-ne'none'-or $Redis-eq'enabled'-or $Kafka-eq'enabled'-or $MinIO-eq'enabled'-or $Kyverno-eq'enabled'-or $Network-eq'cilium')-and -not(Get-Command helm -ErrorAction SilentlyContinue)){throw 'Helm is required for selected components.'}
if(($Dashboard-eq'headlamp'-or $ArgoCD-eq'enabled'-or $Monitoring-eq'enabled')-and $Ingress-eq'none'){throw 'Dashboard, Argo CD and Monitoring require Ingress in this lab.'}
docker info *> $null;if($LASTEXITCODE-ne 0){throw 'Docker engine is not running.'}
if((kind get clusters)-contains $Name){throw "Kind cluster '$Name' already exists."}
$generatedDir=Join-Path $PSScriptRoot '..\generated';New-Item -ItemType Directory -Force -Path $generatedDir|Out-Null;$configPath=Join-Path $generatedDir "$Name.yaml"
$lines=@('kind: Cluster','apiVersion: kind.x-k8s.io/v1alpha4',"name: $Name");if($Network-eq'cilium'){$lines+=@('networking:','  disableDefaultCNI: true','  kubeProxyMode: none')};$lines+=@('nodes:','  - role: control-plane');for($i=1;$i-le$Workers;$i++){$lines+='  - role: worker'};$lines|Set-Content $configPath -Encoding utf8
kind create cluster --name $Name --config $configPath;if($LASTEXITCODE-ne 0){throw 'kind create cluster failed.'};$context="kind-$Name"
if($Network-eq'cilium'){helm repo add cilium https://helm.cilium.io/ --force-update;helm repo update;helm upgrade --install cilium cilium/cilium --kube-context $context -n kube-system --set kubeProxyReplacement=true --set k8sServiceHost="$Name-control-plane" --set k8sServicePort=6443;if($LASTEXITCODE-ne 0){throw 'Cilium installation failed.'};kubectl --context $context -n kube-system rollout status daemonset/cilium --timeout=300s}
kubectl --context $context get nodes -o wide
if($Ingress-ne'none'){& (Join-Path $PSScriptRoot 'install-ingress.ps1') -Controller $Ingress -Cluster $Name}
if($CertManager-eq'enabled'){& (Join-Path $PSScriptRoot 'install-cert-manager.ps1') -Cluster $Name}
if($Metrics-eq'enabled'){& (Join-Path $PSScriptRoot 'install-metrics.ps1') -Cluster $Name}
if($Monitoring-eq'enabled'){& (Join-Path $PSScriptRoot 'install-monitoring.ps1') -Cluster $Name -Ingress $Ingress}
if($Logging-eq'loki'){& (Join-Path $PSScriptRoot 'install-logging.ps1') -Cluster $Name}
if($Vault-eq'enabled'){& (Join-Path $PSScriptRoot 'install-vault.ps1') -Cluster $Name}
if($Redis-eq'enabled'-or $Kafka-eq'enabled'-or $MinIO-eq'enabled'-or $Kyverno-eq'enabled'){}
if($Redis-eq'enabled -or $Kafka-eq'enabled -or $MinIO-eq'enabled -or $Kyverno-eq'enabled){& (Join-Path $PSScriptRoot 'install-extras.ps1') -Cluster $Name -Redis $Redis -Kafka $Kafka -MinIO $MinIO -Kyverno $Kyverno}
if($Dashboard-eq'headlamp'){& (Join-Path $PSScriptRoot 'install-dashboard.ps1') -Dashboard headlamp -Ingress $Ingress -Cluster $Name -Username admin -Password admin}
if($ArgoCD-eq'enabled'){& (Join-Path $PSScriptRoot 'install-argocd.ps1') -Cluster $Name -Ingress $Ingress -Username admin -Password admin}
Write-Host "`nCluster '$Name' ready.";Write-Host "Host OS: $HostOS; Network: $Network; Ingress: $Ingress";if($Logging-eq'loki'){Write-Host 'Logging: Loki + Alloy enabled'};if($Redis-eq'enabled){Write-Host 'Redis: enabled'};if($Kafka-eq'enabled){Write-Host 'Kafka: enabled'};if($MinIO-eq'enabled){Write-Host 'MinIO: enabled'};if($Kyverno-eq'enabled){Write-Host 'Kyverno: enabled'};if($Vault-eq'enabled){Write-Host 'Vault DEV + Agent Injector: enabled; root token=root'}
