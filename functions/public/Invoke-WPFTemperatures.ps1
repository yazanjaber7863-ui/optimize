function Invoke-WPFTemperatures {
    <#
    .SYNOPSIS
        Shows how hot the graphics card and the drives are running, with a warning when they
        are too hot

    .DESCRIPTION
        Only real sensors are shown. NVIDIA cards report through nvidia-smi, which comes with
        their driver; drives report through Windows' storage counters. Windows has no built-in
        way to read the CPU temperature (monitoring apps load their own driver for it), and the
        ACPI "thermal zone" many desktops expose is usually a fixed placeholder, so neither is
        shown as if it were a reading.
    #>

    Step-WinUtilJob -Status "Reading temperatures" -State "Indeterminate"
    $rows = @()
    $hot = 0

    $rows += @{ Label = "Graphics card" }
    $smi = Join-Path $env:SystemRoot "System32\nvidia-smi.exe"
    if (Test-Path -LiteralPath $smi) {
        $lines = @(& $smi --query-gpu=name,temperature.gpu,utilization.gpu,fan.speed,power.draw --format=csv,noheader,nounits 2>$null)
        # Degrees left before the card slows itself down; older drivers do not report it
        $limits = @(& $smi --query-gpu=temperature.gpu.tlimit --format=csv,noheader,nounits 2>$null)
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $fields = @($lines[$index] -split ',\s*')
            if ($fields.Count -lt 5) { continue }
            $temperature = [int]$fields[1]
            $status = if ($temperature -ge 85) { "Bad" } elseif ($temperature -ge 75) { "Warn" } else { "Good" }
            if ($status -ne "Good") { $hot++ }
            $rows += @{ Label = "GPU"; Value = $fields[0] }
            $rows += @{ Label = "Temperature"; Value = "$temperature °C"; Status = $status }
            $rows += @{ Label = "Load"; Value = "$($fields[2])%" }
            $fan = if ($fields[3] -match '^\d+$') { if ([int]$fields[3] -eq 0) { "0% (fans stop when the card is cool, which is normal)" } else { "$($fields[3])%" } } else { "not reported" }
            $rows += @{ Label = "Fan"; Value = $fan }
            if ($fields[4] -match '^[\d.]+$') { $rows += @{ Label = "Power"; Value = "$([math]::Round([double]$fields[4])) W" } }
            if ($index -lt $limits.Count -and "$($limits[$index])".Trim() -match '^-?\d+$') {
                $headroom = [int]"$($limits[$index])".Trim()
                $headroomStatus = if ($headroom -le 5) { "Bad" } elseif ($headroom -le 15) { "Warn" } else { "Good" }
                $rows += @{ Label = "Before slowing down"; Value = "$headroom °C to go"; Status = $headroomStatus }
            }
        }
        if ($lines.Count -eq 0) {
            $rows += @{ Label = "NVIDIA"; Value = "nvidia-smi did not answer" }
        }
    } else {
        $rows += @{ Label = "GPU"; Value = "Only NVIDIA cards report their temperature to Windows tools" }
    }

    $rows += @{ Label = "Drives" }
    foreach ($disk in Get-PhysicalDisk | Sort-Object DeviceId) {
        $counters = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $name = $disk.FriendlyName.Trim()
        if ($counters.Temperature -gt 0) {
            $limit = if ($disk.MediaType -eq "HDD") { 50 } else { 70 }
            $status = if ($counters.Temperature -ge $limit) { "Bad" } elseif ($counters.Temperature -ge $limit - 10) { "Warn" } else { "Good" }
            if ($status -ne "Good") { $hot++ }
            $rows += @{ Label = $name; Value = "$($counters.Temperature) °C"; Status = $status }
        } else {
            $rows += @{ Label = $name; Value = "not reported" }
        }
    }

    $rows += @{ Label = "Processor" }
    $rows += @{ Label = "CPU"; Value = "Windows can't read it without an extra driver. HWiNFO or Core Temp show it." }

    $note = if ($hot -gt 0) {
        "Something is running hot. Check that fans spin and vents aren't blocked; dust is the usual cause. Under a heavy game, a GPU in the 70s °C is normal."
    } else {
        "Everything is at a healthy temperature. Check again while gaming to see the temperatures under load."
    }
    Write-WinUtilLog -Component "Temperatures" -Message "Temperatures checked, $hot running hot"
    Show-WinUtilReport -Title "Temperatures" -Rows $rows -Note $note
}
