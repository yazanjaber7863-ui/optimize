function Test-WinUtilEditionSupported {
    <#
    .SYNOPSIS
        Returns whether a config entry, or one of its registry values, applies to this PC's
        Windows edition

    .DESCRIPTION
        An entry without an "editions" field applies everywhere. An unknown edition is treated
        as supported, so Optimize never blocks something just because it could not tell.

    .PARAMETER Entry
        The tweak, feature or registry entry to check

    .PARAMETER Edition
        The edition to check against. Defaults to the one detected when Optimize started.
    #>
    param(
        $Entry,

        [string]$Edition = $sync.windowsEdition
    )

    $editions = @($Entry.editions | Where-Object { $_ })
    if ($editions.Count -eq 0 -or [string]::IsNullOrWhiteSpace($Edition) -or $Edition -eq "Unknown") {
        return $true
    }
    return $editions -contains $Edition
}
