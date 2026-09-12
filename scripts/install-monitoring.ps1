param([ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s',[ValidateSet('nginx','haproxy')][string]$Ingress='nginx')
$ErrorActionPreference='Stop';$context="kind-$Cluster"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update;helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --kube-context $context -n monitoring --create-namespace `
 --set grafana.adminUser=admin --set grafana.adminPassword=admin `
 --set grafana.sidecar.datasources.enabled=true
if($LASTEXITCODE-ne 0){throw 'Monitoring installation failed.'}
kubectl --context $context -n monitoring rollout status deployment/monitoring-grafana --timeout=300s
$class=if($Ingress-eq'nginx'){'nginx'}else{'haproxy'}
@"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
spec:
  ingressClassName: $class
  rules:
  - host: grafana.localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: monitoring-grafana
            port:
              number: 80
"@|kubectl --context $context apply -f -
Write-Host 'Grafana: http://grafana.localhost:8080 (admin/admin). Prometheus is available inside the cluster.'
