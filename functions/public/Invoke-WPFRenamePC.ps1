function Invoke-WPFRenamePC {
    <#
    .SYNOPSIS
        Renames the PC to a name the user types, then offers a restart (needed for the new name)
    #>

    $newName = Show-WinUtilTextPrompt -Title "Rename PC" -Message "Up to 15 letters, numbers or dashes, for example Sky-PC. The name shows on your network, in Tailscale and in Syncthing." -Default $env:COMPUTERNAME
    if (-not $newName) {
        Write-Host "PC name unchanged." -ForegroundColor Yellow
        return
    }

    # Windows' NetBIOS rules: 1-15 characters, letters, digits and dashes, not only digits
    if ($newName -notmatch '^[A-Za-z0-9-]{1,15}$' -or $newName -match '^\d+$' -or $newName.StartsWith('-') -or $newName.EndsWith('-')) {
        throw "'$newName' can't be a PC name. Use up to 15 letters, numbers or dashes (not only numbers, and not starting or ending with a dash)."
    }
    if ($newName -eq $env:COMPUTERNAME) {
        Write-Host "The PC is already called $newName." -ForegroundColor Yellow
        return
    }

    Step-WinUtilJob -Status "Renaming the PC to $newName" -State "Indeterminate"
    Write-WinUtilLog -Component "RenamePC" -Message "Renaming $env:COMPUTERNAME to $newName"
    Rename-Computer -NewName $newName -Force -ErrorAction Stop
    Register-WinUtilChange -Kind "ComputerName" -Key "ComputerName" -Label "PC name" -Before @{ Name = $env:COMPUTERNAME } -After @{ Name = $newName }
    Write-Host "PC renamed to $newName. It takes effect after a restart." -ForegroundColor Green

    Request-WinUtilRestart -Message "The PC will be called $newName after a restart.`n`nRestart now?" -Reason "Renaming the PC to $newName."
}
