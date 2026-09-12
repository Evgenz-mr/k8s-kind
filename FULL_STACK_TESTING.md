# Full-stack E2E acceptance

This branch expands CI from core data services to the platform layer.

Required green checks before merge:

- `e2e / core`: NGINX, metrics-server, PostgreSQL, MongoDB, Redis, Kafka and MinIO.
- `e2e / cilium`: Cilium cluster and pod-to-service networking.
- `e2e / full-stack`: NGINX, cert-manager, metrics-server, Prometheus/Grafana, Loki, Vault, Headlamp, Argo CD and Kyverno.
- `networkpolicy-e2e / cilium-networkpolicy`: Cilium enforces allow/deny NetworkPolicy behavior.
- `vault-e2e / vault-injector`: Vault Kubernetes auth and Agent Injector place a KV secret in an application pod.
- `windows-e2e / powershell-syntax`: all PowerShell scripts parse and the Windows launcher exposes the expected component switches.

Linux runtime is validated on GitHub-hosted Ubuntu runners. Windows CI validates PowerShell compatibility; the final Docker Desktop/Kind runtime test should also be run on the target Windows workstation because GitHub-hosted Windows runners do not provide the same Docker Desktop environment.
