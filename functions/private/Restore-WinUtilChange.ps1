function Restore-WinUtilChange {
    <#
    .SYNOPSIS
        Puts one change journal entry back to its Before state

    .DESCRIPTION
        Returns $true when it was put back, or a sentence saying why it could not be. The caller
        sets $global:WinUtilJournalPaused so putting things back is not recorded as new changes.

    .PARAMETER Record
        One entry from the change journal
    #>
    param(
        [Parameter(Mandatory)] $Record
    )

    $before = $Record.Before
    switch ($Record.Kind) {
        "Registry" {
            $split = $Record.Key.LastIndexOf('\')
            $path = $Record.Key.Substring(0, $split)
            $name = $Record.Key.Substring($split + 1)
            # HKCU is the hive of whoever is running Optimize, which may not be who changed it
            if ($path -like "HKCU:*" -and $Record.User -and $Record.User -ne $env:USERNAME) {
                return "it is in $($Record.User)'s settings; run Undo All while signed in as $($Record.User)"
            }
            if ($before.Exists) {
                $value = switch ($before.Type) {
                    "Binary" { [byte[]]@($before.Value) }
                    "MultiString" { [string[]]@($before.Value) }
                    "DWord" { [int64]$before.Value }
                    "QWord" { [int64]$before.Value }
                    default { "$($before.Value)" }
                }
                if ($before.Type -eq "DWord") {
                    # A DWord can arrive written as unsigned; the registry provider wants an Int32
                    $value = if ($value -gt [int32]::MaxValue) { [int32]($value - 4294967296) } else { [int32]$value }
                }
                if (-not (Test-Path -LiteralPath $path)) {
                    New-Item -Path $path -Force -ErrorAction Stop | Out-Null
                }
                Set-ItemProperty -LiteralPath $path -Name $name -Type $before.Type -Value $value -Force -ErrorAction Stop
            } elseif (Test-Path -LiteralPath $path) {
                Remove-ItemProperty -LiteralPath $path -Name $name -Force -ErrorAction SilentlyContinue
            }
        }
        "Service" {
            Set-Service -Name $Record.Key -StartupType $before.StartType -ErrorAction Stop
        }
        "Tweak" {
            $tweak = $sync.configs.tweaks.$($Record.Key)
            if (-not $tweak.UndoScript) {
                return "this version of Optimize no longer has an undo for it"
            }
            foreach ($script in $tweak.UndoScript) {
                Invoke-Command -ScriptBlock ([scriptblock]::Create($script)) -ErrorAction Stop
            }
        }
        "Feature" {
            if (-not $before.Enabled) {
                Disable-WindowsOptionalFeature -Online -FeatureName $Record.Key -NoRestart -ErrorAction Stop | Out-Null
            }
        }
        "Appx" {
            return "removed apps can't be put back automatically; reinstall it from the Microsoft Store if you want it"
        }
        "PowerPlan" {
            powercfg.exe /setactive $before.Guid
            if ($LASTEXITCODE -ne 0) {
                return "the old power plan no longer exists; pick one in Settings > System > Power"
            }
        }
        "Dns" {
            $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { "$($_.InterfaceGuid)" -eq $Record.Key } | Select-Object -First 1
            if (-not $adapter) {
                return "that network adapter is gone"
            }
            $servers = @("$($before.Static4) $($before.Static6)" -split '[,\s]+' | Where-Object { $_ })
            if ($servers.Count -eq 0) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $servers -ErrorAction Stop
            }
        }
        "Task" {
            if ($before.Exists) {
                return "the task was deleted and can't be recreated; turn it back on with its button"
            }
            Unregister-ScheduledTask -TaskName $Record.Key -Confirm:$false -ErrorAction SilentlyContinue
        }
        "Firewall" {
            if ($before.Enabled) {
                Enable-NetFirewallRule -Group $Record.Key -ErrorAction Stop
            } else {
                Disable-NetFirewallRule -Group $Record.Key -ErrorAction Stop
            }
        }
        "TimeZone" {
            Set-TimeZone -Id $before.Id -ErrorAction Stop
        }
        "ComputerName" {
            if ($env:COMPUTERNAME -ne $before.Name) {
                Rename-Computer -NewName $before.Name -Force -ErrorAction Stop
            }
        }
        default {
            return "this version of Optimize does not know how to undo '$($Record.Kind)'"
        }
    }
    return $true
}
