function Invoke-WPFAutoClean {
    <#
    .SYNOPSIS
        Turns the weekly automatic cleanup on or off

    .DESCRIPTION
        A scheduled task, "Optimize Weekly Clean", that runs every Sunday at 12:00 as SYSTEM
        (or at the next start if the PC was off). It empties the Windows and user temp folders
        and removes superseded Windows Update files, the silent parts of Optimize My PC.
        Clicking the button again offers to turn it off.
    #>

    $taskName = "Optimize Weekly Clean"
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($existing) {
        $answer = Show-WinUtilMessage -Message "Weekly Auto-Clean is ON (every Sunday at 12:00).`n`nTurn it off?" -Title "Weekly Auto-Clean" -Button "YesNo" -Icon "Question"
        if ("$answer" -eq "Yes") {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host "Weekly Auto-Clean turned off." -ForegroundColor Yellow
            Write-WinUtilLog -Component "AutoClean" -Message "Weekly clean task removed"
        }
        return
    }

    $answer = Show-WinUtilMessage -Message "Turn on Weekly Auto-Clean?`n`nEvery Sunday at 12:00 Windows will quietly delete temp files and old Windows Update files. If the PC is off then, it runs the next time it starts." -Title "Weekly Auto-Clean" -Button "YesNo" -Icon "Question"
    if ("$answer" -ne "Yes") {
        return
    }

    $cleanup = @'
Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Path (Join-Path $_.FullName "AppData\Local\Temp\*") -Recurse -Force -ErrorAction SilentlyContinue
}
dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet
'@
    # Encoded so the script survives being stored as a task argument without any quoting rules
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanup))
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $encoded"
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "12:00"
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Created by Optimize: deletes temp files and old Windows Update files every week." | Out-Null

    Write-Host "Weekly Auto-Clean turned on: every Sunday at 12:00." -ForegroundColor Green
    Write-WinUtilLog -Component "AutoClean" -Message "Weekly clean task created"
}
