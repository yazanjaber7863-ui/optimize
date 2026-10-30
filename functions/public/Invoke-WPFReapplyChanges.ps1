function Invoke-WPFReapplyChanges {
    <#
    .SYNOPSIS
        Sets again the Optimize changes that something, usually a Windows update, has changed back

    .DESCRIPTION
        Uses the values in the change journal, so it needs no tweaks ticked and applies exactly
        what Optimize set before. Script-based tweaks cannot be checked, so they are run again
        too; they are written to be safe to repeat.
    #>

    Step-WinUtilJob -Status "Checking which changes were undone" -State "Indeterminate"
    $changes = @(Update-WinUtilChangeJournal)
    $toReapply = @($changes | Where-Object {
        $_.Kind -eq "Tweak" -or ((Test-WinUtilChangeApplied -Record $_) -eq $false)
    })
    $reset = @($toReapply | Where-Object { $_.Kind -ne "Tweak" })

    if ($reset.Count -eq 0) {
        Show-WinUtilMessage -Title "Reapply Optimize Changes" -Button "OK" -Icon "Information" -Message (
            "Everything Optimize changed is still in place. Nothing to reapply.") | Out-Null
        return
    }

    $sources = @($reset | ForEach-Object { if ($_.Source) { $_.Source } else { "Other" } } | Sort-Object -Unique)
    $answer = Show-WinUtilMessage -Title "Reapply Optimize Changes" -Button "YesNo" -Icon "Question" -Message (
        "$($reset.Count) change(s) were changed back, probably by a Windows update.`n`nFrom: $($sources -join ', ')`n`nSet them again?")
    if ("$answer" -ne "Yes") {
        return
    }

    New-WinUtilAutoRestorePoint -Reason "reapplying Optimize changes"

    $done = 0
    $failed = 0
    $global:WinUtilJournalPaused = $true
    try {
        # Scripts first, then the recorded values, the same order they were first applied in
        $ordered = @($toReapply | Where-Object { $_.Kind -eq "Tweak" } | Sort-Object FirstChanged) +
            @($toReapply | Where-Object { $_.Kind -ne "Tweak" } | Sort-Object FirstChanged)
        $index = 0
        foreach ($record in $ordered) {
            Step-WinUtilJob -Status "Reapplying $($record.Label)" -Percent ([int]($index / $ordered.Count * 100))
            $index++
            try {
                $result = Restore-WinUtilChange -Record $record -To "After"
            } catch {
                $result = $_.Exception.Message
            }
            if ($result -eq $true) {
                $done++
            } else {
                $failed++
                Write-Warning "Could not reapply $($record.Label): $result"
                Write-WinUtilLog -Level "WARN" -Component "Journal" -Message "Could not reapply $($record.Kind) $($record.Key): $result"
            }
        }
    } finally {
        $global:WinUtilJournalPaused = $false
    }

    Write-Host "Reapplied $done change(s)." -ForegroundColor Green
    Write-WinUtilLog -Component "Journal" -Message "Reapply: $done done, $failed could not be"
    Request-WinUtilRestart -Message "Reapplied $done change(s)$(if ($failed) { "; $failed could not be (see the console)" }).`n`nRestart now so everything takes effect?" -Reason "Optimize changes reapplied. Restarting so they take effect."
}
