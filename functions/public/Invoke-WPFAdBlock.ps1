function Invoke-WPFAdBlock {
    <#
    .SYNOPSIS
        Turns PC-wide ad and tracker blocking on or off, asking first either way

    .DESCRIPTION
        Uses AdGuard's free DNS, which answers ad and tracker addresses with nothing, so ads are
        blocked in every browser and app rather than just one. That is gentler than a huge hosts
        file, which slows Windows' DNS service down. Turning it off puts back the exact DNS the
        PC had before, from the change journal, or automatic DNS when there is no record.
    #>

    $provider = "AdGuard_Ads_Trackers"
    $adguard = @($sync.configs.dns.$provider.Primary, $sync.configs.dns.$provider.Secondary)
    $active = @(Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
    })
    $isOn = @($active | Where-Object { $adguard -contains $_ }).Count -gt 0

    if ($isOn) {
        $answer = Show-WinUtilMessage -Title "Block Ads Everywhere" -Button "YesNo" -Icon "Question" -Message (
            "Ad blocking is ON for this PC.`n`nTurn it off?")
        if ("$answer" -ne "Yes") {
            return
        }

        Step-WinUtilJob -Status "Turning off ad blocking" -State "Indeterminate"
        $records = @(Update-WinUtilChangeJournal | Where-Object { $_.Kind -eq "Dns" -and "$($_.After.Provider)" -eq $provider })
        if ($records.Count -gt 0) {
            $global:WinUtilJournalPaused = $true
            try {
                foreach ($record in $records) {
                    $result = Restore-WinUtilChange -Record $record -To "Before"
                    if ($result -ne $true) { Write-Warning "Could not put back $($record.Label): $result" }
                }
            } finally {
                $global:WinUtilJournalPaused = $false
            }
            $keys = @($records | ForEach-Object { $_.Key })
            Update-WinUtilChangeJournal -Update {
                param($journal)
                for ($i = $journal.Count - 1; $i -ge 0; $i--) {
                    if ($journal[$i].Kind -eq "Dns" -and $keys -contains $journal[$i].Key) { $journal.RemoveAt($i) }
                }
            }
        } else {
            $null = Set-WinUtilDNS -DNSProvider "DHCP"
        }
        ipconfig.exe /flushdns | Out-Null
        Write-Host "Ad blocking turned off; DNS is back to what it was." -ForegroundColor Yellow
        return
    }

    $answer = Show-WinUtilMessage -Title "Block Ads Everywhere" -Button "YesNo" -Icon "Question" -Message (
        "Block ads and trackers in every browser and app on this PC?`n`n" +
        "This switches the PC's DNS to AdGuard's free ad-blocking DNS. A few sites, or games that give rewards for watching ads, may not work while it is on.`n`n" +
        "Click this button again any time to turn it off; your old DNS settings are kept.")
    if ("$answer" -ne "Yes") {
        return
    }

    Step-WinUtilJob -Status "Turning on ad blocking" -State "Indeterminate"
    $result = @(Set-WinUtilDNS -DNSProvider $provider)
    if ($result[-1] -ne $true) {
        throw "Ad blocking could not be turned on: changing DNS failed."
    }
    ipconfig.exe /flushdns | Out-Null
    Write-Host "Ad blocking is on for every browser and app." -ForegroundColor Green
}
