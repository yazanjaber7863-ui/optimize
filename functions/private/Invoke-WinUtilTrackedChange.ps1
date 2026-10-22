function Invoke-WinUtilTrackedChange {
    <#
    .SYNOPSIS
        Runs a block that changes settings directly and records what it changed in the change
        journal

    .DESCRIPTION
        For code that writes the registry, services and scheduled tasks itself instead of going
        through Set-WinUtilRegistry, such as the Windows Update profiles. The listed places are
        read before and after the block, and every difference is recorded, so Undo All can put
        those back too.

    .PARAMETER RegistryKeys
        Keys whose values are compared (each key's own values, not its subkeys)

    .PARAMETER Services
        Services whose start type is compared

    .PARAMETER TaskPaths
        Scheduled task folders, as Get-ScheduledTask -TaskPath takes them, whose on/off state
        is compared

    .PARAMETER ScriptBlock
        The work itself
    #>
    param(
        [string[]]$RegistryKeys = @(),
        [string[]]$Services = @(),
        [string[]]$TaskPaths = @(),
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock
    )

    $readRegistry = {
        $values = @{}
        foreach ($key in $RegistryKeys) {
            $item = Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            foreach ($name in $item.GetValueNames()) {
                if ($name) { $values["$key\$name"] = Get-WinUtilRegistryState -Path $key -Name $name }
            }
        }
        $values
    }
    $readServices = {
        $states = @{}
        foreach ($name in $Services) {
            $service = Get-Service -Name $name -ErrorAction SilentlyContinue
            if ($service) { $states[$name] = "$($service.StartType)" }
        }
        $states
    }
    $readTasks = {
        $states = @{}
        foreach ($path in $TaskPaths) {
            foreach ($task in @(Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue)) {
                $states["$($task.TaskPath)$($task.TaskName)"] = "$($task.State)" -ne "Disabled"
            }
        }
        $states
    }

    $registryBefore = & $readRegistry
    $servicesBefore = & $readServices
    $tasksBefore = & $readTasks

    try {
        & $ScriptBlock
    } finally {
        # Recorded even if the block failed halfway: whatever it did change can still be undone
        $registryAfter = & $readRegistry
        $missing = @{ Exists = $false; Value = $null; Type = $null }
        foreach ($name in @($registryBefore.Keys) + @($registryAfter.Keys) | Sort-Object -Unique) {
            $before = if ($registryBefore.ContainsKey($name)) { $registryBefore[$name] } else { $missing }
            $after = if ($registryAfter.ContainsKey($name)) { $registryAfter[$name] } else { $missing }
            if ((Get-WinUtilStateText $before) -ne (Get-WinUtilStateText $after)) {
                Register-WinUtilChange -Kind "Registry" -Key $name -Before $before -After $after
            }
        }

        $servicesAfter = & $readServices
        foreach ($name in $servicesBefore.Keys) {
            if ($servicesAfter[$name] -and $servicesAfter[$name] -ne $servicesBefore[$name]) {
                Register-WinUtilChange -Kind "Service" -Key $name -Label "Service $name" -Before @{ StartType = $servicesBefore[$name] } -After @{ StartType = $servicesAfter[$name] }
            }
        }

        $tasksAfter = & $readTasks
        foreach ($name in $tasksBefore.Keys) {
            if ($tasksAfter.ContainsKey($name) -and $tasksAfter[$name] -ne $tasksBefore[$name]) {
                Register-WinUtilChange -Kind "TaskState" -Key $name -Label "Scheduled task $name" -Before @{ Enabled = $tasksBefore[$name] } -After @{ Enabled = $tasksAfter[$name] }
            }
        }
    }
}
