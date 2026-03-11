# 03-LogAnalyzer.ps1
# Windows Event Log Analyzer
# Purpose: Parse event logs, identify patterns, and generate incident reports
# Author: Oluwatosin Lamodi
# Date: March 2026

param(
    [Parameter(Mandatory=$false)]
    [string]$LogName = "System",

    [Parameter(Mandatory=$false)]
    [int]$DaysBack = 7,

    [Parameter(Mandatory=$false)]
    [string[]]$Severity = @("Error", "Warning"),

    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "..\logs\LogAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  EVENT LOG ANALYZER" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Log Source: $LogName" -ForegroundColor Cyan
Write-Host "  Date Range: Last $DaysBack days" -ForegroundColor Cyan
Write-Host "  Severity Filter: $($Severity -join ', ')" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ---- CALCULATE DATE RANGE ----
$startDate = (Get-Date).AddDays(-$DaysBack)
$endDate = Get-Date
Write-Host "Scanning from $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))..." -ForegroundColor Yellow

# ---- COLLECT EVENTS ----
Write-Host "Collecting events from $LogName log..." -ForegroundColor Yellow
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = $LogName
        Level     = @(1, 2, 3)  # 1=Critical, 2=Error, 3=Warning
        StartTime = $startDate
        EndTime   = $endDate
    } -ErrorAction SilentlyContinue
} catch {
    Write-Host "  No events found matching criteria or access denied." -ForegroundColor Red
    $events = @()
}

if ($events.Count -eq 0) {
    Write-Host "No events found for the specified criteria." -ForegroundColor Yellow
    Write-Host "Trying Application log as fallback..." -ForegroundColor Yellow
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = "Application"
            Level     = @(1, 2, 3)
            StartTime = $startDate
            EndTime   = $endDate
        } -ErrorAction SilentlyContinue
        $LogName = "Application"
    } catch {
        $events = @()
    }
}

$totalEvents = $events.Count
Write-Host ""
Write-Host "Found $totalEvents events" -ForegroundColor Green
Write-Host ""

if ($totalEvents -eq 0) {
    Write-Host "No events to analyze. Your system is running clean!" -ForegroundColor Green
    exit 0
}

# ---- CATEGORIZE EVENTS ----
Write-Host "Categorizing events..." -ForegroundColor Yellow
$critical = ($events | Where-Object { $_.Level -eq 1 }).Count
$errors = ($events | Where-Object { $_.Level -eq 2 }).Count
$warnings = ($events | Where-Object { $_.Level -eq 3 }).Count

Write-Host "  Critical: $critical" -ForegroundColor $(if ($critical -gt 0) { "Red" } else { "Green" })
Write-Host "  Errors:   $errors" -ForegroundColor $(if ($errors -gt 0) { "Red" } else { "Green" })
Write-Host "  Warnings: $warnings" -ForegroundColor $(if ($warnings -gt 0) { "Yellow" } else { "Green" })
Write-Host ""

# ---- TOP 10 MOST FREQUENT EVENTS ----
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  TOP 10 MOST FREQUENT EVENTS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$topEvents = $events | Group-Object -Property Id | Sort-Object Count -Descending | Select-Object -First 10

$topEventResults = foreach ($group in $topEvents) {
    $sampleEvent = $group.Group | Select-Object -First 1
    $levelName = switch ($sampleEvent.Level) {
        1 { "Critical" }
        2 { "Error" }
        3 { "Warning" }
        default { "Info" }
    }

    # Get first and last occurrence
    $firstOccurrence = ($group.Group | Sort-Object TimeCreated | Select-Object -First 1).TimeCreated
    $lastOccurrence = ($group.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated

    # Truncate message for display
    $shortMessage = if ($sampleEvent.Message.Length -gt 80) {
        $sampleEvent.Message.Substring(0, 80) + "..."
    } else {
        $sampleEvent.Message
    }

    $color = switch ($levelName) {
        "Critical" { "Red" }
        "Error"    { "Red" }
        "Warning"  { "Yellow" }
        default    { "White" }
    }

    Write-Host ""
    Write-Host "  Event ID: $($group.Name) | Count: $($group.Count) | Severity: $levelName" -ForegroundColor $color
    Write-Host "  Source: $($sampleEvent.ProviderName)" -ForegroundColor Gray
    Write-Host "  First: $($firstOccurrence.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray
    Write-Host "  Last:  $($lastOccurrence.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray
    Write-Host "  Message: $shortMessage" -ForegroundColor Gray

    [PSCustomObject]@{
        EventID        = $group.Name
        Count          = $group.Count
        Severity       = $levelName
        Source         = $sampleEvent.ProviderName
        FirstSeen      = $firstOccurrence.ToString('yyyy-MM-dd HH:mm:ss')
        LastSeen       = $lastOccurrence.ToString('yyyy-MM-dd HH:mm:ss')
        Message        = $sampleEvent.Message
    }
}

# ---- DAILY BREAKDOWN ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  DAILY EVENT BREAKDOWN" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$dailyBreakdown = $events | Group-Object { $_.TimeCreated.ToString('yyyy-MM-dd') } | Sort-Object Name

foreach ($day in $dailyBreakdown) {
    $dayErrors = ($day.Group | Where-Object { $_.Level -le 2 }).Count
    $dayWarnings = ($day.Group | Where-Object { $_.Level -eq 3 }).Count
    $barLength = [math]::Min($day.Count, 50)
    $bar = "#" * $barLength

    $color = if ($dayErrors -gt 10) { "Red" } elseif ($dayErrors -gt 0) { "Yellow" } else { "Green" }
    Write-Host "  $($day.Name): $bar ($($day.Count) events | $dayErrors errors | $dayWarnings warnings)" -ForegroundColor $color
}

# ---- MEAN TIME BETWEEN FAILURES ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  MEAN TIME BETWEEN FAILURES (MTBF)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$errorEvents = $events | Where-Object { $_.Level -le 2 } | Sort-Object TimeCreated
if ($errorEvents.Count -gt 1) {
    $timeGaps = @()
    for ($i = 1; $i -lt $errorEvents.Count; $i++) {
        $gap = ($errorEvents[$i].TimeCreated - $errorEvents[$i-1].TimeCreated).TotalMinutes
        $timeGaps += $gap
    }
    $avgMTBF = [math]::Round(($timeGaps | Measure-Object -Average).Average, 2)
    $minMTBF = [math]::Round(($timeGaps | Measure-Object -Minimum).Minimum, 2)
    $maxMTBF = [math]::Round(($timeGaps | Measure-Object -Maximum).Maximum, 2)

    Write-Host "  Average time between errors: $avgMTBF minutes" -ForegroundColor White
    Write-Host "  Shortest gap: $minMTBF minutes" -ForegroundColor Yellow
    Write-Host "  Longest gap: $maxMTBF minutes" -ForegroundColor Green
} else {
    Write-Host "  Not enough error events to calculate MTBF" -ForegroundColor Gray
}

# ---- RECOMMENDATIONS ----
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RECOMMENDATIONS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($critical -gt 0) {
    Write-Host "  [URGENT] $critical critical events detected - investigate immediately" -ForegroundColor Red
}
if ($errors -gt 20) {
    Write-Host "  [HIGH] High error volume ($errors errors) - review top event IDs for root cause" -ForegroundColor Red
} elseif ($errors -gt 0) {
    Write-Host "  [MEDIUM] $errors errors found - review and monitor for trends" -ForegroundColor Yellow
}
if ($warnings -gt 50) {
    Write-Host "  [MEDIUM] Elevated warning count ($warnings) - may indicate developing issues" -ForegroundColor Yellow
}

$topEvent = $topEvents | Select-Object -First 1
if ($topEvent.Count -gt 20) {
    Write-Host "  [INFO] Event ID $($topEvent.Name) occurred $($topEvent.Count) times - consider creating a targeted fix" -ForegroundColor Cyan
}

# ---- EXPORT REPORT ----
Write-Host ""
Write-Host "Exporting report..." -ForegroundColor Yellow

$logDir = Split-Path $ReportPath -Parent
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$topEventResults | Export-Csv -Path $ReportPath -NoTypeInformation
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "  Report saved to: $ReportPath" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green