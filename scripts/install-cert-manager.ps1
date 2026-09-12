param(
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Cluster = 'ai-k8s'
)

$ErrorActionPreference = 'Stop'
$context = "kind-$Cluster"
foreach ($cmd in @('helm','kubectl')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Required command '$cmd' was not found in PATH." }
}

Write-Host "Installing cert-manager into '$Cluster'..."
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager `
    --kube-context $context `
    --namespace cert-manager `
    --create-namespace `
    --set crds.enabled=true
if ($LASTEXITCODE -ne 0) { throw 'cert-manager installation failed.' }

kubectl --context $context -n cert-manager rollout status deployment/cert-manager --timeout=240s
kubectl --context $context -n cert-manager rollout status deployment/cert-manager-webhook --timeout=240s
kubectl --context $context -n cert-manager rollout status deployment/cert-manager-cainjector --timeout=240s

# Disposable lab issuer. Certificates signed by it are not trusted by Windows automatically.
@"
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lab-selfsigned
spec:
  selfSigned: {}
"@ | kubectl --context $context apply -f -

Write-Host 'cert-manager installed.'
Write-Host 'ClusterIssuer: lab-selfsigned'
Write-Warning 'The self-signed issuer is for the local lab only; browsers will not trust its certificates automatically.'
