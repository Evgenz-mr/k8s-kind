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

## Create the full DevOps lab in one command

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

Available optional components: Argo CD, cert-manager, metrics-server, Prometheus/Grafana, Loki/Alloy, Vault/Agent Injector, PostgreSQL, MongoDB, Redis, Kafka, MinIO, Kyverno and Cilium (`-Network cilium`).

## Deploy AI Creative frontend + backend locally

The application consists of two repositories:

- `Evgenz-mr/ai-creative-backend`
- `Evgenz-mr/ai-creative-frontend`

For local Kind development no external container registry is required. The deployment script builds both Docker images locally, loads them into the Kind nodes, creates/reconciles the `ai-creative` namespace, deploys both Helm charts, waits for both Deployments and prints the resulting Kubernetes resources.

Recommended directory layout:

```text
C:\Users\<user>\k8s-kind
C:\Users\<user>\ai-creative-backend
C:\Users\<user>\ai-creative-frontend
```

Clone the application repositories once:

```powershell
cd C:\Users\<user>
git clone https://github.com/Evgenz-mr/ai-creative-backend.git
git clone https://github.com/Evgenz-mr/ai-creative-frontend.git
```

Then the complete application deployment is one command from `k8s-kind`:

```powershell
.\scripts\deploy-ai-creative.ps1 -Cluster ai-k8s
```

The script performs:

```text
docker build backend
docker build frontend
kind load docker-image backend
kind load docker-image frontend
kubectl create/apply namespace
helm upgrade --install backend
helm upgrade --install frontend
kubectl rollout status backend/frontend
```

It also tries to add this Windows hosts entry automatically:

```text
127.0.0.1 ai-creative.local
```

Updating the hosts file requires an elevated PowerShell. If the script cannot update it, it prints a warning; run PowerShell as Administrator or add the entry manually.

Open the site at:

```text
http://ai-creative.local:8080
```

Backend ingress:

```text
http://ai-creative.local:8080/api
```

Verify deployment:

```powershell
kubectl --context kind-ai-k8s get pods -n ai-creative
kubectl --context kind-ai-k8s get svc -n ai-creative
kubectl --context kind-ai-k8s get ingress -n ai-creative
```

After changing backend or frontend source code, simply run the same deployment command again. Images are rebuilt/reloaded and Helm reconciles the releases:

```powershell
.\scripts\deploy-ai-creative.ps1 -Cluster ai-k8s
```

Custom source directories are supported:

```powershell
.\scripts\deploy-ai-creative.ps1 `
  -Cluster ai-k8s `
  -BackendPath C:\work\ai-creative-backend `
  -FrontendPath C:\work\ai-creative-frontend
```

## Add components to an existing cluster

```powershell
.\scripts\install-cert-manager.ps1 -Cluster ai-k8s
.\scripts\install-metrics.ps1 -Cluster ai-k8s
.\scripts\install-monitoring.ps1 -Cluster ai-k8s -Ingress nginx
.\scripts\install-logging.ps1 -Cluster ai-k8s
.\scripts\install-vault.ps1 -Cluster ai-k8s
.\scripts\install-databases.ps1 -Cluster ai-k8s -Postgres enabled -MongoDB enabled
.\scripts\install-extras.ps1 -Cluster ai-k8s -Redis enabled -Kafka enabled -MinIO enabled -Kyverno enabled
.\scripts\install-argocd.ps1 -Cluster ai-k8s -Ingress nginx
```

After installation:

```powershell
.\scripts\smoke-test.ps1 -Cluster ai-k8s
kubectl --context kind-ai-k8s get pods -A
```

A successful base smoke test ends with `ALL SMOKE TESTS PASSED.`

## Headlamp dashboard

```powershell
.\scripts\install-dashboard.ps1 -Dashboard headlamp -Ingress nginx -Cluster ai-k8s
```

With the default Kind host port mapping and NGINX configuration, Headlamp is exposed at `http://dashboard.localhost:8080`.

The dashboard installer prints a Kubernetes login token. The `headlamp-admin` account has cluster-admin rights and is intended only for this disposable local lab.

## Choose an Ingress Controller

NGINX:

```powershell
.\scripts\install-ingress.ps1 -Controller nginx -Cluster ai-k8s
```

HAProxy:

```powershell
.\scripts\install-ingress.ps1 -Controller haproxy -Cluster ai-k8s
```

NGINX is scheduled on the Kind control-plane node so its host ports connect to Kind's host mappings: HTTP `localhost:8080`, HTTPS `localhost:8443`.

## Inspect cluster

```powershell
.\scripts\status.ps1
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

## Windows troubleshooting

Docker installed but daemon unavailable:

```powershell
docker context ls
docker info
```

General Kubernetes diagnostics:

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

or for another cluster name:

```powershell
.\scripts\destroy.ps1 -Name devops-lab
```

## Purpose

This lab is intended for fast Kubernetes and AI/DevOps-agent experiments: deployments, services, Ingress, Helm, GitOps/Argo CD, observability, logging, Vault, databases, troubleshooting, scaling and automation. Use the separate Vagrant lab when full Linux VMs, kubeadm or node-level OS administration are required.
