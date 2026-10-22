function Invoke-WPFUndoAllChanges {
    <#
    .SYNOPSIS
        Puts every change in the change journal back the way it was before Optimize

    .DESCRIPTION
        Unlike a tweak's own undo, which writes Windows' default values, this restores what the
        PC actually had. Script-based tweaks run their UndoScript first, newest first, then
        every other change is put back, so the recorded values win. What was put back is moved
        to an archive file next to the journal; anything that could not be stays in the journal.
    #>

    $changes = @(Update-WinUtilChangeJournal)
    if ($changes.Count -eq 0) {
        Show-WinUtilMessage -Title "Undo All Optimize Changes" -Button "OK" -Icon "Information" -Message "Optimize has nothing recorded to undo on this PC." | Out-Null
        return
    }

    $sources = @($changes | ForEach-Object { if ($_.Source) { $_.Source } else { "Other" } } | Sort-Object -Unique)
    $answer = Show-WinUtilMessage -Title "Undo All Optimize Changes" -Button "YesNo" -Icon "Warning" -Message (
        "Put $($changes.Count) change(s) back the way they were before Optimize?`n`n" +
        "From: $($sources -join ', ')`n`n" +
        "Apps Optimize removed are not reinstalled. A restart is needed afterwards.")
    if ("$answer" -ne "Yes") {
        return
    }

    # Scripts first, so the recorded values put back after them are what stays
    $ordered = @($changes | Where-Object { $_.Kind -eq "Tweak" } | Sort-Object LastChanged -Descending) +
        @($changes | Where-Object { $_.Kind -ne "Tweak" } | Sort-Object LastChanged -Descending)

    $restored = New-Object System.Collections.ArrayList
    $failed = New-Object System.Collections.ArrayList
    $global:WinUtilJournalPaused = $true
    try {
        $index = 0
        foreach ($record in $ordered) {
            Step-WinUtilJob -Status "Undoing $($record.Label)" -Percent ([int]($index / $ordered.Count * 100))
            $index++
            try {
                $result = Restore-WinUtilChange -Record $record
            } catch {
                $result = $_.Exception.Message
            }
            if ($result -eq $true) {
                $null = $restored.Add($record)
            } else {
                $null = $failed.Add($record)
                Write-Warning "Could not undo $($record.Label): $result"
                Write-WinUtilLog -Level "WARN" -Component "Journal" -Message "Could not undo $($record.Kind) $($record.Key): $result"
            }
        }
    } finally {
        $global:WinUtilJournalPaused = $false
    }

    # Kept as a record of what was undone, and taken out of the live journal
    $path = if ($sync.changeJournalPath) { $sync.changeJournalPath } else { Join-Path $env:ProgramData "Optimize\changes.json" }
    if ($restored.Count -gt 0) {
        $archive = Join-Path (Split-Path -Parent $path) "changes-undone-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        [ordered]@{ UndoneOn = (Get-Date).ToString("s"); Changes = $restored.ToArray() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $archive -Encoding UTF8
        $keys = @($restored | ForEach-Object { "$($_.Kind)|$($_.Key)" })
        Update-WinUtilChangeJournal -Update {
            param($journal)
            for ($i = $journal.Count - 1; $i -ge 0; $i--) {
                if ($keys -contains "$($journal[$i].Kind)|$($journal[$i].Key)") { $journal.RemoveAt($i) }
            }
        }
    }

    Write-Host "Put back $($restored.Count) change(s)." -ForegroundColor Green
    Write-WinUtilLog -Component "Journal" -Message "Undo All: $($restored.Count) put back, $($failed.Count) could not be"
    if ($failed.Count -gt 0) {
        Write-Warning "$($failed.Count) change(s) could not be put back; they stay listed in $path."
    }
    Request-WinUtilRestart -Message "Put back $($restored.Count) change(s)$(if ($failed.Count) { "; $($failed.Count) could not be (see the console)" }).`n`nRestart now so everything takes effect?" -Reason "Optimize changes undone. Restarting so they take effect."
}
