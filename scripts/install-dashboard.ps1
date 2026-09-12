param(
    [ValidateSet('headlamp', 'none')]
    [string]$Dashboard = 'headlamp',
    [ValidateSet('nginx', 'haproxy')]
    [string]$Ingress = 'nginx',
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Cluster = 'ai-k8s',
    [string]$Username = 'admin',
    [string]$Password = 'admin'
)

$ErrorActionPreference = 'Stop'
if ($Dashboard -eq 'none') { Write-Host 'Dashboard installation skipped.'; exit 0 }
foreach ($cmd in @('helm','kubectl','docker')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Required command '$cmd' was not found in PATH." }
}
$context = "kind-$Cluster"
kubectl --context $context get nodes *> $null
if ($LASTEXITCODE -ne 0) { throw "Kind cluster '$Cluster' is not available." }

helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ --force-update
helm repo update
helm upgrade --install headlamp headlamp/headlamp --kube-context $context --namespace headlamp --create-namespace
if ($LASTEXITCODE -ne 0) { throw 'Headlamp installation failed.' }

# LAB ONLY: full Kubernetes administrator identity.
kubectl --context $context -n headlamp create serviceaccount headlamp-admin --dry-run=client -o yaml | kubectl --context $context apply -f -
kubectl --context $context create clusterrolebinding headlamp-admin --clusterrole=cluster-admin --serviceaccount=headlamp:headlamp-admin --dry-run=client -o yaml | kubectl --context $context apply -f -

if ($Ingress -eq 'nginx') {
    $authLine = docker run --rm httpd:2.4-alpine htpasswd -nbB $Username $Password
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate NGINX Basic Auth credentials.' }
    $authFile = Join-Path $env:TEMP "headlamp-auth-$PID"
    [System.IO.File]::WriteAllText($authFile, "$authLine`n", [System.Text.UTF8Encoding]::new($false))
    kubectl --context $context -n headlamp create secret generic headlamp-basic-auth --from-file="auth=$authFile" --dry-run=client -o yaml | kubectl --context $context apply -f -
    Remove-Item $authFile -Force
    $annotations = @"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: headlamp-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Kubernetes Lab"
"@
    $ingressClass = 'nginx'
} else {
    # HAProxy expects a Secret key named after the user whose value is a crypt(3) password hash.
    $cryptLine = docker run --rm httpd:2.4-alpine htpasswd -nbm $Username $Password
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate HAProxy Basic Auth credentials.' }
    $cryptHash = ($cryptLine -split ':',2)[1].Trim()
    kubectl --context $context -n headlamp create secret generic headlamp-basic-auth --from-literal="$Username=$cryptHash" --dry-run=client -o yaml | kubectl --context $context apply -f -
    $annotations = @"
    haproxy.org/auth-type: basic-auth
    haproxy.org/auth-secret: headlamp/headlamp-basic-auth
    haproxy.org/auth-realm: "Kubernetes Lab"
"@
    $ingressClass = 'haproxy'
}

$manifest = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: headlamp
  namespace: headlamp
  annotations:
$annotations
spec:
  ingressClassName: $ingressClass
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
"@
$manifest | kubectl --context $context apply -f -
if ($LASTEXITCODE -ne 0) { throw 'Headlamp Ingress creation failed.' }

Write-Host ''
Write-Host 'Headlamp installed for the LOCAL LAB.'
Write-Host 'Host: dashboard.local'
Write-Host "Ingress: $Ingress"
Write-Host "Login: $Username"
Write-Host "Password: $Password"
Write-Host 'RBAC: headlamp-admin -> cluster-admin (FULL RIGHTS).'
Write-Warning 'admin/admin and cluster-admin are intentionally insecure and must only be used in this disposable local lab.'
