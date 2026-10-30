#===========================================================================
# Tests - Restore point safety net, ad blocking, Wi-Fi backup, big files, health check
#===========================================================================

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

    foreach ($file in "private\New-WinUtilAutoRestorePoint", "public\Invoke-WPFAdBlock", "public\Invoke-WPFBackupWifi",
        "public\Invoke-WPFBigFiles", "private\Initialize-WinUtilDiskScan", "public\Invoke-WPFHealthCheckTask") {
        . (Join-Path $script:repoRoot "functions\$file.ps1")
    }

    function Write-WinUtilLog { param($Message, $Level, $Component) }
    function Step-WinUtilJob { param($Status, $Percent, $State) }
    function Show-WinUtilMessage { param($Message, $Title, $Button, $Icon) }
    function Show-WinUtilFolderPicker { param($Description, [switch]$ShowNewFolderButton) }
    function Show-WinUtilTextPrompt { param($Title, $Message, $Default) }
    function Show-WinUtilReport { param($Title, $Rows, $Note) }
    function Set-WinUtilDNS { param($DNSProvider) }
    function Update-WinUtilChangeJournal { param([scriptblock]$Update) }
    function Restore-WinUtilChange { param($Record, $To) }
    function Register-WinUtilChange { param($Kind, $Key, $Label, $Before, $After) }
}

Describe "New-WinUtilAutoRestorePoint" {
    BeforeEach {
        Mock Checkpoint-Computer { }
        Mock Enable-ComputerRestore { }
        Mock Write-Host { }
        Mock Write-Warning { }
    }

    It "does not make another restore point within 24 hours" {
        Mock Get-ComputerRestorePoint {
            $point = [pscustomobject]@{ SequenceNumber = 5; CreationTime = "recent" }
            $point | Add-Member -MemberType ScriptMethod -Name ConvertToDateTime -Value { param($t) (Get-Date).AddHours(-2) }
            $point
        }

        New-WinUtilAutoRestorePoint

        Should -Invoke -CommandName Checkpoint-Computer -Times 0 -Exactly
    }

    It "makes one when the last is older than a day" {
        Mock Get-ComputerRestorePoint {
            $point = [pscustomobject]@{ SequenceNumber = 5; CreationTime = "old" }
            $point | Add-Member -MemberType ScriptMethod -Name ConvertToDateTime -Value { param($t) (Get-Date).AddDays(-3) }
            $point
        }

        New-WinUtilAutoRestorePoint -Reason "applying tweaks"

        Should -Invoke -CommandName Checkpoint-Computer -Times 1 -Exactly -ParameterFilter { $Description -like "*applying tweaks*" }
        Should -Invoke -CommandName Enable-ComputerRestore -Times 0 -Exactly
    }

    It "turns System Restore on when there are no restore points at all" {
        Mock Get-ComputerRestorePoint { }

        New-WinUtilAutoRestorePoint

        Should -Invoke -CommandName Enable-ComputerRestore -Times 1 -Exactly
        Should -Invoke -CommandName Checkpoint-Computer -Times 1 -Exactly
    }

    It "warns and carries on when the restore point fails" {
        Mock Get-ComputerRestorePoint { }
        Mock Checkpoint-Computer { throw "System Restore is turned off by policy" }

        { New-WinUtilAutoRestorePoint } | Should -Not -Throw
        Should -Invoke -CommandName Write-Warning -Times 1 -Exactly
    }
}

Describe "Invoke-WPFAdBlock" {
    BeforeEach {
        $script:sync = @{ configs = @{ dns = [pscustomobject]@{ AdGuard_Ads_Trackers = [pscustomobject]@{ Primary = "94.140.14.14"; Secondary = "94.140.15.15" } } } }
        Mock Get-NetAdapter { [pscustomobject]@{ Status = "Up"; ifIndex = 7 } }
        Mock Set-WinUtilDNS { $true }
        Mock Restore-WinUtilChange { $true }
        Mock Update-WinUtilChangeJournal { }
        Mock ipconfig.exe { }
        Mock Write-Host { }
    }
    AfterEach { Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue }

    It "does nothing unless the user says yes" {
        Mock Get-DnsClientServerAddress { [pscustomobject]@{ ServerAddresses = @("10.0.0.1") } }
        Mock Show-WinUtilMessage { "No" }

        Invoke-WPFAdBlock

        Should -Invoke -CommandName Set-WinUtilDNS -Times 0 -Exactly
    }

    It "switches DNS to AdGuard when turned on" {
        Mock Get-DnsClientServerAddress { [pscustomobject]@{ ServerAddresses = @("10.0.0.1") } }
        Mock Show-WinUtilMessage { "Yes" }

        Invoke-WPFAdBlock

        Should -Invoke -CommandName Set-WinUtilDNS -Times 1 -Exactly -ParameterFilter { $DNSProvider -eq "AdGuard_Ads_Trackers" }
    }

    It "puts the recorded DNS back when turned off" {
        Mock Get-DnsClientServerAddress { [pscustomobject]@{ ServerAddresses = @("94.140.14.14") } }
        Mock Show-WinUtilMessage { "Yes" }
        Mock Update-WinUtilChangeJournal {
            if (-not $Update) { [pscustomobject]@{ Kind = "Dns"; Key = "{guid}"; Label = "DNS on Ethernet"; After = [pscustomobject]@{ Provider = "AdGuard_Ads_Trackers" } } }
        }

        Invoke-WPFAdBlock

        Should -Invoke -CommandName Restore-WinUtilChange -Times 1 -Exactly -ParameterFilter { $To -eq "Before" }
        Should -Invoke -CommandName Set-WinUtilDNS -Times 0 -Exactly
    }

    It "falls back to automatic DNS when nothing was recorded" {
        Mock Get-DnsClientServerAddress { [pscustomobject]@{ ServerAddresses = @("94.140.14.14") } }
        Mock Show-WinUtilMessage { "Yes" }

        Invoke-WPFAdBlock

        Should -Invoke -CommandName Set-WinUtilDNS -Times 1 -Exactly -ParameterFilter { $DNSProvider -eq "DHCP" }
    }
}

Describe "Invoke-WPFBackupWifi" {
    BeforeEach {
        # A folder of its own per test, so one test's backup cannot be seen by the next
        $script:pickedFolder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:pickedFolder | Out-Null
        Mock Show-WinUtilMessage { "Yes" }
        Mock Show-WinUtilFolderPicker { $script:pickedFolder }
        Mock Write-Host { }
    }

    It "moves the exported networks into a dated folder and leaves no staging folder" {
        Mock netsh.exe {
            $folder = ($args | Where-Object { "$_" -like "folder=*" }) -replace '^folder=', '' -replace '"', ''
            Set-Content -Path (Join-Path $folder "Wi-Fi-Home.xml") -Value "<WLANProfile/>"
        }

        Invoke-WPFBackupWifi

        @(Get-ChildItem -Path $script:pickedFolder -Recurse -Filter *.xml).Count | Should -Be 1
        (Get-ChildItem -Path $script:pickedFolder -Directory).Name | Should -BeLike "Optimize-wifi-*"
        @(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'owifi-*').Count | Should -Be 0
    }

    It "says so, and makes no folder, when there are no saved networks" {
        Mock netsh.exe { }

        Invoke-WPFBackupWifi

        Should -Invoke -CommandName Show-WinUtilMessage -Times 1 -Exactly -ParameterFilter { $Message -like "*no saved Wi-Fi*" }
        @(Get-ChildItem -Path $script:pickedFolder -Directory -Filter 'Optimize-wifi-*').Count | Should -Be 0
    }

    It "saves nothing unless the user agrees to readable passwords" {
        Mock Show-WinUtilMessage { "No" }
        Mock netsh.exe { }

        Invoke-WPFBackupWifi

        Should -Invoke -CommandName netsh.exe -Times 0 -Exactly
    }
}

Describe "Invoke-WPFBigFiles" {
    BeforeEach {
        Mock Show-WinUtilReport { $script:report = $Rows }
        $script:report = $null
    }

    It "scans nothing when the user cancels" {
        Mock Show-WinUtilTextPrompt { $null }
        Mock Write-Host { }

        Invoke-WPFBigFiles

        Should -Invoke -CommandName Show-WinUtilReport -Times 0 -Exactly
    }

    It "lists the biggest files first, each with a path to open" {
        $root = Join-Path $TestDrive "scan"
        New-Item -ItemType Directory -Path "$root\small", "$root\big" -Force | Out-Null
        [IO.File]::WriteAllBytes("$root\big\large.bin", (New-Object byte[] 300KB))
        [IO.File]::WriteAllBytes("$root\small\tiny.bin", (New-Object byte[] 10KB))

        Initialize-WinUtilDiskScan
        $files = [OptimizeDiskScan]::Scan("$root\", 20)

        $files[0].Key | Should -BeLike "*large.bin"
        $files[0].Value | Should -Be 300KB
        [OptimizeDiskScan]::FolderBytes["$root\big"] | Should -Be 300KB
    }
}

Describe "Invoke-WPFHealthCheckTask" {
    BeforeEach {
        Mock Register-ScheduledTask { }
        Mock Unregister-ScheduledTask { }
        Mock Set-Content { }
        Mock New-Item { }
        Mock Write-Host { }
    }

    It "turns nothing on unless the user says yes" {
        Mock Get-ScheduledTask { }
        Mock Show-WinUtilMessage { "No" }

        Invoke-WPFHealthCheckTask

        Should -Invoke -CommandName Register-ScheduledTask -Times 0 -Exactly
    }

    It "creates a weekly task that runs as the signed-in user in Windows PowerShell" {
        Mock Get-ScheduledTask { }
        Mock Show-WinUtilMessage { "Yes" }

        Invoke-WPFHealthCheckTask

        Should -Invoke -CommandName Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq "Optimize Health Check" -and
                $Principal.LogonType -eq "Interactive" -and
                $Action.Execute -like "*WindowsPowerShell\v1.0\powershell.exe"
        }
    }

    It "offers to turn it off when it is already on" {
        Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = "Optimize Health Check" } }
        Mock Show-WinUtilMessage { "Yes" }

        Invoke-WPFHealthCheckTask

        Should -Invoke -CommandName Unregister-ScheduledTask -Times 1 -Exactly
        Should -Invoke -CommandName Register-ScheduledTask -Times 0 -Exactly
    }
}
