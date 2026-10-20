function Invoke-WPFRestoreApps {
    <#
    .SYNOPSIS
        Installs every app listed in a backup made by Backup Apps
    #>

    $path = Invoke-WPFUIThread -PassThru -ScriptBlock {
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = "Pick an app backup"
        $dialog.Filter = "App backup (*.json)|*.json"
        $dialog.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
        if ($dialog.ShowDialog($sync.Form)) { $dialog.FileName }
    }
    if (-not $path) {
        Write-Host "Restore cancelled." -ForegroundColor Yellow
        return
    }

    $packages = @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).Sources.Packages)
    if ($packages.Count -eq 0) {
        throw "$path is not an app backup, or it lists no apps."
    }

    $answer = Show-WinUtilMessage -Message "Install the $($packages.Count) apps in this backup?`n`nApps you already have are skipped. This can take a while." -Title "Restore Apps" -Button "YesNo" -Icon "Question"
    if ("$answer" -ne "Yes") {
        return
    }

    Step-WinUtilJob -Status "Installing $($packages.Count) apps from the backup" -State "Indeterminate"
    Write-WinUtilLog -Component "Backup" -Message "Importing $($packages.Count) apps from $path"
    winget.exe import --import-file "$path" --ignore-unavailable --ignore-versions --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Some apps could not be installed (winget exit code $LASTEXITCODE). See the lines above."
    } else {
        Write-Host "All apps from the backup are installed." -ForegroundColor Green
    }
}
