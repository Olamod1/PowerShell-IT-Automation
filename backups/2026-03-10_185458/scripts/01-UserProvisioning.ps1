# 01-UserProvisioning.ps1
# Bulk AD User Provisioning Script
# Purpose: Automate new hire account creation from CSV
# Author: Oluwatosin Lamodi
# Date: March 2026

param(
    [Parameter(Mandatory=$false)]
    [string]$CsvPath = "..\data\NewHires.csv",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "..\logs\provisioning_$(Get-Date -Format 'yyyyMMdd').log"
)

# ---- LOGGING FUNCTION ----
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"

    # Create log directory if it doesn't exist
    $logDir = Split-Path $LogPath -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $logEntry | Out-File -Append -FilePath $LogPath
    
    # Color-coded console output
    switch ($Level) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default   { Write-Host $logEntry }
    }
}

# ---- HELPER FUNCTION: Generate username ----
function New-SamAccountName {
    param([string]$FirstName, [string]$LastName)
    $sam = ("$FirstName.$LastName").ToLower() -replace '[^a-z.]', ''
    return $sam
}

# ---- HELPER FUNCTION: Determine OU by department ----
function Get-OUPath {
    param([string]$Department)
    $ouMap = @{
        "IT"            = "OU=IT,OU=Users,DC=bonduelle,DC=local"
        "Manufacturing" = "OU=Manufacturing,OU=Users,DC=bonduelle,DC=local"
        "Logistics"     = "OU=Logistics,OU=Users,DC=bonduelle,DC=local"
        "HR"            = "OU=HR,OU=Users,DC=bonduelle,DC=local"
        "Finance"       = "OU=Finance,OU=Users,DC=bonduelle,DC=local"
    }
    if ($ouMap.ContainsKey($Department)) {
        return $ouMap[$Department]
    } else {
        Write-Log "No OU mapping for department: $Department" "WARNING"
        return "OU=General,OU=Users,DC=bonduelle,DC=local"
    }
}

# ---- HELPER FUNCTION: Determine security groups ----
function Get-DepartmentGroups {
    param([string]$Department)
    $groupMap = @{
        "IT"            = @("SG-IT-Staff", "SG-VPN-Access", "SG-Admin-Tools")
        "Manufacturing" = @("SG-Manufacturing", "SG-MES-Access")
        "Logistics"     = @("SG-Logistics", "SG-Shipping-App")
        "HR"            = @("SG-HR-Staff", "SG-HRIS-Access")
        "Finance"       = @("SG-Finance", "SG-ERP-Access")
    }
    if ($groupMap.ContainsKey($Department)) {
        return $groupMap[$Department]
    }
    return @("SG-AllUsers")
}

# ---- MAIN SCRIPT ----
Write-Log "=========================================="
Write-Log "  USER PROVISIONING SCRIPT STARTED"
Write-Log "=========================================="

# Validate CSV file exists
if (!(Test-Path $CsvPath)) {
    Write-Log "CSV file not found: $CsvPath" "ERROR"
    exit 1
}

# Import user data
$users = Import-Csv -Path $CsvPath
Write-Log "Loaded $($users.Count) user(s) from CSV"

# Track results
$created = 0
$failed = 0
$results = @()

foreach ($user in $users) {
    Write-Log "------------------------------------------"
    Write-Log "Processing: $($user.FirstName) $($user.LastName)"

    # Generate account details
    $sam = New-SamAccountName -FirstName $user.FirstName -LastName $user.LastName
    $upn = "$sam@bonduelle.local"
    $ouPath = Get-OUPath -Department $user.Department
    $groups = Get-DepartmentGroups -Department $user.Department
    $defaultPassword = "Welcome2Bonduelle!"

    Write-Log "  Username:   $sam"
    Write-Log "  UPN:        $upn"
    Write-Log "  OU:         $ouPath"
    Write-Log "  Department: $($user.Department)"
    Write-Log "  Title:      $($user.Title)"
    Write-Log "  Groups:     $($groups -join ', ')"

    # --- SIMULATION MODE ---
    # In production, replace this block with actual New-ADUser commands
    # For this lab, we simulate the creation to demonstrate the logic
    try {
        # Simulated account creation
        Write-Log "  [SIMULATED] Creating AD account for $sam" "SUCCESS"
        Write-Log "  [SIMULATED] Setting password with forced change at next logon" "SUCCESS"
        Write-Log "  [SIMULATED] Enabling MFA enrollment flag" "SUCCESS"

        foreach ($group in $groups) {
            Write-Log "  [SIMULATED] Added to group: $group" "SUCCESS"
        }

        $created++
        $results += [PSCustomObject]@{
            Name       = "$($user.FirstName) $($user.LastName)"
            Username   = $sam
            UPN        = $upn
            Department = $user.Department
            Title      = $user.Title
            OU         = $ouPath
            Groups     = $groups -join "; "
            Status     = "Created"
            Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    catch {
        Write-Log "  FAILED to create account: $_" "ERROR"
        $failed++
        $results += [PSCustomObject]@{
            Name       = "$($user.FirstName) $($user.LastName)"
            Username   = $sam
            UPN        = $upn
            Department = $user.Department
            Title      = $user.Title
            OU         = $ouPath
            Groups     = ""
            Status     = "Failed: $_"
            Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

# ---- SUMMARY REPORT ----
Write-Log "=========================================="
Write-Log "  PROVISIONING SUMMARY"
Write-Log "=========================================="
Write-Log "Total Processed: $($users.Count)"
Write-Log "Successfully Created: $created" "SUCCESS"
if ($failed -gt 0) {
    Write-Log "Failed: $failed" "ERROR"
} else {
    Write-Log "Failed: 0" "SUCCESS"
}

# Export results to CSV report
$reportPath = "..\logs\provisioning_report_$(Get-Date -Format 'yyyyMMdd').csv"
$results | Export-Csv -Path $reportPath -NoTypeInformation
Write-Log "Report exported to: $reportPath"

# Display results table in console
Write-Log ""
Write-Log "ACCOUNT DETAILS:"
$results | Format-Table Name, Username, Department, Groups, Status -AutoSize | Out-String | Write-Host

Write-Log "=========================================="
Write-Log "  SCRIPT COMPLETE"
Write-Log "=========================================="
```

Save the file with `Ctrl+S`. Now let's run it. In the VS Code terminal, make sure you're in the scripts folder:
```
cd C:\Users\olamo\PowerShell-IT-Automation\scripts