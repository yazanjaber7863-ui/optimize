function Uninstall-WinUtilChoco {
    <#
    .SYNOPSIS
        Removes Chocolatey itself, leaving the apps it installed in place

    .DESCRIPTION
        Follows Chocolatey's documented manual uninstall: delete its folder, its environment
        variables and its PATH entry. PATH is edited through the registry so entries such as
        %SystemRoot% stay unexpanded, which [Environment]::SetEnvironmentVariable would not keep.
        A failure is reported as a warning, since the apps are already installed by then.
    #>

    $root = [System.Environment]::GetEnvironmentVariable("ChocolateyInstall", "Machine")
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Join-Path $env:ProgramData "chocolatey"
    }

    # The folder is deleted recursively, so make sure it really is Chocolatey's
    if (-not (Test-Path -LiteralPath (Join-Path $root "choco.exe"))) {
        Write-WinUtilLog -Level "WARN" -Component "Package" -Message "Not removing Chocolatey: no choco.exe in $root"
        Write-Warning "Chocolatey was not removed: no choco.exe in $root"
        return
    }

    Write-WinUtilLog -Component "Package" -Message "Removing Chocolatey from $root"

    try {
        $environmentKeys = @(
            @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" }
            @{ Hive = [Microsoft.Win32.Registry]::CurrentUser; Path = "Environment" }
        )
        foreach ($environmentKey in $environmentKeys) {
            $key = $environmentKey.Hive.OpenSubKey($environmentKey.Path, $true)
            if (-not $key) { continue }

            try {
                $path = $key.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $kept = @($path -split ';' | Where-Object { $_ -and $_ -notlike "$root*" -and $_ -notlike "*%ChocolateyInstall%*" })
                if ($kept.Count -ne @($path -split ';' | Where-Object { $_ }).Count) {
                    $key.SetValue("Path", ($kept -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
                }

                foreach ($name in "ChocolateyInstall", "ChocolateyLastPathUpdate", "ChocolateyToolsLocation") {
                    $key.DeleteValue($name, $false)
                }
            } finally {
                $key.Close()
            }
        }

        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
        }

        $env:PATH = (@($env:PATH -split ';' | Where-Object { $_ -and $_ -notlike "$root*" })) -join ';'
        Remove-Item Env:\ChocolateyInstall -ErrorAction SilentlyContinue

        Write-WinUtilLog -Component "Package" -Message "Chocolatey removed."
    } catch {
        Write-WinUtilLog -Level "WARN" -Component "Package" -Message "Chocolatey could not be fully removed: $($_.Exception.Message)"
        Write-Warning "Chocolatey could not be fully removed: $($_.Exception.Message)"
    }
}
