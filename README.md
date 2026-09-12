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
kind version
kubectl version --client
helm version
```

## Create cluster

```powershell
git clone https://github.com/Evgenz-mr/k8s-kind.git
cd k8s-kind
.\scripts\create.ps1 -Workers 2
```

Dynamic worker count:

```powershell
.\scripts\create.ps1 -Workers 4 -Name devops-lab
```

## Choose an Ingress Controller

The lab supports either NGINX Ingress or HAProxy Kubernetes Ingress. Install only the controller you want.

NGINX:

```powershell
.\scripts\install-ingress.ps1 -Controller nginx
```

HAProxy:

```powershell
.\scripts\install-ingress.ps1 -Controller haproxy
```

For another Kind cluster:

```powershell
.\scripts\install-ingress.ps1 -Controller nginx -Cluster devops-lab
```

Check the controller:

```powershell
kubectl get pods -A
kubectl get ingressclass
```

## Ingress demo application

Deploy a two-replica web application, ClusterIP Service and Ingress:

```powershell
kubectl apply -f .\ingress\demo-app.yaml
kubectl get deployment,pods,service,ingress
```

The example uses host `demo.local`. How traffic is exposed from the Kind network to the Windows host depends on the controller/service configuration; inspect it with:

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

## Useful troubleshooting

```powershell
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.metadata.creationTimestamp
kubectl describe ingress web-demo
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

## Repository structure

```text
k8s-kind/
├── kind/
│   ├── single-node.yaml
│   └── multi-node.yaml
├── scripts/
│   ├── create.ps1
│   ├── destroy.ps1
│   ├── status.ps1
│   └── install-ingress.ps1
├── ingress/
│   └── demo-app.yaml
├── .gitignore
└── README.md
```

## Purpose

This lab is intended for fast Kubernetes and AI/DevOps-agent experiments: deployments, services, Ingress, Helm, troubleshooting, logs, scaling and automation. Use the separate Vagrant lab when full Linux VMs, kubeadm or node-level OS administration are required.
