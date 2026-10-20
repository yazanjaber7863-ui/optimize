function Get-WinUtilTabEntries {
    <#
    .SYNOPSIS
        Returns the entries of one or more config objects that belong on a given tab

    .DESCRIPTION
        An entry with a "tab" field is shown on that tab instead of the one its config file
        normally fills. With no -Tab, the entries without a "tab" field are returned, which is
        what the Tweaks and Config tabs show.

    .PARAMETER Config
        The config objects to read, for example $sync.configs.tweaks and $sync.configs.feature

    .PARAMETER Tab
        The tab header to collect entries for
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$Config,

        [string]$Tab = ""
    )

    $entries = [ordered]@{}
    foreach ($configObject in $Config) {
        foreach ($property in $configObject.PSObject.Properties) {
            if ("$($property.Value.tab)" -eq $Tab) {
                $entries[$property.Name] = $property.Value
            }
        }
    }
    return [pscustomobject]$entries
}
