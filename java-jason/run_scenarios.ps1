$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$jasonJar = 'C:\Program Files\jason-bin-3.3.0\bin\jason'
$javac = 'C:\Program Files\Java\jdk-23\bin\javac.exe'
$java = 'C:\Program Files\Java\jdk-23\bin\java.exe'
$build = Join-Path $PSScriptRoot 'build'
$classes = Join-Path $build 'classes'
$artifacts = Join-Path $PSScriptRoot 'scenario-artifacts'

New-Item -ItemType Directory -Force -Path $classes, (Join-Path $build 'tmp'), $artifacts | Out-Null
& $javac --release 17 -cp $jasonJar -d $classes `
    (Get-ChildItem (Join-Path $PSScriptRoot 'src\main\java\harness') -Filter '*.java').FullName `
    (Get-ChildItem (Join-Path $root 'telemetry') -Filter '*.java').FullName
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed' }

$expected = @{
    scenario1 = @('build','test','security','staging','production')
    scenario2 = @('build','test','test','security','staging','production')
    scenario3 = @('build','test','test')
    scenario4 = @('build','test','security','staging','production','production')
    scenario5 = @('build','test','security','staging','production','production','rollback_production')
    scenario6 = @('build','test','security','staging','production','production','rollback_production')
    scenario7 = @('rollback_production')
    scenario8 = @('rollback_production')
}

$scenarioExpectations = @{
    scenario1 = [ordered]@{ retry_count = 0; recovery = @(); forbidden = @(); final_state = 'completed_success'; master_goal = $true; maintenance_violated = $false; avoidance_violated = $false; beliefs = @('status(build,success)', 'status(production,success)', 'duration(production,42)') }
    scenario2 = [ordered]@{ retry_count = 1; recovery = @(); forbidden = @(); final_state = 'completed_success'; master_goal = $true; maintenance_violated = $false; avoidance_violated = $false; beliefs = @('status(test,fail)', 'status(test,success)') }
    scenario3 = [ordered]@{ retry_count = 1; recovery = @(); forbidden = @('security','staging','production'); final_state = 'stopped'; master_goal = $false; maintenance_violated = $false; avoidance_violated = $false; beliefs = @('status(test,fail)') }
    scenario4 = [ordered]@{ retry_count = 1; recovery = @(); forbidden = @('rollback_production'); final_state = 'completed_success'; master_goal = $true; maintenance_violated = $false; avoidance_violated = $false; beliefs = @('status(production,fail)', 'status(production,success)') }
    scenario5 = [ordered]@{ retry_count = 1; recovery = @('rollback_production'); forbidden = @(); final_state = 'recovered_stopped'; master_goal = $false; maintenance_violated = $false; avoidance_violated = $false; beliefs = @('status(production,fail)', 'status(rollback_production,success)') }
    scenario6 = [ordered]@{ retry_count = 1; recovery = @('rollback_production'); forbidden = @(); final_state = 'recovery_failed'; master_goal = $false; maintenance_violated = $false; avoidance_violated = $false; beliefs = @('status(production,fail)', 'status(rollback_production,fail)') }
    scenario7 = [ordered]@{ retry_count = 0; recovery = @('rollback_production'); forbidden = @('build','test','security','staging','production'); final_state = 'recovered_stopped'; master_goal = $false; maintenance_violated = $true; avoidance_violated = $false; beliefs = @('status(production,success)', 'duration(production,100001)', 'status(rollback_production,success)') }
    scenario8 = [ordered]@{ retry_count = 0; recovery = @('rollback_production'); forbidden = @('build','test','security','staging','production'); final_state = 'recovered_stopped'; master_goal = $false; maintenance_violated = $false; avoidance_violated = $true; beliefs = @('status(production,success)', 'status(rollback_production,success)') }
}

function Get-ActionEntities($lines) {
    $entities = @()
    foreach ($line in $lines) {
        if ($line -match 'run_job entity=([a-z_]+)') { $entities += $Matches[1] }
    }
    return $entities
}

Push-Location $root
$allResults = @()
try {
    foreach ($scenario in $expected.Keys | Sort-Object) {
        $logPath = Join-Path $artifacts ($scenario + '.log')
        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $rawLines = @(& $java '-Djava.awt.headless=true' `
            ('-Dbdi.scenario=' + $scenario) `
            ('-Djava.io.tmpdir=' + (Resolve-Path (Join-Path $build 'tmp'))) `
            ('-Djava.util.logging.config.file=' + (Resolve-Path (Join-Path $PSScriptRoot 'logging.properties'))) `
            -cp "$jasonJar;$classes" `
            jason.infra.local.RunLocalMAS (Join-Path $PSScriptRoot 'scenario.mas2j') `
            '--log-conf' (Join-Path $PSScriptRoot 'logging.properties') 2>&1)
        $lines = @($rawLines | ForEach-Object { $_.ToString() })
        $ErrorActionPreference = $oldErrorActionPreference
        $exitCode = $LASTEXITCODE
        $lines | Set-Content -Path $logPath
        if ($exitCode -ne 0) { throw "$scenario failed to start (exit $exitCode)" }

        $actual = @(Get-ActionEntities $lines)
        $wanted = @($expected[$scenario])
        $expectation = $scenarioExpectations[$scenario]
        if (($actual -join ',') -ne ($wanted -join ',')) {
            throw "$scenario action sequence mismatch. Expected $($wanted -join ','); actual $($actual -join ',')"
        }

        $masterAchieved = [bool]($lines -match 'Master goal achieved')
        $maintenanceSatisfied = [bool]($lines -match 'Maintenance satisfied')
        $maintenanceViolated = [bool]($lines -match 'Maintenance violated')
        $avoidanceViolated = [bool]($lines -match 'Avoidance violation detected')
        $finalState = if ($masterAchieved) { 'completed_success' } elseif ($lines -match 'Recovery completed successfully:') { 'recovered_stopped' } elseif ($lines -match 'Recovery failed:') { 'recovery_failed' } elseif ($lines -match 'Pipeline cannot make further progress|failed; workflow stopped') { 'stopped' } else { 'unknown' }
        $retryCount = 0
        for ($index = 1; $index -lt $actual.Count; $index++) { if ($actual[$index] -eq $actual[$index - 1]) { $retryCount++ } }
        $recoveryActions = @($actual | Where-Object { $_ -eq 'rollback_production' })
        $beliefChanges = @($lines | Where-Object { $_ -match 'belief=' })
        $beliefText = $beliefChanges -join "`n"
        if ($retryCount -ne [int]$expectation.retry_count) { throw "$scenario retry count mismatch" }
        if (($recoveryActions -join ',') -ne (@($expectation.recovery) -join ',')) { throw "$scenario recovery selection mismatch" }
        if ($finalState -ne $expectation.final_state) { throw "$scenario final state mismatch: $finalState" }
        if ($masterAchieved -ne [bool]$expectation.master_goal) { throw "$scenario master goal mismatch" }
        if ($maintenanceViolated -ne [bool]$expectation.maintenance_violated) { throw "$scenario maintenance result mismatch" }
        if ($avoidanceViolated -ne [bool]$expectation.avoidance_violated) { throw "$scenario avoidance result mismatch" }
        foreach ($forbidden in @($expectation.forbidden)) {
            if ($actual -contains $forbidden) { throw "$scenario executed forbidden entity $forbidden" }
        }
        foreach ($belief in @($expectation.beliefs)) {
            if ($beliefText -notmatch [regex]::Escape("belief=$belief")) { throw "$scenario missing belief change $belief" }
        }

        $summary = [ordered]@{
            scenario = $scenario
            initial_beliefs = @($lines | Where-Object { $_ -match 'initial_beliefs=' })
            percept_sequence = @($lines | Where-Object { $_ -match 'observation=' })
            selected_plans = @($lines | Where-Object { $_ -match 'Pursuing achievement|Running entity|completed successfully|retrying|failed; recovery|Maintenance|Avoidance|Master goal|Pipeline reached|workflow stopped' })
            run_job_calls = $actual
            expected_run_job_calls = $wanted
            retry_count = $retryCount
            expected_retry_count = [int]$expectation.retry_count
            recovery_actions = $recoveryActions
            expected_recovery_actions = @($expectation.recovery)
            final_state = $finalState
            expected_final_state = $expectation.final_state
            belief_changes = @($lines | Where-Object { $_ -match 'belief=' })
            final_beliefs = @($lines | Where-Object { $_ -match 'final_beliefs=' })
            achievement_goals_satisfied = $masterAchieved
            maintenance_goals_satisfied = $maintenanceSatisfied
            maintenance_goals_violated = $maintenanceViolated
            avoidance_goals_violated = $avoidanceViolated
            master_goal_expected = [bool]$expectation.master_goal
            forbidden_entities = @($expectation.forbidden)
        }
        $summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $artifacts ($scenario + '.json'))
        $allResults += [pscustomobject]$summary
        Write-Output "$scenario PASS: $($actual -join ' -> ')"
    }
    $allResults | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $artifacts 'phase3-summary.json')
}
finally {
    Pop-Location
}
