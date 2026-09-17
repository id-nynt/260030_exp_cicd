$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Force -Path $out | Out-Null

javac -d $out (Join-Path $PSScriptRoot 'Observation.java'), (Join-Path $PSScriptRoot 'TelemetryAdapter.java')

function Observe([string]$label) {
    Write-Output "--- $label ---"
    java -cp $out telemetry.TelemetryAdapter `
        --entity staging `
        --health-url http://localhost:8081/health `
        --metrics-url http://localhost:8081/metrics `
        --execution success,420
}

Push-Location $root
try {
    Remove-Item Env:STAGING_FAILURE_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:STAGING_FORCE_ERROR_RATE -ErrorAction SilentlyContinue
    Remove-Item Env:STAGING_EXTRA_LATENCY_MS -ErrorAction SilentlyContinue
    docker compose up -d --force-recreate staging | Out-Null
    Start-Sleep -Seconds 2
    Invoke-RestMethod -Method Post -Uri http://localhost:8081/pay -ContentType 'application/json' -Body '{"amount":10}' | Out-Null
    Observe 'healthy'

    $env:STAGING_FAILURE_MODE = 'latency'
    $env:STAGING_EXTRA_LATENCY_MS = '200'
    docker compose up -d --force-recreate staging | Out-Null
    Start-Sleep -Seconds 2
    Invoke-RestMethod http://localhost:8081/health | Out-Null
    Invoke-RestMethod -Method Post -Uri http://localhost:8081/pay -ContentType 'application/json' -Body '{"amount":10}' | Out-Null
    Observe 'high latency'

    Remove-Item Env:STAGING_FAILURE_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:STAGING_EXTRA_LATENCY_MS -ErrorAction SilentlyContinue
    $env:STAGING_FORCE_ERROR_RATE = '1'
    docker compose up -d --force-recreate staging | Out-Null
    Start-Sleep -Seconds 2
    try { Invoke-WebRequest -Method Post -Uri http://localhost:8081/pay -UseBasicParsing | Out-Null } catch { }
    Observe 'high error rate'

    Remove-Item Env:STAGING_FORCE_ERROR_RATE -ErrorAction SilentlyContinue
    $env:STAGING_FAILURE_MODE = 'unhealthy'
    docker compose up -d --force-recreate staging | Out-Null
    Start-Sleep -Seconds 2
    Observe 'unhealthy health check'

    Remove-Item Env:STAGING_FAILURE_MODE -ErrorAction SilentlyContinue
    docker compose up -d --force-recreate staging | Out-Null
    Start-Sleep -Seconds 2
    Observe 'restored healthy'
}
finally {
    Remove-Item Env:STAGING_FAILURE_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:STAGING_FORCE_ERROR_RATE -ErrorAction SilentlyContinue
    Remove-Item Env:STAGING_EXTRA_LATENCY_MS -ErrorAction SilentlyContinue
    Pop-Location
}
