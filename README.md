# PowerShell IT Automation Portfolio

Automated IT operations scripts built for enterprise environments. This project demonstrates PowerShell scripting proficiency for systems administration, monitoring, backup management, and incident response workflows.

## Author

**Oluwatosin Lamodi**  
IT Systems Operations | Cloud & Infrastructure  
[LinkedIn](https://linkedin.com) | olamod1@outlook.com

---

## Scripts Overview

### 01 - User Provisioning (`01-UserProvisioning.ps1`)
Automates bulk Active Directory user account creation from CSV input. Handles standardized username generation, Organizational Unit placement by department, security group assignment, and comprehensive logging.

**Key Features:**
- Reads new hire data from CSV (Name, Department, Title, Email)
- Generates standardized sAMAccountName (first.last format)
- Maps departments to correct OUs and security groups
- Enforces least-privilege access and MFA enrollment
- Produces detailed log files and CSV summary reports

**Usage:**
```powershell
.\scripts\01-UserProvisioning.ps1 -CsvPath ".\data\NewHires.csv"
```

---

### 02 - System Health Check (`02-SystemHealthCheck.ps1`)
Collects real-time system metrics including CPU, memory, disk usage, top processes, and service status. Generates a color-coded HTML dashboard report with configurable warning and critical thresholds.

**Key Features:**
- CPU, memory, and disk utilization monitoring
- Configurable warning (70/75/75%) and critical (85/90/90%) thresholds
- Top 10 processes by CPU consumption
- Critical Windows service status checks
- Professional HTML dashboard report output

**Usage:**
```powershell
.\scripts\02-SystemHealthCheck.ps1
# Open the report:
Start-Process ".\logs\HealthReport_*.html"
```

---

### 03 - Log Analyzer (`03-LogAnalyzer.ps1`)
Parses Windows Event Logs to identify errors, warnings, and critical events. Ranks the top 10 most frequent issues, displays a daily breakdown with visual bar charts, calculates Mean Time Between Failures (MTBF), and provides actionable recommendations.

**Key Features:**
- Scans System and Application event logs for configurable date ranges
- Categorizes events by severity (Critical, Error, Warning)
- Identifies top 10 recurring event IDs with first/last occurrence
- Daily event breakdown with visual histogram
- MTBF calculation for error frequency analysis
- Automated recommendations based on findings

**Usage:**
```powershell
.\scripts\03-LogAnalyzer.ps1 -LogName "System" -DaysBack 7
```

---

### 04 - Backup Automation (`04-BackupAutomation.ps1`)
Performs automated file backups with pre-flight disk space validation, SHA256 checksum integrity verification, and configurable retention policy cleanup.

**Key Features:**
- Pre-backup disk space validation
- Folder-by-folder backup with file count and size tracking
- SHA256 checksum verification for data integrity
- Configurable retention period with automatic cleanup
- Detailed backup summary with pass/fail reporting

**Usage:**
```powershell
.\scripts\04-BackupAutomation.ps1 -RetentionDays 7
```

---

### 05 - Service Monitor (`05-ServiceMonitor.ps1`)
Continuously monitors critical Windows services at configurable intervals. Automatically attempts to restart failed services up to a defined threshold, then escalates for human intervention.

**Key Features:**
- Monitors 7 critical Windows services (DNS, DHCP, Event Log, etc.)
- Configurable check interval and monitoring duration
- Auto-restart with up to 3 retry attempts per service
- Escalation alerts when max restart attempts are exhausted
- Per-service uptime percentage calculation
- Priority-based service classification (Critical, High, Medium, Low)

**Usage:**
```powershell
.\scripts\05-ServiceMonitor.ps1 -CheckIntervalSeconds 30 -MonitorDurationMinutes 3
```

---

## Project Structure

```
PowerShell-IT-Automation/
├── scripts/
│   ├── 01-UserProvisioning.ps1
│   ├── 02-SystemHealthCheck.ps1
│   ├── 03-LogAnalyzer.ps1
│   ├── 04-BackupAutomation.ps1
│   └── 05-ServiceMonitor.ps1
├── data/
│   └── NewHires.csv
├── logs/                  # Generated reports and log files
├── backups/               # Backup destination folder
├── modules/               # Reusable PowerShell modules
├── tests/                 # Script test files
└── README.md
```

## Requirements

- **PowerShell 7.x** (tested on 7.5.4)
- **Windows 10/11** or **Windows Server 2019+**
- Active Directory module (for production use of Script 01)
- Administrator privileges recommended for service monitoring

## Technologies

- PowerShell 7
- Windows Management Instrumentation (WMI/CIM)
- Windows Event Log API
- Active Directory (simulated)
- HTML/CSS for dashboard reporting
- SHA256 checksum verification
- Git version control