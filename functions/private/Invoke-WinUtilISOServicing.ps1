function Get-WinUtilISOComponents {
    <#
    .SYNOPSIS
        The parts of Windows the Win11 Creator can take out of an image, by checkbox key

    .DESCRIPTION
        Packages are provisioned AppX names matched as prefixes, so a renamed build of the same
        app still matches. OneDrive is not an AppX package; it is handled on its own.
    #>
    [ordered]@{
        Copilot   = @("Microsoft.Copilot", "Microsoft.Windows.Ai.Copilot.Provider")
        Widgets   = @("MicrosoftWindows.Client.WebExperience")
        Xbox      = @("Microsoft.GamingApp", "Microsoft.XboxApp", "Microsoft.XboxGamingOverlay", "Microsoft.XboxGameOverlay",
                      "Microsoft.XboxIdentityProvider", "Microsoft.XboxSpeechToTextOverlay", "Microsoft.Xbox.TCUI")
        Cortana   = @("Microsoft.549981C3F5F10")
        Teams     = @("MSTeams", "MicrosoftTeams")
        OneDrive  = @()
        Outlook   = @("Microsoft.OutlookForWindows", "microsoft.windowscommunicationsapps")
        Bing      = @("Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.BingSearch")
        PhoneLink = @("Microsoft.YourPhone")
        Clipchamp = @("Clipchamp.Clipchamp")
        Solitaire = @("Microsoft.MicrosoftSolitaireCollection")
        Feedback  = @("Microsoft.WindowsFeedbackHub", "Microsoft.GetHelp", "Microsoft.Getstarted")
        Maps      = @("Microsoft.WindowsMaps")
    }
}

function Invoke-WinUtilISOServicing {
    <#
    .SYNOPSIS
        Changes the install image itself: keeps one edition, adds updates, removes parts of
        Windows and turns on optional features

    .DESCRIPTION
        Works on the copied install image, never the user's ISO. An install.esd cannot be
        serviced, so it is exported to install.wim first, which also happens when only one
        edition is kept. Each update, removal and feature is tried on its own and a failure is
        a warning, so one package that does not fit this build does not cost the whole image.

        Returns the image path and index that later steps (answer file, drivers) must use.

    .PARAMETER Features
        Optional feature names for DISM, such as NetFx3 or Microsoft-Hyper-V-All
    #>
    param(
        [Parameter(Mandatory)][string]$ISOContentsDir,
        [Parameter(Mandatory)][string]$InstallImagePath,
        [Parameter(Mandatory)][int]$InstallImageIndex,
        [bool]$SingleEdition = $false,
        [string[]]$UpdatePackages = @(),
        [string[]]$RemoveComponents = @(),
        [string[]]$Features = @(),
        [scriptblock]$Log = { param($m) Write-Output $m }
    )

    function Invoke-WinUtilISOServicingDism {
        param([Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$Operation)

        $output = @(& dism.exe /English @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $detail = @($output | Where-Object { "$_".Trim() } | Select-Object -Last 3) -join " "
            throw "DISM $Operation failed with exit code $LASTEXITCODE. $detail"
        }
        return $output
    }

    $sourcesDir = Join-Path $ISOContentsDir "sources"
    $needsMount = $UpdatePackages.Count -gt 0 -or $RemoveComponents.Count -gt 0 -or $Features.Count -gt 0
    $isEsd = [IO.Path]::GetExtension($InstallImagePath) -eq ".esd"

    if ($SingleEdition -or ($isEsd -and $needsMount)) {
        if ($isEsd -and -not $SingleEdition) {
            & $Log "install.esd cannot be changed in place, so only the selected edition is kept."
        }
        & $Log "Keeping only the selected edition (index $InstallImageIndex). This takes several minutes..."
        $exported = Join-Path (Split-Path $ISOContentsDir -Parent) "install_export.wim"
        Invoke-WinUtilISOServicingDism -Operation "export" -Arguments @(
            "/Export-Image", "/SourceImageFile:$InstallImagePath", "/SourceIndex:$InstallImageIndex",
            "/DestinationImageFile:$exported", "/Compress:max", "/CheckIntegrity") | Out-Null

        Remove-Item -LiteralPath $InstallImagePath -Force
        $InstallImagePath = Join-Path $sourcesDir "install.wim"
        Move-Item -LiteralPath $exported -Destination $InstallImagePath -Force
        $InstallImageIndex = 1
        & $Log "The image now holds one edition."
    }

    if ($needsMount) {
        $mountDir = Join-Path (Split-Path $ISOContentsDir -Parent) "service_mount"
        New-Item -ItemType Directory -Path $mountDir -Force | Out-Null
        Set-ItemProperty -LiteralPath $InstallImagePath -Name IsReadOnly -Value $false
        $mounted = $false
        $committed = $false

        try {
            & $Log "Mounting the image to change it..."
            Invoke-WinUtilISOServicingDism -Operation "mount" -Arguments @(
                "/Mount-Image", "/ImageFile:$InstallImagePath", "/Index:$InstallImageIndex", "/MountDir:$mountDir") | Out-Null
            $mounted = $true

            foreach ($package in $UpdatePackages) {
                & $Log "Adding update $(Split-Path $package -Leaf). Large updates take a while..."
                try {
                    Invoke-WinUtilISOServicingDism -Operation "add-package" -Arguments @(
                        "/Image:$mountDir", "/Add-Package", "/PackagePath:$package") | Out-Null
                    & $Log "Added $(Split-Path $package -Leaf)."
                } catch {
                    & $Log "Warning: could not add $(Split-Path $package -Leaf): $_"
                }
            }

            if ($RemoveComponents.Count -gt 0) {
                $components = Get-WinUtilISOComponents
                $provisioned = @()
                try {
                    $provisioned = @(Invoke-WinUtilISOServicingDism -Operation "list-apps" -Arguments @(
                            "/Image:$mountDir", "/Get-ProvisionedAppxPackages") |
                        ForEach-Object { if ("$_" -match '^PackageName\s*:\s*(\S+)') { $Matches[1] } })
                } catch {
                    & $Log "Warning: could not list the apps in the image, so none were removed: $_"
                }

                foreach ($key in $RemoveComponents) {
                    if ($key -eq "OneDrive") {
                        $setup = Join-Path $mountDir "Windows\System32\OneDriveSetup.exe"
                        if (Test-Path -LiteralPath $setup) {
                            takeown.exe /F $setup /A 2>&1 | Out-Null
                            icacls.exe $setup /grant "*S-1-5-32-544:F" 2>&1 | Out-Null
                            Remove-Item -LiteralPath $setup -Force -ErrorAction SilentlyContinue
                        }
                        # New accounts start the OneDrive installer from the default profile's Run key
                        $hive = "HKLM\OptimizeISODefault"
                        reg.exe load $hive (Join-Path $mountDir "Users\Default\NTUSER.DAT") 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            reg.exe delete "$hive\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDriveSetup /f 2>&1 | Out-Null
                            [GC]::Collect()
                            reg.exe unload $hive 2>&1 | Out-Null
                        }
                        if (Test-Path -LiteralPath $setup) {
                            & $Log "Warning: could not remove the OneDrive installer from the image."
                        } else {
                            & $Log "Removed OneDrive."
                        }
                        continue
                    }

                    $prefixes = $components[$key]
                    if (-not $prefixes) {
                        & $Log "Warning: '$key' is not something the creator knows how to remove."
                        continue
                    }
                    $matched = @($provisioned | Where-Object { $name = $_; $prefixes | Where-Object { $name -like "$($_)_*" } })
                    if ($matched.Count -eq 0) {
                        & $Log "$key is not in this image, nothing to remove."
                        continue
                    }
                    foreach ($packageName in $matched) {
                        try {
                            Invoke-WinUtilISOServicingDism -Operation "remove-app" -Arguments @(
                                "/Image:$mountDir", "/Remove-ProvisionedAppxPackage", "/PackageName:$packageName") | Out-Null
                        } catch {
                            & $Log "Warning: could not remove ${packageName}: $_"
                        }
                    }
                    & $Log "Removed $key ($($matched.Count) package(s))."
                }

                if ($RemoveComponents -contains "Widgets") {
                    # Without the policy the taskbar keeps an empty Widgets button
                    $hive = "HKLM\OptimizeISOSoftware"
                    reg.exe load $hive (Join-Path $mountDir "Windows\System32\config\SOFTWARE") 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        reg.exe add "$hive\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f 2>&1 | Out-Null
                        [GC]::Collect()
                        reg.exe unload $hive 2>&1 | Out-Null
                    }
                }
            }

            foreach ($feature in $Features) {
                & $Log "Turning on $feature..."
                $arguments = @("/Image:$mountDir", "/Enable-Feature", "/FeatureName:$feature", "/All")
                if ($feature -eq "NetFx3") {
                    # .NET 3.5 is not in the image itself; the ISO carries it in sources\sxs
                    $arguments += @("/Source:$(Join-Path $sourcesDir 'sxs')", "/LimitAccess")
                }
                try {
                    Invoke-WinUtilISOServicingDism -Operation "enable-feature" -Arguments $arguments | Out-Null
                    & $Log "Turned on $feature."
                } catch {
                    & $Log "Warning: could not turn on $feature (it may not exist in this edition): $_"
                }
            }

            & $Log "Saving the changed image. This takes several minutes..."
            Invoke-WinUtilISOServicingDism -Operation "commit" -Arguments @("/Unmount-Image", "/MountDir:$mountDir", "/Commit") | Out-Null
            $committed = $true
            & $Log "Image saved."
        } finally {
            if ($mounted -and -not $committed) {
                & dism.exe /English /Unmount-Image "/MountDir:$mountDir" /Discard 2>&1 | Out-Null
            }
            Remove-Item -LiteralPath $mountDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    return [pscustomobject]@{ ImagePath = $InstallImagePath; ImageIndex = $InstallImageIndex }
}
