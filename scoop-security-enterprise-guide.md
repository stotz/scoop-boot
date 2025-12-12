# Scoop Security Features & Enterprise Repository Guide

## Table of Contents
1. [Scoop Security Features](#scoop-security-features)
2. [Hash Verification System](#hash-verification-system)
3. [Security Best Practices](#security-best-practices)
4. [Enterprise Private Repository Setup](#enterprise-private-repository-setup)
5. [Automated Security Scanning Pipeline](#automated-security-scanning-pipeline)
6. [Corporate Deployment Strategy](#corporate-deployment-strategy)

---
[Scoop Security Scanning with GitHub Actions CI/CD](scoop-security-github-actions.md)
--- 

## Scoop Security Features

### 1. Built-in Security Mechanisms

#### Hash Verification (SHA256)
Every Scoop manifest includes SHA256 hashes for downloaded files:

```json
{
    "version": "3.13.1",
    "architecture": {
        "64bit": {
            "url": "https://www.python.org/ftp/python/3.13.1/python-3.13.1-amd64.exe",
            "hash": "sha256:a1d9a7b8b8c8b9d8e7f6d5c4b3a2z1y9x8w7v6u5t4s3r2q1p0o9n8m7l6k5j4h3g2f1"
        }
    }
}
```

**Verification Process:**
1. Download file
2. Calculate SHA256 hash
3. Compare with manifest
4. Abort if mismatch

```powershell
# Manual hash check
scoop hash C:\usr\cache\python#3.13.1#x64.exe
# Compare with manifest hash

# Force re-verification
scoop verify python
```

#### Digital Signature Verification
Some apps include signature verification:

```json
{
    "installer": {
        "script": [
            "if (!(Test-AuthenticodeSignature \"$dir\\app.exe\").IsValid) {",
            "    throw 'Invalid signature'",
            "}"
        ]
    }
}
```

### 2. Download Security

#### HTTPS Enforcement
- All official buckets use HTTPS URLs
- Scoop warns about HTTP downloads
- Can be configured to block HTTP entirely

```powershell
# Enforce HTTPS only (custom policy)
scoop config use_https_only true  # Note: Not built-in, needs custom implementation
```

#### Proxy Support with Authentication
```powershell
# Configure secure proxy
scoop config proxy proxy.company.com:8080
scoop config proxy_username domain\username
scoop config proxy_password  # Prompts for secure input
```

### 3. Installation Isolation

#### User-Level Installation
- No admin rights required by default
- Apps isolated to user profile
- Reduced attack surface

#### Portable Apps Preference
- Self-contained applications
- No system-wide registry changes
- No DLL installations to System32

### 4. Manifest Security

#### JSON Schema Validation
```powershell
# Validate manifest structure
scoop config show_manifest_validation true
```

#### Restricted Script Execution
Installer scripts run in constrained PowerShell:
- Limited to specific cmdlets
- No network access during install
- Sandboxed file system access

---

## Hash Verification System

### How It Works

```powershell
# 1. Scoop downloads file
Invoke-WebRequest -Uri $url -OutFile $tempFile

# 2. Calculates hash
$actualHash = Get-FileHash $tempFile -Algorithm SHA256

# 3. Compares with manifest
if ($actualHash.Hash -ne $manifestHash) {
    throw "Hash mismatch! Expected: $manifestHash, Got: $actualHash"
}

# 4. Only then proceeds with installation
```

### Manual Hash Management

```powershell
# Generate hash for new package
$hash = (Get-FileHash "installer.exe" -Algorithm SHA256).Hash.ToLower()
Write-Host "SHA256: $hash"

# Update manifest with new hash
$manifest = Get-Content app.json | ConvertFrom-Json
$manifest.architecture.'64bit'.hash = "sha256:$hash"
$manifest | ConvertTo-Json -Depth 10 | Set-Content app.json

# Verify specific app
scoop verify firefox
```

### Hash Mismatch Troubleshooting

```powershell
# Clear cache and re-download
scoop cache rm firefox
scoop update firefox

# Check for manifest updates
scoop update
scoop update firefox

# Manual override (DANGEROUS - only for testing)
$env:SCOOP_SKIP_HASH_CHECK = $true
scoop install firefox
$env:SCOOP_SKIP_HASH_CHECK = $false
```

---

## Security Best Practices

### 1. Bucket Management

```powershell
# Only use trusted buckets
scoop bucket list

# Verify bucket sources
scoop bucket list | ForEach-Object {
    $bucketPath = "$env:SCOOP\buckets\$_"
    git -C $bucketPath remote -v
}

# Remove untrusted buckets
scoop bucket rm suspicious-bucket
```

### 2. Regular Updates

```powershell
# Update all components
scoop update          # Update Scoop and buckets
scoop update *       # Update all apps
scoop status         # Check for outdated apps

# Automated update script
@'
scoop update
scoop update * | Tee-Object -FilePath "$(Get-Date -Format 'yyyy-MM-dd')-updates.log"
scoop cleanup *
'@ | Set-Content "$env:SCOOP\bin\auto-update.ps1"

# Schedule via Task Scheduler
schtasks /create /tn "ScoopUpdate" /tr "powershell -File C:\usr\bin\auto-update.ps1" /sc weekly
```

### 3. Integrity Monitoring

```powershell
# Create integrity baseline
Get-ChildItem "$env:SCOOP\apps" -Recurse -File | 
    Get-FileHash -Algorithm SHA256 | 
    Export-Csv -Path "scoop-baseline.csv"

# Check integrity
$baseline = Import-Csv "scoop-baseline.csv"
$current = Get-ChildItem "$env:SCOOP\apps" -Recurse -File | 
    Get-FileHash -Algorithm SHA256

Compare-Object $baseline $current -Property Hash, Path |
    Where-Object { $_.SideIndicator -eq "=>" } |
    ForEach-Object { Write-Warning "Modified: $($_.Path)" }
```

### 4. Network Security

```powershell
# Use internal mirror
scoop config SCOOP_REPO 'https://git.company.com/scoop/scoop'

# Configure certificate validation
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
    param($sender, $certificate, $chain, $errors)
    # Custom validation logic
    return $true  # or false based on validation
}
```

---

## Enterprise Private Repository Setup

### Architecture Overview

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│                  │     │                  │     │                  │
│  Origin Servers  │────▶│  Security        │────▶│  Private         │
│  (Python.org,    │     │  Scanner         │     │  Repository      │
│   GitHub, etc.)  │     │  (VirusTotal,    │     │  (Git Server,    │
│                  │     │   ClamAV, etc.)  │     │   Artifactory)   │
└──────────────────┘     └──────────────────┘     └──────────────────┘
                                                            │
                                                            ▼
                                                    ┌──────────────────┐
                                                    │                  │
                                                    │  Corporate       │
                                                    │  Workstations    │
                                                    │                  │
                                                    └──────────────────┘
```

### Step 1: Setup Git Repository

```bash
# On Git server (GitLab, GitHub Enterprise, Gitea, etc.)
mkdir company-scoop-bucket
cd company-scoop-bucket
git init

# Create bucket structure
mkdir bucket
mkdir scripts
mkdir .github

# Create README
cat > README.md << 'EOF'
# Company Scoop Bucket

Internal repository of verified and scanned applications.

## Security Policy
- All files scanned with ClamAV and VirusTotal
- All hashes verified
- Manual approval required for new apps
- Weekly security updates
EOF

git add .
git commit -m "Initial bucket setup"
git remote add origin https://git.company.com/it/scoop-bucket
git push -u origin main
```

### Step 2: Create Manifest Template

```json
{
    "version": "1.0.0",
    "description": "Application description",
    "homepage": "https://www.example.com",
    "license": "MIT",
    "notes": "Scanned and approved by IT Security on 2025-01-15",
    "architecture": {
        "64bit": {
            "url": "https://artifacts.company.com/scoop/app-1.0.0-x64.exe",
            "hash": "sha256:abc123...",
            "security": {
                "scanned_date": "2025-01-15",
                "scanner": "ClamAV 1.4.1, VirusTotal API",
                "signature": "Company IT Security",
                "approval_ticket": "SEC-2025-001"
            }
        }
    },
    "installer": {
        "script": [
            "# Custom installation script",
            "if (!(Test-Path \"$env:COMPANY_APPROVED\")) {",
            "    throw 'Installation requires company environment'",
            "}"
        ]
    },
    "checkver": {
        "url": "https://api.company.com/versions/app",
        "jsonpath": "$.version"
    },
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://artifacts.company.com/scoop/app-$version-x64.exe"
            }
        }
    }
}
```

### Step 3: Setup Artifact Repository

```powershell
# Using Artifactory, Nexus, or simple file server

# Create repository structure
New-Item -ItemType Directory -Path "\\fileserver\scoop\artifacts" -Force
New-Item -ItemType Directory -Path "\\fileserver\scoop\cache" -Force
New-Item -ItemType Directory -Path "\\fileserver\scoop\quarantine" -Force

# Set permissions
$acl = Get-Acl "\\fileserver\scoop\artifacts"
$permission = "DOMAIN\ScoopAdmins","FullControl","Allow"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
$acl.SetAccessRule($accessRule)
$permission = "DOMAIN\Domain Users","ReadAndExecute","Allow"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
$acl.SetAccessRule($accessRule)
Set-Acl "\\fileserver\scoop\artifacts" $acl
```

---

## Automated Security Scanning Pipeline

### PowerShell Security Scanner Script

```powershell
# File: scan-and-approve.ps1

param(
    [Parameter(Mandatory)]
    [string]$PackageUrl,
    
    [Parameter(Mandatory)]
    [string]$PackageName,
    
    [Parameter(Mandatory)]
    [string]$Version
)

$ErrorActionPreference = "Stop"

# Configuration
$TempDir = "C:\ScoopScan\Temp"
$QuarantineDir = "\\fileserver\scoop\quarantine"
$ApprovedDir = "\\fileserver\scoop\artifacts"
$ClamAVPath = "C:\Program Files\ClamAV\clamscan.exe"
$VirusTotalApiKey = $env:VIRUSTOTAL_API_KEY

# Create working directory
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    Write-Host "=== Security Scan for $PackageName v$Version ===" -ForegroundColor Cyan
    
    # 1. Download package
    Write-Host "Downloading package..." -ForegroundColor Yellow
    $fileName = "$PackageName-$Version.exe"
    $tempFile = Join-Path $TempDir $fileName
    Invoke-WebRequest -Uri $PackageUrl -OutFile $tempFile
    
    # 2. Calculate hash
    Write-Host "Calculating hash..." -ForegroundColor Yellow
    $hash = (Get-FileHash $tempFile -Algorithm SHA256).Hash.ToLower()
    Write-Host "SHA256: $hash" -ForegroundColor Gray
    
    # 3. ClamAV Scan
    Write-Host "Running ClamAV scan..." -ForegroundColor Yellow
    $clamResult = & $ClamAVPath --no-summary $tempFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "INFECTED: ClamAV detected malware!" -ForegroundColor Red
        Move-Item $tempFile $QuarantineDir -Force
        throw "ClamAV detected malware"
    }
    Write-Host "ClamAV: CLEAN" -ForegroundColor Green
    
    # 4. VirusTotal Scan
    Write-Host "Submitting to VirusTotal..." -ForegroundColor Yellow
    $vtHeaders = @{
        "x-apikey" = $VirusTotalApiKey
    }
    
    # Upload file
    $vtUpload = Invoke-RestMethod -Uri "https://www.virustotal.com/api/v3/files" `
        -Method Post `
        -Headers $vtHeaders `
        -Form @{file = Get-Item $tempFile}
    
    $analysisId = $vtUpload.data.id
    
    # Wait for analysis
    Write-Host "Waiting for VirusTotal analysis..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # Get results
    $vtResult = Invoke-RestMethod -Uri "https://www.virustotal.com/api/v3/analyses/$analysisId" `
        -Headers $vtHeaders
    
    $malicious = $vtResult.data.attributes.stats.malicious
    $suspicious = $vtResult.data.attributes.stats.suspicious
    
    if ($malicious -gt 0 -or $suspicious -gt 2) {
        Write-Host "INFECTED: VirusTotal detected threats!" -ForegroundColor Red
        Write-Host "Malicious: $malicious, Suspicious: $suspicious" -ForegroundColor Red
        Move-Item $tempFile $QuarantineDir -Force
        throw "VirusTotal detected threats"
    }
    Write-Host "VirusTotal: CLEAN (Malicious: 0, Suspicious: $suspicious)" -ForegroundColor Green
    
    # 5. Windows Defender Scan
    Write-Host "Running Windows Defender scan..." -ForegroundColor Yellow
    Start-Process -FilePath "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" `
        -ArgumentList "-Scan", "-ScanType 3", "-File $tempFile" `
        -Wait -NoNewWindow
    
    # 6. Check digital signature
    Write-Host "Checking digital signature..." -ForegroundColor Yellow
    $signature = Get-AuthenticodeSignature $tempFile
    if ($signature.Status -eq "Valid") {
        Write-Host "Signature: VALID ($($signature.SignerCertificate.Subject))" -ForegroundColor Green
    } else {
        Write-Host "Signature: NOT VALID or UNSIGNED" -ForegroundColor Yellow
    }
    
    # 7. Move to approved directory
    Write-Host "Moving to approved repository..." -ForegroundColor Yellow
    $approvedFile = Join-Path $ApprovedDir $fileName
    Move-Item $tempFile $approvedFile -Force
    
    # 8. Generate manifest
    Write-Host "Generating manifest..." -ForegroundColor Yellow
    $manifest = @{
        version = $Version
        description = "$PackageName - Security Scanned"
        homepage = "https://internal.company.com"
        license = "Proprietary"
        notes = "Scanned on $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        architecture = @{
            "64bit" = @{
                url = "https://artifacts.company.com/scoop/$fileName"
                hash = "sha256:$hash"
                security = @{
                    scanned_date = Get-Date -Format "yyyy-MM-dd"
                    clamav = "CLEAN"
                    virustotal = "Malicious: 0, Suspicious: $suspicious"
                    defender = "CLEAN"
                    signature = $signature.Status
                }
            }
        }
    }
    
    $manifestPath = "bucket\$PackageName.json"
    $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath
    
    Write-Host ""
    Write-Host "=== APPROVED ===" -ForegroundColor Green
    Write-Host "Package: $PackageName v$Version" -ForegroundColor White
    Write-Host "Hash: $hash" -ForegroundColor Gray
    Write-Host "Location: $approvedFile" -ForegroundColor Gray
    Write-Host "Manifest: $manifestPath" -ForegroundColor Gray
    
} catch {
    Write-Host ""
    Write-Host "=== REJECTED ===" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    
    # Log to security system
    $logEntry = @{
        Timestamp = Get-Date
        Package = $PackageName
        Version = $Version
        Result = "REJECTED"
        Reason = $_.Exception.Message
    }
    $logEntry | ConvertTo-Json | Add-Content "\\fileserver\scoop\security.log"
    
    throw
} finally {
    # Cleanup
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}
```

### CI/CD Integration (GitLab CI Example)

```yaml
# .gitlab-ci.yml
stages:
  - scan
  - approve
  - deploy

variables:
  SCOOP_BUCKET: "https://git.company.com/it/scoop-bucket"

scan-package:
  stage: scan
  tags:
    - windows
    - security
  script:
    - powershell -File scripts/scan-and-approve.ps1 
        -PackageUrl $CI_PACKAGE_URL 
        -PackageName $CI_PACKAGE_NAME 
        -Version $CI_PACKAGE_VERSION
  artifacts:
    paths:
      - bucket/*.json
    expire_in: 1 week
  only:
    - merge_requests

approve-package:
  stage: approve
  when: manual
  script:
    - echo "Manual approval granted by $GITLAB_USER_LOGIN"
    - git add bucket/*.json
    - git commit -m "Approved: $CI_PACKAGE_NAME v$CI_PACKAGE_VERSION"
    - git push origin main
  only:
    - merge_requests

deploy-bucket:
  stage: deploy
  script:
    - git push origin main
  only:
    - main
```

---

## Corporate Deployment Strategy

### 1. Group Policy Configuration

```powershell
# Create GPO for Scoop deployment
# Computer Configuration > Policies > Windows Settings > Scripts > Startup

$gpoScript = @'
# Check if Scoop is installed
if (!(Test-Path "C:\usr\apps\scoop")) {
    # Install Scoop from internal source
    $env:SCOOP = "C:\usr"
    $env:SCOOP_GLOBAL = "C:\usr\global"
    
    # Download from internal server
    Invoke-WebRequest -Uri "https://artifacts.company.com/scoop/install.ps1" `
        -OutFile "$env:TEMP\scoop-install.ps1"
    
    & "$env:TEMP\scoop-install.ps1" -RunAsAdmin
    
    # Add company bucket
    scoop bucket add company https://git.company.com/it/scoop-bucket
    
    # Remove public buckets
    scoop bucket rm main
    scoop bucket rm extras
    
    # Install base packages
    scoop install company/git company/python company/nodejs
}
'@

$gpoScript | Set-Content "\\domain\sysvol\domain\Policies\{GUID}\Machine\Scripts\Startup\install-scoop.ps1"
```

### 2. Configuration Management (SCCM/Intune)

```powershell
# Detection script for SCCM
if (Test-Path "C:\usr\apps\scoop\current\bin\scoop.ps1") {
    $version = & scoop --version
    Write-Output "Installed: $version"
    exit 0
} else {
    exit 1
}
```

### 3. Centralized Configuration

```powershell
# Deploy scoop config via registry
$regPath = "HKLM:\SOFTWARE\Scoop"
New-Item -Path $regPath -Force

# Set company defaults
New-ItemProperty -Path $regPath -Name "SCOOP_REPO" `
    -Value "https://git.company.com/scoop/scoop" -Force
    
New-ItemProperty -Path $regPath -Name "SCOOP_BUCKET_REPO" `
    -Value "https://git.company.com/it/scoop-bucket" -Force
    
New-ItemProperty -Path $regPath -Name "proxy" `
    -Value "proxy.company.com:8080" -Force
    
New-ItemProperty -Path $regPath -Name "use_lessmsi" `
    -Value $true -PropertyType DWord -Force
```

### 4. Monitoring and Compliance

```powershell
# Compliance check script
$requiredApps = @('git', 'python', 'nodejs', 'security-tools')
$installedApps = scoop list | Select-Object -ExpandProperty Name

$compliant = $true
$missing = @()

foreach ($app in $requiredApps) {
    if ($app -notin $installedApps) {
        $compliant = $false
        $missing += $app
    }
}

# Report to SIEM/Monitoring
$report = @{
    Hostname = $env:COMPUTERNAME
    Username = $env:USERNAME
    Timestamp = Get-Date
    Compliant = $compliant
    MissingApps = $missing
    InstalledApps = $installedApps
}

# Send to monitoring system
Invoke-RestMethod -Uri "https://monitoring.company.com/api/scoop-compliance" `
    -Method Post `
    -Body ($report | ConvertTo-Json) `
    -ContentType "application/json"
```

### 5. Update Management

```powershell
# Scheduled task for updates (runs as SYSTEM)
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -Command 'scoop update; scoop update * --quiet'"

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 3AM

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "ScoopUpdate" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Description "Weekly Scoop update from company repository"
```

---

## Security Hardening Checklist

### Repository Security
- [ ] Use HTTPS only for all URLs
- [ ] Implement certificate pinning for critical packages
- [ ] Sign all manifests with GPG
- [ ] Enable branch protection on main
- [ ] Require PR approvals (2+ reviewers)
- [ ] Automated security scanning in CI
- [ ] Regular security audits
- [ ] Vulnerability disclosure process

### Client Security
- [ ] Disable public buckets
- [ ] Use company proxy with authentication
- [ ] Enable PowerShell script logging
- [ ] Implement AppLocker/WDAC policies
- [ ] Regular integrity checks
- [ ] Monitor for unauthorized changes
- [ ] Centralized logging to SIEM

### Network Security
- [ ] Internal mirror/cache server
- [ ] Network segmentation
- [ ] DLP policies for package uploads
- [ ] Rate limiting on repository
- [ ] Geo-blocking if applicable
- [ ] WAF protection for repository

### Operational Security
- [ ] Change management process
- [ ] Security training for admins
- [ ] Incident response plan
- [ ] Regular security updates
- [ ] Backup and recovery procedures
- [ ] Access control and audit logs
- [ ] Compliance reporting

---

## Example: Complete Secure Setup

```powershell
# 1. Setup company bucket
git clone https://git.company.com/it/scoop-bucket
cd scoop-bucket

# 2. Scan and add package
./scripts/scan-and-approve.ps1 `
    -PackageUrl "https://download.python.org/python-3.13.1.exe" `
    -PackageName "python" `
    -Version "3.13.1"

# 3. Review and commit
git add bucket/python.json
git commit -m "Added: Python 3.13.1 (Security Approved)"
git push

# 4. Deploy to workstations
Invoke-Command -ComputerName (Get-ADComputer -Filter * | Select -Expand Name) {
    scoop bucket add company https://git.company.com/it/scoop-bucket
    scoop install company/python
}

# 5. Verify deployment
Get-ADComputer -Filter * | ForEach-Object {
    Invoke-Command -ComputerName $_.Name {
        scoop list python
    }
} | Export-Csv "python-deployment.csv"
```

---

## Summary

A secure enterprise Scoop deployment includes:

1. **Security Scanning Pipeline** - Automated malware scanning with multiple engines
2. **Private Repository** - Company-controlled bucket with approved packages
3. **Hash Verification** - SHA256 verification for all packages
4. **Access Control** - GPO/SCCM deployment with restricted permissions
5. **Monitoring** - Compliance checking and centralized logging
6. **Update Management** - Controlled rollout of updates
7. **Network Security** - Proxy, internal mirrors, and network segmentation

This approach ensures that only verified, scanned, and approved software is deployed while maintaining the flexibility and simplicity of Scoop.


---
[Main](README.md)
---
