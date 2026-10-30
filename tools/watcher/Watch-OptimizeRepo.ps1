<#
.SYNOPSIS
    Commits and pushes changes in this repo to GitHub once the files have been quiet for a while

.DESCRIPTION
    Waits for a quiet period so one burst of edits becomes one commit and half-saved work does
    not go up. It holds back, and logs why, when a change looks like a secret, is too big for
    GitHub, or leaves a PowerShell or JSON file broken. It never force-pushes, only touches
    origin, only works on the chosen branch, and stays out of the way of a merge or rebase.

    Pushing does not publish a release; releases stay a manual step.

    Log: %LocalAppData%\Optimize\repo-watcher.log

.EXAMPLE
    .\Watch-OptimizeRepo.ps1 -Install      # start now and at every sign-in
.EXAMPLE
    .\Watch-OptimizeRepo.ps1 -Uninstall    # stop it for good
.EXAMPLE
    .\Watch-OptimizeRepo.ps1 -Once         # check and push right now, then exit
#>
param(
    [string]$RepoPath = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$Branch = "main",
    [int]$QuietSeconds = 300,
    [int]$PollSeconds = 20,
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA "Optimize\repo-watcher.log"),
    [switch]$Once,
    [switch]$Install,
    [switch]$Uninstall
)

$taskName = "Optimize Repo Watcher"

if ($Uninstall) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "The repo watcher is off."
    return
}

if ($Install) {
    $action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$PSCommandPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    # Keeps running on battery, and is not stopped after the default three days
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Write-Output "The repo watcher is on, and starts at every sign-in. Log: $LogPath"
    return
}

function Write-WatcherLog {
    param([string]$Message)
    $line = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $Message"
    # Not Write-Output: that would become part of what Sync-Repo returns
    Write-Host $line
    $folder = Split-Path $LogPath -Parent
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    Add-Content -LiteralPath $LogPath -Value $line
}

function Invoke-Git {
    # git reports progress on stderr, so its exit code is what says whether it worked
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& git -C $RepoPath -c core.quotepath=false @args 2>&1 | ForEach-Object { "$_" })
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output; Text = ($output -join " ") }
    } finally {
        $ErrorActionPreference = $previous
    }
}

function Get-ChangedFiles {
    # Porcelain lines are "XY path" or "XY old -> new"; only what exists afterwards matters
    foreach ($line in (Invoke-Git status --porcelain -uall).Output) {
        if ($line.Length -lt 4) { continue }
        $path = $line.Substring(3)
        if ($path -match ' -> (.+)$') { $path = $Matches[1] }
        $path.Trim('"')
    }
}

function Get-ChangeFingerprint {
    param([string[]]$Files)
    (@($Files | Sort-Object | ForEach-Object {
                $item = Get-Item -LiteralPath (Join-Path $RepoPath $_) -Force -ErrorAction SilentlyContinue
                if ($item) { "$_|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)" } else { "$_|gone" }
            })) -join "`n"
}

function Get-HoldBackReason {
    param([string[]]$Files)

    foreach ($relative in $Files) {
        $full = Join-Path $RepoPath $relative
        $name = Split-Path $relative -Leaf
        if ($name -match '^\.env(\..+)?$|^id_(rsa|ed25519|ecdsa)$|\.(pem|pfx|p12|key)$') {
            return "$relative looks like a secret"
        }
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

        $item = Get-Item -LiteralPath $full -Force
        if ($item.Length -gt 50MB) {
            return "$relative is over 50 MB"
        }
        if ($item.Length -le 5MB) {
            $text = [IO.File]::ReadAllText($full)
            if ($text -match 'ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY') {
                return "$relative contains what looks like a secret"
            }
        }

        if ($item.Extension -in ".ps1", ".psm1") {
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$null, [ref]$errors)
            if (@($errors).Count -gt 0) {
                return "$relative does not parse: $($errors[0].Message)"
            }
        } elseif ($item.Extension -eq ".json") {
            try {
                [void]([IO.File]::ReadAllText($full) | ConvertFrom-Json)
            } catch {
                return "$relative is not valid JSON"
            }
        }
    }
    return $null
}

function Test-GitBusy {
    $gitDir = (Invoke-Git rev-parse --absolute-git-dir).Text
    foreach ($marker in "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "index.lock") {
        if (Test-Path -LiteralPath (Join-Path $gitDir $marker)) { return $true }
    }
    return $false
}

function Sync-Repo {
    <#
        .SYNOPSIS
            One commit-and-push pass. Returns $true when the work is on GitHub or nothing was to do.
    #>
    param([string[]]$Files)

    if ((Invoke-Git branch --show-current).Text -ne $Branch) {
        Write-WatcherLog "Holding back: not on $Branch."
        return $false
    }
    if (Test-GitBusy) {
        Write-WatcherLog "Holding back: git is in the middle of something."
        return $false
    }

    if (@($Files).Count -gt 0) {
        $reason = Get-HoldBackReason -Files $Files
        if ($reason) {
            Write-WatcherLog "Holding back: $reason. Nothing was committed."
            $script:heldBack = $true
            return $false
        }

        $shown = @($Files | Select-Object -First 3) -join ", "
        if (@($Files).Count -gt 3) { $shown += " and $(@($Files).Count - 3) more" }

        $add = Invoke-Git add -A
        if ($add.Code -ne 0) {
            Write-WatcherLog "Could not stage the changes: $($add.Text)"
            return $false
        }
        $commit = Invoke-Git commit -m "Update $shown"
        if ($commit.Code -ne 0) {
            Write-WatcherLog "Could not commit: $($commit.Text)"
            return $false
        }
        Write-WatcherLog "Committed: $shown"
    }

    $pull = Invoke-Git pull --rebase --autostash origin $Branch
    if ($pull.Code -ne 0) {
        Invoke-Git rebase --abort | Out-Null
        Write-WatcherLog "Could not bring in GitHub's changes, so nothing was pushed. Sort this out by hand: $($pull.Text)"
        return $false
    }

    $push = Invoke-Git push origin $Branch
    if ($push.Code -ne 0) {
        Write-WatcherLog "Could not push, will try again: $($push.Text)"
        return $false
    }
    Write-WatcherLog "Pushed to origin/$Branch."
    return $true
}

function Test-UnpushedWork {
    $count = Invoke-Git rev-list --count "origin/$Branch..$Branch"
    return $count.Code -eq 0 -and [int]$count.Text -gt 0
}

if ($Once) {
    $files = @(Get-ChangedFiles)
    if ($files.Count -eq 0 -and -not (Test-UnpushedWork)) {
        Write-WatcherLog "Nothing to update."
        return
    }
    [void](Sync-Repo -Files $files)
    return
}

# Only one watcher at a time, or two would race each other to commit the same files
$single = New-Object System.Threading.Mutex($false, "Local\OptimizeRepoWatcher")
if (-not $single.WaitOne(0)) {
    Write-WatcherLog "Another watcher is already running."
    return
}

Write-WatcherLog "Watching $RepoPath ($Branch). Changes go up after $QuietSeconds seconds of quiet."
$lastFingerprint = ""
$lastChange = Get-Date
$attempted = $null

while ($true) {
    try {
        $files = @(Get-ChangedFiles)
        $fingerprint = Get-ChangeFingerprint -Files $files
        if ($fingerprint -ne $lastFingerprint) {
            $lastFingerprint = $fingerprint
            $lastChange = Get-Date
            $attempted = $null
        }

        $pending = $files.Count -gt 0 -or (Test-UnpushedWork)
        $quiet = ((Get-Date) - $lastChange).TotalSeconds -ge $QuietSeconds
        # A held-back change cannot pass until a file changes, so it is not retried and the log
        # says it once. Anything else, such as a failed push or busy git, is retried on the timer.
        if ($pending -and $quiet -and $attempted -ne $fingerprint) {
            $script:heldBack = $false
            if (-not (Sync-Repo -Files $files)) {
                if ($script:heldBack) {
                    $attempted = $fingerprint
                } else {
                    $lastChange = Get-Date
                }
            }
        }
    } catch {
        Write-WatcherLog "Something went wrong, carrying on: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $PollSeconds
}
