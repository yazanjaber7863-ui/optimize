function Invoke-WPFStartupApps {
    <#
    .SYNOPSIS
        Shows the apps that start with Windows and turns off the ones the user unticks

    .DESCRIPTION
        Uses the same on/off switch as Task Manager's Startup apps page, so nothing is deleted
        and every change can be undone from either place.
    #>

    Step-WinUtilJob -Status "Reading startup apps" -State "Indeterminate"
    $entries = @(Get-WinUtilStartupApps)
    Write-WinUtilLog -Component "Startup" -Message "Found $($entries.Count) startup app(s)"

    $choice = Show-WinUtilStartupPicker -Entries $entries
    if (-not $choice) {
        Write-Host "Startup apps unchanged." -ForegroundColor Yellow
        return
    }

    $ticked = @(($choice -replace '^ok:', '') -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })
    $changed = 0
    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        $wanted = $ticked -contains $index
        if ($wanted -eq $entry.Enabled) { continue }

        Set-WinUtilStartupApp -Entry $entry -Enabled $wanted
        $changed++
        $state = if ($wanted) { "on" } else { "off" }
        Write-Host "Turned $state at startup: $($entry.Name)" -ForegroundColor Cyan
        Write-WinUtilLog -Component "Startup" -Message "Turned $state at startup: $($entry.Name)"
    }

    if ($changed -eq 0) {
        Write-Host "Startup apps unchanged." -ForegroundColor Yellow
    } else {
        Write-Host "Saved $changed change(s). They apply the next time Windows starts." -ForegroundColor Green
    }
}
