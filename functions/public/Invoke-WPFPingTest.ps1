function Invoke-WPFPingTest {
    <#
    .SYNOPSIS
        Measures ping, jitter and packet loss to the router and to big internet servers

    .DESCRIPTION
        The router shows whether the problem is inside the house (Wi-Fi, cable), the internet
        servers whether it is the connection itself.
    #>

    # The route Windows really uses is the one with the lowest route + interface metric. VPN
    # adapters add on-link default routes whose next hop is 0.0.0.0, which is not a router.
    $gateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -and $_.NextHop -ne "0.0.0.0" } |
        Sort-Object { $_.RouteMetric + (Get-NetIPInterface -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric } |
        Select-Object -First 1 -ExpandProperty NextHop
    $targets = @()
    if ($gateway) { $targets += @{ Name = "Your router"; Address = $gateway } }
    $targets += @(
        @{ Name = "Cloudflare"; Address = "1.1.1.1" }
        @{ Name = "Google"; Address = "8.8.8.8" }
        @{ Name = "Quad9"; Address = "9.9.9.9" }
    )

    # Every target is pinged at the same time each round, so the test takes as long as one
    # target's 20 tries instead of all of them back to back
    $pingsEach = 20
    $results = New-Object System.Collections.ArrayList
    foreach ($target in $targets) { $null = $results.Add((New-Object System.Collections.ArrayList)) }
    for ($try = 0; $try -lt $pingsEach; $try++) {
        Step-WinUtilJob -Status "Pinging $($targets.Count) servers ($($try + 1)/$pingsEach)" -Percent ([int]($try / $pingsEach * 100))
        $pingers = @(foreach ($target in $targets) { New-Object System.Net.NetworkInformation.Ping })
        $tasks = @(for ($i = 0; $i -lt $targets.Count; $i++) { $pingers[$i].SendPingAsync($targets[$i].Address, 1000) })
        try { [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tasks) } catch { }
        for ($i = 0; $i -lt $targets.Count; $i++) {
            if ($tasks[$i].Status -eq 'RanToCompletion' -and $tasks[$i].Result.Status -eq 'Success') {
                $null = $results[$i].Add([int]$tasks[$i].Result.RoundtripTime)
            }
            $pingers[$i].Dispose()
        }
        Start-Sleep -Milliseconds 100
    }

    $rows = @(@{ Label = "Ping (lower is better), $pingsEach tries each" })
    for ($index = 0; $index -lt $targets.Count; $index++) {
        $target = $targets[$index]
        $times = $results[$index]

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
    }

    $note = "Green is great for gaming. If your router is yellow or red, the problem is Wi-Fi or the cable - try a wired connection. If only the internet servers are bad, it's your internet provider."
    Show-WinUtilReport -Title "Ping Test" -Rows $rows -Note $note
}
