function Invoke-WPFFixInternet {
    <#
    .SYNOPSIS
        Resets the network stack for when the internet acts weird

    .DESCRIPTION
        1. Flushes the DNS cache - fixes sites that will not load or load the wrong place
        2. Resets Winsock and TCP/IP - fixes broken network settings left by VPNs and other software
        The connection is not released first, so the network stays up until the restart that
        the Winsock and TCP/IP resets need.
    #>

    Step-WinUtilJob -Status "Flushing the DNS cache (1/3)" -Percent 0
    Write-WinUtilLog -Component "Network" -Message "Flushing the DNS cache"
    ipconfig.exe /flushdns | Out-Null

    Step-WinUtilJob -Status "Resetting Winsock (2/3)" -Percent 33
    Write-WinUtilLog -Component "Network" -Message "Resetting Winsock"
    netsh.exe winsock reset | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "Winsock reset finished with exit code $LASTEXITCODE." }

    Step-WinUtilJob -Status "Resetting TCP/IP (3/3)" -Percent 66
    Write-WinUtilLog -Component "Network" -Message "Resetting TCP/IP"
    # Some keys are locked and reported as "Access is denied" on every run; the reset still applies
    netsh.exe int ip reset | Out-Null

    Write-Host "Network reset done. It takes effect after a restart." -ForegroundColor Green
    Request-WinUtilRestart -Message "Network reset done.`n`nRestart now so it takes effect?" -Reason "Network reset done. Restarting so it takes effect."
}
