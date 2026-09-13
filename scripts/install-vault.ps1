param([ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s')
$ErrorActionPreference='Stop'; $context="kind-$Cluster"
foreach($cmd in @('helm','kubectl')){if(-not(Get-Command $cmd -ErrorAction SilentlyContinue)){throw "Required command '$cmd' was not found in PATH."}}

# Remove a stale/broken local repository entry first. On Windows Helm can keep an
# unusable HashiCorp entry after a transient repository/network failure.
$previousErrorActionPreference=$ErrorActionPreference
try {
    $ErrorActionPreference='Continue'
    helm repo remove hashicorp 1>$null 2>$null
} finally {
    $ErrorActionPreference=$previousErrorActionPreference
}

helm repo add hashicorp https://helm.releases.hashicorp.com
if($LASTEXITCODE-ne 0){throw 'Failed to add HashiCorp Helm repository. Check access to helm.releases.hashicorp.com.'}
helm repo update
if($LASTEXITCODE-ne 0){throw 'Failed to update Helm repositories.'}

helm upgrade --install vault hashicorp/vault --kube-context $context --namespace vault --create-namespace --set server.dev.enabled=true --set server.dev.devRootToken=root --set injector.enabled=true --set injector.metrics.enabled=true
if($LASTEXITCODE-ne 0){throw 'Vault installation failed.'}

# Wait for resources explicitly and fail instead of reporting a false success.
Write-Host 'Waiting for Vault resources...'
for($i=1;$i-le 60;$i++){
    kubectl --context $context -n vault get pod vault-0 1>$null 2>$null
    if($LASTEXITCODE-eq 0){break}
    if($i-eq 60){throw 'vault-0 pod was not created within 120 seconds.'}
    Start-Sleep -Seconds 2
}
kubectl --context $context -n vault wait --for=condition=Ready pod/vault-0 --timeout=300s
if($LASTEXITCODE-ne 0){throw 'Vault server did not become Ready.'}
kubectl --context $context -n vault rollout status deployment/vault-agent-injector --timeout=300s
if($LASTEXITCODE-ne 0){throw 'Vault Agent Injector did not become Ready.'}

Write-Host 'Vault DEV lab installed. Root token: root. Agent Injector: enabled.'
Write-Warning 'Vault dev mode is intentionally insecure and in-memory; use only in this disposable lab.'
