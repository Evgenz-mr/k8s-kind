param(
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Cluster = 'ai-k8s',
    [ValidateSet('nginx','haproxy')]
    [string]$Ingress = 'nginx',
    [string]$Username = 'admin',
    [string]$Password = 'admin'
)

$ErrorActionPreference = 'Stop'
$context = "kind-$Cluster"
foreach ($cmd in @('helm','kubectl')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Required command '$cmd' was not found in PATH." }
}

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update
helm upgrade --install argocd argo/argo-cd --kube-context $context --namespace argocd --create-namespace `
  --set configs.params."server\.insecure"=true
if ($LASTEXITCODE -ne 0) { throw 'Argo CD installation failed.' }

kubectl --context $context -n argocd rollout status deployment/argocd-server --timeout=240s

# LAB ONLY: set the built-in Argo CD admin password to admin.
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker is required to generate bcrypt hashes.' }
$bcrypt = docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 $Username $Password
if ($LASTEXITCODE -ne 0) { throw 'Could not generate Argo CD password hash.' }
$hash = ($bcrypt -split ':',2)[1].Trim()
kubectl --context $context -n argocd patch secret argocd-secret --type merge -p "{`"stringData`":{`"admin.password`":`"$hash`",`"admin.passwordMtime`":`"$(Get-Date -Format o)`"}}"
if ($LASTEXITCODE -ne 0) { throw 'Could not set Argo CD admin password.' }
kubectl --context $context -n argocd rollout restart deployment argocd-server

$ingressClass = if ($Ingress -eq 'nginx') { 'nginx' } else { 'haproxy' }
@"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
spec:
  ingressClassName: $ingressClass
  rules:
    - host: argocd.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
"@ | kubectl --context $context apply -f -

Write-Host ''
Write-Host 'Argo CD installed for the LOCAL LAB.'
Write-Host 'Host: argocd.local'
Write-Host "Login: $Username"
Write-Host "Password: $Password"
Write-Warning 'admin/admin is intentionally insecure and must only be used in this disposable local lab.'
