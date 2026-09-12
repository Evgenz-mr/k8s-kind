param([ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s')
$ErrorActionPreference='Stop'; $context="kind-$Cluster"
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update
helm repo update
helm upgrade --install vault hashicorp/vault --kube-context $context --namespace vault --create-namespace --set server.dev.enabled=true --set server.dev.devRootToken=root --set injector.enabled=true --set injector.metrics.enabled=true
if($LASTEXITCODE-ne 0){throw 'Vault installation failed.'}
kubectl --context $context -n vault rollout status deployment/vault-agent-injector --timeout=240s
kubectl --context $context -n vault wait --for=condition=Ready pod/vault-0 --timeout=240s
Write-Host 'Vault DEV lab installed. Root token: root. Agent Injector: enabled.'
Write-Warning 'Vault dev mode is intentionally insecure and in-memory; use only in this disposable lab.'
