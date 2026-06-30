<#
.SYNOPSIS
Interactive Chocolatey package manager with install, uninstall, and upgrade capabilities.

.DESCRIPTION
This script provides a GUI-based Chocolatey package manager that:
- Checks for Chocolatey installation
- Displays current installation status of all packages
- Allows installing new packages
- Allows uninstalling existing packages (with confirmation)
- Checks for available upgrades and offers to update packages
Packages are organized by categories: Browsers, Office Apps, Admin Apps and Utils, Runtimes.
Compatible with Chocolatey v2.6.0+.

.VERSION
3.3.0

.DATE
2026-06-30

.AUTHOR
Filip Fronczak
#>

Clear-Host

#region Chocolatey Installation Check
# Checks if Chocolatey is installed and offers installation if missing
function Test-ChocolateyInstalled {
    $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
    if ($chocoCmd) {
        Write-Host "Chocolatey is already installed." -ForegroundColor Green
        Write-Host "Version: " -NoNewline
        choco --version
        return $true
    }
    return $false
}

# Installs Chocolatey using the official installation script
function Install-Chocolatey {
    Write-Host "`nChocolatey is not installed on this system." -ForegroundColor Yellow
    $response = Read-Host "Do you want to install Chocolatey now? (Y/N)"
    
    if ($response -eq 'Y' -or $response -eq 'y') {
        Write-Host "`nInstalling Chocolatey..." -ForegroundColor Cyan
        try {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            Write-Host "Chocolatey installed successfully!" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "Error installing Chocolatey: $_" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "Chocolatey installation cancelled. Cannot proceed without Chocolatey." -ForegroundColor Red
        return $false
    }
}

# Gets currently installed packages from the package list
function Get-InstalledPackages {
    param (
        [hashtable]$PackageList
    )
    
    Write-Host "Checking installed packages..." -ForegroundColor Cyan
    
    $installedPackages = @()
    $allPackages = @()
    
    # Flatten package list
    foreach ($category in $PackageList.Keys) {
        $allPackages += $PackageList[$category]
    }
    
    # Get all locally installed packages (--local-only removed in Choco 2.6.0)
    $chocoListOutput = choco list 2>&1 | Out-String
    
    # Parse the output line by line
    $lines = $chocoListOutput -split "`r?`n"
    
    # Check each package from our list against the choco output
    foreach ($package in $allPackages) {
        foreach ($line in $lines) {
            # Trim the line
            $line = $line.Trim()
            
            # Skip empty lines and headers/footers
            if ([string]::IsNullOrWhiteSpace($line) -or 
                $line -match "^Chocolatey" -or 
                $line -match "packages installed" -or
                $line -match "Validation Warnings:") {
                continue
            }
            
            # Match lines that start with package name followed by space and version
            if ($line -match "^$package\s+[0-9]") {
                $installedPackages += $package
                break
            }
        }
    }
    
    Write-Host "Found $($installedPackages.Count) installed packages from the list." -ForegroundColor Green
    
    return $installedPackages
}

# Checks for available upgrades
function Get-AvailableUpgrades {
    param (
        [string[]]$InstalledPackages
    )
    
    if ($InstalledPackages.Count -eq 0) {
        return @()
    }
    
    Write-Host "Checking for available upgrades..." -ForegroundColor Cyan
    
    $upgradeablePackages = @()
    
    # Check for outdated packages
    $outdatedOutput = choco outdated --limit-output 2>&1 | Out-String
    
    foreach ($package in $InstalledPackages) {
        if ($outdatedOutput -match "$package\|") {
            $upgradeablePackages += $package
        }
    }
    
    if ($upgradeablePackages.Count -gt 0) {
        Write-Host "Found $($upgradeablePackages.Count) packages with available upgrades." -ForegroundColor Yellow
    }
    else {
        Write-Host "All packages are up to date." -ForegroundColor Green
    }
    
    return $upgradeablePackages
}
#endregion

#region Package Selection GUI
# Creates and displays a GUI for package selection with categories and installation status
function Show-PackageSelectionGUI {
    param (
        [hashtable]$PackageList,
        [string[]]$InstalledPackages = @(),
        [string[]]$UpgradeablePackages = @()
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Enable visual styles for better rendering
    [System.Windows.Forms.Application]::EnableVisualStyles()
    
    # Get DPI scaling factor
    $graphics = [System.Drawing.Graphics]::FromHwnd([System.IntPtr]::Zero)
    $dpiX = $graphics.DpiX
    $scaleFactor = $dpiX / 96.0
    $graphics.Dispose()
    
    # Scale function
    function Scale([int]$value) {
        return [int]($value * $scaleFactor)
    }
    
    # Create form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Chocolatey Package Manager"
    $form.Size = New-Object System.Drawing.Size($(Scale 550), $(Scale 750))
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    
    # Title label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point($(Scale 10), $(Scale 10))
    $titleLabel.Size = New-Object System.Drawing.Size($(Scale 510), $(Scale 20))
    $titleLabel.Text = "Select packages (Checked = Installed, Unchecked = Not Installed)"
    $titleLabel.Font = New-Object System.Drawing.Font("Arial", $(Scale 10), [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($titleLabel)
    
    # Status label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point($(Scale 10), $(Scale 35))
    $statusLabel.Size = New-Object System.Drawing.Size($(Scale 510), $(Scale 20))
    $statusLabel.Text = "Installed: $($InstalledPackages.Count) | Upgrades available: $($UpgradeablePackages.Count)"
    $statusLabel.ForeColor = [System.Drawing.Color]::DarkBlue
    $form.Controls.Add($statusLabel)
    
    # Checklist box for packages
    $checklistBox = New-Object System.Windows.Forms.CheckedListBox
    $checklistBox.Location = New-Object System.Drawing.Point($(Scale 10), $(Scale 60))
    $checklistBox.Size = New-Object System.Drawing.Size($(Scale 510), $(Scale 520))
    $checklistBox.CheckOnClick = $true
    $checklistBox.Font = New-Object System.Drawing.Font("SansSerif", $(Scale 12))
    
    # Track category header indices
    $headerIndices = @()
    
    # Add packages by category
    foreach ($category in @("Browsers", "Office Apps", "Admin Apps and Utils", "Runtimes")) {
        if ($PackageList.ContainsKey($category)) {
            # Add category header
            $headerIndex = $checklistBox.Items.Add("─── $category ───")
            $headerIndices += $headerIndex
            
            # Add packages in this category (sorted)
            foreach ($package in ($PackageList[$category] | Sort-Object)) {
                $displayName = "  $package"
                
                # Add upgrade indicator
                if ($package -in $UpgradeablePackages) {
                    $displayName += " [UPGRADE AVAILABLE]"
                }
                
                $index = $checklistBox.Items.Add($displayName)
                
                # Pre-check if installed
                if ($package -in $InstalledPackages) {
                    $checklistBox.SetItemChecked($index, $true)
                }
            }
            
            # Add blank line for spacing (except after last category)
            if ($category -ne "Runtimes") {
                $spacerIndex = $checklistBox.Items.Add("")
                $headerIndices += $spacerIndex
            }
        }
    }
    
    # Prevent checking/unchecking header items
    $checklistBox.Add_ItemCheck({
        param($sender, $e)
        if ($e.Index -in $headerIndices) {
            $e.NewValue = [System.Windows.Forms.CheckState]::Unchecked
        }
    })
    
    $form.Controls.Add($checklistBox)
    
    # Select All button
    $selectAllButton = New-Object System.Windows.Forms.Button
    $selectAllButton.Location = New-Object System.Drawing.Point($(Scale 10), $(Scale 590))
    $selectAllButton.Size = New-Object System.Drawing.Size($(Scale 100), $(Scale 30))
    $selectAllButton.Text = "Select All"
    $selectAllButton.Font = New-Object System.Drawing.Font("Arial", $(Scale 9))
    $selectAllButton.Add_Click({
        for ($i = 0; $i -lt $checklistBox.Items.Count; $i++) {
            if ($i -notin $headerIndices) {
                $checklistBox.SetItemChecked($i, $true)
            }
        }
    })
    $form.Controls.Add($selectAllButton)
    
    # Clear All button
    $clearAllButton = New-Object System.Windows.Forms.Button
    $clearAllButton.Location = New-Object System.Drawing.Point($(Scale 120), $(Scale 590))
    $clearAllButton.Size = New-Object System.Drawing.Size($(Scale 100), $(Scale 30))
    $clearAllButton.Text = "Clear All"
    $clearAllButton.Font = New-Object System.Drawing.Font("Arial", $(Scale 9))
    $clearAllButton.Add_Click({
        for ($i = 0; $i -lt $checklistBox.Items.Count; $i++) {
            if ($i -notin $headerIndices) {
                $checklistBox.SetItemChecked($i, $false)
            }
        }
    })
    $form.Controls.Add($clearAllButton)
    
    # Upgrade All button
    $upgradeAllButton = New-Object System.Windows.Forms.Button
    $upgradeAllButton.Location = New-Object System.Drawing.Point($(Scale 230), $(Scale 590))
    $upgradeAllButton.Size = New-Object System.Drawing.Size($(Scale 120), $(Scale 30))
    $upgradeAllButton.Text = "Upgrade All"
    $upgradeAllButton.Font = New-Object System.Drawing.Font("Arial", $(Scale 9))
    if ($UpgradeablePackages.Count -eq 0) {
        $upgradeAllButton.Enabled = $false
    }
    $form.Controls.Add($upgradeAllButton)
    
    # Auto-confirm checkbox
    $autoConfirmCheckbox = New-Object System.Windows.Forms.CheckBox
    $autoConfirmCheckbox.Location = New-Object System.Drawing.Point($(Scale 10), $(Scale 630))
    $autoConfirmCheckbox.Size = New-Object System.Drawing.Size($(Scale 300), $(Scale 20))
    $autoConfirmCheckbox.Text = "Auto-confirm installations (use -y switch)"
    $autoConfirmCheckbox.Font = New-Object System.Drawing.Font("Arial", $(Scale 9))
    $autoConfirmCheckbox.Checked = $true
    $form.Controls.Add($autoConfirmCheckbox)
    
    # Apply Changes button
    $applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Location = New-Object System.Drawing.Point($(Scale 270), $(Scale 660))
    $applyButton.Size = New-Object System.Drawing.Size($(Scale 120), $(Scale 30))
    $applyButton.Text = "Apply Changes"
    $applyButton.Font = New-Object System.Drawing.Font("Arial", $(Scale 9), [System.Drawing.FontStyle]::Bold)
    $applyButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $applyButton
    $form.Controls.Add($applyButton)
    
    # Cancel button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point($(Scale 400), $(Scale 660))
    $cancelButton.Size = New-Object System.Drawing.Size($(Scale 100), $(Scale 30))
    $cancelButton.Text = "Cancel"
    $cancelButton.Font = New-Object System.Drawing.Font("Arial", $(Scale 9))
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)
    
    # Handle Upgrade All button click
    $upgradeAllButton.Add_Click({
        $form.Tag = "UpgradeAll"
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $form.Close()
    })
    
    # Show form and get results
    $result = $form.ShowDialog()
    
    # Handle Upgrade All
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes -and $form.Tag -eq "UpgradeAll") {
        return @{
            Action = "UpgradeAll"
            Packages = $UpgradeablePackages
            UseAutoConfirm = $autoConfirmCheckbox.Checked
        }
    }
    
    # Handle Apply Changes
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedPackages = @()
        foreach ($item in $checklistBox.CheckedItems) {
            # Extract package name (remove leading spaces and upgrade indicator)
            $packageName = $item.ToString().Trim() -replace ' \[UPGRADE AVAILABLE\]$', ''
            # Skip headers and empty items
            if ($packageName -ne "" -and -not $packageName.StartsWith("───")) {
                $selectedPackages += $packageName
            }
        }
        
        return @{
            Action = "ApplyChanges"
            SelectedPackages = $selectedPackages
            InstalledPackages = $InstalledPackages
            UseAutoConfirm = $autoConfirmCheckbox.Checked
        }
    }
    
    return $null
}
#endregion

#region Package Installation
# Installs selected Chocolatey packages in a single command and parses results
function Install-ChocoPackages {
    param (
        [string[]]$Packages,
        [bool]$AutoConfirm,
        [bool]$IgnoreChecksum = $false
    )
    
    $installResults = @{
        Success = @()
        Failed = @()
        ChecksumErrors = @()
        AlreadyInstalled = @()
    }
    
    if ($Packages.Count -eq 0) {
        return $installResults
    }
    
    # Build command arguments
    $arguments = @("install")
    if ($AutoConfirm) {
        $arguments += "-y"
    }
    if ($IgnoreChecksum) {
        $arguments += "--ignore-checksums"
    }
    $arguments += $Packages
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Starting package installation..." -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "Installing: $($Packages -join ', ')" -ForegroundColor Yellow
    Write-Host "Command: choco $($arguments -join ' ')" -ForegroundColor Gray
    Write-Host ""
    
    try {
        # Execute choco and stream its output to the console line by line as it
        # is produced, while accumulating the full text into $output so the
        # per-package result parsing below still has the complete log to work with
        $output = & choco $arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            Write-Host $line
            $line
        } | Out-String
        
        # Parse output for each package
        foreach ($package in $Packages) {
            # Check if already installed (highest priority check)
            if ($output -match "$package.*already installed") {
                $installResults.AlreadyInstalled += $package
            }
            # Check for checksum errors
            elseif ($output -match "$package.*checksum|hash.*$package" -and $output -match "error|failed|mismatch") {
                $installResults.ChecksumErrors += $package
                $installResults.Failed += $package
            }
            # Check if this package was newly installed
            elseif ($output -match "$package.*has been installed" -or $output -match "installed $package") {
                $installResults.Success += $package
            }
            # Check for explicit failure messages
            elseif ($output -match "$package.*(failed|error)" -or $output -match "(failed|error).*$package") {
                $installResults.Failed += $package
            }
            # If we can't determine, mark as unknown/failed
            else {
                # Check the summary line to see if it was counted
                if ($output -match "installed (\d+)/(\d+) packages") {
                    # Will handle below
                }
                else {
                    $installResults.Failed += $package
                }
            }
        }
        
        # Display per-package results
        Write-Host ""
        foreach ($package in $Packages) {
            if ($package -in $installResults.Success) {
                Write-Host "[INSTALLED] $package" -ForegroundColor Green
            }
            elseif ($package -in $installResults.AlreadyInstalled) {
                Write-Host "[ALREADY INSTALLED] $package" -ForegroundColor Cyan
            }
            elseif ($package -in $installResults.ChecksumErrors) {
                Write-Host "[CHECKSUM ERROR] $package" -ForegroundColor Red
            }
            elseif ($package -in $installResults.Failed) {
                Write-Host "[FAILED] $package" -ForegroundColor Red
            }
            else {
                Write-Host "[UNKNOWN STATUS] $package" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "Error during installation: $_" -ForegroundColor Red
        # Mark all as failed if the command itself failed
        $installResults.Failed = $Packages
    }
    
    return $installResults
}

# Uninstalls selected Chocolatey packages
function Uninstall-ChocoPackages {
    param (
        [string[]]$Packages,
        [bool]$AutoConfirm
    )
    
    $uninstallResults = @{
        Success = @()
        Failed = @()
    }
    
    if ($Packages.Count -eq 0) {
        return $uninstallResults
    }
    
    # Build command arguments
    $arguments = @("uninstall")
    if ($AutoConfirm) {
        $arguments += "-y"
    }
    $arguments += $Packages
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Starting package uninstallation..." -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "Uninstalling: $($Packages -join ', ')" -ForegroundColor Yellow
    Write-Host "Command: choco $($arguments -join ' ')" -ForegroundColor Gray
    Write-Host ""
    
    try {
        # Execute choco and stream its output to the console line by line as it
        # is produced, while accumulating the full text into $output so the
        # per-package result parsing below still has the complete log to work with
        $output = & choco $arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            Write-Host $line
            $line
        } | Out-String
        
        # Parse output for each package
        foreach ($package in $Packages) {
            if ($output -match "$package.*has been (uninstalled|removed)" -or $output -match "(uninstalled|removed).*$package") {
                $uninstallResults.Success += $package
            }
            else {
                $uninstallResults.Failed += $package
            }
        }
        
        # Display per-package results
        Write-Host ""
        foreach ($package in $Packages) {
            if ($package -in $uninstallResults.Success) {
                Write-Host "[UNINSTALLED] $package" -ForegroundColor Green
            }
            else {
                Write-Host "[FAILED TO UNINSTALL] $package" -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host "Error during uninstallation: $_" -ForegroundColor Red
        $uninstallResults.Failed = $Packages
    }
    
    return $uninstallResults
}

# Upgrades selected Chocolatey packages
function Update-ChocoPackages {
    param (
        [string[]]$Packages,
        [bool]$AutoConfirm
    )
    
    $upgradeResults = @{
        Success = @()
        Failed = @()
        AlreadyLatest = @()
    }
    
    if ($Packages.Count -eq 0) {
        return $upgradeResults
    }
    
    # Build command arguments
    $arguments = @("upgrade")
    if ($AutoConfirm) {
        $arguments += "-y"
    }
    $arguments += $Packages
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Starting package upgrades..." -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "Upgrading: $($Packages -join ', ')" -ForegroundColor Yellow
    Write-Host "Command: choco $($arguments -join ' ')" -ForegroundColor Gray
    Write-Host ""
    
    try {
        # Execute choco and stream its output to the console line by line as it
        # is produced, while accumulating the full text into $output so the
        # per-package result parsing below still has the complete log to work with
        $output = & choco $arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            Write-Host $line
            $line
        } | Out-String
        
        # Parse output for each package
        foreach ($package in $Packages) {
            if ($output -match "$package.*upgraded|$package.*has been upgraded") {
                $upgradeResults.Success += $package
            }
            elseif ($output -match "$package.*is the latest version available") {
                $upgradeResults.AlreadyLatest += $package
            }
            else {
                $upgradeResults.Failed += $package
            }
        }
        
        # Display per-package results
        Write-Host ""
        foreach ($package in $Packages) {
            if ($package -in $upgradeResults.Success) {
                Write-Host "[UPGRADED] $package" -ForegroundColor Green
            }
            elseif ($package -in $upgradeResults.AlreadyLatest) {
                Write-Host "[ALREADY LATEST] $package" -ForegroundColor Cyan
            }
            else {
                Write-Host "[FAILED TO UPGRADE] $package" -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host "Error during upgrade: $_" -ForegroundColor Red
        $upgradeResults.Failed = $Packages
    }
    
    return $upgradeResults
}

# Verifies installed packages
function Confirm-InstalledPackages {
    param (
        [string[]]$Packages
    )
    
    Write-Host "`nVerifying installed packages..." -ForegroundColor Cyan
    
    $verifiedPackages = @()
    $notFoundPackages = @()
    
    # Get all locally installed packages (--local-only removed in Choco 2.6.0)
    $chocoListOutput = choco list 2>&1 | Out-String
    $lines = $chocoListOutput -split "`r?`n"
    
    foreach ($package in $Packages) {
        $found = $false
        foreach ($line in $lines) {
            # Trim the line
            $line = $line.Trim()
            
            # Skip empty lines and headers/footers
            if ([string]::IsNullOrWhiteSpace($line) -or 
                $line -match "^Chocolatey" -or 
                $line -match "packages installed" -or
                $line -match "Validation Warnings:") {
                continue
            }
            
            # Match lines that start with package name followed by space and version
            if ($line -match "^$package\s+[0-9]") {
                $verifiedPackages += $package
                $found = $true
                Write-Host "[OK] $package" -ForegroundColor Green
                break
            }
        }
        
        if (-not $found) {
            $notFoundPackages += $package
            Write-Host "[NOT FOUND] $package" -ForegroundColor Red
        }
    }
    
    return @{
        Verified = $verifiedPackages
        NotFound = $notFoundPackages
    }
}
#endregion

#region Main Script
# Main execution flow
function Main {
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "WARNING: This script should be run as Administrator for best results." -ForegroundColor Yellow
        $continue = Read-Host "Continue anyway? (Y/N)"
        if ($continue -ne 'Y' -and $continue -ne 'y') {
            Write-Host "Script cancelled." -ForegroundColor Red
            return
        }
    }
    
    # Check and install Chocolatey if needed
    if (-not (Test-ChocolateyInstalled)) {
        if (-not (Install-Chocolatey)) {
            Write-Host "`nScript terminated." -ForegroundColor Red
            return
        }
    }
    
    # Define package list organized by categories
    $packageList = @{
        "Browsers" = @(
            "Brave",
            "GoogleChrome",
            "Microsoft-Edge"
        )
        "Office Apps" = @(
            "AdobeReader",
            "Office365business",
            "Onlyoffice",
            "PowerBI"
        )
        "Admin Apps and Utils" = @(
            "7zip.install",
            "Citrix-Workspace-LTSR",
            "git.install",
            "GoogleDrive",
            "NETworkManager",
            "NetRouteView",
            "NotepadPlusPlus.install",
            "OneDrive",
            "Putty.install",
            "SQL-Server-Management-Studio",
            "SysInternals",
            "TotalCommander",
            "VisualStudioCode",
            "vscode.install",
            "WinSCP.install",
            "WireShark"
        )
        "Runtimes" = @(
            "DotNet4.5",
            "DotNet4.5.2",
            "dotnet-8.0-desktopruntime",
            "dotnetfx",
            "msoledbsql",
            "netfx-4.8",
            "netfx-4.8.1",
            "sqlserver-odbcdriver-17",
            "vcredist140",
            "vcredist2017",
            "webview2-runtime"
        )
    }
    
    # Get currently installed packages from the list
    $installedPackages = Get-InstalledPackages -PackageList $packageList
    
    # Check for available upgrades
    $upgradeablePackages = Get-AvailableUpgrades -InstalledPackages $installedPackages
    
    # Show package selection GUI with current status
    Write-Host "`nLaunching package manager GUI..." -ForegroundColor Cyan
    $selection = Show-PackageSelectionGUI -PackageList $packageList -InstalledPackages $installedPackages -UpgradeablePackages $upgradeablePackages
    
    if ($null -eq $selection) {
        Write-Host "`nNo changes made. Script terminated." -ForegroundColor Yellow
        return
    }
    
    # Handle Upgrade All
    if ($selection.Action -eq "UpgradeAll") {
        Write-Host "`nUpgrading all packages with available updates..." -ForegroundColor Cyan
        $upgradeResults = Update-ChocoPackages -Packages $selection.Packages -AutoConfirm $selection.UseAutoConfirm
        
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Upgrade Summary" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        
        if ($upgradeResults.Success.Count -gt 0) {
            Write-Host "`nUpgraded ($($upgradeResults.Success.Count)):" -ForegroundColor Green
            $upgradeResults.Success | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
        }
        
        if ($upgradeResults.AlreadyLatest.Count -gt 0) {
            Write-Host "`nAlready latest ($($upgradeResults.AlreadyLatest.Count)):" -ForegroundColor Cyan
            $upgradeResults.AlreadyLatest | ForEach-Object { Write-Host "  = $_" -ForegroundColor Cyan }
        }
        
        if ($upgradeResults.Failed.Count -gt 0) {
            Write-Host "`nFailed upgrades ($($upgradeResults.Failed.Count)):" -ForegroundColor Red
            $upgradeResults.Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
        
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Upgrade process completed!" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan
        return
    }
    
    # Handle Apply Changes - determine what to install and uninstall
    $packagesToInstall = $selection.SelectedPackages | Where-Object { $_ -notin $selection.InstalledPackages }
    $packagesToUninstall = $selection.InstalledPackages | Where-Object { $_ -notin $selection.SelectedPackages }
    
    # Display planned changes
    if ($packagesToInstall.Count -eq 0 -and $packagesToUninstall.Count -eq 0) {
        Write-Host "`nNo changes detected." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`nPlanned changes:" -ForegroundColor Cyan
    if ($packagesToInstall.Count -gt 0) {
        Write-Host "`nPackages to INSTALL ($($packagesToInstall.Count)):" -ForegroundColor Green
        $packagesToInstall | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
    }
    
    if ($packagesToUninstall.Count -gt 0) {
        Write-Host "`nPackages to UNINSTALL ($($packagesToUninstall.Count)):" -ForegroundColor Yellow
        $packagesToUninstall | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    
    # Confirm uninstalls if any
    if ($packagesToUninstall.Count -gt 0) {
        Write-Host ""
        $confirmUninstall = Read-Host "Do you want to proceed with uninstalling the above packages? (Y/N)"
        if ($confirmUninstall -ne 'Y' -and $confirmUninstall -ne 'y') {
            Write-Host "`nUninstall cancelled. Only installation will proceed." -ForegroundColor Yellow
            $packagesToUninstall = @()
        }
    }
    
    # Execute installations
    $installResults = $null
    if ($packagesToInstall.Count -gt 0) {
        $installResults = Install-ChocoPackages -Packages $packagesToInstall -AutoConfirm $selection.UseAutoConfirm
    }
    
    # Execute uninstalls
    $uninstallResults = $null
    if ($packagesToUninstall.Count -gt 0) {
        $uninstallResults = Uninstall-ChocoPackages -Packages $packagesToUninstall -AutoConfirm $selection.UseAutoConfirm
    }
    
    # Display final summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Operation Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    if ($installResults) {
        if ($installResults.Success.Count -gt 0) {
            Write-Host "`nNewly installed ($($installResults.Success.Count)):" -ForegroundColor Green
            $installResults.Success | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
        }
        
        if ($installResults.AlreadyInstalled.Count -gt 0) {
            Write-Host "`nAlready installed ($($installResults.AlreadyInstalled.Count)):" -ForegroundColor Cyan
            $installResults.AlreadyInstalled | ForEach-Object { Write-Host "  = $_" -ForegroundColor Cyan }
        }
        
        if ($installResults.Failed.Count -gt 0) {
            Write-Host "`nFailed installations ($($installResults.Failed.Count)):" -ForegroundColor Red
            $installResults.Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
    }
    
    if ($uninstallResults) {
        if ($uninstallResults.Success.Count -gt 0) {
            Write-Host "`nUninstalled ($($uninstallResults.Success.Count)):" -ForegroundColor Green
            $uninstallResults.Success | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
        }
        
        if ($uninstallResults.Failed.Count -gt 0) {
            Write-Host "`nFailed uninstalls ($($uninstallResults.Failed.Count)):" -ForegroundColor Red
            $uninstallResults.Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
    }
    
    # Handle checksum errors AFTER all installations complete
    if ($installResults -and $installResults.ChecksumErrors.Count -gt 0) {
        Write-Host "`n========================================" -ForegroundColor Yellow
        Write-Host "Checksum Errors Detected" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "The following packages had checksum errors:" -ForegroundColor Yellow
        $installResults.ChecksumErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        
        $retry = Read-Host "`nDo you want to retry installation with --ignore-checksums? (Y/N)"
        if ($retry -eq 'Y' -or $retry -eq 'y') {
            Write-Host "`nRetrying failed packages with --ignore-checksums..." -ForegroundColor Cyan
            $retryResults = Install-ChocoPackages -Packages $installResults.ChecksumErrors -AutoConfirm $selection.UseAutoConfirm -IgnoreChecksum $true
            
            Write-Host "`n========================================" -ForegroundColor Cyan
            Write-Host "Retry Results" -ForegroundColor Cyan
            Write-Host "========================================" -ForegroundColor Cyan
            
            if ($retryResults.Success.Count -gt 0) {
                Write-Host "`nSuccessfully installed after retry ($($retryResults.Success.Count)):" -ForegroundColor Green
                $retryResults.Success | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
            }
            
            if ($retryResults.Failed.Count -gt 0) {
                Write-Host "`nStill failed ($($retryResults.Failed.Count)):" -ForegroundColor Red
                $retryResults.Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
            }
        }
    }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Process completed!" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

# Execute main function
Main
#endregion
