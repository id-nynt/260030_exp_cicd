$ErrorActionPreference = 'Stop'
$module = $PSScriptRoot
$jasonJar = 'C:\Program Files\jason-bin-3.3.0\bin\jason'
$javac = 'C:\Program Files\Java\jdk-23\bin\javac.exe'
$java = 'C:\Program Files\Java\jdk-23\bin\java.exe'
$classes = Join-Path $module 'build\classes'
$tmp = Join-Path $module 'build\mock-tmp'

if (-not (Test-Path $jasonJar)) { throw "Jason runtime not found: $jasonJar" }
if (-not (Test-Path $javac)) { throw "Java compiler not found: $javac" }
if (-not (Test-Path $java)) { throw "Java runtime not found: $java" }

New-Item -ItemType Directory -Force -Path $classes, $tmp | Out-Null
& $javac --release 17 -cp $jasonJar -d $classes `
    (Get-ChildItem (Join-Path $module 'src\main\java\harness') -Filter '*.java').FullName `
    (Get-ChildItem (Join-Path $module '..\telemetry') -Filter '*.java').FullName
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed' }

Push-Location $module
try {
    Write-Host 'Starting local mock MAS. This does not contact GitHub, Docker, or telemetry.'
    Write-Host 'The console will show the BDI action and belief response, then stop.'
    & $java '-Djava.awt.headless=true' `
        ('-Djava.io.tmpdir=' + (Resolve-Path $tmp)) `
        ('-Djava.util.logging.config.file=' + (Resolve-Path (Join-Path $module 'logging.properties'))) `
        '-cp' "$jasonJar;$classes" `
        jason.infra.local.RunLocalMAS (Join-Path $module 'mock.mas2j') `
        '--log-conf' (Join-Path $module 'logging.properties')
    if ($LASTEXITCODE -ne 0) { throw "Mock MAS failed with exit $LASTEXITCODE" }
}
finally { Pop-Location }
