function Invoke-WPFBigFiles {
    <#
    .SYNOPSIS
        Finds the biggest files and folders on a drive, after asking which drive and whether to
        scan

    .DESCRIPTION
        The walk is done by a few lines of C#: PowerShell's own Get-ChildItem takes minutes on a
        full system drive. Folders that cannot be read are skipped, and links to other folders
        are not followed, so nothing is counted twice. Each result opens its location in File
        Explorer when clicked. Nothing is deleted.
    #>

    $drives = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 } | Sort-Object DriveLetter)
    $system = $env:SystemDrive.TrimEnd(':')
    $choices = ($drives | ForEach-Object { "$($_.DriveLetter): ($([math]::Round(($_.Size - $_.SizeRemaining) / 1GB)) GB used)" }) -join ", "

    $letter = Show-WinUtilTextPrompt -Title "Find Big Files" -Message "Which drive should be scanned? $choices. A full drive takes a minute or two; nothing is changed or deleted." -Default $system
    if (-not $letter) {
        Write-Host "Big files scan cancelled." -ForegroundColor Yellow
        return
    }
    $letter = $letter.Trim().TrimEnd(':', '\').ToUpper()
    if ($drives.DriveLetter -notcontains [char]$letter[0] -or $letter.Length -ne 1) {
        throw "'$letter' is not one of this PC's drives ($(($drives.DriveLetter | ForEach-Object { "$($_):" }) -join ', '))."
    }
    $root = "$($letter):\"

    Initialize-WinUtilDiskScan

    Step-WinUtilJob -Status "Scanning $root for big files" -State "Indeterminate"
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $files = [OptimizeDiskScan]::Scan($root, 20)
    $folders = [OptimizeDiskScan]::FolderBytes
    Write-WinUtilLog -Component "BigFiles" -Message "Scanned $root in $([int]$clock.Elapsed.TotalSeconds)s, $([math]::Round([OptimizeDiskScan]::TotalBytes / 1GB)) GB in files"

    $format = { param($bytes) if ($bytes -ge 1GB) { "{0:N1} GB" -f ($bytes / 1GB) } else { "{0:N0} MB" -f ($bytes / 1MB) } }

    # The biggest folders. Sizes come largest first, so a parent is listed before its children;
    # a child holding most of its parent's size replaces it, so the list points at where the
    # space really is rather than at C:\Users
    $topFolders = New-Object System.Collections.ArrayList
    foreach ($candidate in $folders.GetEnumerator() | Sort-Object Value -Descending) {
        if ($candidate.Value -lt 500MB) { break }
        for ($i = $topFolders.Count - 1; $i -ge 0; $i--) {
            $listed = $topFolders[$i]
            if ($candidate.Key.StartsWith("$($listed.Key)\", [StringComparison]::OrdinalIgnoreCase) -and $candidate.Value -ge 0.8 * $listed.Value) {
                $topFolders.RemoveAt($i)
            }
        }
        $null = $topFolders.Add($candidate)
    }
    $topFolders = @($topFolders | Sort-Object Value -Descending | Select-Object -First 12)

    $rows = @(@{ Label = "Biggest folders" })
    foreach ($folder in $topFolders) {
        $rows += @{ Label = (& $format $folder.Value); Value = $folder.Key; Path = $folder.Key }
    }
    $rows += @{ Label = "Biggest files" }
    foreach ($file in $files) {
        $rows += @{ Label = (& $format $file.Value); Value = $file.Key; Path = $file.Key }
    }

    Show-WinUtilReport -Title "Big Files on $root" -Rows $rows -Note "Click a path to open it in File Explorer. Nothing here is deleted; remove things you no longer need yourself, or uninstall them. Folders like Windows and WinSxS are part of Windows: leave them."
}
