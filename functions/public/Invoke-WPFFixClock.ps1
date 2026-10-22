function Invoke-WPFFixClock {
    <#
    .SYNOPSIS
        Asks for the user's time zone, sets it, and syncs the clock with internet time

    .DESCRIPTION
        1. Time zone - set to what the user picked. Automatic time zone detection is turned off
           so Windows does not switch it back to a wrong guess.
        2. Time sync - turns on automatic internet time, starts the Windows Time service and
           forces an immediate resync.
    #>

    $zoneId = Show-WinUtilTimeZonePicker
    if (-not $zoneId) {
        Write-Host "Fix Clock cancelled." -ForegroundColor Yellow
        return
    }

    Step-WinUtilJob -Status "Setting time zone (1/2)" -Percent 0
    Write-WinUtilLog -Component "Clock" -Message "Setting time zone to $zoneId"
    Register-WinUtilChange -Kind "TimeZone" -Key "TimeZone" -Label "Time zone" -Before @{ Id = (Get-TimeZone).Id } -After @{ Id = $zoneId }
    Set-TimeZone -Id $zoneId -ErrorAction Stop

    # Automatic time zone detection would otherwise override the user's choice
    Set-WinUtilRegistry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate" -Name "Start" -Type DWord -Value 4

    Step-WinUtilJob -Status "Syncing with internet time (2/2)" -Percent 50
    Write-WinUtilLog -Component "Clock" -Message "Turning on internet time sync and resyncing"
    Set-WinUtilRegistry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "Type" -Type String -Value "NTP"
    Set-WinUtilService -Name W32Time -StartupType Automatic
    Start-Service -Name W32Time -ErrorAction SilentlyContinue
    w32tm.exe /config /update | Out-Null

    $resync = w32tm.exe /resync /force 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Usually no internet; the zone is still set and Windows syncs again later on its own
        Write-Warning "Time zone set, but syncing with internet time failed: $($resync -join ' ')"
        return
    }

    $zone = Get-TimeZone
    Write-Host "Clock fixed: $($zone.DisplayName) - it's now $((Get-Date).ToString('HH:mm, ddd d MMM'))" -ForegroundColor Green
    Write-WinUtilLog -Component "Clock" -Message "Clock fixed: $($zone.Id), synced with internet time"
}
