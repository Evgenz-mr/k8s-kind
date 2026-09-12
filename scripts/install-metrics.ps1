param([ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s')
$ErrorActionPreference='Stop'; $context="kind-$Cluster"
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm repo update
helm upgrade --install metrics-server metrics-server/metrics-server --kube-context $context --namespace kube-system --set args[0]=--kubelet-insecure-tls
if($LASTEXITCODE-ne 0){throw 'metrics-server installation failed.'}
kubectl --context $context -n kube-system rollout status deployment/metrics-server --timeout=180s
Write-Host 'metrics-server installed. kubectl top nodes/pods will become available shortly.'
