$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'BDI MAS CONSOLE'
$controller = Join-Path $PSScriptRoot '..\java-jason\run_healthy_demo.ps1'
Write-Host 'BDI MAS CONSOLE' -ForegroundColor Green
Write-Host 'This window shows Jason plans, beliefs, run_job actions, and GitHub results.'
Write-Host 'Keep this window open while the demonstration runs.'
& powershell -ExecutionPolicy Bypass -File $controller
$exitCode = $LASTEXITCODE
Write-Host "BDI MAS controller ended with exit code $exitCode." -ForegroundColor Yellow
Read-Host 'Press Enter to close the BDI MAS CONSOLE'
exit $exitCode
