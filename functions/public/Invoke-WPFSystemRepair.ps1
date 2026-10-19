function Invoke-WPFSystemRepair {
    <#
    .SYNOPSIS
        Checks for system corruption using SFC, and DISM
        Checks for disk failure using Chkdsk

    .DESCRIPTION
        The user picks which steps to run. They always run in this order:
        1. Chkdsk - Checks for disk errors, which can cause system file corruption and notifies of early disk failure
        2. DISM - Repair a corrupted Windows operating system image
        3. SFC - scans protected system files for corruption and fixes them. Runs after DISM
           because SFC repairs files from the component store that DISM has just fixed.
    #>

    $chosen = Show-WinUtilRepairPicker
    if (-not $chosen) {
        Write-Host "System repair cancelled." -ForegroundColor Yellow
        Write-WinUtilLog -Component "SystemRepair" -Message "User cancelled the repair picker"
        return
    }
    $chosen = $chosen -split ","
    Write-WinUtilLog -Component "SystemRepair" -Message "Running: $($chosen -join ', ')"

    # SuccessCodes maps the non-zero exits a step treats as success to what they mean. The codes
    # are per step because the same number means different things: 1 and 2 are ordinary chkdsk
    # outcomes, while 1 from sfc is a failure, and 3010 is a repaired image from DISM only.
    $allSteps = @(
        @{
            Key = "Disk"
            Label = "Checking the disk for errors"
            Arguments = "/c chkdsk /scan /perf"
            # 3 is left out: the disk could not be checked, or has errors an online scan cannot
            # fix, and the steps after this one are not worth running on a disk in that state.
            SuccessCodes = @{
                1 = "errors were found and fixed"
                2 = "cleanup was performed, or was skipped because /f was not given"
            }
        },
        @{
            Key = "DISM"
            Label = "Repairing the Windows image"
            Arguments = "/c dism /online /cleanup-image /restorehealth"
            SuccessCodes = @{
                3010 = "a restart is needed for the repair to take effect"
            }
        },
        @{
            Key = "SFC"
            Label = "Scanning protected system files"
            Arguments = "/c sfc /scannow"
            SuccessCodes = @{}
        }
    )
    $steps = @($allSteps | Where-Object { $chosen -contains $_.Key })

    $completed = 0
    foreach ($step in $steps) {
        Step-WinUtilJob -Status "$($step.Label) ($($completed + 1)/$($steps.Count))" -Percent ([int](($completed / $steps.Count) * 100))
        Write-WinUtilLog -Component "SystemRepair" -Message $step.Label
        # Start-Process does not throw on a nonzero exit, so without this a failed chkdsk, sfc
        # or dism run would still be reported as a completed repair
        $process = Start-Process cmd.exe -ArgumentList $step.Arguments -NoNewWindow -Wait -PassThru
        $exitCode = $process.ExitCode

        if ($exitCode -ne 0) {
            if ($step.SuccessCodes.ContainsKey($exitCode)) {
                # Start-WinUtilJob records WarningRecord output in both the session log and the
                # job result, so accepted nonzero outcomes cannot finish with a green checkmark.
                Write-Warning "$($step.Label) finished: $($step.SuccessCodes[$exitCode])."
            } else {
                throw "$($step.Label) failed with exit code $exitCode."
            }
        }

        $completed++
    }

    # A disk check alone repairs nothing that needs a restart
    if (-not ($chosen -contains "DISM" -or $chosen -contains "SFC")) {
        Write-Host "Disk check finished." -ForegroundColor Green
        return
    }

    # Repaired system files are only picked up after a restart
    $answer = Show-WinUtilMessage -Message "System repair finished.`n`nRestart now so Windows uses the repaired files?`n`nSave your work first. A 15-second countdown starts after you click Yes, and you can still cancel it." -Title "Restart to finish repair" -Button "YesNo" -Icon "Question"
    $restart = "Cancel"
    if ("$answer" -eq "Yes") {
        $restart = Show-WinUtilRestartCountdown -Seconds 15 -Reason "System repair finished. Restarting so Windows uses the repaired files."
    }

    if ($restart -eq "Restart") {
        Write-WinUtilLog -Component "SystemRepair" -Message "Restarting after the repair"
        shutdown.exe /r /t 0
    } else {
        Write-Host "Restart later to finish applying the repair." -ForegroundColor Yellow
    }
}
