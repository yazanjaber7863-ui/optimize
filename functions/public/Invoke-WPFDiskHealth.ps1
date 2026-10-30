function Invoke-WPFDiskHealth {
    <#
    .SYNOPSIS
        Shows each physical drive's health, wear, temperature and error counts

    .DESCRIPTION
        Reads Windows' own storage health and reliability counters (the same data as
        Settings > System > Storage > Disks & volumes). Some drives, mostly USB ones and older
        HDDs, do not report every counter, and those are shown as "not reported".
    #>

    Step-WinUtilJob -Status "Reading disk health" -State "Indeterminate"

    $rows = @()
    $problems = 0
    foreach ($disk in Get-PhysicalDisk | Sort-Object DeviceId) {
        $counters = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue

        $type = if ($disk.MediaType -eq 'SSD') { if ($disk.BusType -eq 'NVMe') { "NVMe SSD" } else { "SSD" } } elseif ($disk.MediaType -eq 'HDD') { "Hard drive" } else { "$($disk.BusType) drive" }
        $rows += @{ Label = "$($disk.FriendlyName.Trim()) ($([math]::Round($disk.Size / 1GB)) GB $type)" }

        $healthStatus = switch ("$($disk.HealthStatus)") { "Healthy" { "Good" } "Warning" { "Warn" } default { "Bad" } }
        if ($healthStatus -ne "Good") { $problems++ }
        $rows += @{ Label = "Health"; Value = "$($disk.HealthStatus)"; Status = $healthStatus }

        if ($null -ne $counters.Wear) {
            # Wear is the percentage of the drive's rated life used up
            $wearStatus = if ($counters.Wear -ge 90) { "Bad" } elseif ($counters.Wear -ge 70) { "Warn" } else { "Good" }
            if ($wearStatus -ne "Good") { $problems++ }
            $rows += @{ Label = "Life left"; Value = "$(100 - $counters.Wear)%"; Status = $wearStatus }
        } else {
            $rows += @{ Label = "Life left"; Value = "not reported" }
        }

        if ($counters.Temperature -gt 0) {
            $tempStatus = if ($counters.Temperature -ge 70) { "Bad" } elseif ($counters.Temperature -ge 60) { "Warn" } else { "Good" }
            $rows += @{ Label = "Temperature"; Value = "$($counters.Temperature) $([char]0xB0)C"; Status = $tempStatus }
        } else {
            $rows += @{ Label = "Temperature"; Value = "not reported" }
        }

        if ($null -ne $counters.PowerOnHours) {
            $rows += @{ Label = "Powered on"; Value = "$($counters.PowerOnHours) hours (about $([math]::Round($counters.PowerOnHours / 24)) days)" }
        }

        $errors = [int]$counters.ReadErrorsUncorrected + [int]$counters.WriteErrorsUncorrected
        if ($null -ne $counters.ReadErrorsUncorrected -or $null -ne $counters.WriteErrorsUncorrected) {
            if ($errors -gt 0) { $problems++ }
            $rows += @{ Label = "Uncorrected errors"; Value = "$errors"; Status = $(if ($errors -gt 0) { "Bad" } else { "Good" }) }
        }
    }

    $note = if ($problems -gt 0) {
        "Something needs attention. Back up anything important on the drives marked red or yellow."
    } else {
        "All drives look healthy."
    }
    Write-WinUtilLog -Component "DiskHealth" -Message "Disk health checked, $problems problem(s)"
    Show-WinUtilReport -Title "Disk Health" -Rows $rows -Note $note
}
