param(
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Name = 'ai-k8s'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    throw "Required command 'kind' was not found in PATH."
}

kind delete cluster --name $Name
if ($LASTEXITCODE -ne 0) { throw 'kind delete cluster failed.' }

Write-Host "Kind cluster '$Name' deleted."
