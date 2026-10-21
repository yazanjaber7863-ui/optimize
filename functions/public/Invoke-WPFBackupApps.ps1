function Invoke-WPFBackupApps {
    <#
    .SYNOPSIS
        Saves a list of the installed apps that winget knows to a file, for Restore Apps on
        another PC or after a reinstall
    #>

    $defaultName = "Optimize-apps-$env:COMPUTERNAME-$(Get-Date -Format 'yyyy-MM-dd').json"
    $path = Invoke-WPFUIThread -PassThru -Parameters @{ DefaultName = $defaultName } -ScriptBlock {
        param($DefaultName)
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Title = "Save app backup"
        $dialog.FileName = $DefaultName
        $dialog.Filter = "App backup (*.json)|*.json"
        $dialog.InitialDirectory = [Environment]::GetFolderPath("MyDocuments")
        if ($dialog.ShowDialog($sync.Form)) { $dialog.FileName }
    }
    if (-not $path) {
        Write-Host "Backup cancelled." -ForegroundColor Yellow
        return
    }

    Step-WinUtilJob -Status "Listing installed apps" -State "Indeterminate"
    Write-WinUtilLog -Component "Backup" -Message "Exporting installed apps to $path"
    # The save dialog already asked before replacing a file. Removing it first means a failed
    # export cannot leave the old backup behind looking like a new one.
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    winget.exe export --output "$path" --source winget --accept-source-agreements --disable-interactivity | Out-Null
    if (-not (Test-Path -LiteralPath $path)) {
        throw "winget could not write the backup (exit code $LASTEXITCODE)."
    }

    $count = @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).Sources.Packages).Count
    Write-Host "Saved $count apps to $path" -ForegroundColor Green
    Write-Host "Copy it to a USB stick or cloud folder. On the new PC use Backup > Restore Apps." -ForegroundColor Cyan
}
