# Kuber Console + Keycloak on an existing Kind cluster

This installs only the Kuber-branded Kubernetes console and a local Keycloak OIDC provider. It does not deploy the ARGUS application and does not delete or recreate the Kind cluster. Keycloak and the console live in the isolated `kuber-system` namespace; a sample namespace-admin binding is limited to `kuber-e2e`. The API server is configured for OIDC, so Kubernetes must be 1.34 or newer.

## Prerequisites

Docker Desktop, Kind, kubectl, Helm, OpenSSL, and Mike Farah yq v4 must be on PATH. The script expects the target cluster's current kubectl context to match its Kind name (for example, `kind-ai-k8s`). Local ports 9000 and 9443 must be free. Keep the existing cluster; if the Kubernetes version is older than 1.34, stop and plan a separate test cluster rather than recreating it in place.

Check the cluster and version first:

```powershell
kind get clusters
kubectl config current-context
kubectl --context kind-ai-k8s version
```

## Deploy

From the `k8s-kind` repository root, replace `ai-k8s` with the cluster name from `kind get clusters`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\deploy-kuber-console.ps1 -Cluster ai-k8s
```

The script applies Keycloak and the dashboard in `kuber-system`, creates `kuber-e2e` for an isolated RBAC test, creates local-only generated certificates and secrets under the ignored `generated\kuber-console` directory, patches the existing Kind control-plane static Pod manifest after saving a backup inside that node container, opens local-only port-forwards, and runs health and RBAC checks. It never runs `kind delete cluster`.

Add this hosts entry from an elevated editor:

```text
127.0.0.1 keycloak.kuber.local
```

Trust the generated CA from elevated PowerShell if the browser reports an untrusted certificate:

```powershell
certutil -addstore -f Root .\generated\kuber-console\ca.crt
```

Open `https://keycloak.kuber.local:9443`, sign into the Keycloak admin account using the password in `generated\kuber-console\keycloak-admin.txt`, and create users in realm `kuber`. Add cluster administrators only to `kuber-cluster-admins`; add namespace administrators only to `kuber-namespace-admins`. The console account flow uses OIDC authorization code; no password is saved by Kuber.

Open the dashboard at `http://localhost:9000`, select login, and test each role with a separate user. Run the automated checks again with:

```powershell
.\scripts\test-kuber-console.ps1 -Cluster ai-k8s
```

Expected RBAC: namespace admin can read pods in `kuber-e2e`, cannot delete namespaces, and cluster admin can read nodes. The namespace-admin group has no RoleBinding in `kuber-system`, so it cannot read Keycloak credentials there. Browser authentication should also be verified manually with both test users.

## Rollback

To restore the original API server manifest, first keep the cluster available and run:

```powershell
docker exec ai-k8s-control-plane sh -c "cp /etc/kubernetes/manifests/kube-apiserver.yaml.kuber-backup /etc/kubernetes/manifests/kube-apiserver.yaml"
```

Wait for `kubectl --context kind-ai-k8s get nodes` to recover, then remove only the Kuber release and Keycloak workload if desired:

```powershell
helm uninstall kuber-console --kube-context kind-ai-k8s -n kuber-system
kubectl --context kind-ai-k8s -n kuber-system delete deployment kuber-keycloak
```

Do not delete namespaces as part of cleanup if they contain anything else. Generated CA keys and passwords are local secrets: do not commit or share the generated directory. Keycloak storage is ephemeral in this local test setup.
