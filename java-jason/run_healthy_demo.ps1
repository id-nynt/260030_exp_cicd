$ErrorActionPreference = 'Stop'
$gradle = if (Test-Path (Join-Path $PSScriptRoot 'gradlew.bat')) {
    Join-Path $PSScriptRoot 'gradlew.bat'
} elseif (Get-Command gradle -ErrorAction SilentlyContinue) {
    'gradle'
} else {
    throw 'Gradle is required. Install Gradle or add the Gradle Wrapper under java-jason, then rerun.'
}
Push-Location $PSScriptRoot
try {
    Write-Host 'Starting MAS Console through Gradle task run...' -ForegroundColor Green
    Write-Host 'Gradle is executing java-jason/real.mas2j; Jason output is shown below.' -ForegroundColor Green
    & $gradle run --console=plain --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Gradle run failed with exit $LASTEXITCODE" }
}
finally { Pop-Location }
