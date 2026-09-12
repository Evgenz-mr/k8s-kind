param(
    [ValidateRange(0, 10)]
    [int]$Workers = 2,

    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Name = 'ai-k8s',

    [ValidateSet('nginx', 'haproxy', 'none')]
    [string]$Ingress = 'nginx',

    [ValidateSet('headlamp', 'none')]
    [string]$Dashboard = 'headlamp'
)

$ErrorActionPreference = 'Stop'

foreach ($cmd in @('docker', 'kind', 'kubectl')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Required command '$cmd' was not found in PATH." }
}
if (($Ingress -ne 'none' -or $Dashboard -ne 'none') -and -not (Get-Command helm -ErrorAction SilentlyContinue)) {
    throw "Helm is required when Ingress or Dashboard installation is enabled."
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
    if ($LASTEXITCODE -ne 0) { throw 'Ingress installation failed.' }
}

if ($Dashboard -eq 'headlamp') {
    if ($Ingress -eq 'none') { throw 'Headlamp dashboard requires an Ingress controller in this lab configuration.' }
    & (Join-Path $PSScriptRoot 'install-dashboard.ps1') -Dashboard headlamp -Ingress $Ingress -Cluster $Name
    if ($LASTEXITCODE -ne 0) { throw 'Dashboard installation failed.' }
}

Write-Host "Cluster '$Name' is ready."
