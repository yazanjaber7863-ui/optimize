function Invoke-WPFPingTest {
    <#
    .SYNOPSIS
        Measures ping, jitter and packet loss to the router and to big internet servers

    .DESCRIPTION
        The router shows whether the problem is inside the house (Wi-Fi, cable), the internet
        servers whether it is the connection itself.
    #>

    $gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    $targets = @()
    if ($gateway) { $targets += @{ Name = "Your router"; Address = $gateway } }
    $targets += @(
        @{ Name = "Cloudflare"; Address = "1.1.1.1" }
        @{ Name = "Google"; Address = "8.8.8.8" }
        @{ Name = "Quad9"; Address = "9.9.9.9" }
    )

    $pingsEach = 20
    $pinger = New-Object System.Net.NetworkInformation.Ping
    $rows = @(@{ Label = "Ping (lower is better), $pingsEach tries each" })
    $index = 0
    foreach ($target in $targets) {
        Step-WinUtilJob -Status "Pinging $($target.Name) ($($index + 1)/$($targets.Count))" -Percent ([int]($index / $targets.Count * 100))
        $times = New-Object System.Collections.ArrayList
        for ($try = 0; $try -lt $pingsEach; $try++) {
            try {
                $reply = $pinger.Send($target.Address, 1000)
                if ($reply.Status -eq 'Success') { $null = $times.Add([int]$reply.RoundtripTime) }
            } catch { }
            Start-Sleep -Milliseconds 100
        }

        $lost = [math]::Round(($pingsEach - $times.Count) / $pingsEach * 100)
        if ($times.Count -eq 0) {
            $rows += @{ Label = $target.Name; Value = "no reply (100% lost)"; Status = "Bad" }
        } else {
            $average = [math]::Round(($times | Measure-Object -Average).Average)
            # Jitter: how much the ping jumps between tries, which is what feels like lag in games
            $jumps = for ($k = 1; $k -lt $times.Count; $k++) { [math]::Abs($times[$k] - $times[$k - 1]) }
            $jitter = if ($jumps) { [math]::Round(($jumps | Measure-Object -Average).Average) } else { 0 }
            $status = if ($lost -gt 2 -or $average -gt 100 -or $jitter -gt 20) { "Bad" } elseif ($lost -gt 0 -or $average -gt 50 -or $jitter -gt 8) { "Warn" } else { "Good" }
            $rows += @{ Label = $target.Name; Value = "$average ms, jitter $jitter ms, $lost% lost"; Status = $status }
        }
        $index++
    }
    $pinger.Dispose()

    $note = "Green is great for gaming. If your router is yellow or red, the problem is Wi-Fi or the cable - try a wired connection. If only the internet servers are bad, it's your internet provider."
    Show-WinUtilReport -Title "Ping Test" -Rows $rows -Note $note
}
