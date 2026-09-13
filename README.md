# k8s-kind

Lightweight local Kubernetes lab for Windows/DevOps experiments using Kind.

Kind runs Kubernetes nodes as Docker containers, so clusters are quick to create and destroy.

## Requirements

- Docker Desktop / compatible Docker runtime
- Kind
- kubectl
- Helm
- PowerShell

```powershell
docker version
docker info
kind version
kubectl version --client
helm version
```

On Windows, if PowerShell blocks local scripts, enable execution only for the current PowerShell process:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Make sure Docker Desktop is fully started and `docker info` returns both Client and Server information before creating the cluster.

## Create a basic cluster

```powershell
git clone https://github.com/Evgenz-mr/k8s-kind.git
cd k8s-kind
.\scripts\create.ps1 -Workers 2
```

The default installation creates a Kind cluster with two workers, NGINX Ingress and Headlamp.

Dynamic worker count / custom cluster name:

```powershell
.\scripts\create.ps1 -Workers 4 -Name devops-lab
```

## Create the full DevOps lab in one command

For a fresh cluster, the complete local stack can be requested directly from `create.ps1`:

```powershell
.\scripts\create.ps1 `
  -Workers 2 `
  -Ingress nginx `
  -Dashboard headlamp `
  -ArgoCD enabled `
  -CertManager enabled `
  -Metrics enabled `
  -Monitoring enabled `
  -Vault enabled `
  -Logging loki `
  -Postgres enabled `
  -MongoDB enabled `
  -Redis enabled `
  -Kafka enabled `
  -MinIO enabled `
  -Kyverno enabled
```

Available optional components include:

- Argo CD
- cert-manager
- metrics-server
- Prometheus + Grafana
- Loki + Grafana Alloy
- HashiCorp Vault + Agent Injector
- PostgreSQL
- MongoDB
- Redis
- Kafka
- MinIO
- Kyverno
- Cilium (`-Network cilium`)

Do not rerun `create.ps1` against an existing cluster with the same name. Use the component installers below instead.

## Add components to an existing cluster

For an already-created `ai-k8s` cluster, install components independently:

```powershell
# cert-manager
.\scripts\install-cert-manager.ps1 -Cluster ai-k8s

# metrics-server
.\scripts\install-metrics.ps1 -Cluster ai-k8s

# Prometheus + Grafana
.\scripts\install-monitoring.ps1 -Cluster ai-k8s -Ingress nginx

# Loki + Grafana Alloy
.\scripts\install-logging.ps1 -Cluster ai-k8s

# Vault + Agent Injector
.\scripts\install-vault.ps1 -Cluster ai-k8s

# PostgreSQL + MongoDB
.\scripts\install-databases.ps1 -Cluster ai-k8s -Postgres enabled -MongoDB enabled

# Redis + Kafka + MinIO + Kyverno
.\scripts\install-extras.ps1 -Cluster ai-k8s -Redis enabled -Kafka enabled -MinIO enabled -Kyverno enabled

# Argo CD
.\scripts\install-argocd.ps1 -Cluster ai-k8s -Ingress nginx
```

For first-time Windows validation, installing these sequentially is recommended so a component-specific failure is immediately visible.

After installation:

```powershell
.\scripts\smoke-test.ps1 -Cluster ai-k8s
kubectl --context kind-ai-k8s get pods -A
```

A successful base smoke test ends with:

```text
ALL SMOKE TESTS PASSED.
```

## Headlamp dashboard

Headlamp is installed by default. To install or reconcile it on an existing cluster:

```powershell
.\scripts\install-dashboard.ps1 -Dashboard headlamp -Ingress nginx -Cluster ai-k8s
```

Check its Ingress:

```powershell
kubectl --context kind-ai-k8s -n headlamp get ingress
```

With the default Kind host port mapping and NGINX configuration, Headlamp is exposed at `http://dashboard.localhost:8080`.

The dashboard installer prints a Kubernetes login token. The `headlamp-admin` account has cluster-admin rights and is intended only for this disposable local lab.

## Choose an Ingress Controller

The lab supports either NGINX Ingress or HAProxy Kubernetes Ingress. Install only the controller you want.

NGINX:

```powershell
.\scripts\install-ingress.ps1 -Controller nginx -Cluster ai-k8s
```

HAProxy:

```powershell
.\scripts\install-ingress.ps1 -Controller haproxy -Cluster ai-k8s
```

Check the controller:

```powershell
kubectl --context kind-ai-k8s get pods -n ingress-nginx
kubectl --context kind-ai-k8s get ingressclass
```

NGINX is scheduled on the Kind control-plane node so its host ports connect to Kind's host mappings: HTTP `localhost:8080`, HTTPS `localhost:8443`.

## Ingress demo application

Deploy a two-replica web application, ClusterIP Service and Ingress:

```powershell
kubectl apply -f .\ingress\demo-app.yaml
kubectl get deployment,pods,service,ingress
```

Inspect routing with:

```powershell
kubectl get svc -A
kubectl get ingress web-demo -o wide
```

## Inspect cluster

```powershell
.\scripts\status.ps1
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

Named cluster:

```powershell
.\scripts\status.ps1 -Name devops-lab
```

## Windows troubleshooting

Docker installed but daemon unavailable:

```powershell
docker context ls
docker info
```

If an NGINX controller remains Pending:

```powershell
kubectl --context kind-ai-k8s -n ingress-nginx get pods
kubectl --context kind-ai-k8s -n ingress-nginx describe pod <pod-name>
```

For general Kubernetes diagnostics:

```powershell
kubectl --context kind-ai-k8s get pods -A -o wide
kubectl --context kind-ai-k8s get events -A --sort-by=.metadata.creationTimestamp
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl logs -f <pod-name>
kubectl exec -it <pod-name> -- sh
```

## Delete cluster

```powershell
.\scripts\destroy.ps1
```

or:

```powershell
.\scripts\destroy.ps1 -Name devops-lab
```

## Purpose

This lab is intended for fast Kubernetes and AI/DevOps-agent experiments: deployments, services, Ingress, Helm, GitOps/Argo CD, observability, logging, Vault, databases, troubleshooting, scaling and automation. Use the separate Vagrant lab when full Linux VMs, kubeadm or node-level OS administration are required.
