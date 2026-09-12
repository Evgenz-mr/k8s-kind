# AI Creative GitOps

This folder connects the portfolio application repositories to the local Kind/Argo CD lab.

## Repositories

- `Evgenz-mr/ai-creative-backend` — Spring Boot API and Helm chart.
- `Evgenz-mr/ai-creative-frontend` — Next.js UI and Helm chart.

Both Argo CD Applications track `main` and render the `helm/` directory from each repository.

## Flow

`Git -> GitHub Actions -> GHCR -> Argo CD -> Kubernetes -> Ingress -> frontend -> backend`

## Bootstrap

Create the lab with Argo CD enabled, then apply the applications:

### Windows

```powershell
./scripts/create.ps1 -ArgoCD enabled
./scripts/deploy-ai-creative.ps1
```

### Linux/macOS

Create/install the lab with Argo CD, then run:

```bash
./scripts/deploy-ai-creative.sh
```

Add these local hostnames to your hosts file if your lab setup does not already manage them:

```text
127.0.0.1 ai-creative.local
127.0.0.1 argocd.local
```

## Container registry

The application charts use:

- `ghcr.io/evgenz-mr/ai-creative-backend:latest`
- `ghcr.io/evgenz-mr/ai-creative-frontend:latest`

For the simplest local lab flow, make both GHCR packages public after the first successful publish. If you keep the packages private, create a Kubernetes registry pull secret and set `imagePullSecrets` in the application Helm values.

## Expected result

Argo CD should show both applications as `Synced` and `Healthy`. The site is available at `http://ai-creative.local`; the frontend calls `http://ai-creative-backend:8080` inside the `ai-creative` namespace.
