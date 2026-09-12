param(
    [ValidateRange(0, 10)]
    [int]$Workers = 2,

    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Name = 'ai-k8s'
)

$ErrorActionPreference = 'Stop'

foreach ($cmd in @('docker', 'kind', 'kubectl')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "Required command '$cmd' was not found in PATH."
    }
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker is installed but the Docker engine is not running.'
}

$existing = kind get clusters
if ($existing -contains $Name) {
    throw "Kind cluster '$Name' already exists. Delete it first or choose another -Name."
}

$generatedDir = Join-Path $PSScriptRoot '..\generated'
New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null
$configPath = Join-Path $generatedDir "$Name.yaml"

$lines = @(
    'kind: Cluster',
    'apiVersion: kind.x-k8s.io/v1alpha4',
    "name: $Name",
    'nodes:',
    '  - role: control-plane'
)

for ($i = 1; $i -le $Workers; $i++) {
    $lines += '  - role: worker'
}

$lines | Set-Content -Path $configPath -Encoding utf8

Write-Host "Creating Kind cluster '$Name' with 1 control-plane and $Workers worker(s)..."
kind create cluster --name $Name --config $configPath
if ($LASTEXITCODE -ne 0) { throw 'kind create cluster failed.' }

kubectl cluster-info --context "kind-$Name"
kubectl get nodes -o wide

Write-Host "Cluster '$Name' is ready."
