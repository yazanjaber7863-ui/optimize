function Invoke-WPFGamingMode {
    <#
    .SYNOPSIS
        Sets the PC up for games: High Performance power plan, Game Mode on, Xbox Game Bar off

    .DESCRIPTION
        1. High Performance power plan - keeps the CPU at full speed. Windows 11 laptops often
           hide this plan, so it is recreated from its built-in template when missing. An active
           Ultimate Performance plan is kept, since it is faster still.
        2. Game Mode - Windows gives the game priority and holds back updates while playing.
        3. Xbox Game Bar and background recording - off, they cost FPS. Clips still work in
           Medal or the NVIDIA App.
        Undo: pick Balanced under Settings > System > Power.
    #>

    $highPerformance = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

    Step-WinUtilJob -Status "Switching to the High Performance power plan (1/3)" -Percent 0
    # Ultimate Performance is a step above High Performance, so it is kept when already active
    $active = powercfg.exe /getactivescheme
    if ("$active" -match 'Ultimate Performance') {
        Write-WinUtilLog -Component "Gaming" -Message "Keeping the active Ultimate Performance power plan"
    } else {
        Write-WinUtilLog -Component "Gaming" -Message "Activating the High Performance power plan"
        powercfg.exe /setactive $highPerformance 2>$null
    }
    if ($LASTEXITCODE -ne 0) {
        $duplicated = powercfg.exe /duplicatescheme $highPerformance
        $guid = ($duplicated | Select-String -Pattern '[A-Fa-f0-9-]{36}').Matches.Value
        if (-not $guid) {
            throw "powercfg could not create the High Performance power plan."
        }
        powercfg.exe /setactive $guid
        if ($LASTEXITCODE -ne 0) {
            throw "powercfg could not activate the High Performance power plan (exit code $LASTEXITCODE)."
        }
    }

    Step-WinUtilJob -Status "Turning on Game Mode (2/3)" -Percent 33
    Write-WinUtilLog -Component "Gaming" -Message "Turning on Game Mode"
    Set-WinUtilRegistry -Name "AutoGameModeEnabled" -Path "HKCU:\Software\Microsoft\GameBar" -Type "DWord" -Value 1
    Set-WinUtilRegistry -Name "AllowAutoGameMode" -Path "HKCU:\Software\Microsoft\GameBar" -Type "DWord" -Value 1

    Step-WinUtilJob -Status "Turning off Xbox Game Bar and background recording (3/3)" -Percent 66
    Write-WinUtilLog -Component "Gaming" -Message "Turning off Xbox Game Bar and background recording"
    Set-WinUtilRegistry -Name "UseNexusForGameBarEnabled" -Path "HKCU:\Software\Microsoft\GameBar" -Type "DWord" -Value 0
    Set-WinUtilRegistry -Name "AppCaptureEnabled" -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Type "DWord" -Value 0
    Set-WinUtilRegistry -Name "GameDVR_Enabled" -Path "HKCU:\System\GameConfigStore" -Type "DWord" -Value 0

    Write-Host "Gaming Mode on: performance power plan, Game Mode on, Xbox Game Bar off." -ForegroundColor Green
}
