# 02-SystemHealthCheck.ps1
# System Health Check Dashboard
# Purpose: Collect system metrics and generate an HTML health report
# Author: Oluwatosin Lamodi
# Date: March 2026

param(
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "..\logs\HealthReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
)

# ---- THRESHOLDS ----
$cpuWarning = 70
$cpuCritical = 85
$memWarning = 75
$memCritical = 90
$diskWarning = 75
$diskCritical = 90

# ---- HELPER: Determine status and color ----
function Get-StatusInfo {
    param([double]$Value, [double]$Warning, [double]$Critical)
    if ($Value -ge $Critical) {
        return @{ Status = "CRITICAL"; Color = "#FF4444"; Emoji = "RED" }
    } elseif ($Value -ge $Warning) {
        return @{ Status = "WARNING"; Color = "#FFA500"; Emoji = "YEL" }
    } else {
        return @{ Status = "HEALTHY"; Color = "#44BB44"; Emoji = "GRN" }
    }
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SYSTEM HEALTH CHECK - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ---- 1. CPU USAGE ----
Write-Host "Checking CPU..." -ForegroundColor Yellow
$cpuLoad = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
$cpuInfo = Get-StatusInfo -Value $cpuLoad -Warning $cpuWarning -Critical $cpuCritical
$cpuDetails = Get-CimInstance -ClassName Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors

Write-Host "  CPU Load: $cpuLoad% - $($cpuInfo.Status)" -ForegroundColor $(
    if ($cpuInfo.Status -eq "CRITICAL") { "Red" }
    elseif ($cpuInfo.Status -eq "WARNING") { "Yellow" }
    else { "Green" }
)

# ---- 2. MEMORY USAGE ----
Write-Host "Checking Memory..." -ForegroundColor Yellow
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$freeMemGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$usedMemGB = [math]::Round($totalMemGB - $freeMemGB, 2)
$memPercent = [math]::Round(($usedMemGB / $totalMemGB) * 100, 1)
$memInfo = Get-StatusInfo -Value $memPercent -Warning $memWarning -Critical $memCritical

Write-Host "  Memory: $usedMemGB GB / $totalMemGB GB ($memPercent%) - $($memInfo.Status)" -ForegroundColor $(
    if ($memInfo.Status -eq "CRITICAL") { "Red" }
    elseif ($memInfo.Status -eq "WARNING") { "Yellow" }
    else { "Green" }
)

# ---- 3. DISK USAGE ----
Write-Host "Checking Disks..." -ForegroundColor Yellow
$disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $totalGB = [math]::Round($_.Size / 1GB, 2)
    $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
    $usedGB = [math]::Round($totalGB - $freeGB, 2)
    $usedPercent = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }
    $diskStatus = Get-StatusInfo -Value $usedPercent -Warning $diskWarning -Critical $diskCritical

    Write-Host "  Drive $($_.DeviceID) $usedGB GB / $totalGB GB ($usedPercent%) - $($diskStatus.Status)" -ForegroundColor $(
        if ($diskStatus.Status -eq "CRITICAL") { "Red" }
        elseif ($diskStatus.Status -eq "WARNING") { "Yellow" }
        else { "Green" }
    )

    [PSCustomObject]@{
        Drive       = $_.DeviceID
        TotalGB     = $totalGB
        UsedGB      = $usedGB
        FreeGB      = $freeGB
        UsedPercent = $usedPercent
        Status      = $diskStatus.Status
        Color       = $diskStatus.Color
    }
}

# ---- 4. TOP PROCESSES ----
Write-Host ""
Write-Host "Top 10 Processes by CPU:" -ForegroundColor Yellow
$topProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 |
    ForEach-Object {
        [PSCustomObject]@{
            Name      = $_.ProcessName
            PID       = $_.Id
            CPU_Sec   = [math]::Round($_.CPU, 2)
            MemoryMB  = [math]::Round($_.WorkingSet64 / 1MB, 2)
        }
    }

$topProcesses | Format-Table Name, PID, CPU_Sec, MemoryMB -AutoSize

# ---- 5. KEY SERVICES ----
Write-Host "Checking Services..." -ForegroundColor Yellow
$servicesToCheck = @("wuauserv", "Spooler", "W32Time", "WinRM", "EventLog", "Dhcp", "Dnscache")
$serviceResults = foreach ($svcName in $servicesToCheck) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        $svcStatus = if ($svc.Status -eq "Running") {
            Write-Host "  $($svc.DisplayName): Running" -ForegroundColor Green
            "Running"
        } else {
            Write-Host "  $($svc.DisplayName): $($svc.Status)" -ForegroundColor Red
            "$($svc.Status)"
        }
        [PSCustomObject]@{
            ServiceName = $svc.DisplayName
            ShortName   = $svcName
            Status      = $svcStatus
            Color       = if ($svcStatus -eq "Running") { "#44BB44" } else { "#FF4444" }
        }
    }
}

# ---- 6. UPTIME ----
$uptime = (Get-Date) - $os.LastBootUpTime
$uptimeString = "$($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"
Write-Host ""
Write-Host "  System Uptime: $uptimeString" -ForegroundColor Cyan

# ---- GENERATE HTML REPORT ----
Write-Host ""
Write-Host "Generating HTML Report..." -ForegroundColor Yellow

$diskRowsHtml = ($disks | ForEach-Object {
    "<tr>
        <td>$($_.Drive)</td>
        <td>$($_.TotalGB) GB</td>
        <td>$($_.UsedGB) GB</td>
        <td>$($_.FreeGB) GB</td>
        <td style='color:$($_.Color); font-weight:bold;'>$($_.UsedPercent)%</td>
        <td style='color:$($_.Color); font-weight:bold;'>$($_.Status)</td>
    </tr>"
}) -join "`n"

$processRowsHtml = ($topProcesses | ForEach-Object {
    "<tr>
        <td>$($_.Name)</td>
        <td>$($_.PID)</td>
        <td>$($_.CPU_Sec)</td>
        <td>$($_.MemoryMB) MB</td>
    </tr>"
}) -join "`n"

$serviceRowsHtml = ($serviceResults | ForEach-Object {
    "<tr>
        <td>$($_.ServiceName)</td>
        <td>$($_.ShortName)</td>
        <td style='color:$($_.Color); font-weight:bold;'>$($_.Status)</td>
    </tr>"
}) -join "`n"

$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Health Report - $env:COMPUTERNAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #1B3A5C; border-bottom: 3px solid #2E86AB; padding-bottom: 10px; }
        h2 { color: #2E86AB; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        th { background: #1B3A5C; color: white; padding: 12px; text-align: left; }
        td { padding: 10px 12px; border-bottom: 1px solid #eee; }
        tr:hover { background: #f0f7ff; }
        .summary-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin: 20px 0; }
        .card { background: white; border-radius: 8px; padding: 20px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); text-align: center; }
        .card h3 { margin: 0 0 10px 0; color: #666; font-size: 14px; }
        .card .value { font-size: 36px; font-weight: bold; }
        .footer { margin-top: 30px; color: #999; font-size: 12px; }
    </style>
</head>
<body>
    <h1>System Health Report</h1>
    <p><strong>Computer:</strong> $env:COMPUTERNAME | <strong>Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Uptime:</strong> $uptimeString</p>

    <div class="summary-grid">
        <div class="card">
            <h3>CPU USAGE</h3>
            <div class="value" style="color:$($cpuInfo.Color)">$cpuLoad%</div>
            <div style="color:$($cpuInfo.Color)">$($cpuInfo.Status)</div>
        </div>
        <div class="card">
            <h3>MEMORY USAGE</h3>
            <div class="value" style="color:$($memInfo.Color)">$memPercent%</div>
            <div>$usedMemGB / $totalMemGB GB</div>
        </div>
        <div class="card">
            <h3>SYSTEM UPTIME</h3>
            <div class="value" style="color:#2E86AB; font-size:24px;">$uptimeString</div>
        </div>
        <div class="card">
            <h3>SERVICES</h3>
            <div class="value" style="color:#44BB44">$(($serviceResults | Where-Object {$_.Status -eq 'Running'}).Count) / $($serviceResults.Count)</div>
            <div>Running</div>
        </div>
    </div>

    <h2>Disk Usage</h2>
    <table>
        <tr><th>Drive</th><th>Total</th><th>Used</th><th>Free</th><th>Used %</th><th>Status</th></tr>
        $diskRowsHtml
    </table>

    <h2>Top 10 Processes by CPU</h2>
    <table>
        <tr><th>Process</th><th>PID</th><th>CPU (sec)</th><th>Memory</th></tr>
        $processRowsHtml
    </table>

    <h2>Service Status</h2>
    <table>
        <tr><th>Service</th><th>Name</th><th>Status</th></tr>
        $serviceRowsHtml
    </table>

    <div class="footer">
        <p>Generated by SystemHealthCheck.ps1 | Author: Oluwatosin Lamodi | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
</body>
</html>
"@

# Create logs directory if needed
$logDir = Split-Path $ReportPath -Parent
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$htmlReport | Out-File -FilePath $ReportPath -Encoding UTF8

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  HEALTH CHECK COMPLETE" -ForegroundColor Green
Write-Host "  Report saved to: $ReportPath" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "To view the report, run:" -ForegroundColor Cyan
Write-Host "  Start-Process `"$ReportPath`"" -ForegroundColor Cyan
