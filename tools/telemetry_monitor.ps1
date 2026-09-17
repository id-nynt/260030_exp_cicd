param(
    [Parameter(Mandatory=$true)][string]$Entity,
    [Parameter(Mandatory=$true)][string]$HealthUrl,
    [Parameter(Mandatory=$true)][string]$MetricsUrl,
    [string]$ProductionHealthUrl = '',
    [string]$ProductionMetricsUrl = '',
    [int]$IntervalSeconds = 5
)
$ErrorActionPreference = 'Continue'
function Get-MetricValue([string]$text, [string]$name) {
    $pattern = "(?m)^$([regex]::Escape($name))(?:\{[^}]*\})?\s+([-+0-9.eE]+)"
    $match = [regex]::Match($text, $pattern)
    if ($match.Success) { return [double]$match.Groups[2].Value }
    return $null
}
function Get-Health([string]$url) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 5
        $body = $response.Content | ConvertFrom-Json
        return [ordered]@{ health = $body.status; reachable = $true }
    } catch { return [ordered]@{ health = 'unknown'; reachable = $false } }
}
Write-Host 'TELEMETRY MONITOR' -ForegroundColor Cyan
Write-Host "staging=$HealthUrl / $MetricsUrl"
if ($ProductionHealthUrl -and $ProductionMetricsUrl) { Write-Host "production=$ProductionHealthUrl / $ProductionMetricsUrl" }
Write-Host 'Execution status is not exposed by the application endpoint; see the BDI monitor.'
while ($true) {
    $targets = @([ordered]@{ entity = $Entity; health = $HealthUrl; metrics = $MetricsUrl })
    if ($ProductionHealthUrl -and $ProductionMetricsUrl) { $targets += [ordered]@{ entity = 'production'; health = $ProductionHealthUrl; metrics = $ProductionMetricsUrl } }
    foreach ($target in $targets) {
        $now = (Get-Date).ToString('o')
        $health = Get-Health $target.health
        $errorRate = $null; $latency = $null
        try {
            $metrics = (Invoke-WebRequest -UseBasicParsing -Uri $target.metrics -TimeoutSec 5).Content
            $errorRate = Get-MetricValue $metrics 'payment_error_rate'
            if ($null -eq $errorRate) {
                $requests = Get-MetricValue $metrics 'payment_request_count_total'
                $errors = Get-MetricValue $metrics 'payment_error_count_total'
                if ($null -ne $requests -and $requests -gt 0 -and $null -ne $errors) { $errorRate = $errors / $requests }
            }
            $count = Get-MetricValue $metrics 'payment_request_latency_ms_milliseconds_count'
            $sum = Get-MetricValue $metrics 'payment_request_latency_ms_milliseconds_sum'
            if ($null -ne $count -and $count -gt 0 -and $null -ne $sum) { $latency = $sum / $count }
            $dataStatus = 'fresh'
        } catch { $dataStatus = 'unavailable' }
        $rateText = if ($null -eq $errorRate) { 'n/a' } else { '{0:N3}' -f $errorRate }
        $latencyText = if ($null -eq $latency) { 'n/a' } else { '{0:N1} ms' -f $latency }
        Write-Host "$now | entity=$($target.entity) | health=$($health.health) | error_rate=$rateText | latency=$latencyText | execution_status=see-bdi-monitor | data_status=$dataStatus"
    }
    Start-Sleep -Seconds $IntervalSeconds
}
