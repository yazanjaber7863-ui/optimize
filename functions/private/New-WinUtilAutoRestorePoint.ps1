function New-WinUtilAutoRestorePoint {
    <#
    .SYNOPSIS
        Makes a Windows restore point before Optimize changes the system, at most once a day

    .DESCRIPTION
        A safety net under every bigger change (Run Tweaks, Undo All, Reapply): if anything goes
        wrong, Maintenance > Go Back to a Restore Point returns the whole system to this moment.
        Skipped when there is already a restore point from the last 24 hours, which also keeps
        Windows' own once-a-day limit from refusing it. If System Restore is off on the system
        drive it is turned on, since there is nothing to go back to otherwise.

        A failure is a warning, not an error: the change the user asked for still goes ahead.

    .PARAMETER Reason
        What is about to happen, shown in the restore point's description
    #>
    param(
        [string]$Reason = "Optimize changes"
    )

    try {
        $latest = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1
        if ($latest -and $latest.ConvertToDateTime($latest.CreationTime) -gt (Get-Date).AddHours(-24)) {
            Write-WinUtilLog -Component "RestorePoint" -Message "A restore point from the last 24 hours exists, not making another"
            return
        }

        Step-WinUtilJob -Status "Making a restore point first, just in case" -State "Indeterminate"
        Write-Host "Making a restore point before $Reason, just in case..." -ForegroundColor Cyan
        if (-not $latest) {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        }
        Checkpoint-Computer -Description "Before $Reason (Optimize)" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-WinUtilLog -Component "RestorePoint" -Message "Restore point made before $Reason"
    } catch {
        Write-Warning "Could not make a restore point first ($($_.Exception.Message)). Carrying on."
        Write-WinUtilLog -Level "WARN" -Component "RestorePoint" -Message "Automatic restore point failed: $($_.Exception.Message)"
    }
}
