function Get-WinUtilStateText {
    <#
    .SYNOPSIS
        Turns a recorded state into text that is the same whenever the state is the same

    .DESCRIPTION
        A state is a hashtable when it is recorded and an object once it is read back from the
        journal, and the two list their fields in different orders. Sorting the fields and
        writing every value as text lets states be compared however they were stored.

    .PARAMETER State
        A hashtable or object, or $null
    #>
    param($State)

    if ($null -eq $State) {
        return ""
    }

    $pairs = if ($State -is [System.Collections.IDictionary]) {
        foreach ($key in $State.Keys) { @{ Name = "$key"; Value = $State[$key] } }
    } else {
        foreach ($property in $State.PSObject.Properties) { @{ Name = $property.Name; Value = $property.Value } }
    }

    $parts = foreach ($pair in @($pairs | Sort-Object { $_.Name })) {
        $value = if ($null -eq $pair.Value) { "<null>" } else { (@($pair.Value) | ForEach-Object { "$_" }) -join "," }
        "$($pair.Name)=$value"
    }
    return ($parts -join ";")
}
