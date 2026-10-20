function Invoke-WPFInstall {
    <#
    .SYNOPSIS
        Installs the selected programs using winget, if one or more of the selected programs are already installed on the system, winget will try and perform an upgrade if there's a newer version to install.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [PSObject[]]$PackagesToInstall = $($sync.selectedApps | Foreach-Object { $sync.configs.applicationsHashtable.$_ })
    )

    if ($PackagesToInstall.Count -eq 0) {
        $WarningMsg = "Please select the program(s) to install or upgrade."
        Show-WinUtilMessage -Message $WarningMsg -Title "Optimize" -Button "OK" -Icon "Warning"
        return
    }

    $ManagerPreference = $sync.preferences.packagemanager

    # Apps that are only on Chocolatey need it installed even when winget is preferred. Ask
    # first, and offer to take Chocolatey back off once the install is done.
    $OfferChocoRemoval = $false
    $chocoOnly = @($PackagesToInstall | Where-Object {
        ([string]::IsNullOrWhiteSpace([string]$_.winget) -or $_.winget -eq "na") -and
            -not [string]::IsNullOrWhiteSpace([string]$_.choco) -and $_.choco -ne "na"
    })
    if ($ManagerPreference -ne "Choco" -and $chocoOnly.Count -gt 0 -and -not (Get-Command choco -ErrorAction SilentlyContinue)) {
        $names = ($chocoOnly | ForEach-Object { if ($_.content) { $_.content } else { $_.choco } }) -join ", "
        $answer = Show-WinUtilMessage -Title "Chocolatey needed" -Button "YesNo" -Icon "Warning" -Message (
            "$names is not on winget, only on Chocolatey.`n`n" +
            "To install $names, Optimize has to install Chocolatey first. If you don't want Chocolatey, $names can't be installed from here.`n`n" +
            "Install Chocolatey and continue?")

        if ($answer -eq "Yes") {
            $OfferChocoRemoval = $true
        } else {
            Write-WinUtilLog -Component "Install" -Message "Chocolatey declined, skipping: $names"
            $PackagesToInstall = @($PackagesToInstall | Where-Object { $chocoOnly -notcontains $_ })
            if ($PackagesToInstall.Count -eq 0) {
                return
            }
        }
    }

    Write-WinUtilLog -Component "Install" -Message "Install requested for $(@($PackagesToInstall).Count) selected package(s) using preference: $ManagerPreference"
    $packageSummary = Get-WinUtilPackageLogSummary -Packages $PackagesToInstall -Preference $ManagerPreference
    Write-WinUtilLog -Component "Install" -Message "Install selected package(s): $($packageSummary -join '; ')"

    Start-WinUtilJob -Name "Install" -Description "Installing apps" -DisableAppList -Parameters @{
        PackagesToInstall = $PackagesToInstall
        ManagerPreference = $ManagerPreference
        OfferChocoRemoval = $OfferChocoRemoval
    } -ScriptBlock {
        param($PackagesToInstall, $ManagerPreference, $OfferChocoRemoval)

        $packagesSorted = Get-WinUtilSelectedPackages -PackageList $PackagesToInstall -Preference $ManagerPreference
        $packagesWinget = $packagesSorted['Winget']
        $packagesChoco = $packagesSorted['Choco']
        $totalPackages = @($packagesWinget).Count + @($packagesChoco).Count
        $completedPackages = 0
        Write-WinUtilLog -Component "Install" -Message "Install package manager split: winget=$(@($packagesWinget).Count), choco=$(@($packagesChoco).Count)"

        $results = @()

        if ($packagesWinget.Count -gt 0 -and $packagesWinget -ne "0") {
            Install-WinUtilWinget
            foreach ($program in $packagesWinget) {
                $position = $completedPackages + 1
                Step-WinUtilJob -Status "Installing $program ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

                $results += Measure-WinUtilStep -Scope "Install" -Name "winget $program" -ScriptBlock {
                    Install-WinUtilProgramWinget -Action Install -Programs @($program)
                }
                $completedPackages++
                Step-WinUtilJob -Status "Installed $program ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
            }
        }

        if ($packagesChoco.Count -gt 0) {
            $position = $completedPackages + 1
            Step-WinUtilJob -Status "Installing Chocolatey packages ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

            Install-WinUtilChoco
            $chocoBase = [int](($completedPackages / $totalPackages) * 100)
            $chocoSpan = [int]((@($packagesChoco).Count / $totalPackages) * 100)
            $results += Measure-WinUtilStep -Scope "Install" -Name "choco $($packagesChoco -join ', ')" -ScriptBlock {
                Install-WinUtilProgramChoco -Action Install -Programs $packagesChoco -ProgressBase $chocoBase -ProgressSpan $chocoSpan
            }
            $completedPackages += @($packagesChoco).Count
            Step-WinUtilJob -Status "Installed Chocolatey packages ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
        }

        if ($OfferChocoRemoval) {
            $answer = Show-WinUtilMessage -Title "Remove Chocolatey?" -Button "YesNo" -Icon "Question" -Message (
                "Optimize installed Chocolatey only to get $($packagesChoco -join ', ').`n`n" +
                "Remove Chocolatey now? The apps stay installed. To update or uninstall them from Optimize later, Chocolatey has to be installed again (you can always uninstall them from Windows Settings).")
            if ($answer -eq "Yes") {
                Step-WinUtilJob -Status "Removing Chocolatey" -State "Indeterminate"
                Uninstall-WinUtilChoco
            }
        }

        Complete-WinUtilPackageRun -Action "Install" -Results $results
    }
}
