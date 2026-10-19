function Invoke-WPFOptimiseMyPC {
    <#
    .SYNOPSIS
        One-click cleanup: removes temporary files, then runs Disk Cleanup and the
        Windows component store cleanup

    .DESCRIPTION
        1. Temp files - empties the user and Windows TEMP folders (files in use are skipped)
        2. Disk Cleanup - cleanmgr with every handler selected on the system drive
        3. Component cleanup - DISM removes superseded Windows Update files. /ResetBase is left
           out on purpose so installed updates can still be uninstalled afterwards.
    #>

    $drive = $Env:SystemDrive
    $freeBefore = (Get-PSDrive -Name $drive.TrimEnd(':')).Free

    Step-WinUtilJob -Status "Removing temporary files (1/3)" -Percent 0
    Write-WinUtilLog -Component "Optimise" -Message "Removing temporary files"
    # A temp folder always holds files something has open, including this run's own
    Remove-Item -Path "$Env:Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$Env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

    Step-WinUtilJob -Status "Running Disk Cleanup (2/3)" -Percent 33
    Write-WinUtilLog -Component "Optimise" -Message "Running Disk Cleanup on $drive"
    Start-Process cleanmgr.exe -ArgumentList "/d $drive /VERYLOWDISK" -Wait

    Step-WinUtilJob -Status "Cleaning up old Windows Update files (3/3)" -Percent 66
    Write-WinUtilLog -Component "Optimise" -Message "Running DISM component cleanup"
    $process = Start-Process dism.exe -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup" -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Warning "Windows Update file cleanup finished with exit code $($process.ExitCode)."
    }

    $freedMB = [math]::Round(((Get-PSDrive -Name $drive.TrimEnd(':')).Free - $freeBefore) / 1MB)
    if ($freedMB -lt 0) { $freedMB = 0 }
    Write-Host "Optimise My PC finished - freed about $freedMB MB on $drive" -ForegroundColor Green
    Write-WinUtilLog -Component "Optimise" -Message "Freed about $freedMB MB on $drive"
}
