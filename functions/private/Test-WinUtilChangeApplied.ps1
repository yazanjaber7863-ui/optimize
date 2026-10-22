function Test-WinUtilChangeApplied {
    <#
    .SYNOPSIS
        Checks whether a change journal entry is still in place, for example after a Windows
        update

    .DESCRIPTION
        Returns $true when the PC still matches what Optimize set, $false when something (often
        a feature update) has changed it back, and $null when it cannot be told, as for a
        script-based tweak.

    .PARAMETER Record
        One entry from the change journal
    #>
    param(
        [Parameter(Mandatory)] $Record
    )

    $after = $Record.After
    try {
        switch ($Record.Kind) {
            "Registry" {
                $split = $Record.Key.LastIndexOf('\')
                if ($Record.Key -like "HKCU:*" -and $Record.User -and $Record.User -ne $env:USERNAME) { return $null }
                $current = Get-WinUtilRegistryState -Path $Record.Key.Substring(0, $split) -Name $Record.Key.Substring($split + 1)
                return (Get-WinUtilStateText $current) -eq (Get-WinUtilStateText $after)
            }
            "Service" { return "$((Get-Service -Name $Record.Key -ErrorAction Stop).StartType)" -eq "$($after.StartType)" }
            "Feature" { return ("$((Get-WindowsOptionalFeature -Online -FeatureName $Record.Key -ErrorAction Stop).State)" -eq "Enabled") -eq [bool]$after.Enabled }
            "Appx" { return -not (Get-AppxPackage -Name $Record.Key -AllUsers -ErrorAction SilentlyContinue) }
            "PowerPlan" { return "$(powercfg.exe /getactivescheme)" -match [regex]::Escape($after.Guid) }
            "Task" { return [bool](Get-ScheduledTask -TaskName $Record.Key -ErrorAction SilentlyContinue) -eq [bool]$after.Exists }
            "TaskState" {
                $split = $Record.Key.LastIndexOf('\')
                $task = Get-ScheduledTask -TaskPath $Record.Key.Substring(0, $split + 1) -TaskName $Record.Key.Substring($split + 1) -ErrorAction Stop
                return ("$($task.State)" -ne "Disabled") -eq [bool]$after.Enabled
            }
            "Firewall" {
                $off = @(Get-NetFirewallRule -Group $Record.Key -ErrorAction Stop | Where-Object { "$($_.Enabled)" -ne "True" }).Count
                return ($off -eq 0) -eq [bool]$after.Enabled
            }
            "TimeZone" { return (Get-TimeZone).Id -eq $after.Id }
            "ComputerName" { return $env:COMPUTERNAME -eq $after.Name }
            default { return $null }
        }
    } catch {
        return $null
    }
}
