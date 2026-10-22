function Get-WinUtilWindowsEdition {
    <#
    .SYNOPSIS
        Returns which Windows edition family this PC runs: Home, Pro, Education, Enterprise or
        Unknown

    .DESCRIPTION
        Config entries can list the editions they work on in an "editions" field. The families
        here are what those lists use. Variants are folded into their family: Home Single
        Language is Home, Pro for Workstations and Pro Education are Pro, LTSC and IoT Enterprise
        are Enterprise. Server is treated as Enterprise, since it honors the same policies.

    .PARAMETER EditionId
        The EditionID to classify. Defaults to this PC's, from the registry.
    #>
    param(
        [string]$EditionId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name EditionID -ErrorAction SilentlyContinue).EditionID
    )

    switch -Wildcard ($EditionId) {
        "Core*" { return "Home" }
        "Professional*" { return "Pro" }
        "Education*" { return "Education" }
        "Enterprise*" { return "Enterprise" }
        "IoTEnterprise*" { return "Enterprise" }
        "Server*" { return "Enterprise" }
        default { return "Unknown" }
    }
}
