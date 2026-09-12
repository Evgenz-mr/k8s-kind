param(
    [ValidateSet('headlamp', 'none')]
    [string]$Dashboard = 'headlamp',

    [ValidateSet('nginx', 'haproxy')]
    [string]$Ingress = 'nginx',

    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Cluster = 'ai-k8s',

    [string]$Username = 'admin'
)

$ErrorActionPreference = 'Stop'
if ($Dashboard -eq 'none') { Write-Host 'Dashboard installation skipped.'; exit 0 }

foreach ($cmd in @('helm','kubectl')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Required command '$cmd' was not found in PATH." }
}

$context = "kind-$Cluster"
kubectl --context $context get nodes *> $null
if ($LASTEXITCODE -ne 0) { throw "Kind cluster '$Cluster' is not available." }

helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ --force-update
helm repo update
helm upgrade --install headlamp headlamp/headlamp --kube-context $context --namespace headlamp --create-namespace
if ($LASTEXITCODE -ne 0) { throw 'Headlamp installation failed.' }

# Create a lab administrator identity for Headlamp's Kubernetes/RBAC login.
kubectl --context $context -n headlamp create serviceaccount headlamp-admin --dry-run=client -o yaml | kubectl --context $context apply -f -
kubectl --context $context create clusterrolebinding headlamp-admin --clusterrole=cluster-admin --serviceaccount=headlamp:headlamp-admin --dry-run=client -o yaml | kubectl --context $context apply -f -
$token = kubectl --context $context -n headlamp create token headlamp-admin --duration=24h

# Generate an ingress-level password. It is never written to Git.
$chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%'
$password = -join (1..20 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })

if ($Ingress -eq 'nginx') {
    # Generate an htpasswd-compatible bcrypt entry using a temporary container.
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker is required to generate the Basic Auth secret." }
    $authLine = docker run --rm httpd:2.4-alpine htpasswd -nbB $Username $password
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate Basic Auth credentials.' }
    $authFile = Join-Path $env:TEMP "headlamp-auth-$PID"
    [System.IO.File]::WriteAllText($authFile, "$authLine`n", [System.Text.UTF8Encoding]::new($false))
    kubectl --context $context -n headlamp create secret generic headlamp-basic-auth --from-file="auth=$authFile" --dry-run=client -o yaml | kubectl --context $context apply -f -
    Remove-Item $authFile -Force

    @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: headlamp
  namespace: headlamp
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: headlamp-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Kubernetes Lab"
spec:
  ingressClassName: nginx
  rules:
    - host: dashboard.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: headlamp
                port:
                  number: 80
"@ | kubectl --context $context apply -f -
} else {
    Write-Warning 'Headlamp was installed, but automatic username/password protection is currently implemented for NGINX Ingress only. Use the Headlamp Kubernetes token or add HAProxy authentication configuration.'
}

Write-Host ''
Write-Host 'Headlamp installed.'
Write-Host "URL host: dashboard.local"
if ($Ingress -eq 'nginx') {
    Write-Host "Ingress login: $Username"
    Write-Host "Ingress password: $password"
}
Write-Host ''
Write-Host 'Headlamp Kubernetes login token (valid for 24h):'
Write-Host $token
Write-Host ''
Write-Warning 'Save the credentials now. The generated password is not committed to Git.'
