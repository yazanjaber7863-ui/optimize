function Invoke-WPFWhatsRunning {
    <#
    .SYNOPSIS
        Shows which apps are using the most memory and CPU right now, and which ones start
        with Windows
    #>

    Step-WinUtilJob -Status "Checking what is running" -State "Indeterminate"

    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB = $os.TotalVisibleMemorySize / 1MB
    $usedGB = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB
    $usedPercent = [math]::Round($usedGB / $totalGB * 100)

    # CPU is the time each process used between two samples a second apart, shared across all
    # logical processors the way Task Manager shows it
    $cores = [Environment]::ProcessorCount
    $first = @{}
    foreach ($process in Get-Process) {
        if ($null -ne $process.CPU) { $first[$process.Id] = $process.CPU }
    }
    Start-Sleep -Seconds 1
    $processes = @(Get-Process)

    $byName = $processes | Where-Object { $_.Id -ne 0 -and $_.ProcessName -ne "Idle" } | Group-Object ProcessName | ForEach-Object {
        $cpuSeconds = 0
        foreach ($process in $_.Group) {
            if ($null -ne $process.CPU -and $first.ContainsKey($process.Id)) { $cpuSeconds += $process.CPU - $first[$process.Id] }
        }
        # The description is the name people know, e.g. "Google Chrome" rather than "chrome"
        $friendly = ($_.Group | Where-Object { $_.Description } | Select-Object -First 1).Description
        [pscustomobject]@{
            Name = $(if ($friendly) { $friendly.Trim() } else { $_.Name })
            Count = $_.Count
            MemoryMB = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB
            CpuPercent = $cpuSeconds / $cores * 100
        }
    }

    $rows = @(
        @{ Label = "Memory" }
        @{ Label = "In use"; Value = "{0:N1} GB of {1:N0} GB ({2}%)" -f $usedGB, $totalGB, $usedPercent; Status = $(if ($usedPercent -ge 90) { "Bad" } elseif ($usedPercent -ge 75) { "Warn" } else { "" }) }
        @{ Label = "Using the most memory" }
    )
    foreach ($app in $byName | Sort-Object MemoryMB -Descending | Select-Object -First 8) {
        $size = if ($app.MemoryMB -ge 1024) { "{0:N1} GB" -f ($app.MemoryMB / 1024) } else { "{0:N0} MB" -f $app.MemoryMB }
        $windows = if ($app.Count -gt 1) { " ($($app.Count) processes)" } else { "" }
        $rows += @{ Label = $app.Name; Value = "$size$windows"; Status = $(if ($app.MemoryMB -ge 2048) { "Warn" } else { "" }) }
    }

    $rows += @{ Label = "Using the most CPU right now" }
    $busy = @($byName | Where-Object { $_.CpuPercent -ge 1 } | Sort-Object CpuPercent -Descending | Select-Object -First 5)
    if ($busy.Count -eq 0) {
        $rows += @{ Label = "Nothing busy"; Value = "Every app is under 1% CPU"; Status = "Good" }
    }
    foreach ($app in $busy) {
        $rows += @{ Label = $app.Name; Value = "{0:N0}% CPU" -f $app.CpuPercent; Status = $(if ($app.CpuPercent -ge 50) { "Bad" } elseif ($app.CpuPercent -ge 20) { "Warn" } else { "" }) }
    }

    $startup = @(Get-WinUtilStartupApps | Where-Object Enabled)
    $rows += @{ Label = "Starts with Windows" }
    if ($startup.Count -eq 0) {
        $rows += @{ Label = "Nothing"; Value = "No apps start with Windows"; Status = "Good" }
    }
    foreach ($app in $startup) {
        $rows += @{ Label = $app.Name; Value = "on, for $($app.Scope)" }
    }

    $note = "To stop apps opening with Windows, use Startup Apps on the Maintenance tab. Closing an app you are not using frees its memory straight away."
    Show-WinUtilReport -Title "What's Using My PC" -Rows $rows -Note $note
}
