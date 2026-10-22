function Invoke-WPFRemoteDesktop {
    <#
    .SYNOPSIS
        Sets this PC up to be controlled with Remote Desktop, or turns that off again

    .DESCRIPTION
        Only Pro, Education and Enterprise can be controlled this way, which is what the
        "editions" field on the button says. Turning it on:
        1. Allows Remote Desktop connections, keeping Network Level Authentication on
        2. Enables the Remote Desktop firewall rules, by group ID so it works in any language
        3. Turns off "only allow Windows Hello sign-in", which otherwise rejects every password,
           and Remote Desktop cannot sign in with a PIN
        Then it shows the addresses and the user name to connect with.
    #>

    $terminalServer = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
    $firewallGroup = "@FirewallAPI.dll,-28752"
    $isOn = (Get-ItemProperty -Path $terminalServer -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections -eq 0

    if ($isOn) {
        # "No" is what an unattended run answers, so it must be the answer that changes nothing
        $answer = Show-WinUtilMessage -Title "Remote Desktop" -Button "YesNo" -Icon "Question" -Message (
            "Remote Desktop is ON for this PC.`n`nTurn it off?`n`n(No shows how to connect instead.)")
        if ("$answer" -eq "Yes") {
            Step-WinUtilJob -Status "Turning off Remote Desktop" -State "Indeterminate"
            Set-ItemProperty -Path $terminalServer -Name fDenyTSConnections -Type DWord -Value 1
            Disable-NetFirewallRule -Group $firewallGroup -ErrorAction SilentlyContinue
            Write-WinUtilLog -Component "RemoteDesktop" -Message "Remote Desktop turned off"
            Write-Host "Remote Desktop turned off." -ForegroundColor Yellow
            return
        }
    } else {
        $answer = Show-WinUtilMessage -Title "Set Up Remote Desktop" -Button "YesNo" -Icon "Question" -Message (
            "Let other devices control this PC with Remote Desktop?`n`n" +
            "This turns on Remote Desktop, allows it through the firewall, and lets you sign in with your password (Remote Desktop can't use a PIN).`n`n" +
            "Anyone who knows your account password and can reach this PC could sign in, so use a strong password. Connecting over Tailscale keeps it off the open internet.")
        if ("$answer" -ne "Yes") {
            return
        }

        Step-WinUtilJob -Status "Turning on Remote Desktop" -State "Indeterminate"
        Write-WinUtilLog -Component "RemoteDesktop" -Message "Turning on Remote Desktop"
        Set-ItemProperty -Path $terminalServer -Name fDenyTSConnections -Type DWord -Value 0
        # Network Level Authentication: the password is checked before a session is created
        Set-ItemProperty -Path "$terminalServer\WinStations\RDP-Tcp" -Name UserAuthentication -Type DWord -Value 1
        Enable-NetFirewallRule -Group $firewallGroup -ErrorAction Stop

        $passwordLess = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"
        if ((Get-ItemProperty -Path $passwordLess -Name DevicePasswordLessBuildVersion -ErrorAction SilentlyContinue).DevicePasswordLessBuildVersion -eq 2) {
            Set-ItemProperty -Path $passwordLess -Name DevicePasswordLessBuildVersion -Type DWord -Value 0
            Write-WinUtilLog -Component "RemoteDesktop" -Message "Turned off Windows Hello-only sign-in so passwords work"
        }
        Write-Host "Remote Desktop turned on." -ForegroundColor Green
    }

    # A Microsoft account signs in with its email; a local account with its user name
    $account = Get-LocalUser -Name $env:USERNAME -ErrorAction SilentlyContinue
    $email = Get-ChildItem -Path "HKCU:\Software\Microsoft\IdentityCRL\UserExtendedProperties" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty PSChildName
    $userName = if ("$($account.PrincipalSource)" -eq "MicrosoftAccount" -and $email) { $email } else { "$env:COMPUTERNAME\$env:USERNAME" }
    $password = if ("$($account.PrincipalSource)" -eq "MicrosoftAccount") { "your Microsoft account password (not your PIN)" } else { "your Windows password" }

    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" })
    # Tailscale hands out addresses in 100.64.0.0/10
    $tailscale = @($addresses | Where-Object { $_.IPAddress -match '^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.' })
    $local = @($addresses | Where-Object { $tailscale -notcontains $_ })

    $rows = @(
        @{ Label = "Connect with" }
        @{ Label = "App"; Value = "Windows App (phone, Mac, PC) - tap +, then Add PC" }
        @{ Label = "User name"; Value = $userName }
        @{ Label = "Password"; Value = $password }
        @{ Label = "PC address" }
    )
    foreach ($ip in $tailscale) { $rows += @{ Label = "From anywhere"; Value = "$($ip.IPAddress) (Tailscale on)"; Status = "Good" } }
    foreach ($ip in $local) { $rows += @{ Label = "At home"; Value = "$($ip.IPAddress) ($($ip.InterfaceAlias))" } }
    if ($tailscale.Count -eq 0) {
        $rows += @{ Label = "From anywhere"; Value = "Turn on Tailscale on this PC to get an address that works away from home"; Status = "Warn" }
    }

    $note = "Skip the sign-in button in Windows App: it is only for work and school cloud PCs. If a new password is refused, sign in on this PC with it once first."
    Show-WinUtilReport -Title "Remote Desktop" -Rows $rows -Note $note
}
