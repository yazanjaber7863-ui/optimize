function Show-WinUtilFolderPicker {
    <#
    .SYNOPSIS
        Asks for a folder and returns its path, or $null when cancelled

    .DESCRIPTION
        WPF on .NET Framework has no folder picker, so this uses the Windows Forms one, on the
        interface thread so it can be called from a job body.

    .PARAMETER Description
        The line shown at the top of the picker

    .PARAMETER ShowNewFolderButton
        Let the user make a new folder, for saving into
    #>
    param(
        [string]$Description = "Pick a folder",
        [switch]$ShowNewFolderButton
    )

    if (-not (Test-WinUtilUIAlive)) {
        Write-WinUtilLog -Level "WARN" -Component "Dialog" -Message "No window for the folder picker"
        return $null
    }

    $path = Invoke-WPFUIThread -PassThru -Parameters @{ Description = $Description; NewFolder = [bool]$ShowNewFolderButton } -ScriptBlock {
        param($Description, $NewFolder)
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $Description
        $dialog.ShowNewFolderButton = $NewFolder
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.SelectedPath }
        $dialog.Dispose()
    }

    if ([string]::IsNullOrWhiteSpace("$path")) { return $null }
    return "$path"
}
