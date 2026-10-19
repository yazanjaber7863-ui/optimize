function Request-WinUtilRestart {
    <#
    .SYNOPSIS
        Asks whether to restart now and, on Yes, restarts after a cancellable countdown

    .PARAMETER Message
        The Yes/No question. A note about saving work and the countdown is added to it.

    .PARAMETER Reason
        Shown in the countdown window.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$Reason,

        [int]$Seconds = 15
    )

    $answer = Show-WinUtilMessage -Message "$Message`n`nSave your work first. A $Seconds-second countdown starts after you click Yes, and you can still cancel it." -Title "Restart needed" -Button "YesNo" -Icon "Question"
    $restart = "Cancel"
    if ("$answer" -eq "Yes") {
        $restart = Show-WinUtilRestartCountdown -Seconds $Seconds -Reason $Reason
    }

    if ($restart -eq "Restart") {
        Write-WinUtilLog -Component "Restart" -Message $Reason
        shutdown.exe /r /t 0
    } else {
        Write-Host "Restart later to finish." -ForegroundColor Yellow
    }
}
