function Invoke-WPFBackupDrivers {
    <#
    .SYNOPSIS
        Saves every driver installed on this PC (not the ones built into Windows) to a folder

    .DESCRIPTION
        After a Windows reinstall, Restore Drivers installs them all from that folder, so Wi-Fi,
        audio, chipset and the rest work straight away without hunting for downloads.
    #>

    $parent = Show-WinUtilFolderPicker -Description "Where should the driver backup go? A USB stick or another drive is best, so it survives a reinstall." -ShowNewFolderButton
    if (-not $parent) {
        Write-Host "Driver backup cancelled." -ForegroundColor Yellow
        return
    }

    $folder = Join-Path $parent "Optimize-drivers-$env:COMPUTERNAME-$(Get-Date -Format 'yyyy-MM-dd')"
    New-Item -ItemType Directory -Path $folder -Force | Out-Null

    Step-WinUtilJob -Status "Saving drivers to $folder" -State "Indeterminate"
    Write-WinUtilLog -Component "Drivers" -Message "Exporting drivers to $folder"
    # Only the drivers added to this PC; the ones that ship with Windows come back on their own
    $drivers = @(Export-WindowsDriver -Online -Destination $folder -ErrorAction Stop)

    $readme = @(
        "Driver backup made by Optimize on $(Get-Date -Format 'yyyy-MM-dd HH:mm') from $env:COMPUTERNAME."
        "To install them: Optimize > Backup > Restore Drivers, and pick this folder."
        ""
        $drivers | Sort-Object ClassName, ProviderName | ForEach-Object { "$($_.ClassName): $($_.ProviderName) $($_.Version) ($($_.OriginalFileName | Split-Path -Leaf))" }
    )
    $readme | Set-Content -LiteralPath (Join-Path $folder "README.txt") -Encoding UTF8

    $sizeMB = [math]::Round((Get-ChildItem -LiteralPath $folder -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
    Write-Host "Saved $($drivers.Count) drivers ($sizeMB MB) to $folder" -ForegroundColor Green
    Write-WinUtilLog -Component "Drivers" -Message "Exported $($drivers.Count) drivers ($sizeMB MB)"
}
