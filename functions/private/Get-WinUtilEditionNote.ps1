function Get-WinUtilEditionNote {
    <#
    .SYNOPSIS
        Explains which editions an entry needs, for its tooltip and the skipped-entry warning

    .PARAMETER Editions
        The entry's "editions" list

    .PARAMETER Short
        Return the few words shown after the entry's name instead of a full sentence
    #>
    param(
        [string[]]$Editions,

        [switch]$Short
    )

    $all = @("Home", "Pro", "Education", "Enterprise")
    $missing = @($all | Where-Object { $Editions -notcontains $_ })
    $edition = if ($sync.windowsEdition) { $sync.windowsEdition } else { "Unknown" }

    if ($Short) {
        if ($missing.Count -eq 1) { return "(not on $($missing[0]))" }
        return "($($Editions -join '/') only)"
    }
    return "Needs Windows $($Editions -join ', ' -replace ', (?=[^,]+$)', ' or '). This PC has Windows $edition, so it is turned off here."
}
