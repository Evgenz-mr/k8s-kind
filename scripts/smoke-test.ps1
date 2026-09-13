param([ValidatePattern('^[a-z0-9-]+$')][string]$Cluster='ai-k8s')
$ErrorActionPreference='Stop';$ctx="kind-$Cluster";$failed=$false
function Test-Step($Name,[scriptblock]$Command){Write-Host "[TEST] $Name";try{& $Command;if($LASTEXITCODE-ne 0){throw "exit $LASTEXITCODE"};Write-Host '[PASS]'}catch{Write-Host "[FAIL] $($_.Exception.Message)";$script:failed=$true}}
Test-Step 'Nodes Ready' { kubectl --context $ctx wait --for=condition=Ready nodes --all --timeout=60s }
Test-Step 'No failed pods' { $bad=kubectl --context $ctx get pods -A --field-selector=status.phase=Failed -o name;if($bad){throw $bad} }
Test-Step 'CoreDNS Ready' { kubectl --context $ctx -n kube-system rollout status deployment/coredns --timeout=60s }
Test-Step 'DNS resolution' { kubectl --context $ctx run dns-smoke --image=busybox:1.36 --restart=Never --rm -i --command -- nslookup kubernetes.default.svc.cluster.local }
Test-Step 'API discovery' { kubectl --context $ctx api-resources *> $null }
# Metrics is optional. Windows PowerShell 5.1 can turn kubectl's expected NotFound stderr
# into NativeCommandError when ErrorActionPreference is Stop, so probe it non-fatally.
$previousErrorActionPreference=$ErrorActionPreference
try {
    $ErrorActionPreference='Continue'
    $metrics=kubectl --context $ctx get apiservice v1beta1.metrics.k8s.io -o name 2>$null
    $metricsExitCode=$LASTEXITCODE
}
finally {
    $ErrorActionPreference=$previousErrorActionPreference
}
if($metricsExitCode -eq 0 -and $metrics){Test-Step 'Metrics API' { kubectl --context $ctx top nodes }}
Write-Host '';kubectl --context $ctx get pods -A
if($failed){throw 'One or more smoke tests failed.'};Write-Host 'ALL SMOKE TESTS PASSED.'
