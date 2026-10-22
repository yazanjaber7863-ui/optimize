function Restore-WinUtilChange {
    <#
    .SYNOPSIS
        Puts one change journal entry into its Before state (undo) or its After state (reapply)

    .DESCRIPTION
        Returns $true when done, or a sentence saying why it could not be. The caller sets
        $global:WinUtilJournalPaused so this is not recorded as a new change.

    .PARAMETER Record
        One entry from the change journal

    .PARAMETER To
        Before puts back what the PC had before Optimize. After puts back what Optimize set,
        for when a Windows update has changed it back.
    #>
    param(
        [Parameter(Mandatory)] $Record,

        [ValidateSet("Before", "After")]
        [string]$To = "Before"
    )

    $state = $Record.$To
    switch ($Record.Kind) {
        "Registry" {
            $split = $Record.Key.LastIndexOf('\')
            $path = $Record.Key.Substring(0, $split)
            $name = $Record.Key.Substring($split + 1)
            # HKCU is the hive of whoever is running Optimize, which may not be who changed it
            if ($path -like "HKCU:*" -and $Record.User -and $Record.User -ne $env:USERNAME) {
                return "it is in $($Record.User)'s settings; run this while signed in as $($Record.User)"
            }
            if ($state.Exists) {
                $value = switch ($state.Type) {
                    "Binary" { [byte[]]@($state.Value) }
                    "MultiString" { [string[]]@($state.Value) }
                    "DWord" { [int64]$state.Value }
                    "QWord" { [int64]$state.Value }
                    default { "$($state.Value)" }
                }
                if ($state.Type -eq "DWord") {
                    # A DWord can arrive written as unsigned; the registry provider wants an Int32
                    $value = if ($value -gt [int32]::MaxValue) { [int32]($value - 4294967296) } else { [int32]$value }
                }
                if (-not (Test-Path -LiteralPath $path)) {
                    New-Item -Path $path -Force -ErrorAction Stop | Out-Null
                }
                Set-ItemProperty -LiteralPath $path -Name $name -Type $state.Type -Value $value -Force -ErrorAction Stop
            } elseif (Test-Path -LiteralPath $path) {
                Remove-ItemProperty -LiteralPath $path -Name $name -Force -ErrorAction SilentlyContinue
            }
        }
        "Service" {
            Set-Service -Name $Record.Key -StartupType $state.StartType -ErrorAction Stop
        }
        "Tweak" {
            $tweak = $sync.configs.tweaks.$($Record.Key)
            $scripts = if ($state.Applied) { $tweak.InvokeScript } else { $tweak.UndoScript }
            if (-not $scripts) {
                return "this version of Optimize no longer has that tweak"
            }
            foreach ($script in $scripts) {
                Invoke-Command -ScriptBlock ([scriptblock]::Create($script)) -ErrorAction Stop
            }
        }
        "Feature" {
            if ($state.Enabled) {
                Enable-WindowsOptionalFeature -Online -FeatureName $Record.Key -All -NoRestart -ErrorAction Stop | Out-Null
            } else {
                Disable-WindowsOptionalFeature -Online -FeatureName $Record.Key -NoRestart -ErrorAction Stop | Out-Null
            }
        }
        "Appx" {
            if ($state.Installed) {
                return "removed apps can't be put back automatically; reinstall it from the Microsoft Store if you want it"
            }
            foreach ($package in @(Get-AppxPackage -Name $Record.Key -AllUsers -ErrorAction SilentlyContinue)) {
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            }
        }
        "PowerPlan" {
            powercfg.exe /setactive $state.Guid
            if ($LASTEXITCODE -ne 0) {
                return "that power plan no longer exists; pick one in Settings > System > Power"
            }
        }
        "Dns" {
            if ($state.Provider) {
                # A provider choice applies to every connected adapter, as Apply DNS does
                if (-not (@(Set-WinUtilDNS -DNSProvider $state.Provider))[-1]) {
                    return "setting DNS to $($state.Provider) failed"
                }
                return $true
            }
            $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { "$($_.InterfaceGuid)" -eq $Record.Key } | Select-Object -First 1
            if (-not $adapter) {
                return "that network adapter is gone"
            }
            $servers = @("$($state.Static4) $($state.Static6)" -split '[,\s]+' | Where-Object { $_ })
            if ($servers.Count -eq 0) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $servers -ErrorAction Stop
            }
        }
        "Task" {
            if ($state.Exists) {
                return "the task can't be recreated from here; turn it on with its button"
            }
            Unregister-ScheduledTask -TaskName $Record.Key -Confirm:$false -ErrorAction SilentlyContinue
        }
        "TaskState" {
            $split = $Record.Key.LastIndexOf('\')
            $taskPath = $Record.Key.Substring(0, $split + 1)
            $taskName = $Record.Key.Substring($split + 1)
            if ($state.Enabled) {
                Enable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
            } else {
                Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
            }
        }
        "Firewall" {
            if ($state.Enabled) {
                Enable-NetFirewallRule -Group $Record.Key -ErrorAction Stop
            } else {
                Disable-NetFirewallRule -Group $Record.Key -ErrorAction Stop
            }
        }
        "TimeZone" {
            Set-TimeZone -Id $state.Id -ErrorAction Stop
        }
        "ComputerName" {
            if ($env:COMPUTERNAME -ne $state.Name) {
                Rename-Computer -NewName $state.Name -Force -ErrorAction Stop
            }
        }
        default {
            return "this version of Optimize does not know how to change '$($Record.Kind)'"
        }
    }
    return $true
}
