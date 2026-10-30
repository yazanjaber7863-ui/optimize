function Invoke-WPFBackupWifi {
    <#
    .SYNOPSIS
        Saves every Wi-Fi network this PC knows, with its password, to a folder

    .DESCRIPTION
        Restore Wi-Fi adds them on another PC or after a reinstall, so it connects straight
        away. Windows can only export the passwords as plain text, which the user is told before
        anything is saved. The networks are counted from the exported files rather than from
        netsh's text, which is translated on non-English Windows.
    #>

    $answer = Show-WinUtilMessage -Title "Backup Wi-Fi" -Button "YesNo" -Icon "Warning" -Message (
        "Save this PC's Wi-Fi networks and their passwords?`n`n" +
        "Windows saves the passwords as readable text, so anyone who opens the backup folder can see them. Keep it on your own USB stick or drive, and delete it once you have restored it.")
    if ("$answer" -ne "Yes") {
        return
    }

    $parent = Show-WinUtilFolderPicker -Description "Where should the Wi-Fi backup go?" -ShowNewFolderButton
    if (-not $parent) {
        Write-Host "Wi-Fi backup cancelled." -ForegroundColor Yellow
        return
    }
    Step-WinUtilJob -Status "Saving Wi-Fi networks" -State "Indeterminate"
    # netsh cuts file names short when the folder path is long (it wrote "KAESS" for "KAESSR"),
    # so it exports into a short temporary folder and the files are moved afterwards
    $staging = Join-Path ([IO.Path]::GetTempPath()) "owifi-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
        netsh.exe wlan export profile key=clear folder="$staging" | Out-Null
        $saved = @(Get-ChildItem -LiteralPath $staging -Filter *.xml)
        if ($saved.Count -gt 0) {
            $folder = Join-Path $parent "Optimize-wifi-$env:COMPUTERNAME-$(Get-Date -Format 'yyyy-MM-dd')"
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $saved | Move-Item -Destination $folder -Force
        }
    } finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($saved.Count -eq 0) {
        Show-WinUtilMessage -Title "Backup Wi-Fi" -Button "OK" -Icon "Information" -Message (
            "There are no saved Wi-Fi networks to back up. This PC may have no Wi-Fi adapter, or has never joined a Wi-Fi network.") | Out-Null
        return
    }
    Write-WinUtilLog -Component "Backup" -Message "Saved $($saved.Count) Wi-Fi profile(s) to $folder"
    Write-Host "Saved $($saved.Count) Wi-Fi network(s) to $folder" -ForegroundColor Green
    Write-Host "The passwords in it are readable; keep the folder private." -ForegroundColor Yellow
}
