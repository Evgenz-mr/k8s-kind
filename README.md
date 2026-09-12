# k8s-kind

Lightweight local Kubernetes lab for Windows/DevOps experiments using [Kind](https://kind.sigs.k8s.io/).

Kind runs Kubernetes nodes as Docker containers, so it is much faster to create and destroy than a VM-based lab.

## Requirements

Install and start:

- Docker Desktop (or another Docker-compatible container runtime supported by Kind)
- Kind
- kubectl
- PowerShell

Verify:

```powershell
docker version
kind version
kubectl version --client
```

## Quick start — dynamic cluster

Clone the repository:

```powershell
git clone https://github.com/Evgenz-mr/k8s-kind.git
cd k8s-kind
```

Create one control-plane and two workers:

```powershell
.\scripts\create.ps1 -Workers 2
```

Create a larger cluster:

```powershell
.\scripts\create.ps1 -Workers 4 -Name devops-lab
```

The script generates the Kind YAML automatically, creates the cluster, selects its kubeconfig context and prints the nodes.

## Static examples

Single-node cluster:

```powershell
kind create cluster --config .\kind\single-node.yaml
```

Fixed three-node cluster:

```powershell
kind create cluster --config .\kind\multi-node.yaml
```

## Inspect the cluster

```powershell
.\scripts\status.ps1
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

For a named cluster:

```powershell
.\scripts\status.ps1 -Name devops-lab
```

## Example: deploy nginx

```powershell
kubectl apply -f .\examples\nginx\deployment.yaml
kubectl get deployment,pods,service
```

Scale it:

```powershell
kubectl scale deployment nginx --replicas=4
kubectl get pods -o wide
```

Inspect logs:

```powershell
kubectl logs deployment/nginx
```

Test the service without installing an ingress controller:

```powershell
kubectl port-forward service/nginx 8080:80
```

Then open `http://localhost:8080`.

Delete the example:

```powershell
kubectl delete -f .\examples\nginx\deployment.yaml
```

## Example: ConfigMap

```powershell
kubectl apply -f .\examples\configmap\app.yaml
kubectl logs configmap-demo
kubectl get configmap demo-config -o yaml
kubectl delete -f .\examples\configmap\app.yaml
```

## Useful kubectl commands

```powershell
kubectl get nodes
kubectl get pods -A
kubectl get pods -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl logs -f <pod-name>
kubectl exec -it <pod-name> -- sh
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl rollout status deployment/nginx
kubectl rollout restart deployment/nginx
```

## Delete the cluster

Default cluster:

```powershell
.\scripts\destroy.ps1
```

Named cluster:

```powershell
.\scripts\destroy.ps1 -Name devops-lab
```

Kind removes only the selected Kind cluster; it does not touch unrelated VirtualBox VMs.

## Repository structure

```text
k8s-kind/
├── kind/
│   ├── single-node.yaml
│   └── multi-node.yaml
├── scripts/
│   ├── create.ps1
│   ├── destroy.ps1
│   └── status.ps1
├── examples/
│   ├── nginx/
│   │   └── deployment.yaml
│   └── configmap/
│       └── app.yaml
├── .gitignore
└── README.md
```

## Why this lab exists

This repository is intended for fast Kubernetes and AI/DevOps-agent experiments: deployments, services, Helm charts, troubleshooting, logs, scaling, manifests and automation. Use the separate Vagrant lab when experiments require full Linux VMs, kubeadm or node-level operating-system administration.
