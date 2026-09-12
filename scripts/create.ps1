param(
    [ValidateRange(0, 10)]
    [int]$Workers = 2,

    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Name = 'ai-k8s',

    [ValidateSet('nginx', 'haproxy', 'none')]
    [string]$Ingress = 'nginx',

    [ValidateSet('headlamp', 'none')]
    [string]$Dashboard = 'headlamp',

    [ValidateSet('enabled', 'disabled')]
    [string]$ArgoCD = 'disabled'
)

$ErrorActionPreference = 'Stop'

foreach ($cmd in @('docker', 'kind', 'kubectl')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Required command '$cmd' was not found in PATH." }
}
if (($Ingress -ne 'none' -or $Dashboard -ne 'none' -or $ArgoCD -eq 'enabled') -and -not (Get-Command helm -ErrorAction SilentlyContinue)) {
    throw 'Helm is required for the selected lab components.'
}
if (($Dashboard -eq 'headlamp' -or $ArgoCD -eq 'enabled') -and $Ingress -eq 'none') {
    throw 'Dashboard and Argo CD require an Ingress controller in this lab configuration.'
}

docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker is installed but the Docker engine is not running.' }

$existing = kind get clusters
if ($existing -contains $Name) { throw "Kind cluster '$Name' already exists. Delete it first or choose another -Name." }

$generatedDir = Join-Path $PSScriptRoot '..\generated'
New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null
$configPath = Join-Path $generatedDir "$Name.yaml"

$lines = @('kind: Cluster','apiVersion: kind.x-k8s.io/v1alpha4',"name: $Name",'nodes:','  - role: control-plane')
for ($i = 1; $i -le $Workers; $i++) { $lines += '  - role: worker' }
$lines | Set-Content -Path $configPath -Encoding utf8

Write-Host "Creating Kind cluster '$Name' with 1 control-plane and $Workers worker(s)..."
kind create cluster --name $Name --config $configPath
if ($LASTEXITCODE -ne 0) { throw 'kind create cluster failed.' }

kubectl cluster-info --context "kind-$Name"
kubectl --context "kind-$Name" get nodes -o wide

if ($Ingress -ne 'none') {
    & (Join-Path $PSScriptRoot 'install-ingress.ps1') -Controller $Ingress -Cluster $Name
}
if ($Dashboard -eq 'headlamp') {
    & (Join-Path $PSScriptRoot 'install-dashboard.ps1') -Dashboard headlamp -Ingress $Ingress -Cluster $Name -Username admin -Password admin
}
if ($ArgoCD -eq 'enabled') {
    & (Join-Path $PSScriptRoot 'install-argocd.ps1') -Cluster $Name -Ingress $Ingress -Username admin -Password admin
}

Write-Host ''
Write-Host "Cluster '$Name' is ready."
if ($Dashboard -eq 'headlamp') { Write-Host 'Dashboard: dashboard.local  admin/admin' }
if ($ArgoCD -eq 'enabled') { Write-Host 'Argo CD:   argocd.local     admin/admin' }
