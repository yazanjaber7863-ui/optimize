function Invoke-WPFCreateRestorePoint {
    <#
    .SYNOPSIS
        Creates a restore point now, the same way the "Restore Point - Create" tweak does
    #>

    Step-WinUtilJob -Status "Creating a restore point" -State "Indeterminate"
    Invoke-WinUtilTweaks "WPFTweaksRestorePoint"
}
