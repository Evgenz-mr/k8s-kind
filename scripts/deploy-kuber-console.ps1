[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9-]+$')][string]$Cluster = 'ai-k8s'
)

$ErrorActionPreference = 'Stop'
$Context = "kind-$Cluster"
$Root = Split-Path $PSScriptRoot -Parent
$AppRoot = Join-Path $Root 'apps\kuber-console'
$Generated = Join-Path $Root 'generated\kuber-console'
$SystemNamespace = 'kuber-system'
$TargetNamespace = 'kuber-e2e'
$Node = "$Cluster-control-plane"
$ExternalIssuer = 'https://keycloak.kuber.local:9443/realms/kuber'
$authFlag = '--authentication-config=/etc/kubernetes/kuber-authentication.yaml'

function Invoke-Native {
    param([scriptblock]$Command, [string]$ErrorMessage)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $ErrorMessage }
}

foreach ($cmd in @('docker','kind','kubectl','helm','openssl','yq','curl.exe')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Required command '$cmd' was not found in PATH." }
}
if (-not ((kind get clusters) -contains $Cluster)) { throw "Kind cluster '$Cluster' does not exist. Existing clusters will not be deleted or recreated." }
$CurrentContext = (kubectl config current-context).Trim()
if ($CurrentContext -ne $Context) { throw "Current kubectl context is '$CurrentContext', expected '$Context'. Run: kubectl config use-context $Context; then retry." }
$existingApiManifest = docker exec $Node cat /etc/kubernetes/manifests/kube-apiserver.yaml
if ($LASTEXITCODE -ne 0) { throw "Could not inspect the existing kube-apiserver manifest in $Node." }
$existingAuthConfig = $existingApiManifest | Select-String -Pattern '--authentication-config='
if ($existingAuthConfig -and -not ($existingAuthConfig.Line -match [regex]::Escape($authFlag))) {
    throw 'The existing kube-apiserver already has a different --authentication-config flag. No Kubernetes resources have been changed.'
}

$version = kubectl --context $Context version -o json | ConvertFrom-Json
$minor = [int]($version.serverVersion.minor -replace '\D','')
if ([int]$version.serverVersion.major -lt 1 -or $minor -lt 34) {
    throw "Kubernetes 1.34+ is required for structured OIDC AuthenticationConfiguration; found $($version.serverVersion.gitVersion). This script will not recreate the cluster."
}

foreach ($port in @(9443,9000)) {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    try { $listener.Start() } catch { throw "Local port $port is busy. Stop its current listener before deploying Kuber Console." } finally { $listener.Stop() }
}

$yqVersion = (& yq --version)
if ($yqVersion -notmatch 'version v?4\.') { throw "Mike Farah yq v4 is required; found: $yqVersion" }
if (-not (Test-Path (Join-Path $AppRoot 'Chart.yaml'))) { throw "Kuber Console chart not found at $AppRoot" }
New-Item -ItemType Directory -Force -Path $Generated | Out-Null

Write-Host "[1/8] Checking existing Kind cluster '$Cluster' and Kubernetes $($version.serverVersion.gitVersion)..."
Invoke-Native { cmd.exe /c 'docker info >NUL 2>&1' } 'Docker engine is unavailable.'

Write-Host '[2/8] Reserving the Keycloak Service address...'
Invoke-Native { kubectl --context $Context apply -f (Join-Path $AppRoot 'oidc\keycloak-service.yaml') } 'Could not create the Keycloak namespace and Service.'
$targetNamespaceYaml = kubectl --context $Context create namespace $TargetNamespace --dry-run=client -o yaml
Invoke-Native { $targetNamespaceYaml | kubectl --context $Context apply -f - } 'Could not create the isolated namespace-admin test namespace.'
$serviceIp = ''
for ($i = 0; $i -lt 30 -and -not $serviceIp; $i++) {
    $service = kubectl --context $Context -n $SystemNamespace get service keycloak -o json | ConvertFrom-Json
    $serviceIp = $service.spec.clusterIP
    if (-not $serviceIp) { Start-Sleep -Seconds 2 }
}
if (-not $serviceIp -or $serviceIp -eq 'None') { throw 'Keycloak Service did not receive a ClusterIP.' }

Write-Host '[3/8] Creating local TLS CA, Keycloak certificate, realm and Secrets...'
$caKey = Join-Path $Generated 'ca.key'
$caCrt = Join-Path $Generated 'ca.crt'
$serverKey = Join-Path $Generated 'tls.key'
$serverCrt = Join-Path $Generated 'tls.crt'
$config = Join-Path $Generated 'openssl.cnf'
$csr = Join-Path $Generated 'tls.csr'
$caConfig = Join-Path $Generated 'ca-openssl.cnf'
$rotateCa = $false
if ((Test-Path $caCrt) -and (Test-Path $caKey)) {
    $constraints = @(openssl x509 -in $caCrt -noout -ext basicConstraints 2>$null | Select-String 'CA:TRUE')
    if ($LASTEXITCODE -ne 0 -or $constraints.Count -ne 1) { $rotateCa = $true }
} else {
    $rotateCa = $true
}
if ($rotateCa) {
    @'
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_ca
[dn]
CN = Kuber local OIDC CA
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
'@ | Set-Content -Path $caConfig -Encoding ascii
    Invoke-Native { openssl req -x509 -newkey rsa:3072 -nodes -days 825 -keyout $caKey -out $caCrt -config $caConfig } 'Could not generate local OIDC CA.'
}
@"
[req]
distinguished_name = dn
req_extensions = req_ext
prompt = no
[dn]
CN = keycloak.kuber.local
[req_ext]
subjectAltName = @alt_names
[server_ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = keycloak.kuber.local
DNS.2 = keycloak.${SystemNamespace}.svc
DNS.3 = keycloak.${SystemNamespace}.svc.cluster.local
IP.1 = $serviceIp
"@ | Set-Content -Path $config -Encoding ascii
if ($rotateCa -or -not (Test-Path $serverKey) -or -not (Test-Path $serverCrt)) {
    Invoke-Native { openssl req -new -newkey rsa:3072 -nodes -keyout $serverKey -out $csr -subj '/CN=keycloak.kuber.local' -config $config } 'Could not generate Keycloak TLS key.'
    Invoke-Native { openssl x509 -req -in $csr -CA $caCrt -CAkey $caKey -CAcreateserial -out $serverCrt -days 397 -sha256 -extensions server_ext -extfile $config } 'Could not sign Keycloak TLS certificate.'
}
$caFingerprintOutput = (openssl x509 -in $caCrt -noout -fingerprint -sha256)
if ($LASTEXITCODE -ne 0 -or -not $caFingerprintOutput) { throw 'Could not calculate the OIDC CA fingerprint.' }
$caFingerprint = (($caFingerprintOutput -split '=', 2)[-1] -replace ':', '').Trim().ToLowerInvariant()
if ($caFingerprint -notmatch '^[0-9a-f]{64}$') { throw 'The OIDC CA fingerprint has an unexpected format.' }

$adminFile = Join-Path $Generated 'keycloak-admin.txt'
$clientSecretFile = Join-Path $Generated 'oidc-client-secret.txt'
if (-not (Test-Path $adminFile)) {
    $adminPassword = (openssl rand -base64 30).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $adminPassword) { throw 'Could not generate Keycloak administrator password.' }
    "username=kcadmin`npassword=$adminPassword" | Set-Content -Path $adminFile -Encoding ascii
    $adminPassword = $null
}
if (-not (Test-Path $clientSecretFile)) {
    $clientSecret = (openssl rand -hex 32).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $clientSecret) { throw 'Could not generate OIDC client secret.' }
    Set-Content -Path $clientSecretFile -Value $clientSecret -NoNewline -Encoding ascii
}
$cookieEncryptionKeyFile = Join-Path $Generated 'cookie-encryption-key.txt'
$cookieAuthenticationKeyFile = Join-Path $Generated 'cookie-authentication-key.txt'
$cookieEncryptionKey = if (Test-Path $cookieEncryptionKeyFile) { (Get-Content $cookieEncryptionKeyFile -Raw).Trim() } else { '' }
if ($cookieEncryptionKey -notmatch '^[0-9a-f]{32}$') {
    $cookieEncryptionKey = (openssl rand -hex 16).Trim()
    if ($LASTEXITCODE -ne 0 -or $cookieEncryptionKey -notmatch '^[0-9a-f]{32}$') { throw 'Could not generate a valid 32-character Console cookie encryption key.' }
    Set-Content -Path $cookieEncryptionKeyFile -Value $cookieEncryptionKey -NoNewline -Encoding ascii
}
$cookieAuthenticationKey = if (Test-Path $cookieAuthenticationKeyFile) { (Get-Content $cookieAuthenticationKeyFile -Raw).Trim() } else { '' }
if ($cookieAuthenticationKey -notmatch '^[0-9a-f]{64}$') {
    $cookieAuthenticationKey = (openssl rand -hex 32).Trim()
    if ($LASTEXITCODE -ne 0 -or $cookieAuthenticationKey -notmatch '^[0-9a-f]{64}$') { throw 'Could not generate a valid 64-character Console cookie authentication key.' }
    Set-Content -Path $cookieAuthenticationKeyFile -Value $cookieAuthenticationKey -NoNewline -Encoding ascii
}
$adminPassword = ((Get-Content $adminFile | Where-Object { $_ -like 'password=*' }) -replace '^password=','')
$clientSecret = (Get-Content $clientSecretFile -Raw).Trim()
$realmFile = Join-Path $Generated 'kuber-realm.json'
$realm = @{
    realm = 'kuber'; enabled = $true
    groups = @(@{ name = 'kuber-cluster-admins' }, @{ name = 'kuber-namespace-admins' })
    users = @(@{
        username = 'evgen'
        firstName = 'Evgen'
        lastName = 'Admin'
        email = 'evgen@kuber.local'
        enabled = $true
        emailVerified = $true
        credentials = @(@{
            type = 'password'
            value = 'evgen'
            temporary = $false
        })
        groups = @('/kuber-cluster-admins')
    })
    clients = @(@{
        clientId = 'kuber-console'; name = 'Kuber Console'; enabled = $true
        protocol = 'openid-connect'; publicClient = $false; secret = $clientSecret
        standardFlowEnabled = $true; directAccessGrantsEnabled = $false
        redirectUris = @('http://localhost:9000/auth/callback', 'http://localhost:9000/')
        webOrigins = @('http://localhost:9000')
        protocolMappers = @(@{
            name = 'groups'; protocol = 'openid-connect'; protocolMapper = 'oidc-group-membership-mapper'; consentRequired = $false
            config = @{ 'claim.name'='groups'; 'full.path'='false'; 'id.token.claim'='true'; 'access.token.claim'='true'; 'userinfo.token.claim'='true' }
        },@{
            name = 'full-name'; protocol = 'openid-connect'; protocolMapper = 'oidc-full-name-mapper'; consentRequired = $false
            config = @{ 'id.token.claim'='true'; 'access.token.claim'='true'; 'userinfo.token.claim'='true' }
        },@{
            name = 'kuber-console-audience'; protocol = 'openid-connect'; protocolMapper = 'oidc-audience-mapper'; consentRequired = $false
            config = @{ 'included.client.audience'='kuber-console'; 'id.token.claim'='true'; 'access.token.claim'='true' }
        })
    })
}
$realm | ConvertTo-Json -Depth 12 | Set-Content -Path $realmFile -Encoding ascii
Invoke-Native { kubectl --context $Context -n $SystemNamespace create secret tls kuber-keycloak-tls --cert=$serverCrt --key=$serverKey --dry-run=client -o yaml | kubectl --context $Context apply -f - } 'Could not apply Keycloak TLS Secret.'
Invoke-Native { kubectl --context $Context -n $SystemNamespace create secret generic kuber-keycloak-admin --from-literal=username=kcadmin --from-literal=password=$adminPassword --dry-run=client -o yaml | kubectl --context $Context apply -f - } 'Could not apply Keycloak administrator Secret.'
Invoke-Native { kubectl --context $Context -n $SystemNamespace create secret generic kuber-oidc-ca --from-file=ca.crt=$caCrt --dry-run=client -o yaml | kubectl --context $Context apply -f - } 'Could not apply OIDC CA Secret.'
Invoke-Native { kubectl --context $Context -n $SystemNamespace create secret generic kuber-oidc-client --from-literal=client-secret=$clientSecret --dry-run=client -o yaml | kubectl --context $Context apply -f - } 'Could not apply OIDC client Secret.'
Invoke-Native { kubectl --context $Context -n $SystemNamespace create secret generic kuber-console-session --from-file=cookie-encryption-key=$cookieEncryptionKeyFile --from-file=cookie-authentication-key=$cookieAuthenticationKeyFile --dry-run=client -o yaml | kubectl --context $Context apply -f - } 'Could not apply Console session key Secret.'
Invoke-Native { kubectl --context $Context -n $SystemNamespace create secret generic kuber-keycloak-realm --from-file=kuber-realm.json=$realmFile --dry-run=client -o yaml | kubectl --context $Context apply -f - } 'Could not apply Keycloak realm Secret.'
$adminPassword = $null; $clientSecret = $null; $cookieEncryptionKey = $null; $cookieAuthenticationKey = $null; $realm = $null
Invoke-Native { kubectl --context $Context apply -f (Join-Path $AppRoot 'oidc\keycloak-deployment.yaml') } 'Could not deploy Keycloak.'
# Realm import only runs when Keycloak starts with an empty local database. This test setup is ephemeral.
Invoke-Native { kubectl --context $Context -n $SystemNamespace rollout restart deployment/kuber-keycloak } 'Could not restart Keycloak to import the configured realm.'
Invoke-Native { kubectl --context $Context -n $SystemNamespace rollout status deployment/kuber-keycloak --timeout=5m } 'Keycloak did not become ready.'

Write-Host '[4/8] Preparing Kubernetes OIDC authentication configuration...'
$pem = (Get-Content $caCrt -Raw).TrimEnd() -split "`r?`n" | ForEach-Object { "        $_" }
$authConfig = Join-Path $Generated 'authentication.yaml'
$auth = @"
apiVersion: apiserver.config.k8s.io/v1
kind: AuthenticationConfiguration
jwt:
  - issuer:
      url: $ExternalIssuer
      discoveryURL: https://keycloak.${SystemNamespace}.svc:9443/realms/kuber/.well-known/openid-configuration
      certificateAuthority: |
$($pem -join "`n")
      audiences:
        - kuber-console
    claimMappings:
      username:
        claim: preferred_username
        prefix: "oidc:"
      groups:
        claim: groups
        prefix: "oidc:"
"@
Set-Content -Path $authConfig -Value $auth -Encoding ascii
Invoke-Native { docker cp $authConfig "${Node}:/etc/kubernetes/kuber-authentication.yaml" } 'Could not copy OIDC AuthenticationConfiguration into the control-plane node.'
$manifest = '/etc/kubernetes/manifests/kube-apiserver.yaml'
$backup = "$manifest.kuber-backup"
Invoke-Native { docker exec $Node sh -c "test -f $backup || cp $manifest $backup" } 'Could not back up the kube-apiserver static Pod manifest.'
$localManifest = Join-Path $Generated 'kube-apiserver.yaml'
Invoke-Native { docker cp "${Node}:$manifest" $localManifest } 'Could not read kube-apiserver static Pod manifest.'
if (-not (Select-String -Path $localManifest -SimpleMatch $authFlag -Quiet)) {
    $patchFile = Join-Path $Generated 'patch-apiserver.yq'
    $patch = @'
(.spec.containers[] | select(.name == "kube-apiserver") | .args) += ["--authentication-config=/etc/kubernetes/kuber-authentication.yaml"] |
.spec.volumes += [{"name":"kuber-authn","hostPath":{"path":"/etc/kubernetes/kuber-authentication.yaml","type":"File"}}] |
(.spec.containers[] | select(.name == "kube-apiserver") | .volumeMounts) += [{"name":"kuber-authn","mountPath":"/etc/kubernetes/kuber-authentication.yaml","readOnly":true}] |
.spec.hostAliases = ((.spec.hostAliases // []) + [{"ip":"SERVICE_IP","hostnames":["keycloak.kuber.local","keycloak.kuber-system.svc","keycloak.kuber-system.svc.cluster.local"]}])
'@
    $patch.Replace('SERVICE_IP', $serviceIp) | Set-Content -Path $patchFile -Encoding ascii
    $expression = Get-Content $patchFile -Raw
    Invoke-Native { yq eval --inplace --from-file $patchFile $localManifest } 'Could not patch kube-apiserver manifest for OIDC.'
    Invoke-Native { docker cp $localManifest "${Node}:$manifest" } 'Could not install the OIDC-enabled kube-apiserver manifest.'
}
if ($existingAuthConfig -and -not (Select-String -Path $localManifest -SimpleMatch $caFingerprint -Quiet)) {
    $rotationPatch = Join-Path $Generated 'patch-apiserver-ca-rotation.yq'
    '.metadata.annotations."kuber.local/oidc-ca-fingerprint" = "' + $caFingerprint + '"' | Set-Content -Path $rotationPatch -Encoding ascii
    Invoke-Native { yq eval --inplace --from-file $rotationPatch $localManifest } 'Could not mark kube-apiserver for OIDC CA rotation.'
    Invoke-Native { docker cp $localManifest "${Node}:$manifest" } 'Could not restart kube-apiserver after rotating the OIDC CA.'
}

$apiReady = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        kubectl --context $Context get nodes 2>$null *> $null
        if ($LASTEXITCODE -eq 0) { $apiReady = $true; break }
    } catch {
        # kubectl may briefly return EOF while the static kube-apiserver Pod restarts.
    }
    Start-Sleep -Seconds 3
}
if (-not $apiReady) { throw 'Kubernetes API did not recover after the OIDC configuration change. Inspect kube-apiserver logs before retrying.' }
Invoke-Native { kubectl --context $Context get nodes } 'Kubernetes API did not recover after the OIDC configuration change.'

Write-Host '[5/8] Installing the Kuber Console chart (dashboard only; no ARGUS application stack)...'
$valuesFile = Join-Path $Generated 'kuber-oidc-values.yaml'
@"
auth:
  issuerUrl: $ExternalIssuer
  issuerHostAlias: $serviceIp
rbac:
  namespace: $TargetNamespace
"@ | Set-Content -Path $valuesFile -Encoding utf8
Invoke-Native { helm upgrade --install kuber-console $AppRoot --kube-context $Context --namespace $SystemNamespace --create-namespace -f $valuesFile --wait --timeout 10m } 'Kuber Console Helm deployment failed.'
Invoke-Native { kubectl --context $Context -n $SystemNamespace rollout status deployment/kuber-console --timeout=180s } 'Kuber Console did not become ready.'

Write-Host '[6/8] Starting local-only port forwards for the login flow...'
$logKeycloak = Join-Path $Generated 'keycloak-port-forward.log'
$logConsole = Join-Path $Generated 'console-port-forward.log'
$pfKeycloak = Start-Process -FilePath 'kubectl.exe' -ArgumentList @('--context',$Context,'-n',$SystemNamespace,'port-forward','svc/keycloak','9443:9443') -PassThru -WindowStyle Hidden -RedirectStandardOutput $logKeycloak -RedirectStandardError (Join-Path $Generated 'keycloak-port-forward.err')
$pfConsole = Start-Process -FilePath 'kubectl.exe' -ArgumentList @('--context',$Context,'-n',$SystemNamespace,'port-forward','svc/kuber-console','9000:9000') -PassThru -WindowStyle Hidden -RedirectStandardOutput $logConsole -RedirectStandardError (Join-Path $Generated 'console-port-forward.err')
Set-Content -Path (Join-Path $Generated 'port-forward-pids.txt') -Value "keycloak=$($pfKeycloak.Id)`nconsole=$($pfConsole.Id)" -Encoding ascii
Start-Sleep -Seconds 3
if ($pfKeycloak.HasExited -or $pfConsole.HasExited) { throw "A port-forward process exited. Check logs under $Generated" }
Invoke-Native { curl.exe --ssl-no-revoke --fail --silent --show-error --cacert $caCrt --resolve keycloak.kuber.local:9443:127.0.0.1 https://keycloak.kuber.local:9443/realms/kuber/.well-known/openid-configuration -o (Join-Path $Generated 'oidc-discovery.json') } 'Keycloak OIDC discovery check failed.'
Invoke-Native { curl.exe --fail --silent --show-error http://localhost:9000/ -o NUL } 'Kuber Console HTTP check failed.'

Write-Host '[7/8] Running RBAC boundary checks...'
$readPods = (kubectl --context $Context auth can-i get pods -n $TargetNamespace --as=oidc:e2e-ns-admin --as-group=oidc:kuber-namespace-admins).Trim()
$deleteNs = (kubectl --context $Context auth can-i delete namespaces --as=oidc:e2e-ns-admin --as-group=oidc:kuber-namespace-admins).Trim()
$readNodes = (kubectl --context $Context auth can-i get nodes --as=oidc:e2e-cluster-admin --as-group=oidc:kuber-cluster-admins).Trim()
if ($readPods -ne 'yes' -or $deleteNs -ne 'no' -or $readNodes -ne 'yes') { throw "RBAC checks failed: get pods=$readPods; delete namespaces=$deleteNs; cluster admin get nodes=$readNodes" }

Write-Host '[8/8] Deployment and smoke checks passed.'
Write-Host "Keycloak admin credentials: $adminFile"
Write-Host 'Add to Windows hosts file (as Administrator): 127.0.0.1 keycloak.kuber.local'
Write-Host "Trust local CA (elevated PowerShell): certutil -addstore -f Root `"$caCrt`""
Write-Host "Create users in Keycloak realm kuber and add each only to kuber-cluster-admins or kuber-namespace-admins. Namespace admins are scoped to $TargetNamespace."
Write-Host 'Console: http://localhost:9000  |  Keycloak: https://keycloak.kuber.local:9443'
Write-Host "Port-forward process IDs and logs: $Generated"
Write-Host "Port-forward process IDs: $Generated\port-forward-pids.txt (stop only those PIDs with Stop-Process)."
