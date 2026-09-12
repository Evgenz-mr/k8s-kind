param([ValidateSet('nginx','haproxy')][string]$Controller='nginx',[ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s')
$ErrorActionPreference='Stop';$context="kind-$Cluster"
foreach($cmd in @('helm','kubectl')){if(-not(Get-Command $cmd -ErrorAction SilentlyContinue)){throw "Required command '$cmd' was not found in PATH."}}
kubectl --context $context get nodes *> $null;if($LASTEXITCODE-ne 0){throw "Kind cluster '$Cluster' is not available."}
kubectl --context $context label node "$Cluster-control-plane" ingress-ready=true --overwrite | Out-Null
if($Controller-eq'nginx'){
 helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update;helm repo update
 helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --kube-context $context -n ingress-nginx --create-namespace `
  --set controller.service.type=ClusterIP `
  --set controller.hostPort.enabled=true `
  --set-string 'controller.nodeSelector.ingress-ready=true'
 if($LASTEXITCODE-ne 0){throw 'NGINX Ingress installation failed.'}
 kubectl --context $context -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=240s
}else{
 helm repo add haproxytech https://haproxytech.github.io/helm-charts --force-update;helm repo update
 helm upgrade --install haproxy-kubernetes-ingress haproxytech/kubernetes-ingress --kube-context $context -n haproxy-controller --create-namespace `
  --set controller.hostNetwork=true `
  --set-string 'controller.nodeSelector.ingress-ready=true'
 if($LASTEXITCODE-ne 0){throw 'HAProxy Ingress installation failed.'}
 kubectl --context $context -n haproxy-controller rollout status deployment/haproxy-kubernetes-ingress --timeout=240s
}
Write-Host "Ingress '$Controller' ready. Kind host mappings expose HTTP on localhost:8080 and HTTPS on localhost:8443."
