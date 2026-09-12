param([ValidateSet('headlamp','none')][string]$Dashboard='headlamp',[ValidateSet('nginx','haproxy')][string]$Ingress='nginx',[ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s',[string]$Username='admin',[string]$Password='admin')
$ErrorActionPreference='Stop';if($Dashboard-eq'none'){return};$ctx="kind-$Cluster"
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ --force-update;helm repo update
helm upgrade --install headlamp headlamp/headlamp --kube-context $ctx -n headlamp --create-namespace;if($LASTEXITCODE-ne 0){throw 'Headlamp installation failed.'};kubectl --context $ctx -n headlamp rollout status deployment/headlamp --timeout=240s
kubectl --context $ctx -n headlamp create serviceaccount headlamp-admin --dry-run=client -o yaml|kubectl --context $ctx apply -f -
kubectl --context $ctx create clusterrolebinding headlamp-admin --clusterrole=cluster-admin --serviceaccount=headlamp:headlamp-admin --dry-run=client -o yaml|kubectl --context $ctx apply -f -
$class=if($Ingress-eq'nginx'){'nginx'}else{'haproxy'}
@"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: headlamp, namespace: headlamp}
spec:
  ingressClassName: $class
  rules:
    - host: dashboard.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: {name: headlamp, port: {number: 80}}
"@|kubectl --context $ctx apply -f -
$token=kubectl --context $ctx -n headlamp create token headlamp-admin --duration=24h
Write-Host 'Headlamp: http://dashboard.localhost:8080';Write-Host 'Paste this Kubernetes token into Headlamp:';Write-Host $token
Write-Warning 'headlamp-admin has cluster-admin rights and is only for this disposable local lab.'
