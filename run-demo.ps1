param(
    [ValidateSet('mock','real')][string]$Mode = 'mock',
    [switch]$SkipGeneration,
    [int]$TelemetryIntervalSeconds = 5
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$javaRoot = Join-Path $root 'java-jason'
$runtimeDir = Join-Path $javaRoot 'runtime-artifacts'
$logFile = if ($env:BDI_LOG_FILE) { $env:BDI_LOG_FILE } else { Join-Path $runtimeDir 'demo.jsonl' }
Write-Host '=== BDI research demonstration ===' -ForegroundColor Cyan
Write-Host "mode=$Mode"
if (-not $SkipGeneration) {
    Write-Host '[1/4] Validating and generating workflow/BDI configuration...' -ForegroundColor Yellow
    & py (Join-Path $root 'tools\model_transform.py')
    if ($LASTEXITCODE -ne 0) { throw 'Configuration validation/generation failed.' }
}
if ($Mode -eq 'mock') {
    Write-Host '[2/4] Starting deterministic BDI validation.' -ForegroundColor Yellow
    Write-Host 'This mode uses in-memory execution; it does not contact GitHub or Docker.'
    & powershell -ExecutionPolicy Bypass -File (Join-Path $javaRoot 'run_scenarios.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Deterministic BDI validation failed.' }
    Write-Host '[3/4] Telemetry monitor: not started because mock mode has no application endpoint.'
    Write-Host '[4/4] Results: java-jason\scenario-artifacts\phase3-summary.json' -ForegroundColor Green
    exit 0
}
Write-Host '[2/4] Checking real-mode prerequisites...' -ForegroundColor Yellow
$required = @('GITHUB_TOKEN','GITHUB_REPOSITORY','GITHUB_REF','STAGING_HEALTH_URL','STAGING_METRICS_URL','PRODUCTION_HEALTH_URL','PRODUCTION_METRICS_URL','BDI_DEPLOYMENT_MODE','BDI_DEPLOYMENT_HOST')
foreach ($name in $required) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) { throw "$name is required for real mode." }
}
if ($env:BDI_PERSISTENT_DEPLOYMENT_CONFIRMED -ne '1') {
    throw 'Real mode blocked: set BDI_PERSISTENT_DEPLOYMENT_CONFIRMED=1 only after confirming that GitHub deployment targets remain alive after the workflow runner exits.'
}
if ($env:BDI_DEPLOYMENT_MODE -ne 'runner') {
    throw 'Real mode requires BDI_DEPLOYMENT_MODE=runner. Local Compose is not the GitHub deployment target.'
}
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
$env:BDI_LOG_FILE = $logFile
Write-Host '[3/4] Opening separate telemetry and BDI monitor windows...' -ForegroundColor Yellow
$telemetryScript = Join-Path $root 'tools\telemetry_monitor.ps1'
$bdiScript = Join-Path $root 'tools\bdi_monitor.ps1'
$telemetryArgs = @('-NoExit','-ExecutionPolicy','Bypass','-File',$telemetryScript,'-Entity','staging','-HealthUrl',$env:STAGING_HEALTH_URL,'-MetricsUrl',$env:STAGING_METRICS_URL,'-ProductionHealthUrl',$env:PRODUCTION_HEALTH_URL,'-ProductionMetricsUrl',$env:PRODUCTION_METRICS_URL,'-IntervalSeconds',$TelemetryIntervalSeconds)
Start-Process powershell.exe -ArgumentList $telemetryArgs
$bdiArgs = @('-NoExit','-ExecutionPolicy','Bypass','-File',$bdiScript,'-LogFile',$logFile)
Start-Process powershell.exe -ArgumentList $bdiArgs
Write-Host '[4/4] Opening the BDI MAS console window...' -ForegroundColor Yellow
Write-Host "BDI log: $logFile"
$controllerScript = Join-Path $root 'tools\run_bdi_controller.ps1'
Start-Process powershell.exe -ArgumentList @('-NoExit','-ExecutionPolicy','Bypass','-File',$controllerScript) -WindowStyle Normal
Write-Host 'Three windows are now expected:' -ForegroundColor Green
Write-Host '  1. TELEMETRY MONITOR'
Write-Host '  2. BDI DECISION MONITOR'
Write-Host '  3. BDI MAS CONSOLE'
