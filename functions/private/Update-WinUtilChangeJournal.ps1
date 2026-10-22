function Update-WinUtilChangeJournal {
    <#
    .SYNOPSIS
        Reads the change journal, lets a script block change the list, and saves it

    .DESCRIPTION
        The journal is the file where Optimize writes down what each setting was before it
        changed it, so everything can be put back later: %ProgramData%\Optimize\changes.json,
        which Windows keeps across feature updates. Jobs run in their own runspaces, so a named
        mutex makes each read-change-write happen one at a time.

    .PARAMETER Update
        Gets the list of change records (a List[object]) and changes it in place. Leave it out
        to only read.
    #>
    param(
        [scriptblock]$Update
    )

    $path = if ($sync.changeJournalPath) { $sync.changeJournalPath } else { Join-Path $env:ProgramData "Optimize\changes.json" }
    $mutex = New-Object System.Threading.Mutex($false, "Global\OptimizeChangeJournal")
    $null = $mutex.WaitOne(10000)
    try {
        $changes = New-Object System.Collections.Generic.List[object]
        if (Test-Path -LiteralPath $path) {
            $saved = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($record in @($saved.Changes)) {
                if ($record) { $changes.Add($record) }
            }
        }

        if (-not $Update) {
            # Unrolled, so callers write @(Update-WinUtilChangeJournal) and get the records
            return $changes.ToArray()
        }

        & $Update $changes

        if ($changes.Count -eq 0) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        } else {
            $folder = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $folder)) {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
            }
            $document = [ordered]@{
                About = "Written by Optimize. Each entry is a setting Optimize changed and what it was before, so Maintenance > Undo All Optimize Changes can put it back."
                Version = 1
                Changes = $changes.ToArray()
            }
            $document | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
        }
    } finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}
