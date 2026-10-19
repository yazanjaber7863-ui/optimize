function Set-WinUtilStartupApp {
    <#
    .SYNOPSIS
        Turns one startup entry from Get-WinUtilStartupApps on or off the way Task Manager does
    #>
    param(
        [Parameter(Mandatory)]
        $Entry,

        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    # 12 bytes: a state byte, three zero bytes, then when it was turned off as a FILETIME
    if ($Enabled) {
        $value = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    } else {
        $value = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTime()))
    }

    if (-not (Test-Path -Path $Entry.ApprovedPath)) {
        $null = New-Item -Path $Entry.ApprovedPath -Force
    }
    Set-ItemProperty -Path $Entry.ApprovedPath -Name $Entry.ApprovedName -Value $value -Type Binary
}
