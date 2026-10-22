#===========================================================================
# Tests - Change journal (record what Optimize changed, and put it back)
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    foreach ($name in "Update-WinUtilChangeJournal", "Register-WinUtilChange", "Get-WinUtilStateText",
        "Get-WinUtilRegistryState", "Restore-WinUtilChange", "Test-WinUtilChangeApplied", "Set-WinUtilRegistry",
        "Invoke-WinUtilTrackedChange") {
        . (Join-Path $script:repoRoot "functions\private\$name.ps1")
    }

    function Write-WinUtilLog { param($Message, $Level, $Component) }

    $script:testKey = "HKCU:\Software\OptimizeJournalTest"
}

Describe "Get-WinUtilStateText" {
    It "reads the same for a hashtable and the object it becomes in the journal" {
        $state = @{ Type = "DWord"; Exists = $true; Value = 0 }
        $roundTripped = $state | ConvertTo-Json | ConvertFrom-Json

        Get-WinUtilStateText $roundTripped | Should -Be (Get-WinUtilStateText $state)
    }

    It "treats a number and its text as the same value" {
        Get-WinUtilStateText @{ Value = 0 } | Should -Be (Get-WinUtilStateText @{ Value = "0" })
    }
}

Describe "Register-WinUtilChange" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            changeJournalPath = Join-Path $TestDrive "changes-$([guid]::NewGuid()).json"
            windowsEdition = "Education"
        })
        $global:WinUtilJournalPaused = $false
    }
    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        $global:WinUtilChangeSource = $null
    }

    It "keeps the first Before and the latest After" {
        Register-WinUtilChange -Kind "Service" -Key "Spooler" -Before @{ StartType = "Automatic" } -After @{ StartType = "Manual" }
        Register-WinUtilChange -Kind "Service" -Key "Spooler" -Before @{ StartType = "Manual" } -After @{ StartType = "Disabled" }

        $changes = @(Update-WinUtilChangeJournal)
        $changes.Count | Should -Be 1
        $changes[0].Before.StartType | Should -Be "Automatic"
        $changes[0].After.StartType | Should -Be "Disabled"
    }

    It "drops the entry once it is back where it started" {
        Register-WinUtilChange -Kind "Service" -Key "Spooler" -Before @{ StartType = "Automatic" } -After @{ StartType = "Manual" }
        Register-WinUtilChange -Kind "Service" -Key "Spooler" -Before @{ StartType = "Manual" } -After @{ StartType = "Automatic" }

        @(Update-WinUtilChangeJournal).Count | Should -Be 0
        Test-Path -LiteralPath $script:sync.changeJournalPath | Should -BeFalse
    }

    It "records nothing when nothing changes" {
        Register-WinUtilChange -Kind "Registry" -Key "HKCU:\X\Y" -Before @{ Exists = $true; Value = 1; Type = "DWord" } -After @{ Exists = $true; Value = "1"; Type = "DWord" }

        @(Update-WinUtilChangeJournal).Count | Should -Be 0
    }

    It "notes which tweak or button made the change, the edition and the Windows build" {
        $global:WinUtilChangeSource = "Telemetry - Disable"
        Register-WinUtilChange -Kind "Service" -Key "DiagTrack" -Before @{ StartType = "Automatic" } -After @{ StartType = "Disabled" }

        $record = @(Update-WinUtilChangeJournal)[0]
        $record.Source | Should -Be "Telemetry - Disable"
        $record.Edition | Should -Be "Education"
        $record.WindowsBuild | Should -Not -BeNullOrEmpty
    }

    It "records nothing while Undo All is putting things back" {
        $global:WinUtilJournalPaused = $true
        try {
            Register-WinUtilChange -Kind "Service" -Key "Spooler" -Before @{ StartType = "Automatic" } -After @{ StartType = "Manual" }
        } finally {
            $global:WinUtilJournalPaused = $false
        }

        @(Update-WinUtilChangeJournal).Count | Should -Be 0
    }
}

Describe "Registry changes round trip" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{ changeJournalPath = Join-Path $TestDrive "changes-$([guid]::NewGuid()).json" })
        $global:WinUtilJournalPaused = $false
        Remove-Item -Path $script:testKey -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $script:testKey -Force | Out-Null
        New-ItemProperty -Path $script:testKey -Name "Existing" -PropertyType DWord -Value 5 | Out-Null
        New-ItemProperty -Path $script:testKey -Name "Bytes" -PropertyType Binary -Value ([byte[]](1, 2, 3)) | Out-Null
        Mock Write-Host { }
    }
    AfterEach {
        Remove-Item -Path $script:testKey -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
    }

    It "records the old values when Set-WinUtilRegistry changes them" {
        Set-WinUtilRegistry -Path $script:testKey -Name "Existing" -Type DWord -Value 0
        Set-WinUtilRegistry -Path $script:testKey -Name "New" -Type String -Value "hello"
        Set-WinUtilRegistry -Path $script:testKey -Name "Bytes" -Type Binary -Value ([byte[]](9, 9))

        $changes = @(Update-WinUtilChangeJournal)
        $changes.Count | Should -Be 3
        ($changes | Where-Object Key -like "*\Existing").Before.Value | Should -Be 5
        ($changes | Where-Object Key -like "*\New").Before.Exists | Should -BeFalse
        foreach ($record in $changes) { Test-WinUtilChangeApplied -Record $record | Should -BeTrue }
    }

    It "puts every value back the way it was" {
        Set-WinUtilRegistry -Path $script:testKey -Name "Existing" -Type DWord -Value 0
        Set-WinUtilRegistry -Path $script:testKey -Name "New" -Type String -Value "hello"
        Set-WinUtilRegistry -Path $script:testKey -Name "Bytes" -Type Binary -Value ([byte[]](9, 9))

        $global:WinUtilJournalPaused = $true
        try {
            foreach ($record in @(Update-WinUtilChangeJournal)) { Restore-WinUtilChange -Record $record | Should -BeTrue }
        } finally {
            $global:WinUtilJournalPaused = $false
        }

        (Get-ItemProperty -Path $script:testKey).Existing | Should -Be 5
        (Get-Item -Path $script:testKey).GetValueKind("Existing") | Should -Be "DWord"
        (Get-Item -Path $script:testKey).GetValueNames() | Should -Not -Contain "New"
        ((Get-ItemProperty -Path $script:testKey).Bytes -join ",") | Should -Be "1,2,3"
    }

    It "notices when something changed a value back" {
        Set-WinUtilRegistry -Path $script:testKey -Name "Existing" -Type DWord -Value 0
        Set-ItemProperty -Path $script:testKey -Name "Existing" -Value 5

        $record = @(Update-WinUtilChangeJournal)[0]
        Test-WinUtilChangeApplied -Record $record | Should -BeFalse
    }

    It "reapplies a value that was changed back" {
        Set-WinUtilRegistry -Path $script:testKey -Name "Existing" -Type DWord -Value 0
        Set-ItemProperty -Path $script:testKey -Name "Existing" -Value 5
        $record = @(Update-WinUtilChangeJournal)[0]

        Restore-WinUtilChange -Record $record -To "After" | Should -BeTrue

        (Get-ItemProperty -Path $script:testKey).Existing | Should -Be 0
        Test-WinUtilChangeApplied -Record $record | Should -BeTrue
    }

    It "records what a block changed directly, without Set-WinUtilRegistry" {
        Invoke-WinUtilTrackedChange -RegistryKeys @($script:testKey) -ScriptBlock {
            Set-ItemProperty -Path $script:testKey -Name "Existing" -Value 7
            New-ItemProperty -Path $script:testKey -Name "Added" -PropertyType DWord -Value 1 | Out-Null
            Remove-ItemProperty -Path $script:testKey -Name "Bytes"
        }

        $changes = @(Update-WinUtilChangeJournal)
        $changes.Count | Should -Be 3
        ($changes | Where-Object Key -like "*\Existing").Before.Value | Should -Be 5
        ($changes | Where-Object Key -like "*\Added").Before.Exists | Should -BeFalse
        ($changes | Where-Object Key -like "*\Bytes").After.Exists | Should -BeFalse
    }

    It "still records what a block changed when the block fails" {
        { Invoke-WinUtilTrackedChange -RegistryKeys @($script:testKey) -ScriptBlock {
            Set-ItemProperty -Path $script:testKey -Name "Existing" -Value 7
            throw "failed halfway"
        } } | Should -Throw "failed halfway"

        @(Update-WinUtilChangeJournal).Count | Should -Be 1
    }

    It "removes a value Optimize added when the change is undone" {
        Set-WinUtilRegistry -Path $script:testKey -Name "New" -Type DWord -Value 1
        Set-WinUtilRegistry -Path $script:testKey -Name "New" -Type DWord -Value "<RemoveEntry>"

        @(Update-WinUtilChangeJournal).Count | Should -Be 0
    }
}
