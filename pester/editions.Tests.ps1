#===========================================================================
# Tests - Windows edition support
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilWindowsEdition.ps1")
    . (Join-Path $script:repoRoot "functions\private\Test-WinUtilEditionSupported.ps1")
    . (Join-Path $script:repoRoot "functions\private\Get-WinUtilEditionNote.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilTweaks.ps1")
    . (Join-Path $script:repoRoot "functions\private\Invoke-WinUtilFeatureInstall.ps1")

    function Write-WinUtilLog { param($Message, $Level, $Component) }
    function Set-WinUtilRegistry { param($Name, $Path, $Type, $Value) }
    function Set-WinUtilService { param($Name, $StartupType) }
    function Invoke-WinUtilScript { param($ScriptBlock, $Name) }

    $script:configRoot = Join-Path $script:repoRoot "config"
}

Describe "Get-WinUtilWindowsEdition" {
    It "folds <EditionId> into <Expected>" -TestCases @(
        @{ EditionId = "Core"; Expected = "Home" }
        @{ EditionId = "CoreSingleLanguage"; Expected = "Home" }
        @{ EditionId = "Professional"; Expected = "Pro" }
        @{ EditionId = "ProfessionalWorkstation"; Expected = "Pro" }
        @{ EditionId = "ProfessionalEducation"; Expected = "Pro" }
        @{ EditionId = "Education"; Expected = "Education" }
        @{ EditionId = "Enterprise"; Expected = "Enterprise" }
        @{ EditionId = "EnterpriseS"; Expected = "Enterprise" }
        @{ EditionId = "IoTEnterprise"; Expected = "Enterprise" }
        @{ EditionId = "ServerStandard"; Expected = "Enterprise" }
        @{ EditionId = "SomethingNew"; Expected = "Unknown" }
    ) {
        Get-WinUtilWindowsEdition -EditionId $EditionId | Should -Be $Expected
    }
}

Describe "Test-WinUtilEditionSupported" {
    It "allows an entry with no editions list on any edition" {
        Test-WinUtilEditionSupported -Entry ([pscustomobject]@{ Content = "x" }) -Edition "Home" | Should -BeTrue
    }

    It "blocks an entry on an edition it does not list" {
        $entry = [pscustomobject]@{ editions = @("Pro", "Education", "Enterprise") }
        Test-WinUtilEditionSupported -Entry $entry -Edition "Home" | Should -BeFalse
        Test-WinUtilEditionSupported -Entry $entry -Edition "Pro" | Should -BeTrue
    }

    It "never blocks when the edition could not be told" {
        $entry = [pscustomobject]@{ editions = @("Pro") }
        Test-WinUtilEditionSupported -Entry $entry -Edition "Unknown" | Should -BeTrue
        Test-WinUtilEditionSupported -Entry $entry -Edition "" | Should -BeTrue
    }
}

Describe "Get-WinUtilEditionNote" {
    BeforeEach { $script:sync = @{ windowsEdition = "Home" } }
    AfterEach { Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue }

    It "names the one edition left out" {
        Get-WinUtilEditionNote -Editions "Pro", "Education", "Enterprise" -Short | Should -Be "(not on Home)"
    }

    It "lists the editions when several are left out" {
        Get-WinUtilEditionNote -Editions "Education", "Enterprise" -Short | Should -Be "(Education/Enterprise only)"
    }

    It "says what this PC has" {
        Get-WinUtilEditionNote -Editions "Pro", "Enterprise" | Should -Be "Needs Windows Pro or Enterprise. This PC has Windows Home, so it is turned off here."
    }
}

Describe "Edition checks when running" {
    BeforeEach {
        Mock Set-WinUtilRegistry { }
        Mock Write-Warning { }
        Mock Enable-WindowsOptionalFeature { }
        $script:sync = [Hashtable]::Synchronized(@{
            windowsEdition = "Home"
            configs = @{
                tweaks = [pscustomobject]@{
                    WPFProOnly = [pscustomobject]@{
                        Content = "Pro only"
                        editions = @("Pro", "Education", "Enterprise")
                        registry = @([pscustomobject]@{ Path = "HKCU:\X"; Name = "A"; Type = "DWord"; Value = "1"; OriginalValue = "0" })
                    }
                    WPFMixed = [pscustomobject]@{
                        Content = "Mixed"
                        registry = @(
                            [pscustomobject]@{ Path = "HKCU:\X"; Name = "Everywhere"; Type = "DWord"; Value = "1"; OriginalValue = "0" }
                            [pscustomobject]@{ Path = "HKCU:\X"; Name = "HomeOnly"; Type = "DWord"; Value = "1"; OriginalValue = "0"; editions = @("Home") }
                            [pscustomobject]@{ Path = "HKCU:\X"; Name = "PolicyOnly"; Type = "DWord"; Value = "1"; OriginalValue = "0"; editions = @("Education", "Enterprise") }
                        )
                    }
                }
                feature = [pscustomobject]@{
                    WPFFeatureshyperv = [pscustomobject]@{ Content = "Hyper-V"; feature = @("Microsoft-Hyper-V-All"); editions = @("Pro", "Education", "Enterprise") }
                }
            }
        })
    }
    AfterEach { Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue }

    It "skips a whole tweak this edition cannot use, with a warning" {
        Invoke-WinUtilTweaks -CheckBox "WPFProOnly"

        Should -Invoke -CommandName Set-WinUtilRegistry -Times 0 -Exactly
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like "*Pro only*Home*" }
    }

    It "writes only the registry values meant for this edition" {
        Invoke-WinUtilTweaks -CheckBox "WPFMixed"

        Should -Invoke -CommandName Set-WinUtilRegistry -Times 2 -Exactly
        Should -Invoke -CommandName Set-WinUtilRegistry -Times 0 -Exactly -ParameterFilter { $Name -eq "PolicyOnly" }
    }

    It "undoes only the registry values meant for this edition" {
        Invoke-WinUtilTweaks -CheckBox "WPFMixed" -undo $true

        Should -Invoke -CommandName Set-WinUtilRegistry -Times 1 -Exactly -ParameterFilter { $Name -eq "HomeOnly" -and $Value -eq "0" }
        Should -Invoke -CommandName Set-WinUtilRegistry -Times 0 -Exactly -ParameterFilter { $Name -eq "PolicyOnly" }
    }

    It "does not install a Windows feature this edition does not have" {
        Invoke-WinUtilFeatureInstall -CheckBox "WPFFeatureshyperv"

        Should -Invoke -CommandName Enable-WindowsOptionalFeature -Times 0 -Exactly
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly
    }

    It "installs it on an edition that has it" {
        $script:sync.windowsEdition = "Pro"

        Invoke-WinUtilFeatureInstall -CheckBox "WPFFeatureshyperv"

        Should -Invoke -CommandName Enable-WindowsOptionalFeature -Times 1 -Exactly
    }
}

Describe "editions in the config files" {
    It "only names known editions in <File>" -TestCases @(
        @{ File = "tweaks.json" }
        @{ File = "feature.json" }
    ) {
        $config = Get-Content -Path (Join-Path $script:configRoot $File) -Raw -Encoding UTF8 | ConvertFrom-Json
        $known = @("Home", "Pro", "Education", "Enterprise")
        $problems = foreach ($entry in $config.PSObject.Properties) {
            $lists = @(@{ Where = $entry.Name; Editions = $entry.Value.editions })
            foreach ($registryEntry in @($entry.Value.registry)) {
                if ($registryEntry) { $lists += @{ Where = "$($entry.Name) registry $($registryEntry.Name)"; Editions = $registryEntry.editions } }
            }
            foreach ($list in $lists) {
                if ($null -eq $list.Editions) { continue }
                if (@($list.Editions).Count -eq 0) { "$($list.Where): empty editions list" }
                foreach ($edition in @($list.Editions)) {
                    if ($known -notcontains $edition) { "$($list.Where): unknown edition '$edition'" }
                }
            }
        }
        $problems | Should -BeNullOrEmpty
    }
}
