function Invoke-WPFDriverUpdates {
    <#
    .SYNOPSIS
        Finds driver updates on Windows Update, installs them if the user agrees, then opens
        the vendor driver apps that are installed

    .DESCRIPTION
        1. Windows Update - searches for drivers that are offered but not installed and lists
           them. Nothing is installed until the user says Yes.
        2. Vendor apps - NVIDIA App and Intel Driver & Support Assistant carry newer GPU and
           chipset drivers than Windows Update does, so they are opened for the user to check.
    #>

    Step-WinUtilJob -Status "Searching Windows Update for drivers (1/3)" -State "Indeterminate"
    Write-WinUtilLog -Component "Drivers" -Message "Searching Windows Update for driver updates"
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $search = $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    $drivers = @($search.Updates | ForEach-Object { $_ })

    $rebootRequired = $false
    if ($drivers.Count -eq 0) {
        Write-Host "Windows Update has no driver updates for this PC." -ForegroundColor Green
        Write-WinUtilLog -Component "Drivers" -Message "No driver updates offered"
    } else {
        $names = ($drivers | ForEach-Object { " - $($_.Title)" }) -join "`n"
        Write-WinUtilLog -Component "Drivers" -Message "Found $($drivers.Count) driver update(s):`n$names"
        $answer = Show-WinUtilMessage -Message "Windows Update found $($drivers.Count) driver update(s):`n`n$names`n`nInstall them now?" -Title "Driver updates" -Button "YesNo" -Icon "Question"

        if ("$answer" -eq "Yes") {
            $collection = New-Object -ComObject Microsoft.Update.UpdateColl
            foreach ($driver in $drivers) {
                if (-not $driver.EulaAccepted) { $driver.AcceptEula() }
                $null = $collection.Add($driver)
            }

            Step-WinUtilJob -Status "Downloading $($drivers.Count) driver(s) (2/3)" -State "Indeterminate"
            Write-WinUtilLog -Component "Drivers" -Message "Downloading driver updates"
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $collection
            $null = $downloader.Download()

            Step-WinUtilJob -Status "Installing $($drivers.Count) driver(s) (2/3)" -State "Indeterminate"
            Write-WinUtilLog -Component "Drivers" -Message "Installing driver updates"
            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $collection
            $installResult = $installer.Install()
            $rebootRequired = $installResult.RebootRequired

            # OperationResultCode: 2 succeeded, 3 succeeded with errors, 4 failed, 5 aborted
            for ($index = 0; $index -lt $collection.Count; $index++) {
                $code = $installResult.GetUpdateResult($index).ResultCode
                $title = $collection.Item($index).Title
                if ($code -eq 2) {
                    Write-Host "Installed: $title" -ForegroundColor Green
                } else {
                    Write-Warning "Could not install $title (result code $code)."
                }
            }
        } else {
            Write-Host "Skipped installing driver updates." -ForegroundColor Yellow
        }
    }

    Step-WinUtilJob -Status "Opening driver apps (3/3)" -Percent 90
    $vendorApps = @(Get-StartApps | Where-Object { $_.Name -match '^NVIDIA app|Intel.*Driver.*Support Assistant' })
    foreach ($app in $vendorApps) {
        Write-WinUtilLog -Component "Drivers" -Message "Opening $($app.Name)"
        Start-Process "shell:AppsFolder\$($app.AppID)"
    }
    if ($vendorApps.Count -eq 0) {
        Write-Host "NVIDIA App and Intel Driver & Support Assistant are not installed. Install them from the Install tab for the newest GPU and chipset drivers." -ForegroundColor Yellow
    } else {
        Write-Host "Opened $(($vendorApps.Name) -join ' and ') - check there for GPU and chipset drivers." -ForegroundColor Cyan
    }

    if ($rebootRequired) {
        Request-WinUtilRestart -Message "Driver updates were installed.`n`nRestart now so they take effect?" -Reason "Driver updates installed. Restarting so they take effect."
    }
}
