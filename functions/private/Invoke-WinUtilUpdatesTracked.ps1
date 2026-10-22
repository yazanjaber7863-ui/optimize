function Invoke-WinUtilUpdatesTracked {
    <#
    .SYNOPSIS
        Runs one of the Windows Update profiles and records what it changed in the change journal

    .DESCRIPTION
        The profiles write the registry, services and scheduled tasks directly. These are the
        places they touch, read before and after so Undo All can put them back.

    .PARAMETER Label
        The name the changes are recorded under

    .PARAMETER ScriptBlock
        The profile to run
    #>
    param(
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory, Position = 0)] [scriptblock]$ScriptBlock
    )

    $global:WinUtilChangeSource = $Label
    try {
        Invoke-WinUtilTrackedChange -ScriptBlock $ScriptBlock -RegistryKeys @(
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        ) -Services @("BITS", "wuauserv", "UsoSvc") -TaskPaths @(
            '\Microsoft\Windows\InstallService\*'
            '\Microsoft\Windows\UpdateOrchestrator\*'
            '\Microsoft\Windows\UpdateAssistant\*'
            '\Microsoft\Windows\WaaSMedic\*'
            '\Microsoft\Windows\WindowsUpdate\*'
            '\Microsoft\WindowsUpdate\*'
        )
    } finally {
        $global:WinUtilChangeSource = $null
    }
}
