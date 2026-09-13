param(
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Cluster = 'ai-k8s',
    [string]$Namespace = 'ai-creative',
    [string]$BackendPath = (Join-Path (Split-Path $PSScriptRoot -Parent) '..\ai-creative-backend'),
    [string]$FrontendPath = (Join-Path (Split-Path $PSScriptRoot -Parent) '..\ai-creative-frontend'),
    [string]$HostName = 'ai-creative.local',
    [switch]$NoCache
)

$ErrorActionPreference = 'Stop'
$Context = "kind-$Cluster"
$BackendImage = 'ai-creative-backend:local'
$FrontendImage = 'ai-creative-frontend:local'

function Invoke-Native {
    param([scriptblock]$Command, [string]$ErrorMessage)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $ErrorMessage }
}

foreach ($cmd in @('docker','kind','kubectl','helm')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Required command '$cmd' was not found in PATH." }
}
if (-not (Test-Path (Join-Path $BackendPath 'Dockerfile'))) { throw "Backend not found: $BackendPath" }
if (-not (Test-Path (Join-Path $FrontendPath 'Dockerfile'))) { throw "Frontend not found: $FrontendPath" }
if (-not ((kind get clusters) -contains $Cluster)) { throw "Kind cluster '$Cluster' does not exist." }

Write-Host '[1/9] Checking Docker...'
Invoke-Native { docker info | Out-Null } 'Docker daemon is not available.'

Write-Host '[2/9] Removing previous local application images...'
foreach ($image in @($BackendImage,$FrontendImage)) {
    docker image inspect $image *> $null
    if ($LASTEXITCODE -eq 0) {
        docker image rm -f $image
        if ($LASTEXITCODE -ne 0) { throw "Failed to remove old image $image" }
    }
}

Write-Host '[3/9] Building fresh backend image...'
if ($NoCache) { Invoke-Native { docker build --no-cache -t $BackendImage $BackendPath } 'Backend image build failed.' }
else { Invoke-Native { docker build -t $BackendImage $BackendPath } 'Backend image build failed.' }

Write-Host '[4/9] Building fresh frontend image...'
if ($NoCache) { Invoke-Native { docker build --no-cache -t $FrontendImage $FrontendPath } 'Frontend image build failed.' }
else { Invoke-Native { docker build -t $FrontendImage $FrontendPath } 'Frontend image build failed.' }

Write-Host '[5/9] Loading fresh images into every Kind node...'
Invoke-Native { kind load docker-image $BackendImage --name $Cluster } 'Failed to load backend image into Kind.'
Invoke-Native { kind load docker-image $FrontendImage --name $Cluster } 'Failed to load frontend image into Kind.'

Write-Host '[6/9] Creating namespace...'
kubectl --context $Context create namespace $Namespace --dry-run=client -o yaml | kubectl --context $Context apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Failed to create/reconcile namespace.' }

Write-Host '[7/9] Deploying backend and frontend with Helm...'
Invoke-Native { helm upgrade --install ai-creative-backend (Join-Path $BackendPath 'helm') --kube-context $Context -n $Namespace --set image.repository=ai-creative-backend --set image.tag=local --set image.pullPolicy=IfNotPresent --set ingress.host=$HostName --set config.corsOrigins="http://${HostName}:8080" } 'Backend Helm deployment failed.'
Invoke-Native { helm upgrade --install ai-creative-frontend (Join-Path $FrontendPath 'helm') --kube-context $Context -n $Namespace --set image.repository=ai-creative-frontend --set image.tag=local --set image.pullPolicy=IfNotPresent --set ingress.host=$HostName } 'Frontend Helm deployment failed.'

# The tag stays :local, so force Kubernetes to recreate pods and consume the freshly loaded image.
Write-Host '[8/9] Restarting deployments to use fresh images...'
Invoke-Native { kubectl --context $Context -n $Namespace rollout restart deployment/ai-creative-backend } 'Backend restart failed.'
Invoke-Native { kubectl --context $Context -n $Namespace rollout restart deployment/ai-creative-frontend } 'Frontend restart failed.'
Invoke-Native { kubectl --context $Context -n $Namespace rollout status deployment/ai-creative-backend --timeout=180s } 'Backend did not become ready.'
Invoke-Native { kubectl --context $Context -n $Namespace rollout status deployment/ai-creative-frontend --timeout=180s } 'Frontend did not become ready.'

Write-Host '[9/9] Cleaning dangling Docker build images...'
docker image prune -f | Out-Host

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsEntry = "127.0.0.1 $HostName"
$hasHost = Select-String -Path $hostsPath -Pattern "(^|\s)$([regex]::Escape($HostName))(\s|$)" -Quiet -ErrorAction SilentlyContinue
if (-not $hasHost) {
    try { Add-Content -Path $hostsPath -Value "`r`n$hostsEntry" -ErrorAction Stop }
    catch { Write-Warning "Could not update hosts file. Add as Administrator: $hostsEntry" }
}

kubectl --context $Context -n $Namespace get pods,svc,ingress
Write-Host ''
Write-Host 'AI Creative fresh deployment is ready.'
Write-Host "Site: http://${HostName}:8080"
Write-Host "API ingress: http://${HostName}:8080/api"
