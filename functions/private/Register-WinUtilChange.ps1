function Register-WinUtilChange {
    <#
    .SYNOPSIS
        Writes one change into the change journal

    .DESCRIPTION
        The first time something is changed, its Before state is kept. Later changes to the same
        thing only update After, so the journal always remembers what it was before Optimize
        touched it at all. When After matches Before again, for example after an undo, the
        entry is dropped: there is nothing left to put back.

        Does nothing while $global:WinUtilJournalPaused is set, which Undo All uses so putting
        things back is not itself recorded.

    .PARAMETER Kind
        Registry, Service, Tweak, Feature, Appx, PowerPlan, Dns, Task, Firewall, TimeZone or
        ComputerName

    .PARAMETER Key
        What was changed, unique within its kind, e.g. "HKCU:\...\Value" for a registry value

    .PARAMETER Label
        A readable name for the report

    .PARAMETER Before
        The state before this change, as a hashtable

    .PARAMETER After
        The state after it
    #>
    param(
        [Parameter(Mandatory)] [string]$Kind,
        [Parameter(Mandatory)] [string]$Key,
        [string]$Label = $Key,
        [hashtable]$Before,
        [hashtable]$After
    )

    if ($global:WinUtilJournalPaused) {
        return
    }

    $now = (Get-Date).ToString("s")
    $source = if ($global:WinUtilChangeSource) { "$global:WinUtilChangeSource" } else { "" }
    $build = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).CurrentBuild

    try {
        Update-WinUtilChangeJournal -Update {
            param($changes)

            $existing = $null
            for ($index = 0; $index -lt $changes.Count; $index++) {
                if ($changes[$index].Kind -eq $Kind -and $changes[$index].Key -eq $Key) {
                    $existing = $index
                    break
                }
            }

            $beforeState = if ($null -ne $existing) { $changes[$existing].Before } else { $Before }
            if ((Get-WinUtilStateText $beforeState) -eq (Get-WinUtilStateText $After)) {
                if ($null -ne $existing) { $changes.RemoveAt($existing) }
                return
            }

            if ($null -ne $existing) {
                $record = $changes[$existing]
                $record.After = $After
                $record.LastChanged = $now
                if ($source) { $record.Source = $source }
            } else {
                $changes.Add([pscustomobject][ordered]@{
                    Kind = $Kind
                    Key = $Key
                    Label = $Label
                    Source = $source
                    User = $env:USERNAME
                    Before = $Before
                    After = $After
                    FirstChanged = $now
                    LastChanged = $now
                    WindowsBuild = $build
                    Edition = $sync.windowsEdition
                })
            }
        }
    } catch {
        # The journal is a safety net; failing to write it must not stop the change itself
        Write-WinUtilLog -Level "WARN" -Component "Journal" -Message "Could not record $Kind $Key`: $($_.Exception.Message)"
    }
}
