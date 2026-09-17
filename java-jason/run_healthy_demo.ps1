$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$jasonJar = 'C:\Program Files\jason-bin-3.3.0\bin\jason'
$javac = 'C:\Program Files\Java\jdk-23\bin\javac.exe'
$java = 'C:\Program Files\Java\jdk-23\bin\java.exe'
$classes = Join-Path $PSScriptRoot 'build\classes'
$tmp = Join-Path $PSScriptRoot 'build\tmp'
New-Item -ItemType Directory -Force -Path $classes, $tmp | Out-Null
& $javac --release 17 -cp $jasonJar -d $classes `
    (Get-ChildItem (Join-Path $PSScriptRoot 'src\main\java\harness') -Filter '*.java').FullName `
    (Get-ChildItem (Join-Path $root 'telemetry') -Filter '*.java').FullName
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed' }
Push-Location $root
try {
    & $java '-Djava.awt.headless=true' `
        ('-Djava.io.tmpdir=' + (Resolve-Path $tmp)) `
        ('-Djava.util.logging.config.file=' + (Resolve-Path (Join-Path $PSScriptRoot 'logging.properties'))) `
        '-cp' "$jasonJar;$classes" `
        jason.infra.local.RunLocalMAS (Join-Path $PSScriptRoot 'real.mas2j') `
        '--log-conf' (Join-Path $PSScriptRoot 'logging.properties')
    if ($LASTEXITCODE -ne 0) { throw "Healthy demonstration failed with exit $LASTEXITCODE" }
}
finally { Pop-Location }
