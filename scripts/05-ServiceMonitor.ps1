# 05-ServiceMonitor.ps1
# Windows Service Monitor with Auto-Restart
# Purpose: Monitor critical services, restart on failure, alert on persistent issues
# Author: Oluwatosin Lamodi
# Date: March 2026

param(
    [Parameter(Mandatory=$false)]
    [int]$CheckIntervalSeconds = 30,

    [Parameter(Mandatory=$false)]
    [int]$MaxRestartAttempts = 3,

    [Parameter(Mandatory=$false)]
    [int]$MonitorDurationMinutes = 3,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "..\logs\servicemonitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# ---- SERVICES TO MONITOR ----
$servicesToMonitor = @(
    @{ Name = "Spooler";    DisplayName = "Print Spooler";       Priority = "Medium" },
    @{ Name = "W32Time";    DisplayName = "Windows Time";        Priority = "High" },
    @{ Name = "EventLog";   DisplayName = "Windows Event Log";   Priority = "Critical" },
    @{ Name = "Dhcp";       DisplayName = "DHCP Client";         Priority = "High" },
    @{ Name = "Dnscache";   DisplayName = "DNS Client";          Priority = "Critical" },
    @{ Name = "WinRM";      DisplayName = "WinRM";               Priority = "Medium" },
    @{ Name = "wuauserv";   DisplayName = "Windows Update";      Priority = "Low" }
)

# ---- LOGGING ----
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    $logDir = Split-Path $LogPath -Parent
    if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logEntry | Out-File -Append -FilePath $LogPath
    switch ($Level) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "ALERT"   { Write-Host $logEntry -ForegroundColor Magenta }
        default   { Write-Host $logEntry }
    }
}

# ---- RESTART TRACKER ----
$restartTracker = @{}
foreach ($svc in $servicesToMonitor) {
    $restartTracker[$svc.Name] = @{
        Attempts    = 0
        LastRestart = $null
        Exhausted   = $false
    }
}

# ---- SERVICE CHECK FUNCTION ----
function Test-ServiceHealth {
    param([hashtable]$ServiceDef)

    $svc = Get-Service -Name $ServiceDef.Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        return [PSCustomObject]@{
            Name        = $ServiceDef.Name
            DisplayName = $ServiceDef.DisplayName
            Status      = "NOT FOUND"
            Priority    = $ServiceDef.Priority
            Action      = "None"
            Color       = "Gray"
        }
    }

    if ($svc.Status -eq "Running") {
        return [PSCustomObject]@{
            Name        = $ServiceDef.Name
            DisplayName = $ServiceDef.DisplayName
            Status      = "Running"
            Priority    = $ServiceDef.Priority
            Action      = "None"
            Color       = "Green"
        }
    }

    # Service is NOT running
    $tracker = $restartTracker[$ServiceDef.Name]

    if ($tracker.Exhausted) {
        return [PSCustomObject]@{
            Name        = $ServiceDef.Name
            DisplayName = $ServiceDef.DisplayName
            Status      = "$($svc.Status)"
            Priority    = $ServiceDef.Priority
            Action      = "ESCALATE - Max restarts exceeded"
            Color       = "Red"
        }
    }

    # Attempt restart
    $tracker.Attempts++
    $tracker.LastRestart = Get-Date
    Write-Log "  Attempting restart ($($tracker.Attempts)/$MaxRestartAttempts): $($ServiceDef.DisplayName)" "WARNING"

    try {
        Start-Service -Name $ServiceDef.Name -ErrorAction Stop
        Start-Sleep -Seconds 3
        $refreshed = Get-Service -Name $ServiceDef.Name

        if ($refreshed.Status -eq "Running") {
            Write-Log "  RESTART SUCCESSFUL: $($ServiceDef.DisplayName)" "SUCCESS"
            return [PSCustomObject]@{
                Name        = $ServiceDef.Name
                DisplayName = $ServiceDef.DisplayName
                Status      = "Restarted"
                Priority    = $ServiceDef.Priority
                Action      = "Auto-restarted (attempt $($tracker.Attempts))"
                Color       = "Yellow"
            }
        }
    } catch {
        Write-Log "  Restart failed: $($_.Exception.Message)" "ERROR"
    }

    if ($tracker.Attempts -ge $MaxRestartAttempts) {
        $tracker.Exhausted = $true
        Write-Log "  MAX RESTART ATTEMPTS REACHED: $($ServiceDef.DisplayName)" "ALERT"
        Write-Log "  *** ESCALATION REQUIRED - Notify on-call engineer ***" "ALERT"
        return [PSCustomObject]@{
            Name        = $ServiceDef.Name
            DisplayName = $ServiceDef.DisplayName
            Status      = "$($svc.Status)"
            Priority    = $ServiceDef.Priority
            Action      = "ESCALATE - Restart failed after $MaxRestartAttempts attempts"
            Color       = "Red"
        }
    }

    return [PSCustomObject]@{
        Name        = $ServiceDef.Name
        DisplayName = $ServiceDef.DisplayName
        Status      = "$($svc.Status)"
        Priority    = $ServiceDef.Priority
        Action      = "Restart attempted - will retry"
        Color       = "Yellow"
    }
}

# ---- MAIN MONITORING LOOP ----
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SERVICE MONITOR" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Monitoring $($servicesToMonitor.Count) services" -ForegroundColor Cyan
Write-Host "  Check interval: ${CheckIntervalSeconds}s" -ForegroundColor Cyan
Write-Host "  Duration: $MonitorDurationMinutes minutes" -ForegroundColor Cyan
Write-Host "  Max restart attempts: $MaxRestartAttempts" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Ctrl+C to stop monitoring early" -ForegroundColor Gray
Write-Host ""

$startTime = Get-Date
$endTime = $startTime.AddMinutes($MonitorDurationMinutes)
$checkCount = 0
$allResults = @()

while ((Get-Date) -lt $endTime) {
    $checkCount++
    Write-Log "--- CHECK #$checkCount at $(Get-Date -Format 'HH:mm:ss') ---"

    $checkResults = foreach ($svcDef in $servicesToMonitor) {
        $result = Test-ServiceHealth -ServiceDef $svcDef
        $statusColor = switch ($result.Color) {
            "Green"  { "Green" }
            "Yellow" { "Yellow" }
            "Red"    { "Red" }
            default  { "Gray" }
        }

        if ($result.Status -eq "Running") {
            Write-Host "  [OK]    $($result.DisplayName)" -ForegroundColor Green
        } elseif ($result.Status -eq "Restarted") {
            Write-Host "  [FIXED] $($result.DisplayName) - Auto-restarted" -ForegroundColor Yellow
        } else {
            Write-Host "  [DOWN]  $($result.DisplayName) - $($result.Action)" -ForegroundColor Red
        }

        $result
    }

    $allResults += $checkResults
    $running = ($checkResults | Where-Object { $_.Status -eq "Running" }).Count
    $total = $checkResults.Count
    Write-Log "Status: $running/$total services running"
    Write-Log ""

    # Wait for next check unless we've reached the end
    if ((Get-Date) -lt $endTime) {
        Write-Host "  Next check in $CheckIntervalSeconds seconds..." -ForegroundColor Gray
        Start-Sleep -Seconds $CheckIntervalSeconds
    }
}

# ---- FINAL REPORT ----
Write-Log "============================================"
Write-Log "  MONITORING SESSION COMPLETE"
Write-Log "============================================"
Write-Log "  Duration: $MonitorDurationMinutes minutes"
Write-Log "  Total Checks: $checkCount"

# Summary per service
Write-Log ""
Write-Log "  SERVICE SUMMARY:"
foreach ($svcDef in $servicesToMonitor) {
    $svcResults = $allResults | Where-Object { $_.Name -eq $svcDef.Name }
    $upCount = ($svcResults | Where-Object { $_.Status -eq "Running" -or $_.Status -eq "Restarted" }).Count
    $totalChecks = $svcResults.Count
    $uptimePercent = if ($totalChecks -gt 0) { [math]::Round(($upCount / $totalChecks) * 100, 1) } else { 0 }
    $tracker = $restartTracker[$svcDef.Name]

    $color = if ($uptimePercent -eq 100) { "Green" } elseif ($uptimePercent -ge 80) { "Yellow" } else { "Red" }
    Write-Host "    $($svcDef.DisplayName): $uptimePercent% uptime | Restart attempts: $($tracker.Attempts)" -ForegroundColor $color
    Write-Log "    $($svcDef.DisplayName): $uptimePercent% uptime | Restart attempts: $($tracker.Attempts)"
}

# Export results
$reportPath = "..\logs\servicemonitor_report_$(Get-Date -Format 'yyyyMMdd').csv"
$logDir = Split-Path $reportPath -Parent
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$allResults | Export-Csv -Path $reportPath -NoTypeInformation

Write-Log ""
Write-Log "  Report exported: $reportPath"
Write-Log "============================================"
Write-Log "  MONITOR COMPLETE"
Write-Log "============================================"
