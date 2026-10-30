function Invoke-WPFSpeedTest {
    <#
    .SYNOPSIS
        Measures download and upload speed against Cloudflare's speed test servers

    .DESCRIPTION
        Four transfers run side by side for about six seconds in each direction, the way
        speed.cloudflare.com does it, since one transfer cannot fill a fast connection. Each
        direction stops at about 300 MB so a test never eats a data cap.
    #>

    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    $streams = 4
    $seconds = 6
    $capBytes = 300MB

    $measure = {
        param([string]$Direction)
        $payload = if ($Direction -eq "up") { New-Object byte[] (10MB) } else { $null }
        $startTransfer = {
            if ($Direction -eq "up") {
                $client.PostAsync("https://speed.cloudflare.com/__up", (New-Object System.Net.Http.ByteArrayContent(, $payload)))
            } else {
                $client.GetByteArrayAsync("https://speed.cloudflare.com/__down?bytes=$(25MB)")
            }
        }

        $clock = [Diagnostics.Stopwatch]::StartNew()
        $tasks = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $streams; $i++) { $null = $tasks.Add((& $startTransfer)) }
        $bytes = [int64]0
        $failures = 0
        while ($tasks.Count -gt 0) {
            $done = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]$tasks.ToArray(), 1000)
            if ($done -lt 0) { continue }
            $task = $tasks[$done]
            $tasks.RemoveAt($done)
            if ($task.Status -eq 'RanToCompletion') {
                $bytes += if ($Direction -eq "up") { $payload.Length } else { $task.Result.Length }
            } else {
                $failures++
            }
            if ($clock.Elapsed.TotalSeconds -lt $seconds -and $bytes -lt $capBytes -and $failures -lt 3) {
                $null = $tasks.Add((& $startTransfer))
            }
            Step-WinUtilJob -Status "Testing $($Direction)load speed ($([math]::Min(100, [int]($clock.Elapsed.TotalSeconds / $seconds * 100)))%)" -Percent $(if ($Direction -eq "down") { [int]([math]::Min(1, $clock.Elapsed.TotalSeconds / $seconds) * 50) } else { 50 + [int]([math]::Min(1, $clock.Elapsed.TotalSeconds / $seconds) * 50) })
        }
        $clock.Stop()
        if ($bytes -eq 0) { return $null }
        return [math]::Round($bytes * 8 / 1e6 / $clock.Elapsed.TotalSeconds)
    }

    try {
        $download = & $measure "down"
        $upload = & $measure "up"
    } finally {
        $client.Dispose()
    }

    if ($null -eq $download -and $null -eq $upload) {
        throw "Could not reach the speed test server. Check that the internet is connected."
    }

    $rows = @(@{ Label = "Speed (higher is better)" })
    if ($null -ne $download) {
        $rows += @{ Label = "Download"; Value = "$download Mbps"; Status = $(if ($download -ge 100) { "Good" } elseif ($download -ge 25) { "Warn" } else { "Bad" }) }
    } else {
        $rows += @{ Label = "Download"; Value = "failed"; Status = "Bad" }
    }
    if ($null -ne $upload) {
        $rows += @{ Label = "Upload"; Value = "$upload Mbps"; Status = $(if ($upload -ge 20) { "Good" } elseif ($upload -ge 5) { "Warn" } else { "Bad" }) }
    } else {
        $rows += @{ Label = "Upload"; Value = "failed"; Status = "Bad" }
    }
    $rows += @{ Label = "What it means" }
    $rows += @{ Label = "Gaming"; Value = "Needs little speed (5 Mbps is plenty); ping matters more. Use Ping Test for that." }
    $rows += @{ Label = "Streaming 4K"; Value = "About 25 Mbps per stream" }
    $rows += @{ Label = "Big downloads"; Value = $(if ($null -ne $download) { "A 50 GB game takes about $([math]::Ceiling(50 * 8000 / [math]::Max($download, 1) / 60)) minutes" } else { "-" }) }

    Write-WinUtilLog -Component "SpeedTest" -Message "Download $download Mbps, upload $upload Mbps"
    Show-WinUtilReport -Title "Speed Test" -Rows $rows -Note "Measured against Cloudflare's servers. Wi-Fi is usually slower than a cable; if this is much lower than your internet plan, test again on a cable."
}
