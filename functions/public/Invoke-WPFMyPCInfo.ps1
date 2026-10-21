function Invoke-WPFMyPCInfo {
    <#
    .SYNOPSIS
        Shows one window with the PC's name, Windows edition and activation, CPU, GPU, RAM,
        disks and uptime
    #>

    Step-WinUtilJob -Status "Reading PC info" -State "Indeterminate"

    $os = Get-CimInstance Win32_OperatingSystem
    $computer = Get-CimInstance Win32_ComputerSystem
    $board = Get-CimInstance Win32_BaseBoard
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Parsec|Virtual|Remote|Basic Display' })
    $memory = @(Get-CimInstance Win32_PhysicalMemory)
    # Filtering on Windows' application ID lets the licensing service skip every other product;
    # matching on Name made it load them all, which took over 10 seconds
    $license = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -Property LicenseStatus, Name | Select-Object -First 1
    $displayVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).DisplayVersion

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeText = if ($uptime.Days -gt 0) { "$($uptime.Days) day(s), $($uptime.Hours) h" } else { "$($uptime.Hours) h $($uptime.Minutes) min" }
    $activated = $license -and $license.LicenseStatus -eq 1

    $rows = @(
        @{ Label = "This PC" }
        @{ Label = "Name"; Value = $env:COMPUTERNAME }
        @{ Label = "Motherboard"; Value = "$($board.Manufacturer -replace '^Micro-Star International.*', 'MSI') $($board.Product)".Trim() }
        @{ Label = "Up for"; Value = $uptimeText; Status = $(if ($uptime.TotalDays -ge 7) { "Warn" } else { "" }) }
        @{ Label = "Windows" }
        @{ Label = "Edition"; Value = ($os.Caption -replace '^Microsoft ', '') }
        @{ Label = "Version"; Value = "$displayVersion (build $($os.BuildNumber))" }
        @{ Label = "Activation"; Value = $(if ($activated) { "Activated" } else { "Not activated" }); Status = $(if ($activated) { "Good" } else { "Bad" }) }
        @{ Label = "Hardware" }
        @{ Label = "CPU"; Value = "$($cpu.Name.Trim()) ($($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads)" }
    )
    foreach ($gpu in $gpus) {
        $rows += @{ Label = "GPU"; Value = "$($gpu.Name) - driver $($gpu.DriverVersion)" }
    }
    $totalGB = [math]::Round(($memory | Measure-Object -Property Capacity -Sum).Sum / 1GB)
    $speed = ($memory | Measure-Object -Property ConfiguredClockSpeed -Maximum).Maximum
    $rows += @{ Label = "RAM"; Value = "$totalGB GB ($($memory.Count) stick(s) at $speed MT/s)" }

    $rows += @{ Label = "Drives" }
    foreach ($volume in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter) {
        $freePercent = if ($volume.Size -gt 0) { [math]::Round($volume.SizeRemaining / $volume.Size * 100) } else { 0 }
        $status = if ($freePercent -lt 10) { "Bad" } elseif ($freePercent -lt 20) { "Warn" } else { "" }
        $label = "$($volume.DriveLetter):" + $(if ($volume.FileSystemLabel) { " $($volume.FileSystemLabel)" } else { "" })
        $rows += @{ Label = $label; Value = "$([math]::Round($volume.SizeRemaining / 1GB)) GB free of $([math]::Round($volume.Size / 1GB)) GB ($freePercent% free)"; Status = $status }
    }

    $note = if ($uptime.TotalDays -ge 7) { "Tip: this PC has not restarted in a week. A restart clears memory and finishes updates." } else { "" }
    Show-WinUtilReport -Title "My PC" -Rows $rows -Note $note
}
