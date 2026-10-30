function Invoke-WPFRestoreWifi {
    <#
    .SYNOPSIS
        Adds the Wi-Fi networks from a folder made by Backup Wi-Fi, for every user on this PC
    #>

    $folder = Show-WinUtilFolderPicker -Description "Pick the Wi-Fi backup folder (Optimize-wifi-...)"
    if (-not $folder) {
        Write-Host "Wi-Fi restore cancelled." -ForegroundColor Yellow
        return
    }

    $files = @(Get-ChildItem -LiteralPath $folder -Filter *.xml -File)
    if ($files.Count -eq 0) {
        throw "$folder has no Wi-Fi networks in it. Pick the folder Backup Wi-Fi made."
    }

    Step-WinUtilJob -Status "Adding $($files.Count) Wi-Fi network(s)" -State "Indeterminate"
    $added = 0
    foreach ($file in $files) {
        $output = netsh.exe wlan add profile filename="$($file.FullName)" user=all 2>&1
        if ($LASTEXITCODE -eq 0) {
            $added++
        } else {
            Write-Warning "Could not add $($file.BaseName): $(($output | Out-String).Trim())"
        }
    }

    if ($added -eq 0) {
        throw "No Wi-Fi networks could be added. This PC may have no Wi-Fi adapter."
    }
    Write-WinUtilLog -Component "Backup" -Message "Added $added of $($files.Count) Wi-Fi profile(s) from $folder"
    Write-Host "Added $added Wi-Fi network(s). This PC joins them when they are in range." -ForegroundColor Green
}
