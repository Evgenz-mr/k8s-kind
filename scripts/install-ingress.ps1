param(
    [ValidateSet('nginx', 'haproxy')]
    [string]$Controller = 'nginx',

    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Cluster = 'ai-k8s'
)

$ErrorActionPreference = 'Stop'
$context = "kind-$Cluster"

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    throw "Required command 'helm' was not found in PATH."
}
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "Required command 'kubectl' was not found in PATH."
}

kubectl --context $context get nodes *> $null
if ($LASTEXITCODE -ne 0) { throw "Kind cluster '$Cluster' is not available." }

switch ($Controller) {
    'nginx' {
        Write-Host "Installing ingress-nginx into '$Cluster'..."
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
        helm repo update
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
            --kube-context $context `
            --namespace ingress-nginx `
            --create-namespace
        if ($LASTEXITCODE -ne 0) { throw 'NGINX Ingress installation failed.' }
        kubectl --context $context -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
    }
    'haproxy' {
        Write-Host "Installing HAProxy Kubernetes Ingress into '$Cluster'..."
        helm repo add haproxytech https://haproxytech.github.io/helm-charts --force-update
        helm repo update
        helm upgrade --install haproxy-kubernetes-ingress haproxytech/kubernetes-ingress `
            --kube-context $context `
            --namespace haproxy-controller `
            --create-namespace
        if ($LASTEXITCODE -ne 0) { throw 'HAProxy Ingress installation failed.' }
        kubectl --context $context -n haproxy-controller get pods
    }
}

Write-Host "Ingress controller '$Controller' installed."
