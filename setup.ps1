Clear-Host
# GitHub Script Runner - Token Setup
# Author: Filip Fronczak
# Version: 1.0.1
# Date: 2024-12-08
# Public setup script for configuring GitHub token authentication
# Repository: https://github.com/Wolfsberg/ScriptRunner

Write-Host "`n" -NoNewline
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "GitHub Script Runner - Token Setup" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

Write-Host "`nThis script will securely configure your GitHub token for script execution."
Write-Host "Your token will be encrypted and stored locally at:"
Write-Host "  $env:USERPROFILE\.github-token.xml`n" -ForegroundColor Gray

# Warning for security awareness
Write-Host "SECURITY NOTICE:" -ForegroundColor Yellow
Write-Host "  - This script does NOT send your token anywhere" -ForegroundColor Gray
Write-Host "  - Token is encrypted and stored ONLY on this machine" -ForegroundColor Gray
Write-Host "  - You can review this script at:" -ForegroundColor Gray
Write-Host "    https://github.com/Wolfsberg/ScriptRunner/blob/main/setup.ps1`n" -ForegroundColor Gray

# Prompt for token
Write-Host "Enter your GitHub Personal Access Token (PAT):" -ForegroundColor Yellow
Write-Host "(Input will be hidden for security)" -ForegroundColor Gray
Write-Host "Token: " -NoNewline -ForegroundColor Yellow
$tokenSecure = Read-Host -AsSecureString

if ($tokenSecure.Length -eq 0) {
    Write-Host "`nError: No token provided. Setup cancelled.`n" -ForegroundColor Red
    exit 1
}

Write-Host "`nStoring token..." -NoNewline

try {
    # Create directory if it doesn't exist
    $tokenDir = Split-Path $env:USERPROFILE\.github-token.xml
    if (-not (Test-Path $tokenDir)) {
        New-Item -ItemType Directory -Path $tokenDir -Force | Out-Null
    }
    
    # Store encrypted token
    $tokenSecure | Export-Clixml -Path "$env:USERPROFILE\.github-token.xml" -Force
    Write-Host " OK" -ForegroundColor Green
    
    # Test token validity
    Write-Host "Testing token..." -NoNewline
    
    # Convert SecureString to plain text for testing
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenSecure)
    $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    
    $headers = @{
        Authorization = "token $plainToken"
        Accept = "application/vnd.github.v3+json"
    }
    
    # Test authentication
    $testResult = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method Get -ErrorAction Stop
    Write-Host " OK" -ForegroundColor Green
    Write-Host "Authenticated as: $($testResult.login)" -ForegroundColor Gray
    
    # Test ScriptRunner repository access
    Write-Host "Testing ScriptRunner access..." -NoNewline
    try {
        $repoTest = Invoke-RestMethod -Uri "https://api.github.com/repos/Wolfsberg/ScriptRunner" -Headers $headers -Method Get -ErrorAction Stop
        Write-Host " OK" -ForegroundColor Green
        Write-Host "Repository: $($repoTest.full_name)" -ForegroundColor Gray
    }
    catch {
        Write-Host " WARNING" -ForegroundColor Yellow
        Write-Host "Cannot access Wolfsberg/ScriptRunner repository." -ForegroundColor Yellow
        Write-Host "Your token may not have access to required repositories.`n" -ForegroundColor Yellow
    }
    
    # List accessible repositories
    Write-Host "`nChecking accessible repositories..." -NoNewline
    try {
        $repos = Invoke-RestMethod -Uri "https://api.github.com/user/repos?per_page=100&affiliation=owner,collaborator,organization_member" -Headers $headers -Method Get -ErrorAction Stop
        $scriptRepos = $repos | Where-Object { $_.name -ne "ScriptRunner" }
        Write-Host " OK" -ForegroundColor Green
        
        if ($scriptRepos.Count -gt 0) {
            Write-Host "`nAccessible script repositories:" -ForegroundColor Cyan
            $scriptRepos | ForEach-Object {
                $privacy = if ($_.private) { "[Private]" } else { "[Public]" }
                Write-Host "  $privacy $($_.full_name)" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "`nWARNING: No script repositories accessible." -ForegroundColor Yellow
            Write-Host "Contact your administrator for access to script repositories." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host " WARNING" -ForegroundColor Yellow
        Write-Host "Could not list repositories." -ForegroundColor Yellow
    }
    
    Write-Host "`n" -NoNewline
    Write-Host ("=" * 80) -ForegroundColor Green
    Write-Host "Setup complete!" -ForegroundColor Green
    Write-Host ("=" * 80) -ForegroundColor Green
    
    # Check if run.ps1 exists locally
    if (Test-Path ".\run.ps1") {
        Write-Host "`nYou can now run scripts with: .\run.ps1`n" -ForegroundColor Cyan
    }
    else {
        Write-Host "`nNext steps:" -ForegroundColor Cyan
        Write-Host "  1. Download run.ps1 from ScriptRunner repository" -ForegroundColor Gray
        Write-Host "  2. Run: .\run.ps1`n" -ForegroundColor Gray
    }
}
catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Message -like "*401*" -or $_.Exception.Message -like "*403*") {
        Write-Host "`nToken is invalid or doesn't have required permissions." -ForegroundColor Yellow
        Write-Host "Please verify:" -ForegroundColor Yellow
        Write-Host "  - Token is a valid GitHub Personal Access Token" -ForegroundColor Gray
        Write-Host "  - Token has 'Contents: Read' permission" -ForegroundColor Gray
        Write-Host "  - Token has access to required repositories`n" -ForegroundColor Gray
    }
    elseif ($_.Exception.Message -like "*404*") {
        Write-Host "`nRepository not found or token doesn't have access.`n" -ForegroundColor Yellow
    }
    
    exit 1
}
