function Invoke-WPFLuaMacros {
    <#
    .SYNOPSIS
        Installs LuaMacros, or removes it when it is already installed

    .DESCRIPTION
        LuaMacros is not on winget or Chocolatey; it ships as a zip from hidmacros.eu. That site
        has gone offline, so the zip comes from the Internet Archive's copy when the site does
        not answer. Either way the file must match the hash of the known release (2020-07-13)
        before anything is unpacked.
    #>

    $installDir = Join-Path $env:ProgramFiles "LuaMacros"
    $shortcut = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\LuaMacros.lnk"
    $sha256 = "C22CAFA93AAE3840C8AF68C196181ECF23D4765C8DE0B0DF426BFCAD2047B40B"
    $sources = @(
        "https://www.hidmacros.eu/luamacros.zip",
        "https://web.archive.org/web/20260409233003id_/https://www.hidmacros.eu/luamacros.zip"
    )

    if (Test-Path -LiteralPath (Join-Path $installDir "LuaMacros.exe")) {
        $answer = Show-WinUtilMessage -Title "LuaMacros" -Button "YesNo" -Icon "Question" -Message (
            "LuaMacros is already installed in $installDir.`n`nRemove it? Scripts you saved somewhere else are kept.")
        if ($answer -ne "Yes") {
            return
        }
        Get-Process -Name LuaMacros -ErrorAction SilentlyContinue | Stop-Process -Force
        Remove-Item -LiteralPath $installDir -Recurse -Force
        Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
        Write-WinUtilLog -Component "Install" -Message "Removed LuaMacros from $installDir"
        Write-Host "LuaMacros removed." -ForegroundColor Green
        return
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $zip = Join-Path ([IO.Path]::GetTempPath()) "luamacros-$([guid]::NewGuid().ToString('N')).zip"
    try {
        Step-WinUtilJob -Status "Downloading LuaMacros" -State "Indeterminate"
        $downloaded = $false
        foreach ($source in $sources) {
            try {
                Invoke-WebRequest -Uri $source -OutFile $zip -UseBasicParsing -TimeoutSec 60
                if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -eq $sha256) {
                    $downloaded = $true
                    break
                }
                Write-Warning "The file from $source is not the known LuaMacros release, skipping it."
            } catch {
                Write-Warning "Could not download from $source`: $($_.Exception.Message)"
            }
        }
        if (-not $downloaded) {
            throw "LuaMacros could not be downloaded. Check the internet connection and try again."
        }

        Step-WinUtilJob -Status "Installing LuaMacros" -State "Indeterminate"
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $installDir)

        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($shortcut)
        $link.TargetPath = Join-Path $installDir "LuaMacros.exe"
        $link.WorkingDirectory = $installDir
        $link.Save()
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    }

    Write-WinUtilLog -Component "Install" -Message "Installed LuaMacros to $installDir"
    Write-Host "LuaMacros installed. Open it from the Start menu; sample scripts are in $installDir\samples." -ForegroundColor Green
}
