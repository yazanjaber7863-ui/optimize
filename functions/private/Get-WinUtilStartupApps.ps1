function Get-WinUtilStartupApps {
    <#
    .SYNOPSIS
        Lists the apps that start with Windows from the Run keys and Startup folders

    .DESCRIPTION
        On or off is read from the StartupApproved keys, the same place Task Manager's Startup
        apps page keeps it, so both always agree. An entry with no StartupApproved value is on.
    #>

    $approvedUser = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"
    $approvedMachine = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"

    $entries = New-Object System.Collections.ArrayList

    $runKeys = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Approved = "$approvedUser\Run"; Scope = "you" }
        @{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; Approved = "$approvedMachine\Run"; Scope = "all users" }
        @{ Path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Approved = "$approvedMachine\Run32"; Scope = "all users" }
    )
    foreach ($runKey in $runKeys) {
        $key = Get-Item -Path $runKey.Path -ErrorAction SilentlyContinue
        if (-not $key) { continue }
        foreach ($valueName in $key.GetValueNames()) {
            if ([string]::IsNullOrWhiteSpace($valueName)) { continue }
            $null = $entries.Add([pscustomobject]@{
                Name = $valueName
                Command = [string]$key.GetValue($valueName)
                Scope = $runKey.Scope
                ApprovedPath = $runKey.Approved
                ApprovedName = $valueName
            })
        }
    }

    $folders = @(
        @{ Path = [Environment]::GetFolderPath("Startup"); Approved = "$approvedUser\StartupFolder"; Scope = "you" }
        @{ Path = [Environment]::GetFolderPath("CommonStartup"); Approved = "$approvedMachine\StartupFolder"; Scope = "all users" }
    )
    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder.Path)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $folder.Path -File | Where-Object { $_.Name -ne "desktop.ini" }) {
            $null = $entries.Add([pscustomobject]@{
                Name = $file.BaseName
                Command = $file.FullName
                Scope = $folder.Scope
                ApprovedPath = $folder.Approved
                ApprovedName = $file.Name
            })
        }
    }

    foreach ($entry in $entries) {
        # Run value names are often IDs such as "MicrosoftEdgeAutoLaunch_1CCC...", so the name
        # the program gives itself is shown when there is one
        $exe = if ($entry.Command -match '^\s*"([^"]+)"') { $Matches[1] } elseif ($entry.Command -match '^\s*(\S+?\.exe)') { $Matches[1] } else { $null }
        $description = if ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)) { (Get-Item -LiteralPath $exe).VersionInfo.FileDescription } else { $null }
        if ([string]::IsNullOrWhiteSpace($description)) { $description = $entry.Name }
        $entry.Name = $description.Trim()

        $state = (Get-ItemProperty -Path $entry.ApprovedPath -Name $entry.ApprovedName -ErrorAction SilentlyContinue).$($entry.ApprovedName)
        # The first byte is even when the app is allowed to start and odd when it is turned off
        $enabled = ($null -eq $state) -or (($state[0] -band 1) -eq 0)
        $entry | Add-Member -NotePropertyName Enabled -NotePropertyValue $enabled
    }

    return @($entries | Sort-Object Name)
}
