#===========================================================================
# Tests - Win11 Creator image servicing and first-logon Optimize run
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilISOServicing.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilISOScript.ps1")
}

Describe "Invoke-WinUtilISOServicing" {
    BeforeEach {
        $script:contents = Join-Path $TestDrive "iso_$([guid]::NewGuid().ToString('N'))\iso_contents"
        New-Item -ItemType Directory -Path "$script:contents\sources" -Force | Out-Null
        $script:dismCalls = [System.Collections.Generic.List[string]]::new()
        $script:failOn = $null

        # A fake dism that records each call and writes the exported image where asked
        function global:dism.exe {
            $line = $args -join " "
            $script:dismCalls.Add($line)
            $global:LASTEXITCODE = 0
            if ($script:failOn -and $line -like $script:failOn) { $global:LASTEXITCODE = 50; return "Error: 50" }
            $destination = $args | Where-Object { "$_" -like "/DestinationImageFile:*" }
            if ($destination) { Set-Content -Path ("$destination" -replace '^/DestinationImageFile:', '') -Value "exported" }
            if ($line -like "*/Get-ProvisionedAppxPackages*") {
                "PackageName : Microsoft.BingNews_4.1.0.0_neutral_~_8wekyb3d8bbwe"
                "PackageName : Microsoft.BingWeather_4.2.0.0_neutral_~_8wekyb3d8bbwe"
                "PackageName : Microsoft.WindowsCalculator_11.0.0.0_neutral_~_8wekyb3d8bbwe"
            }
        }
        function global:reg.exe { $global:LASTEXITCODE = 1 }
        $script:logLines = [System.Collections.Generic.List[string]]::new()
        $script:logger = { param($m) $script:logLines.Add($m) }
    }

    AfterEach {
        Remove-Item Function:\dism.exe, Function:\reg.exe -ErrorAction SilentlyContinue
    }

    It "keeps one edition by exporting it and points later steps at index 1" {
        Set-Content -Path "$script:contents\sources\install.wim" -Value "original"

        $result = Invoke-WinUtilISOServicing -ISOContentsDir $script:contents -InstallImagePath "$script:contents\sources\install.wim" `
            -InstallImageIndex 6 -SingleEdition $true -Log $script:logger

        $result.ImageIndex | Should -Be 1
        $result.ImagePath | Should -Be "$script:contents\sources\install.wim"
        Get-Content $result.ImagePath | Should -Be "exported"
        $script:dismCalls[0] | Should -BeLike "*/Export-Image*/SourceIndex:6*"
        @($script:dismCalls | Where-Object { $_ -like "*/Mount-Image*" }).Count | Should -Be 0
    }

    It "turns install.esd into install.wim before changing it" {
        Set-Content -Path "$script:contents\sources\install.esd" -Value "original"

        $result = Invoke-WinUtilISOServicing -ISOContentsDir $script:contents -InstallImagePath "$script:contents\sources\install.esd" `
            -InstallImageIndex 2 -Features @("NetFx3") -Log $script:logger

        $result.ImagePath | Should -BeLike "*install.wim"
        Test-Path "$script:contents\sources\install.esd" | Should -BeFalse
        $script:dismCalls | Where-Object { $_ -like "*/Enable-Feature*" } | Should -BeLike "*/FeatureName:NetFx3*/Source:*sxs*/LimitAccess*"
    }

    It "removes only the packages of the ticked parts of Windows, then saves the image" {
        Set-Content -Path "$script:contents\sources\install.wim" -Value "original"

        Invoke-WinUtilISOServicing -ISOContentsDir $script:contents -InstallImagePath "$script:contents\sources\install.wim" `
            -InstallImageIndex 1 -RemoveComponents @("Bing") -Log $script:logger | Out-Null

        $removed = @($script:dismCalls | Where-Object { $_ -like "*/Remove-ProvisionedAppxPackage*" })
        $removed.Count | Should -Be 2
        $removed -join " " | Should -Not -Match "Calculator"
        $script:dismCalls[-1] | Should -BeLike "*/Unmount-Image*/Commit*"
    }

    It "warns and carries on when one update does not fit" {
        Set-Content -Path "$script:contents\sources\install.wim" -Value "original"
        $script:failOn = "*bad.msu*"

        Invoke-WinUtilISOServicing -ISOContentsDir $script:contents -InstallImagePath "$script:contents\sources\install.wim" `
            -InstallImageIndex 1 -UpdatePackages @("C:\u\bad.msu", "C:\u\good.msu") -Log $script:logger | Out-Null

        @($script:logLines | Where-Object { $_ -like "Warning:*bad.msu*" }).Count | Should -Be 1
        $script:dismCalls | Where-Object { $_ -like "*good.msu*" } | Should -Not -BeNullOrEmpty
        $script:dismCalls[-1] | Should -BeLike "*/Commit*"
    }

    It "throws away the mount when saving fails" {
        Set-Content -Path "$script:contents\sources\install.wim" -Value "original"
        $script:failOn = "*/Commit*"

        { Invoke-WinUtilISOServicing -ISOContentsDir $script:contents -InstallImagePath "$script:contents\sources\install.wim" `
            -InstallImageIndex 1 -Features @("NetFx3") -Log $script:logger } | Should -Throw

        $script:dismCalls[-1] | Should -BeLike "*/Discard*"
    }
}

Describe "First-logon Optimize run" {
    It "adds the selections file and starts Optimize on first logon" {
        $template = Get-Content (Join-Path $script:repoRoot "tools\autounattend.xml") -Raw
        $contents = Join-Path $TestDrive "media"
        New-Item -ItemType Directory -Path $contents -Force | Out-Null

        Invoke-WinUtilISOScript -ISOContentsDir $contents -AutoUnattendXml $template -InstallImageIndex 1 `
            -FirstLogonSelections @("WPFTweaksTelemetry", "WPFInstallvlc") -Log { param($m) }

        [xml]$written = Get-Content (Join-Path $contents "autounattend.xml") -Raw
        $ns = New-Object System.Xml.XmlNamespaceManager($written.NameTable)
        $ns.AddNamespace('sg', 'https://schneegans.de/windows/unattend-generator/')
        $selections = $written.SelectSingleNode('//sg:File[@path="C:\Windows\Setup\Scripts\Optimize-FirstLogon.json"]', $ns).InnerText | ConvertFrom-Json
        $selections | Should -Be @("WPFTweaksTelemetry", "WPFInstallvlc")
        $written.SelectSingleNode('//sg:File[@path="C:\Windows\Setup\Scripts\FirstLogon.ps1"]', $ns).InnerText | Should -Match 'Optimize-FirstLogon\.ps1'
        $written.SelectSingleNode('//sg:File[@path="C:\Windows\Setup\Scripts\Optimize-FirstLogon.ps1"]', $ns).InnerText | Should -Match "-Config 'C:\\Windows\\Setup\\Scripts\\Optimize-FirstLogon\.json'"
    }

    It "adds nothing for Optimize when no preset or apps were picked" {
        $template = Get-Content (Join-Path $script:repoRoot "tools\autounattend.xml") -Raw
        $contents = Join-Path $TestDrive "media2"
        New-Item -ItemType Directory -Path $contents -Force | Out-Null

        Invoke-WinUtilISOScript -ISOContentsDir $contents -AutoUnattendXml $template -InstallImageIndex 1 -Log { param($m) }

        Get-Content (Join-Path $contents "autounattend.xml") -Raw | Should -Not -Match 'Optimize-FirstLogon'
    }
}
