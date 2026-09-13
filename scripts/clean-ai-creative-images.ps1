param(
    [switch]$AllDangling
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'docker was not found in PATH.' }
docker info | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Docker daemon is not available.' }

Write-Host 'Removing local AI Creative images...'
$ids = docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | Where-Object { $_ -match '^ai-creative-(backend|frontend):' } | ForEach-Object { ($_ -split '\s+')[1] } | Sort-Object -Unique
if ($ids) {
    foreach ($id in $ids) { docker image rm -f $id }
} else {
    Write-Host 'No local AI Creative images found.'
}

if ($AllDangling) {
    Write-Host 'Removing all dangling Docker images...'
    docker image prune -f
}

Write-Host 'Current AI Creative images:'
docker images --filter 'reference=ai-creative-*'
