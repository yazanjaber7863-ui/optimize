function Invoke-WPFLoadSetup {
    <#
    .SYNOPSIS
        Ticks the apps, tweaks and features from a file made by Save My Setup, the same as Import
        in the settings menu

    .DESCRIPTION
        Nothing runs until the user presses Install or Run Tweaks, so they can look over what was
        ticked first. The dialogs belong to the interface thread, so the work is handed to it.
    #>

    Invoke-WPFUIThread -ScriptBlock { Invoke-WPFImpex -type "import" }
}
