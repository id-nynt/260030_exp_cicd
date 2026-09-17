param(
    [ValidateSet('healthy','high-error-rate','high-latency','unhealthy','execution-failure')][Parameter(Mandatory=$true)][string]$Scenario,
    [ValidateSet('staging','production')][string]$Entity = 'production'
)
$ErrorActionPreference = 'Stop'

if ($Scenario -eq 'execution-failure') {
    $plan = Join-Path $PSScriptRoot 'experiments\manual-execution-failure.properties'
    "$Entity.1.failure_mode=health_failure" | Set-Content -LiteralPath $plan
    $env:BDI_EXECUTION_PLAN = (Resolve-Path $plan)
    Write-Host "Execution failure plan written to $plan"
    Write-Host 'Restart run-demo.ps1 -Mode real so the next GitHub dispatch receives this plan.'
    exit 0
}

$failureMode = switch ($Scenario) {
    'healthy' { 'none' }
    'high-error-rate' { 'high_error_rate' }
    'high-latency' { 'high_latency' }
    'unhealthy' { 'unhealthy' }
}
$rate = if ($Scenario -eq 'high-error-rate') { '1' } else { '0' }
$latency = if ($Scenario -eq 'high-latency') { '1500' } else { '0' }
$deploymentMode = if ($env:BDI_DEPLOYMENT_MODE) { $env:BDI_DEPLOYMENT_MODE } else { 'compose' }

if ($deploymentMode -eq 'compose') {
    Write-Host "Recreating local Compose $Entity with failure_mode=$failureMode error_rate=$rate extra_latency_ms=$latency"
    $envName = $Entity.ToUpperInvariant()
    [Environment]::SetEnvironmentVariable("${envName}_FAILURE_MODE", $failureMode, 'Process')
    [Environment]::SetEnvironmentVariable("${envName}_FORCE_ERROR_RATE", $rate, 'Process')
    [Environment]::SetEnvironmentVariable("${envName}_EXTRA_LATENCY_MS", $latency, 'Process')
    docker compose up -d --force-recreate $Entity | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose failed. Is Docker Desktop running?' }
    Write-Host 'Compose injection complete. This affects local Compose, not a GitHub deployment.'
    exit 0
}

if ($deploymentMode -ne 'runner') { throw 'BDI_DEPLOYMENT_MODE must be compose or runner.' }
$targetHost = if ($env:BDI_DEPLOYMENT_HOST) { $env:BDI_DEPLOYMENT_HOST } else { 'localhost' }
$sshUser = $env:BDI_DEPLOYMENT_SSH_USER
$container = "payment-$Entity"
$port = if ($Entity -eq 'staging') { '8081' } else { '8082' }
$remoteCommand = @"
set -e
container='$container'
if [ '$Scenario' = 'unhealthy' ]; then docker stop `"$container`"; exit 0; fi
if [ '$Scenario' = 'healthy' ]; then docker start `"$container`"; exit 0; fi
image=`$(docker inspect --format '{{.Config.Image}}' `"$container`")
docker rm -f `"$container`" >/dev/null 2>&1 || true
docker run --detach --name `"$container`" --publish ${port}:8080 \
  --env SERVICE_VERSION=manual-injection \
  --env DEPLOYMENT_ENVIRONMENT=$Entity \
  --env FAILURE_MODE=$failureMode \
  --env FORCE_ERROR_RATE=$rate \
  --env EXTRA_LATENCY_MS=$latency \
  `"$image`"
"@
if ($targetHost -in @('localhost','127.0.0.1')) {
    bash -lc $remoteCommand
} else {
    if ([string]::IsNullOrWhiteSpace($sshUser)) { throw 'BDI_DEPLOYMENT_SSH_USER is required for a remote persistent host.' }
    $sshTarget = "$sshUser@$targetHost"
    ssh $sshTarget $remoteCommand
}
if ($LASTEXITCODE -ne 0) { throw 'Persistent deployment injection failed.' }
Write-Host "Injected $Scenario into persistent $Entity container on $targetHost."
