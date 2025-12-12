# Scoop Security Scanning with GitHub Actions CI/CD 

## GitHub Actions Workflow Examples

### 1. Basic Security Scan Workflow

```yaml
# .github/workflows/security-scan.yml
name: Security Scan for Scoop Packages

on:
  pull_request:
    paths:
      - 'bucket/*.json'
      - 'packages/*.txt'
  workflow_dispatch:
    inputs:
      package_url:
        description: 'Package URL to scan'
        required: true
        type: string
      package_name:
        description: 'Package name'
        required: true
        type: string
      package_version:
        description: 'Package version'
        required: true
        type: string

env:
  VIRUSTOTAL_API_KEY: ${{ secrets.VIRUSTOTAL_API_KEY }}
  ARTIFACTS_REPO: ${{ secrets.ARTIFACTS_REPO }}

jobs:
  security-scan:
    runs-on: windows-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Setup PowerShell modules
        run: |
          Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
          Install-Module -Name Pester -Force -Scope CurrentUser
      
      - name: Download and scan package
        id: scan
        run: |
          $PackageUrl = "${{ github.event.inputs.package_url }}"
          $PackageName = "${{ github.event.inputs.package_name }}"
          $Version = "${{ github.event.inputs.package_version }}"
          
          # Run security scan script
          ./scripts/scan-and-approve.ps1 `
            -PackageUrl $PackageUrl `
            -PackageName $PackageName `
            -Version $Version
          
          # Set outputs for next steps
          echo "package_name=$PackageName" >> $env:GITHUB_OUTPUT
          echo "package_version=$Version" >> $env:GITHUB_OUTPUT
        shell: pwsh
      
      - name: Upload scan results
        uses: actions/upload-artifact@v4
        with:
          name: scan-results-${{ steps.scan.outputs.package_name }}
          path: |
            scan-results/*.json
            scan-results/*.log
          retention-days: 30
      
      - name: Create issue if malware detected
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `🚨 Security Alert: Malware detected in ${context.payload.inputs.package_name}`,
              body: `Package: ${context.payload.inputs.package_name} v${context.payload.inputs.package_version}\nStatus: INFECTED\nAction: Quarantined\n\nSee workflow run: ${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`,
              labels: ['security', 'malware', 'critical']
            });
```

### 2. Automated Package Update Scanner

```yaml
# .github/workflows/auto-update-scan.yml
name: Automated Package Update Scanner

on:
  schedule:
    - cron: '0 2 * * MON'  # Every Monday at 2 AM UTC
  workflow_dispatch:

jobs:
  check-updates:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.check.outputs.matrix }}
      has_updates: ${{ steps.check.outputs.has_updates }}
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Check for package updates
        id: check
        run: |
          # Check for updates and create matrix
          python3 scripts/check-updates.py > updates.json
          
          if [ -s updates.json ]; then
            echo "has_updates=true" >> $GITHUB_OUTPUT
            echo "matrix=$(cat updates.json)" >> $GITHUB_OUTPUT
          else
            echo "has_updates=false" >> $GITHUB_OUTPUT
            echo "matrix={\"include\":[]}" >> $GITHUB_OUTPUT
          fi
  
  scan-updates:
    needs: check-updates
    if: needs.check-updates.outputs.has_updates == 'true'
    runs-on: windows-latest
    strategy:
      matrix: ${{ fromJson(needs.check-updates.outputs.matrix) }}
      fail-fast: false
      max-parallel: 3
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Cache malware signatures
        uses: actions/cache@v4
        with:
          path: |
            C:\ProgramData\ClamAV\*.cvd
            C:\ProgramData\ClamAV\*.cld
          key: clamav-db-${{ hashFiles('**/freshclam.conf') }}
          restore-keys: clamav-db-
      
      - name: Install ClamAV
        run: |
          choco install clamav -y
          freshclam
        shell: pwsh
      
      - name: Security scan
        run: |
          ./scripts/scan-and-approve.ps1 `
            -PackageUrl "${{ matrix.url }}" `
            -PackageName "${{ matrix.name }}" `
            -Version "${{ matrix.version }}"
        shell: pwsh
      
      - name: Update manifest
        if: success()
        run: |
          $manifest = Get-Content "bucket/${{ matrix.name }}.json" | ConvertFrom-Json
          $manifest.version = "${{ matrix.version }}"
          $manifest.architecture.'64bit'.url = "${{ matrix.url }}"
          $manifest.architecture.'64bit'.hash = "${{ env.FILE_HASH }}"
          $manifest | ConvertTo-Json -Depth 10 | Set-Content "bucket/${{ matrix.name }}.json"
        shell: pwsh
      
      - name: Create Pull Request
        if: success()
        uses: peter-evans/create-pull-request@v6
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: "Update: ${{ matrix.name }} to ${{ matrix.version }}"
          title: "🔄 Update ${{ matrix.name }} to ${{ matrix.version }} (Security Scanned)"
          body: |
            ## Package Update
            - **Package:** ${{ matrix.name }}
            - **Version:** ${{ matrix.version }}
            - **Status:** ✅ Security Scan Passed
            
            ### Security Scan Results
            - ClamAV: CLEAN
            - VirusTotal: 0 detections
            - Windows Defender: CLEAN
            - Digital Signature: Valid
            
            ### Checklist
            - [x] Automated security scan passed
            - [ ] Manual review required
            - [ ] Approved for production
          branch: update-${{ matrix.name }}-${{ matrix.version }}
          labels: |
            update
            security-scanned
            automated
```

### 3. Manual Approval Workflow

```yaml
# .github/workflows/manual-approval.yml
name: Manual Package Approval

on:
  pull_request_review:
    types: [submitted]
  issue_comment:
    types: [created]

jobs:
  approve-package:
    if: |
      (github.event.review.state == 'approved' && 
       contains(github.event.pull_request.labels.*.name, 'security-scanned')) ||
      (github.event.issue.pull_request && 
       github.event.comment.body == '/approve' && 
       contains(github.event.sender.login, github.event.repository.owner.login))
    
    runs-on: ubuntu-latest
    
    permissions:
      contents: write
      pull-requests: write
      packages: write
    
    steps:
      - name: Checkout PR
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.ref }}
      
      - name: Get package info
        id: package
        run: |
          # Extract package name from PR branch
          PACKAGE=$(echo "${{ github.event.pull_request.head.ref }}" | sed 's/update-\(.*\)-[0-9].*/\1/')
          VERSION=$(echo "${{ github.event.pull_request.head.ref }}" | sed 's/.*-\([0-9].*\)/\1/')
          echo "name=$PACKAGE" >> $GITHUB_OUTPUT
          echo "version=$VERSION" >> $GITHUB_OUTPUT
      
      - name: Sign manifest with GPG
        run: |
          echo "${{ secrets.GPG_PRIVATE_KEY }}" | gpg --import
          gpg --detach-sign --armor bucket/${{ steps.package.outputs.name }}.json
      
      - name: Upload to artifact repository
        run: |
          # Upload to GitHub Packages or other artifact store
          curl -X PUT \
            -H "Authorization: Bearer ${{ secrets.GITHUB_TOKEN }}" \
            -H "Content-Type: application/octet-stream" \
            --data-binary @"artifacts/${{ steps.package.outputs.name }}-${{ steps.package.outputs.version }}.exe" \
            "https://maven.pkg.github.com/${{ github.repository }}/scoop/${{ steps.package.outputs.name }}/${{ steps.package.outputs.version }}/${{ steps.package.outputs.name }}-${{ steps.package.outputs.version }}.exe"
      
      - name: Commit signature
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add bucket/*.json.asc
          git commit -m "Add GPG signature for ${{ steps.package.outputs.name }}"
          git push
      
      - name: Merge PR
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.pulls.merge({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.payload.pull_request.number,
              commit_title: `Approved: ${{ steps.package.outputs.name }} v${{ steps.package.outputs.version }}`,
              commit_message: `Security scanned and approved by ${context.actor}`,
              merge_method: 'squash'
            });
      
      - name: Tag release
        run: |
          git tag "${{ steps.package.outputs.name }}-${{ steps.package.outputs.version }}"
          git push origin "${{ steps.package.outputs.name }}-${{ steps.package.outputs.version }}"
```

### 4. Deployment to Production

```yaml
# .github/workflows/deploy-production.yml
name: Deploy to Production Repository

on:
  push:
    branches: [main]
    paths:
      - 'bucket/*.json'
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Git
        run: |
          git config --global user.name "GitHub Actions"
          git config --global user.email "actions@github.com"
      
      - name: Sync to production repository
        env:
          PROD_REPO_TOKEN: ${{ secrets.PROD_REPO_TOKEN }}
        run: |
          # Clone production repository
          git clone https://${PROD_REPO_TOKEN}@github.com/${{ vars.PROD_REPO }} prod-repo
          
          # Sync bucket files
          cp -r bucket/* prod-repo/bucket/
          
          # Commit and push
          cd prod-repo
          git add .
          git commit -m "Sync from main repository - $(date +'%Y-%m-%d %H:%M')" || true
          git push
      
      - name: Invalidate CDN cache
        run: |
          curl -X POST \
            -H "Authorization: Bearer ${{ secrets.CDN_API_KEY }}" \
            -H "Content-Type: application/json" \
            -d '{"paths": ["/bucket/*"]}' \
            https://api.cdn.company.com/purge
      
      - name: Notify Teams/Slack
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          text: |
            🚀 Scoop bucket deployed to production
            Repository: ${{ github.repository }}
            Commit: ${{ github.sha }}
            Author: ${{ github.actor }}
          webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

### 5. Complete Security Pipeline with Matrix Testing

```yaml
# .github/workflows/security-pipeline.yml
name: Complete Security Pipeline

on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: '0 0 * * *'  # Daily

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Validate JSON manifests
        run: |
          for file in bucket/*.json; do
            jq empty "$file" || exit 1
          done
      
      - name: Check manifest schema
        run: |
          npm install -g ajv-cli
          ajv validate -s schema/manifest.schema.json -d "bucket/*.json"
  
  security-scan:
    needs: lint
    runs-on: windows-latest
    strategy:
      matrix:
        scanner: [clamav, defender, custom]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup scanner - ${{ matrix.scanner }}
        run: |
          if ("${{ matrix.scanner }}" -eq "clamav") {
            choco install clamav -y
            freshclam
          } elseif ("${{ matrix.scanner }}" -eq "defender") {
            Update-MpSignature
          }
        shell: pwsh
      
      - name: Run security scan
        run: |
          ./scripts/scan-with-${{ matrix.scanner }}.ps1
        shell: pwsh
  
  virustotal:
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: VirusTotal scan
        uses: crazy-max/ghaction-virustotal@v4
        with:
          vt_api_key: ${{ secrets.VIRUSTOTAL_API_KEY }}
          files: |
            artifacts/*.exe
            artifacts/*.msi
  
  sign-and-deploy:
    needs: [security-scan, virustotal]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Import GPG key
        run: |
          echo "${{ secrets.GPG_PRIVATE_KEY }}" | gpg --import
      
      - name: Sign manifests
        run: |
          for file in bucket/*.json; do
            gpg --detach-sign --armor "$file"
          done
      
      - name: Deploy to production
        run: |
          ./scripts/deploy-to-production.sh
```

## GitHub-Specific Features

### 1. GitHub Environments

```yaml
# Define environments in repo settings
name: Deploy with Environments

jobs:
  deploy-staging:
    environment: staging
    # ...
  
  deploy-production:
    environment:
      name: production
      url: https://scoop.company.com
    # Requires manual approval if configured
```

### 2. GitHub Packages as Artifact Store

```yaml
# Upload to GitHub Packages
- name: Upload to GitHub Packages
  run: |
    echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
    
    # Upload binary as OCI artifact
    oras push ghcr.io/${{ github.repository }}/packages/${{ matrix.name }}:${{ matrix.version }} \
      ./artifacts/${{ matrix.name }}-${{ matrix.version }}.exe
```

### 3. Branch Protection Rules

```yaml
# .github/branch-protection.yml (for reference - set in UI)
protection_rules:
  main:
    required_status_checks:
      contexts:
        - lint
        - security-scan (clamav)
        - security-scan (defender)
        - virustotal
    required_pull_request_reviews:
      required_approving_review_count: 2
      dismiss_stale_reviews: true
    enforce_admins: true
    restrictions:
      users: ["security-team"]
```

### 4. Dependabot for Bucket Updates

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
  
  # Custom ecosystem for Scoop manifests
  - package-ecosystem: "docker"  # Workaround
    directory: "/bucket"
    schedule:
      interval: "daily"
    labels:
      - "dependencies"
      - "scoop-manifest"
```

### 5. Security Scanning with GitHub Advanced Security

```yaml
# .github/workflows/codeql.yml
name: "CodeQL"

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  analyze:
    runs-on: windows-latest
    permissions:
      security-events: write
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: github/codeql-action/init@v3
        with:
          languages: 'powershell'
      
      - uses: github/codeql-action/analyze@v3
```

## Helper Scripts

### Check for Updates (Python)

```python
# scripts/check-updates.py
#!/usr/bin/env python3
import json
import requests
import subprocess
from pathlib import Path

def check_package_updates():
    bucket_path = Path("bucket")
    updates = []
    
    for manifest_file in bucket_path.glob("*.json"):
        with open(manifest_file) as f:
            manifest = json.load(f)
        
        package_name = manifest_file.stem
        current_version = manifest.get("version")
        
        # Check for updates (example with checkver)
        if "checkver" in manifest:
            checkver = manifest["checkver"]
            if "url" in checkver:
                try:
                    response = requests.get(checkver["url"])
                    # Parse version from response
                    # ... version parsing logic ...
                    new_version = "1.2.3"  # Example
                    
                    if new_version != current_version:
                        updates.append({
                            "name": package_name,
                            "version": new_version,
                            "url": manifest["architecture"]["64bit"]["url"].replace(current_version, new_version)
                        })
                except Exception as e:
                    print(f"Error checking {package_name}: {e}")
    
    print(json.dumps({"include": updates}))

if __name__ == "__main__":
    check_package_updates()
```

## Comparison: GitHub Actions vs GitLab CI

| Feature | GitHub Actions | GitLab CI |
|---------|---------------|-----------|
| **Pricing** | Free for public repos, 2000 min/month for private | Free for public, 400 min/month for private |
| **Windows Runners** | Yes (windows-latest) | Yes (with tags) |
| **Secret Management** | Repository/Organization secrets | CI/CD Variables |
| **Manual Approval** | Via Environments | Via `when: manual` |
| **Artifact Storage** | 90 days default | 30 days default |
| **Package Registry** | GitHub Packages | GitLab Package Registry |
| **Security Scanning** | Advanced Security (paid) | Built-in SAST/DAST |
| **Matrix Builds** | Native support | Via parallel keyword |
| **Caching** | actions/cache | cache keyword |
| **Marketplace** | GitHub Marketplace | GitLab templates |

## Best Practices for GitHub Actions

1. **Use Environments** for staging/production separation
2. **Enable Required Status Checks** in branch protection
3. **Use OIDC** for cloud deployments (no long-lived secrets)
4. **Cache dependencies** (ClamAV signatures, packages)
5. **Use Composite Actions** for reusable workflows
6. **Enable Dependabot** for automatic updates
7. **Use GitHub Packages** for artifact storage
8. **Implement CODEOWNERS** for approval workflows
9. **Use workflow_dispatch** for manual triggers
10. **Monitor with GitHub Insights** and API

---
[Main](README.md)
---
