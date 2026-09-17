param([Parameter(Mandatory=$true)][string]$LogFile)
$ErrorActionPreference = 'Continue'
Write-Host "BDI MONITOR: $LogFile" -ForegroundColor Green
Write-Host 'Waiting for structured BDI events...'
while (-not (Test-Path -LiteralPath $LogFile)) { Start-Sleep -Milliseconds 500 }
Get-Content -LiteralPath $LogFile -Wait | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    try {
        $event = $_ | ConvertFrom-Json
        $entity = if ($event.entity) { $event.entity } else { '-' }
        $details = @()
        foreach ($name in @('selected_next_action','selected_plan','belief','property','value','status','github_run_id','error')) {
            if ($null -ne $event.$name) { $details += "$name=$($event.$name)" }
        }
        $detailText = if ($details.Count) { $details -join ' ' } else { '' }
        Write-Host "$($event.timestamp) | event=$($event.event) | entity=$entity $detailText"
    } catch { Write-Host $_ }
}
