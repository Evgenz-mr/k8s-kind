param(
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Cluster = 'ai-k8s',
    [string]$Namespace = 'ai-creative',
    [string]$BackendPath = (Join-Path (Split-Path $PSScriptRoot -Parent) '..\ai-creative-backend'),
    [string]$FrontendPath = (Join-Path (Split-Path $PSScriptRoot -Parent) '..\ai-creative-frontend'),
    [string]$HostName = 'ai-creative.local'
)

$ErrorActionPreference = 'Stop'
$Context = "kind-$Cluster"

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

Write-Host '[1/7] Checking Docker...'
Invoke-Native { docker info | Out-Null } 'Docker daemon is not available.'

Write-Host '[2/7] Building backend image...'
Invoke-Native { docker build -t ai-creative-backend:local $BackendPath } 'Backend image build failed.'

Write-Host '[3/7] Building frontend image...'
Invoke-Native { docker build -t ai-creative-frontend:local $FrontendPath } 'Frontend image build failed.'

Write-Host '[4/7] Loading images into Kind...'
Invoke-Native { kind load docker-image ai-creative-backend:local --name $Cluster } 'Failed to load backend image into Kind.'
Invoke-Native { kind load docker-image ai-creative-frontend:local --name $Cluster } 'Failed to load frontend image into Kind.'

Write-Host '[5/7] Creating namespace...'
kubectl --context $Context create namespace $Namespace --dry-run=client -o yaml | kubectl --context $Context apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Failed to create/reconcile namespace.' }

Write-Host '[6/7] Deploying backend and frontend with Helm...'
Invoke-Native { helm upgrade --install ai-creative-backend (Join-Path $BackendPath 'helm') --kube-context $Context -n $Namespace --set image.repository=ai-creative-backend --set image.tag=local --set image.pullPolicy=IfNotPresent --set ingress.host=$HostName --set config.corsOrigins="http://${HostName}:8080" } 'Backend Helm deployment failed.'
Invoke-Native { helm upgrade --install ai-creative-frontend (Join-Path $FrontendPath 'helm') --kube-context $Context -n $Namespace --set image.repository=ai-creative-frontend --set image.tag=local --set image.pullPolicy=IfNotPresent --set ingress.host=$HostName } 'Frontend Helm deployment failed.'

Write-Host '[7/7] Waiting for applications...'
Invoke-Native { kubectl --context $Context -n $Namespace rollout status deployment/ai-creative-backend --timeout=180s } 'Backend did not become ready.'
Invoke-Native { kubectl --context $Context -n $Namespace rollout status deployment/ai-creative-frontend --timeout=180s } 'Frontend did not become ready.'

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsEntry = "127.0.0.1 $HostName"
$hasHost = Select-String -Path $hostsPath -Pattern "(^|\s)$([regex]::Escape($HostName))(\s|$)" -Quiet -ErrorAction SilentlyContinue
if (-not $hasHost) {
    try {
        Add-Content -Path $hostsPath -Value "`r`n$hostsEntry" -ErrorAction Stop
        Write-Host "Added $hostsEntry to Windows hosts file."
    } catch {
        Write-Warning "Could not update the Windows hosts file. Run PowerShell as Administrator and add: $hostsEntry"
    }
}

kubectl --context $Context -n $Namespace get pods,svc,ingress
Write-Host ''
Write-Host 'AI Creative deployment is ready.'
Write-Host "Site: http://${HostName}:8080"
Write-Host "API ingress: http://${HostName}:8080/api"
