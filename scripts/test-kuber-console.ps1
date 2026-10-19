[CmdletBinding()]
param([ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s')
$ErrorActionPreference='Stop'
$Context="kind-$Cluster"
$SystemNamespace='kuber-system'
$TargetNamespace='kuber-e2e'
$Generated=Join-Path (Split-Path $PSScriptRoot -Parent) 'generated\kuber-console'
$ca=Join-Path $Generated 'ca.crt'
foreach($cmd in @('kubectl','curl.exe')){if(-not(Get-Command $cmd -ErrorAction SilentlyContinue)){throw "Required command '$cmd' was not found in PATH."}}
if(-not(Test-Path $ca)){throw "CA certificate not found: $ca. Run scripts\deploy-kuber-console.ps1 first."}

Write-Host '[1/7] API and node health'
kubectl --context $Context get nodes
if($LASTEXITCODE -ne 0){throw 'Kubernetes API is not responding.'}

Write-Host '[2/7] Keycloak and Console rollout'
kubectl --context $Context -n $SystemNamespace rollout status deployment/kuber-keycloak --timeout=60s
if($LASTEXITCODE -ne 0){throw 'Keycloak is not ready.'}
kubectl --context $Context -n $SystemNamespace rollout status deployment/kuber-console --timeout=60s
if($LASTEXITCODE -ne 0){throw 'Kuber Console is not ready.'}

Write-Host '[3/7] OIDC session cookie keys'
$sessionSecret=kubectl --context $Context -n $SystemNamespace get secret kuber-console-session -o json | ConvertFrom-Json
if($LASTEXITCODE -ne 0 -or -not $sessionSecret.data.'cookie-encryption-key' -or -not $sessionSecret.data.'cookie-authentication-key'){throw 'Kuber Console session key Secret is missing or incomplete.'}
$encryptionKeyLength=[Convert]::FromBase64String($sessionSecret.data.'cookie-encryption-key').Length
$authenticationKeyLength=[Convert]::FromBase64String($sessionSecret.data.'cookie-authentication-key').Length
if($encryptionKeyLength -ne 32 -or $authenticationKeyLength -ne 64){throw "Invalid Console session key lengths: encryption=$encryptionKeyLength (expected 32), authentication=$authenticationKeyLength (expected 64)."}
$consoleDeployment=kubectl --context $Context -n $SystemNamespace get deployment kuber-console -o json | ConvertFrom-Json
$consoleArgs=$consoleDeployment.spec.template.spec.containers | Where-Object {$_.name -eq 'console'} | Select-Object -ExpandProperty args
if($consoleArgs -notcontains '--public-dir=/opt/bridge/static'){throw 'Console deployment is missing the static asset directory flag.'}
if($consoleArgs -notcontains '--cookie-encryption-key-file=/var/run/kuber-session/cookie-encryption-key' -or $consoleArgs -notcontains '--cookie-authentication-key-file=/var/run/kuber-session/cookie-authentication-key'){throw 'Console deployment is missing required OIDC cookie key flags.'}

Write-Host '[4/7] OIDC discovery issuer and TLS'
$discovery=curl.exe --ssl-no-revoke --fail --silent --show-error --cacert $ca --resolve keycloak.kuber.local:9443:127.0.0.1 https://keycloak.kuber.local:9443/realms/kuber/.well-known/openid-configuration | ConvertFrom-Json
if($LASTEXITCODE -ne 0 -or $discovery.issuer -ne 'https://keycloak.kuber.local:9443/realms/kuber'){throw "OIDC discovery mismatch: $($discovery.issuer)"}

Write-Host '[5/7] Dashboard HTTP endpoint'
curl.exe --fail --silent --show-error http://localhost:9000/ -o NUL
if($LASTEXITCODE -ne 0){throw 'Kuber Console is not reachable at http://localhost:9000.'}

Write-Host '[6/7] Namespace administrator boundary'
$read=(kubectl --context $Context auth can-i get pods -n $TargetNamespace --as=oidc:e2e-ns-admin --as-group=oidc:kuber-namespace-admins).Trim()
$delete=(kubectl --context $Context auth can-i delete namespaces --as=oidc:e2e-ns-admin --as-group=oidc:kuber-namespace-admins).Trim()
if($read -ne 'yes' -or $delete -ne 'no'){throw "Expected namespace admin get pods=yes and delete namespaces=no; got $read / $delete."}

Write-Host '[7/7] Cluster administrator boundary'
$nodes=(kubectl --context $Context auth can-i get nodes --as=oidc:e2e-cluster-admin --as-group=oidc:kuber-cluster-admins).Trim()
if($nodes -ne 'yes'){throw "Expected cluster admin get nodes=yes; got $nodes."}
Write-Host 'ALL KUBER CONSOLE E2E SMOKE CHECKS PASSED.'
Write-Host 'Browser login itself is a manual check: open http://localhost:9000 and authenticate with a Keycloak user.'
