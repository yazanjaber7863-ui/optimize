function Invoke-WPFShowChanges {
    <#
    .SYNOPSIS
        Lists everything Optimize has changed on this PC and whether each change is still in place

    .DESCRIPTION
        Reads the change journal and groups it by the tweak or button that made each change. A
        Windows feature update can quietly put settings back; those are counted per group and
        listed, so it is clear what to apply again.
    #>

    Step-WinUtilJob -Status "Reading what Optimize changed" -State "Indeterminate"
    $changes = @(Update-WinUtilChangeJournal)
    $path = if ($sync.changeJournalPath) { $sync.changeJournalPath } else { Join-Path $env:ProgramData "Optimize\changes.json" }

    if ($changes.Count -eq 0) {
        Show-WinUtilReport -Title "What Optimize Changed" -Rows @(
            @{ Label = "Nothing yet" }
            @{ Label = "Changes"; Value = "Optimize has not changed anything on this PC since it started keeping track."; Status = "Good" }
        ) -Note "Every tweak, switch and button that changes a setting is written down in $path."
        return
    }

    $build = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).CurrentBuild
    $oldBuilds = @($changes | Where-Object { $_.WindowsBuild -and $_.WindowsBuild -ne $build } | ForEach-Object { $_.WindowsBuild } | Sort-Object -Unique)
    $oldEditions = @($changes | Where-Object { $_.Edition -and $_.Edition -ne $sync.windowsEdition } | ForEach-Object { $_.Edition } | Sort-Object -Unique)

    $rows = @(
        @{ Label = "Summary" }
        @{ Label = "Changes recorded"; Value = "$($changes.Count)" }
        @{ Label = "First change"; Value = (@($changes | ForEach-Object { $_.FirstChanged } | Sort-Object)[0] -replace 'T', ' ') }
    )
    if ($oldBuilds.Count -gt 0) {
        $rows += @{ Label = "Windows updated"; Value = "Some changes were made on build $($oldBuilds -join ', '); this PC is now on $build. Updates can reset settings."; Status = "Warn" }
    }
    if ($oldEditions.Count -gt 0) {
        $rows += @{ Label = "Edition changed"; Value = "Some changes were made on Windows $($oldEditions -join ', '); this PC now has $($sync.windowsEdition)."; Status = "Warn" }
    }

    $resetTotal = 0
    foreach ($group in $changes | Group-Object { if ($_.Source) { $_.Source } else { "Other" } } | Sort-Object Name) {
        $rows += @{ Label = $group.Name }
        $reset = New-Object System.Collections.ArrayList
        $unknown = 0
        foreach ($record in $group.Group) {
            $applied = Test-WinUtilChangeApplied -Record $record
            if ($applied -eq $false) { $null = $reset.Add($record) } elseif ($null -eq $applied) { $unknown++ }
        }
        $resetTotal += $reset.Count

        $count = "$($group.Count) change$(if ($group.Count -ne 1) { 's' })"
        if ($reset.Count -eq 0) {
            $rows += @{ Label = "Status"; Value = "$count, all in place"; Status = "Good" }
        } else {
            $rows += @{ Label = "Status"; Value = "$count, $($reset.Count) changed back"; Status = "Warn" }
            foreach ($record in $reset) {
                $rows += @{ Label = "Changed back"; Value = $record.Label; Status = "Warn" }
            }
        }
        if ($unknown -gt 0) {
            $rows += @{ Label = "Can't check"; Value = "$unknown (scripts and DNS can't be read back)" }
        }
    }

    $note = "The full list is in $path. Undo All Optimize Changes puts every one of these back the way it was before Optimize."
    if ($resetTotal -gt 0) {
        $note = "Something, often a Windows update, changed $resetTotal setting(s) back. Reapply Optimize Changes sets them again. $note"
    }
    Show-WinUtilReport -Title "What Optimize Changed" -Rows $rows -Note $note
}
