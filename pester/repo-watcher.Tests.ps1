#===========================================================================
# Tests - Repo watcher, against real git repos in a temp folder
#===========================================================================

BeforeAll {
    $script:watcher = (Resolve-Path (Join-Path $PSScriptRoot "..\tools\watcher\Watch-OptimizeRepo.ps1")).Path

    function Invoke-TestGit {
        param([string]$Repo)
        $previous = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & git -C $Repo @args 2>&1 | ForEach-Object { "$_" }
        } finally {
            $ErrorActionPreference = $previous
        }
    }
}

Describe "Watch-OptimizeRepo" {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:remote = Join-Path $script:root "remote.git"
        $script:repo = Join-Path $script:root "repo"
        $script:log = Join-Path $script:root "watcher.log"
        New-Item -ItemType Directory -Path $script:repo -Force | Out-Null
        Invoke-TestGit $script:root init -q --bare -b main $script:remote | Out-Null
        Invoke-TestGit $script:repo init -q -b main | Out-Null
        Invoke-TestGit $script:repo config user.email "test@example.com" | Out-Null
        Invoke-TestGit $script:repo config user.name "Test" | Out-Null
        Invoke-TestGit $script:repo remote add origin $script:remote | Out-Null
        Set-Content -Path (Join-Path $script:repo "readme.txt") -Value "first"
        Invoke-TestGit $script:repo add -A | Out-Null
        Invoke-TestGit $script:repo commit -q -m "first" | Out-Null
        Invoke-TestGit $script:repo push -q -u origin main | Out-Null
        $script:start = (Invoke-TestGit $script:remote rev-parse main)
    }

    It "commits and pushes a change" {
        Set-Content -Path (Join-Path $script:repo "new.txt") -Value "hello"

        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        Invoke-TestGit $script:remote log -1 --format=%s main | Should -Be "Update new.txt"
        Invoke-TestGit $script:repo status --porcelain | Should -BeNullOrEmpty
    }

    It "pushes a commit that is waiting even with no file changes" {
        Set-Content -Path (Join-Path $script:repo "new.txt") -Value "hello"
        Invoke-TestGit $script:repo add -A | Out-Null
        Invoke-TestGit $script:repo commit -q -m "by hand" | Out-Null

        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        Invoke-TestGit $script:remote log -1 --format=%s main | Should -Be "by hand"
    }

    It "does nothing when nothing changed" {
        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        Invoke-TestGit $script:remote rev-parse main | Should -Be $script:start
    }

    It "holds back a file containing a token" {
        Set-Content -Path (Join-Path $script:repo "config.txt") -Value ("token=ghp_" + ("a" * 36))

        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        Invoke-TestGit $script:remote rev-parse main | Should -Be $script:start
        (Invoke-TestGit $script:repo log --format=%s) | Should -Not -Contain "Update config.txt"
        Get-Content $script:log -Raw | Should -Match "looks like a secret"
    }

    It "holds back a private key file by its name" {
        Set-Content -Path (Join-Path $script:repo "server.pem") -Value "not really"

        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        Invoke-TestGit $script:remote rev-parse main | Should -Be $script:start
    }

    It "holds back a PowerShell file that does not parse" {
        Set-Content -Path (Join-Path $script:repo "broken.ps1") -Value "function Oops {"

        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        Invoke-TestGit $script:remote rev-parse main | Should -Be $script:start
        Get-Content $script:log -Raw | Should -Match "does not parse"
    }

    It "holds back a JSON file that is not valid" {
        Set-Content -Path (Join-Path $script:repo "broken.json") -Value "{ nope"

        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        Invoke-TestGit $script:remote rev-parse main | Should -Be $script:start
    }

    It "does nothing on another branch" {
        Invoke-TestGit $script:repo switch -q -c side | Out-Null
        Set-Content -Path (Join-Path $script:repo "new.txt") -Value "hello"

        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        Invoke-TestGit $script:remote rev-parse main | Should -Be $script:start
        Invoke-TestGit $script:repo status --porcelain | Should -Not -BeNullOrEmpty
    }

    It "brings in changes made on GitHub before pushing" {
        $other = Join-Path $script:root "other"
        Invoke-TestGit $script:root clone -q $script:remote $other | Out-Null
        Invoke-TestGit $other config user.email "test@example.com" | Out-Null
        Invoke-TestGit $other config user.name "Test" | Out-Null
        Set-Content -Path (Join-Path $other "theirs.txt") -Value "theirs"
        Invoke-TestGit $other add -A | Out-Null
        Invoke-TestGit $other commit -q -m "theirs" | Out-Null
        Invoke-TestGit $other push -q origin main | Out-Null
        Set-Content -Path (Join-Path $script:repo "mine.txt") -Value "mine"

        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        $subjects = Invoke-TestGit $script:remote log --format=%s main
        $subjects | Should -Contain "theirs"
        $subjects | Should -Contain "Update mine.txt"
    }

    It "leaves the repo clean and pushes nothing when GitHub's changes conflict" {
        $other = Join-Path $script:root "other"
        Invoke-TestGit $script:root clone -q $script:remote $other | Out-Null
        Invoke-TestGit $other config user.email "test@example.com" | Out-Null
        Invoke-TestGit $other config user.name "Test" | Out-Null
        Set-Content -Path (Join-Path $other "readme.txt") -Value "theirs"
        Invoke-TestGit $other add -A | Out-Null
        Invoke-TestGit $other commit -q -m "theirs" | Out-Null
        Invoke-TestGit $other push -q origin main | Out-Null
        $theirs = Invoke-TestGit $script:remote rev-parse main
        Set-Content -Path (Join-Path $script:repo "readme.txt") -Value "mine"

        & $script:watcher -RepoPath $script:repo -LogPath $script:log -Once | Out-Null

        Invoke-TestGit $script:remote rev-parse main | Should -Be $theirs
        Test-Path (Join-Path $script:repo ".git\rebase-merge") | Should -BeFalse
        Get-Content $script:log -Raw | Should -Match "Sort this out by hand"
    }
}
