# 04-BackupAutomation.ps1
# Automated Backup Verification Script
# Purpose: Verify backups completed successfully and alert on failures
# Author: Oluwatosin Lamodi
# Date: March 2026

param(
    [Parameter(Mandatory=$false)]
    [string]$BackupSource = "C:\Users\olamo\PowerShell-IT-Automation",

    [Parameter(Mandatory=$false)]
    [string]$BackupDest = "C:\Users\olamo\PowerShell-IT-Automation\backups",

    [Parameter(Mandatory=$false)]
    [int]$RetentionDays = 7,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "..\logs\backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
        default   { Write-Host $logEntry }
    }
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  BACKUP AUTOMATION SCRIPT" -ForegroundColor Cyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ---- STEP 1: PRE-BACKUP VALIDATION ----
Write-Log "Starting backup process..."
Write-Log "Source: $BackupSource"
Write-Log "Destination: $BackupDest"
Write-Log "Retention: $RetentionDays days"
Write-Log ""

# Verify source exists
if (!(Test-Path $BackupSource)) {
    Write-Log "Backup source not found: $BackupSource" "ERROR"
    exit 1
}

# Create backup destination
$todayFolder = Join-Path $BackupDest (Get-Date -Format 'yyyy-MM-dd_HHmmss')
try {
    New-Item -ItemType Directory -Path $todayFolder -Force | Out-Null
    Write-Log "Created backup folder: $todayFolder" "SUCCESS"
} catch {
    Write-Log "Failed to create backup folder: $_" "ERROR"
    exit 1
}

# ---- STEP 2: CHECK DISK SPACE ----
Write-Log "Checking available disk space..."
$destDrive = (Split-Path $BackupDest -Qualifier)
$disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$destDrive'"
$freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)

# Calculate source size
$sourceSize = (Get-ChildItem $BackupSource -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$sourceSizeMB = [math]::Round($sourceSize / 1MB, 2)
$sourceSizeGB = [math]::Round($sourceSize / 1GB, 2)

Write-Log "Source size: $sourceSizeMB MB"
Write-Log "Free space on $destDrive : $freeGB GB"

if ($sourceSizeGB -gt ($freeGB * 0.9)) {
    Write-Log "WARNING: Backup may consume more than 90% of free space!" "WARNING"
}

# ---- STEP 3: PERFORM BACKUP ----
Write-Log ""
Write-Log "============================================"
Write-Log "  COPYING FILES"
Write-Log "============================================"

$foldersToBackup = @("scripts", "data", "modules", "logs")
$totalFiles = 0
$totalSize = 0
$failedFiles = 0
$backupResults = @()

foreach ($folder in $foldersToBackup) {
    $sourcePath = Join-Path $BackupSource $folder
    if (Test-Path $sourcePath) {
        Write-Log "Backing up: $folder"
        $destPath = Join-Path $todayFolder $folder

        try {
            # Copy the entire folder
            Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force

            # Count what was copied
            $copiedFiles = Get-ChildItem $destPath -Recurse -File -ErrorAction SilentlyContinue
            $fileCount = $copiedFiles.Count
            $folderSize = ($copiedFiles | Measure-Object -Property Length -Sum).Sum
            $folderSizeMB = [math]::Round($folderSize / 1MB, 2)

            $totalFiles += $fileCount
            $totalSize += $folderSize

            Write-Log "  Copied $fileCount files ($folderSizeMB MB)" "SUCCESS"

            $backupResults += [PSCustomObject]@{
                Folder    = $folder
                Files     = $fileCount
                SizeMB    = $folderSizeMB
                Status    = "Success"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        } catch {
            Write-Log "  FAILED to backup $folder : $_" "ERROR"
            $failedFiles++
            $backupResults += [PSCustomObject]@{
                Folder    = $folder
                Files     = 0
                SizeMB    = 0
                Status    = "Failed: $_"
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
    } else {
        Write-Log "  Folder not found, skipping: $folder" "WARNING"
    }
}

# ---- STEP 4: VERIFY BACKUP INTEGRITY ----
Write-Log ""
Write-Log "============================================"
Write-Log "  VERIFYING BACKUP INTEGRITY"
Write-Log "============================================"

$verifyPassed = 0
$verifyFailed = 0

foreach ($folder in $foldersToBackup) {
    $sourcePath = Join-Path $BackupSource $folder
    $destPath = Join-Path $todayFolder $folder

    if ((Test-Path $sourcePath) -and (Test-Path $destPath)) {
        $sourceFiles = Get-ChildItem $sourcePath -Recurse -File -ErrorAction SilentlyContinue
        $destFiles = Get-ChildItem $destPath -Recurse -File -ErrorAction SilentlyContinue

        $sourceCount = if ($sourceFiles) { $sourceFiles.Count } else { 0 }
        $destCount = if ($destFiles) { $destFiles.Count } else { 0 }

        if ($sourceCount -eq $destCount) {
            Write-Log "  $folder : $destCount / $sourceCount files verified" "SUCCESS"
            $verifyPassed++
        } else {
            Write-Log "  $folder : MISMATCH - Source: $sourceCount, Backup: $destCount" "ERROR"
            $verifyFailed++
        }
    }
}

# Checksum verification on a sample file
Write-Log ""
Write-Log "Running checksum verification on sample files..."
$sampleFiles = Get-ChildItem $todayFolder -Recurse -File | Select-Object -First 3
foreach ($file in $sampleFiles) {
    $relativePath = $file.FullName.Replace($todayFolder, "")
    $originalFile = Join-Path $BackupSource $relativePath.TrimStart("\")

    if (Test-Path $originalFile) {
        $sourceHash = (Get-FileHash $originalFile -Algorithm SHA256).Hash
        $backupHash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash

        if ($sourceHash -eq $backupHash) {
            Write-Log "  CHECKSUM MATCH: $($file.Name)" "SUCCESS"
        } else {
            Write-Log "  CHECKSUM MISMATCH: $($file.Name)" "ERROR"
            $verifyFailed++
        }
    }
}

# ---- STEP 5: RETENTION CLEANUP ----
Write-Log ""
Write-Log "============================================"
Write-Log "  RETENTION CLEANUP"
Write-Log "============================================"

if (Test-Path $BackupDest) {
    $oldBackups = Get-ChildItem $BackupDest -Directory | Where-Object {
        $_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays)
    }

    if ($oldBackups.Count -gt 0) {
        foreach ($old in $oldBackups) {
            Write-Log "  Removing old backup: $($old.Name)" "WARNING"
            Remove-Item $old.FullName -Recurse -Force
        }
        Write-Log "  Cleaned up $($oldBackups.Count) old backup(s)" "SUCCESS"
    } else {
        Write-Log "  No backups older than $RetentionDays days found" "SUCCESS"
    }
}

# ---- STEP 6: GENERATE SUMMARY ----
$totalSizeMB = [math]::Round($totalSize / 1MB, 2)

Write-Log ""
Write-Log "============================================"
Write-Log "  BACKUP SUMMARY"
Write-Log "============================================"
Write-Log "  Total Files Copied:    $totalFiles"
Write-Log "  Total Size:            $totalSizeMB MB"
Write-Log "  Folders Verified:      $verifyPassed passed, $verifyFailed failed"
Write-Log "  Failed Operations:     $failedFiles"
Write-Log "  Backup Location:       $todayFolder"

if ($failedFiles -eq 0 -and $verifyFailed -eq 0) {
    Write-Log "" 
    Write-Log "  BACKUP STATUS: SUCCESSFUL" "SUCCESS"
    Write-Log "  All files copied and verified successfully." "SUCCESS"
} else {
    Write-Log ""
    Write-Log "  BACKUP STATUS: COMPLETED WITH ERRORS" "ERROR"
    Write-Log "  Review log for details: $LogPath" "ERROR"
}

# Export results
$reportPath = "..\logs\backup_report_$(Get-Date -Format 'yyyyMMdd').csv"
$backupResults | Export-Csv -Path $reportPath -NoTypeInformation
Write-Log "  Report exported to: $reportPath"

Write-Log ""
Write-Log "============================================"
Write-Log "  BACKUP SCRIPT COMPLETE"
Write-Log "============================================"