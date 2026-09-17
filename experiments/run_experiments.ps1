param(
    [string]$ScenarioFile = (Join-Path $PSScriptRoot 'scenarios.json'),
    [string]$OnlyScenario = '',
    [int]$TimeoutMinutes = 25
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$javaRoot = Join-Path $root 'java-jason'
$jasonJar = 'C:\Program Files\jason-bin-3.3.0\bin\jason'
$javac = 'C:\Program Files\Java\jdk-23\bin\javac.exe'
$java = 'C:\Program Files\Java\jdk-23\bin\java.exe'
$resultsRoot = Join-Path $PSScriptRoot 'results'
$buildClasses = Join-Path $javaRoot 'build\classes'
$buildTmp = Join-Path $javaRoot 'build\tmp'

function Read-ScenarioFile([string]$path) {
    return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Write-ExecutionPlan($scenario, [string]$path) {
    $lines = @()
    if ($null -ne $scenario.execution) {
        foreach ($entityProperty in $scenario.execution.PSObject.Properties) {
            $entity = $entityProperty.Name
            $values = @($entityProperty.Value)
            for ($index = 0; $index -lt $values.Count; $index++) {
                $injection = $values[$index]
                $attempt = $index + 1
                foreach ($field in @('failure_mode', 'force_error_rate', 'extra_latency_ms', 'execution_delay_ms')) {
                    if ($null -ne $injection.PSObject.Properties[$field]) {
                        $lines += "$entity.$attempt.$field=$($injection.$field)"
                    }
                }
            }
        }
    }
    Set-Content -LiteralPath $path -Value $lines
}

function Set-LocalInjection($scenario) {
    foreach ($environment in @('staging', 'production')) {
        $config = $scenario.local.$environment
        $prefix = $environment.ToUpperInvariant()
        $failureMode = if ($null -ne $config -and $null -ne $config.failure_mode) { $config.failure_mode } else { 'none' }
        $rate = if ($null -ne $config -and $null -ne $config.force_error_rate) { $config.force_error_rate } else { '0' }
        $latency = if ($null -ne $config -and $null -ne $config.extra_latency_ms) { $config.extra_latency_ms } else { '0' }
        [Environment]::SetEnvironmentVariable("${prefix}_FAILURE_MODE", "$failureMode", 'Process')
        [Environment]::SetEnvironmentVariable("${prefix}_FORCE_ERROR_RATE", "$rate", 'Process')
        [Environment]::SetEnvironmentVariable("${prefix}_EXTRA_LATENCY_MS", "$latency", 'Process')
        [Environment]::SetEnvironmentVariable("${prefix}_SERVICE_VERSION", "$($scenario.name)-$($env:BDI_EXPERIMENT_ID)", 'Process')
    }
}

function Start-Traffic($scenario) {
    $jobs = @()
    foreach ($environment in @('staging', 'production')) {
        $config = $scenario.local.$environment
        $needsTraffic = $null -ne $config -and (($config.failure_mode -in @('high_latency', 'latency', 'high_error_rate', 'error')) -or [double]$config.force_error_rate -gt 0)
        if ($needsTraffic) {
            $port = if ($environment -eq 'staging') { 8081 } else { 8082 }
            $jobs += Start-Job -ScriptBlock {
                param($url)
                while ($true) {
                    try { Invoke-WebRequest -UseBasicParsing -Method Post -Uri $url -Body '{"amount":10}' -ContentType 'application/json' | Out-Null } catch { }
                    Start-Sleep -Milliseconds 200
                }
            } -ArgumentList "http://localhost:$port/pay"
        }
    }
    return $jobs
}

function Stop-Traffic($jobs) {
    foreach ($job in @($jobs)) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Wait-Healthy([int]$port) {
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$port/health" -TimeoutSec 2
            if ($response.StatusCode -eq 200) { return }
        } catch { }
        Start-Sleep -Seconds 1
    }
    throw "Local service on port $port did not become healthy"
}

function Start-Controller([string]$logFile, [string]$errorFile) {
    $args = @(
        '-Djava.awt.headless=true',
        ('-Djava.io.tmpdir=' + (Resolve-Path $buildTmp)),
        ('-Djava.util.logging.config.file=' + (Resolve-Path (Join-Path $javaRoot 'logging.properties'))),
        '-cp', "$jasonJar;$buildClasses",
        'jason.infra.local.RunLocalMAS',
        (Join-Path $javaRoot 'real.mas2j'),
        '--log-conf', (Join-Path $javaRoot 'logging.properties')
    )
    return Start-Process -FilePath $java -ArgumentList $args -WorkingDirectory $root `
        -RedirectStandardOutput $logFile -RedirectStandardError $errorFile -PassThru
}

function Wait-Terminal($process, [string]$consoleFile, [int]$limitMinutes) {
    $deadline = (Get-Date).AddMinutes($limitMinutes)
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        $text = if (Test-Path $consoleFile) { Get-Content -Raw -LiteralPath $consoleFile } else { '' }
        if ($text -match 'Master goal achieved\.' -or
            $text -match 'Recovery completed successfully:' -or
            $text -match 'Recovery failed:' -or
            $text -match 'Pipeline cannot make further progress\.' -or
            $text -match 'failed; workflow stopped\.') {
            Start-Sleep -Seconds 3
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    return if (Test-Path $consoleFile) { Get-Content -Raw -LiteralPath $consoleFile } else { '' }
}

function Parse-Events([string]$path) {
    if (-not (Test-Path $path)) { return @() }
    $events = @()
    foreach ($line in Get-Content -LiteralPath $path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $events += ($line | ConvertFrom-Json) } catch { }
    }
    return $events
}

function Assert-Scenario($scenario, $result, $console) {
    $expected = $scenario.expected
    if (($result.entity_executions.entity -join ',') -ne ($expected.actions -join ',')) {
        throw "$($scenario.name): action sequence mismatch"
    }
    if ($result.final_workflow_state -ne $expected.state) { throw "$($scenario.name): final state mismatch" }
    if ([bool]$result.goal_satisfaction.achievement -ne [bool]$expected.master_goal) { throw "$($scenario.name): achievement mismatch" }
    if ($null -ne $expected.retry_count -and $result.retry_count -ne [int]$expected.retry_count) { throw "$($scenario.name): retry count mismatch" }
    if ($null -ne $expected.recovery_actions -and (($result.recovery_actions -join ',') -ne ($expected.recovery_actions -join ','))) { throw "$($scenario.name): recovery mismatch" }
    foreach ($entity in @($expected.no_entities)) {
        if ($result.entity_executions.entity -contains $entity) { throw "$($scenario.name): unexpected entity $entity" }
    }
    if ($expected.maintenance_violated -and -not $result.goal_satisfaction.maintenance_violated) { throw "$($scenario.name): maintenance violation missing" }
    if ($null -ne $expected.observation) {
        $matching = @($result.observations | Where-Object {
            $_.entity -eq $expected.observation.entity -and $_.property -eq $expected.observation.property -and [double]$_.value -ge [double]$expected.observation.min
        })
        if ($matching.Count -eq 0) { throw "$($scenario.name): expected observation missing" }
    }
}

New-Item -ItemType Directory -Force -Path $buildClasses, $buildTmp, $resultsRoot | Out-Null
& $javac --release 17 -cp $jasonJar -d $buildClasses `
    (Get-ChildItem (Join-Path $javaRoot 'src\main\java\harness') -Filter '*.java').FullName `
    (Get-ChildItem (Join-Path $root 'telemetry') -Filter '*.java').FullName
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed' }

$catalog = Read-ScenarioFile $ScenarioFile
$scenarios = @($catalog.scenarios)
if ($OnlyScenario) { $scenarios = @($scenarios | Where-Object name -eq $OnlyScenario) }
if ($scenarios.Count -eq 0) { throw 'No matching scenarios' }
docker info | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is required and must be running' }

foreach ($scenario in $scenarios) {
    $experimentId = "$($scenario.name)-$([Guid]::NewGuid().ToString('N').Substring(0,12))"
    $resultDir = Join-Path $resultsRoot $experimentId
    New-Item -ItemType Directory -Force -Path $resultDir | Out-Null
    $planFile = Join-Path $resultDir 'execution-plan.properties'
    $structuredFile = Join-Path $resultDir 'runtime.jsonl'
    $consoleFile = Join-Path $resultDir 'controller.stdout.log'
    $errorFile = Join-Path $resultDir 'controller.stderr.log'
    $start = Get-Date
    $traffic = @()
    try {
        [Environment]::SetEnvironmentVariable('BDI_EXPERIMENT_ID', $experimentId, 'Process')
        [Environment]::SetEnvironmentVariable('BDI_RELEASE_ID', "$($scenario.name)-candidate", 'Process')
        [Environment]::SetEnvironmentVariable('BDI_EXECUTION_PLAN', $planFile, 'Process')
        [Environment]::SetEnvironmentVariable('BDI_LOG_FILE', $structuredFile, 'Process')
        [Environment]::SetEnvironmentVariable('STAGING_HEALTH_URL', 'http://localhost:8081/health', 'Process')
        [Environment]::SetEnvironmentVariable('STAGING_METRICS_URL', 'http://localhost:8081/metrics', 'Process')
        [Environment]::SetEnvironmentVariable('PRODUCTION_HEALTH_URL', 'http://localhost:8082/health', 'Process')
        [Environment]::SetEnvironmentVariable('PRODUCTION_METRICS_URL', 'http://localhost:8082/metrics', 'Process')
        Write-ExecutionPlan $scenario $planFile
        Set-LocalInjection $scenario

        docker compose down --remove-orphans | Out-Null
        docker compose up -d --build | Out-Null
        Wait-Healthy 8081
        Wait-Healthy 8082
        $traffic = Start-Traffic $scenario
        $controller = Start-Controller $consoleFile $errorFile
        $console = Wait-Terminal $controller $consoleFile $TimeoutMinutes
        $events = @(Parse-Events $structuredFile)
        $decisions = @($events | Where-Object event -eq 'bdi_decision')
        $starts = @($events | Where-Object event -eq 'github_execution_started')
        $terminals = @($events | Where-Object event -eq 'execution_terminal')
        $observations = @($events | Where-Object event -in @('observation_collected', 'observation_normalized'))
        $beliefs = @($events | Where-Object event -eq 'percept_published')
        $entities = @($decisions | ForEach-Object {
            [ordered]@{ entity = $_.entity; execution_id = $_.execution_id; github_run_id = $_.github_run_id; deployment_environment = $_.deployment_environment }
        })
        $executionRecords = @($starts | ForEach-Object {
            $startEvent = $_
            $endEvent = $terminals | Where-Object github_run_id -eq $_.github_run_id | Select-Object -First 1
            [ordered]@{ entity = $_.entity; execution_id = $_.execution_id; github_run_id = $_.github_run_id; start = $_.timestamp; end = if ($null -ne $endEvent) { $endEvent.timestamp } else { $null }; status = if ($null -ne $endEvent) { $endEvent.status } else { 'unknown' } }
        })
        $retryCount = [Math]::Max(0, $entities.Count - (@($entities.entity | Select-Object -Unique)).Count)
        $recoveryActions = @($entities | Where-Object entity -eq 'rollback_production' | ForEach-Object entity)
        $state = if ($console -match 'Master goal achieved\.') { 'completed_success' } elseif ($console -match 'Recovery completed successfully:') { 'recovered_stopped' } elseif ($console -match 'Recovery failed:') { 'recovery_failed' } elseif ($console -match 'Pipeline cannot make further progress\.|failed; workflow stopped\.') { 'stopped' } else { 'timeout' }
        $timestamps = @($executionRecords | ForEach-Object { if ($_.start) { [DateTime]$_.start }; if ($_.end) { [DateTime]$_.end } })
        $duration = if ($timestamps.Count -gt 1) { (($timestamps | Measure-Object -Maximum).Maximum - ($timestamps | Measure-Object -Minimum).Minimum).TotalMilliseconds } else { ((Get-Date) - $start).TotalMilliseconds }
        $result = [ordered]@{
            experiment_id = $experimentId
            scenario = $scenario.name
            entity_executions = $entities
            executions = $executionRecords
            observations = $observations
            belief_changes = $beliefs
            bdi_decisions = $decisions
            retry_count = $retryCount
            recovery_actions = $recoveryActions
            final_workflow_state = $state
            goal_satisfaction = [ordered]@{
                achievement = [bool]($console -match 'Master goal achieved\.')
                maintenance_satisfied = [bool]($console -match 'Maintenance satisfied')
                maintenance_violated = [bool]($console -match 'Maintenance violated')
                avoidance_violated = [bool]($console -match 'Avoidance violation detected')
            }
            total_pipeline_duration_ms = [Math]::Round($duration, 0)
        }
        $result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $resultDir 'result.json')
        Assert-Scenario $scenario $result $console
        Write-Output "$($scenario.name) PASS ($experimentId)"
    }
    catch {
        $_ | Out-String | Set-Content -LiteralPath (Join-Path $resultDir 'runner-error.txt')
        throw
    }
    finally {
        Stop-Traffic $traffic
        docker compose down --remove-orphans | Out-Null
    }
}
