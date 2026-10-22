function Get-WinUtilRegistryState {
    <#
    .SYNOPSIS
        Reads one registry value as a state for the change journal: whether it exists, its
        value and its type

    .PARAMETER Path
        The key, e.g. HKCU:\Software\Microsoft\GameBar

    .PARAMETER Name
        The value name
    #>
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name
    )

    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $key -or $key.GetValueNames() -notcontains $Name) {
        return @{ Exists = $false; Value = $null; Type = $null }
    }
    # Unexpanded, so a %SystemRoot% path is put back as written
    $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    return @{ Exists = $true; Value = $value; Type = "$($key.GetValueKind($Name))" }
}
