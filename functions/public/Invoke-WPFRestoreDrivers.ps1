function Invoke-WPFRestoreDrivers {
    <#
    .SYNOPSIS
        Installs every driver in a folder made by Backup Drivers (or any folder of .inf drivers)
    #>

    $folder = Show-WinUtilFolderPicker -Description "Pick the driver backup folder (Optimize-drivers-...)"
    if (-not $folder) {
        Write-Host "Driver restore cancelled." -ForegroundColor Yellow
        return
    }

    $infCount = @(Get-ChildItem -LiteralPath $folder -Filter *.inf -Recurse -File -ErrorAction SilentlyContinue).Count
    if ($infCount -eq 0) {
        throw "$folder has no drivers in it (no .inf files). Pick the folder Backup Drivers made."
    }

    $answer = Show-WinUtilMessage -Title "Restore Drivers" -Button "YesNo" -Icon "Question" -Message (
        "Install the $infCount driver(s) in this folder?`n`n$folder`n`nDrivers that are already up to date are skipped. A restart may be needed.")
    if ("$answer" -ne "Yes") {
        return
    }

    Step-WinUtilJob -Status "Installing $infCount driver(s)" -State "Indeterminate"
    Write-WinUtilLog -Component "Drivers" -Message "Installing drivers from $folder"
    $output = pnputil.exe /add-driver (Join-Path $folder "*.inf") /subdirs /install
    $exitCode = $LASTEXITCODE
    $output | Select-Object -Last 6 | ForEach-Object { Write-Host $_ }

    # pnputil: 0 done, 3010 done but a restart is needed, 259 nothing newer to install
    switch ($exitCode) {
        0 { Write-Host "Drivers installed." -ForegroundColor Green }
        259 { Write-Host "Every driver in the backup was already installed." -ForegroundColor Green }
        3010 {
            Request-WinUtilRestart -Message "Drivers installed.`n`nRestart now so they take effect?" -Reason "Drivers installed. Restarting so they take effect."
        }
        default { Write-Warning "Some drivers could not be installed (pnputil exit code $exitCode). See the lines above." }
    }
}
