function Invoke-WPFHealthCheckTask {
    <#
    .SYNOPSIS
        Turns the weekly health check on or off, asking first either way

    .DESCRIPTION
        A scheduled task, "Optimize Health Check", runs every Sunday at 13:00 while the user is
        signed in (or at the next sign-in if the PC was off) and shows a Windows notification
        only when something needs attention:
        - a drive that is unhealthy, wearing out, too hot or nearly full
        - an NVIDIA graphics card that is hot at the time of the check
        - Optimize settings that a Windows update has changed back
        The check is a script written to %ProgramData%\Optimize, so it runs without Optimize
        open. It runs as the signed-in user because notifications belong to a user's session.
    #>

    $taskName = "Optimize Health Check"
    $folder = Join-Path $env:ProgramData "Optimize"
    $scriptPath = Join-Path $folder "HealthCheck.ps1"

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        $answer = Show-WinUtilMessage -Title "Weekly Health Check" -Button "YesNo" -Icon "Question" -Message (
            "The weekly health check is ON (Sundays at 13:00).`n`nTurn it off?")
        if ("$answer" -eq "Yes") {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
            Register-WinUtilChange -Kind "Task" -Key $taskName -Label "Scheduled task $taskName" -Before @{ Exists = $true } -After @{ Exists = $false }
            Write-Host "Weekly health check turned off." -ForegroundColor Yellow
        }
        return
    }

    $answer = Show-WinUtilMessage -Title "Weekly Health Check" -Button "YesNo" -Icon "Question" -Message (
        "Turn on a weekly health check?`n`n" +
        "Every Sunday it quietly checks your drives, graphics card temperature, free space and Optimize's settings, and shows a notification only if something needs attention. It doesn't change anything.")
    if ("$answer" -ne "Yes") {
        return
    }

    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Set-Content -LiteralPath $scriptPath -Encoding UTF8 -Value @'
# Written by Optimize (Health > Weekly Health Check). Checks the PC and shows a notification
# only when something needs attention. Turn it off with the same button.
$problems = New-Object System.Collections.ArrayList

foreach ($disk in Get-PhysicalDisk) {
    $name = $disk.FriendlyName.Trim()
    if ("$($disk.HealthStatus)" -ne "Healthy") { $null = $problems.Add("$name reports $($disk.HealthStatus) health. Back up what matters on it.") }
    $counters = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    if ($counters.Wear -ge 80) { $null = $problems.Add("$name has used $($counters.Wear)% of its life.") }
    $hotAt = if ($disk.MediaType -eq "HDD") { 50 } else { 70 }
    if ($counters.Temperature -ge $hotAt) { $null = $problems.Add("$name is at $($counters.Temperature) C.") }
}

foreach ($volume in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }) {
    $free = [math]::Round($volume.SizeRemaining / $volume.Size * 100)
    if ($free -lt 10) { $null = $problems.Add("Drive $($volume.DriveLetter): is $(100 - $free)% full.") }
}

$smi = Join-Path $env:SystemRoot "System32\nvidia-smi.exe"
if (Test-Path $smi) {
    foreach ($line in @(& $smi --query-gpu=name,temperature.gpu --format=csv,noheader,nounits 2>$null)) {
        $fields = $line -split ',\s*'
        if ($fields.Count -ge 2 -and [int]$fields[1] -ge 85) { $null = $problems.Add("$($fields[0]) is at $($fields[1]) C. Check its fans and dust.") }
    }
}

# Registry changes Optimize made that are no longer in place, usually after a Windows update
$journal = Join-Path $env:ProgramData "Optimize\changes.json"
if (Test-Path $journal) {
    $reset = 0
    foreach ($record in @((Get-Content $journal -Raw | ConvertFrom-Json).Changes | Where-Object { $_.Kind -eq "Registry" })) {
        if ($record.Key -like "HKCU:*" -and $record.User -ne $env:USERNAME) { continue }
        $split = $record.Key.LastIndexOf('\')
        $key = Get-Item -LiteralPath $record.Key.Substring(0, $split) -ErrorAction SilentlyContinue
        $name = $record.Key.Substring($split + 1)
        $exists = $key -and ($key.GetValueNames() -contains $name)
        if ($exists -ne [bool]$record.After.Exists) { $reset++; continue }
        if ($exists -and ((@($key.GetValue($name)) -join ',') -ne (@($record.After.Value) -join ','))) { $reset++ }
    }
    if ($reset -gt 0) { $null = $problems.Add("$reset Optimize setting(s) were changed back, probably by a Windows update. Open Optimize > Maintenance > Reapply Optimize Changes.") }
}

if ($problems.Count -eq 0) { return }

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
$text = [System.Security.SecurityElement]::Escape(($problems | Select-Object -First 3) -join "`n")
$more = if ($problems.Count -gt 3) { " (+$($problems.Count - 3) more)" } else { "" }
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>Optimize health check$more</text><text>$text</text></binding></visual></toast>")
# Windows PowerShell's own app ID, so the notification needs no app registered for it
$appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
'@

    # Windows PowerShell, not 7: the notification classes are only there in 5.1
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $action = New-ScheduledTaskAction -Execute $powershell -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "13:00"
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    # The signed-in user, with full rights so the disk counters can be read; nothing is stored
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Created by Optimize: weekly check of drives, temperatures and settings; notifies only when something needs attention." | Out-Null
    Register-WinUtilChange -Kind "Task" -Key $taskName -Label "Scheduled task $taskName" -Before @{ Exists = $false } -After @{ Exists = $true }

    Write-Host "Weekly health check turned on: Sundays at 13:00, notifying only if something needs attention." -ForegroundColor Green
    Write-WinUtilLog -Component "HealthCheck" -Message "Weekly health check task created"
}
