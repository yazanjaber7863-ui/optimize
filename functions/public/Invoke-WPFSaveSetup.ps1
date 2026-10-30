function Invoke-WPFSaveSetup {
    <#
    .SYNOPSIS
        Saves the apps, tweaks and features ticked in Optimize to a file, the same as Export in
        the settings menu

    .DESCRIPTION
        Load My Setup on another PC ticks the same things again. Export also copies a one-line
        command that installs Optimize and applies the file. The dialogs belong to the interface
        thread, so the work is handed to it.
    #>

    Invoke-WPFUIThread -ScriptBlock { Invoke-WPFImpex -type "export" }
}
