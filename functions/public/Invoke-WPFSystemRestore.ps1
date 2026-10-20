function Invoke-WPFSystemRestore {
    <#
    .SYNOPSIS
        Opens Windows' System Restore, where the user picks a restore point to go back to
    #>

    $points = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
    if ($points.Count -eq 0) {
        Write-Warning "There are no restore points yet. Use 'Create Restore Point Now' first."
        return
    }
    Write-Host "Opening System Restore ($($points.Count) restore point(s) available)." -ForegroundColor Cyan
    Start-Process "$env:SystemRoot\System32\rstrui.exe"
}
