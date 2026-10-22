function Invoke-WinUtilFeatureInstall ($CheckBox) {
    Write-WinUtilLog -Component "Feature" -Message "Applying feature action: $CheckBox"

    # Hyper-V and Windows Sandbox, for example, do not exist on Home
    $featureEntry = $sync.configs.feature.$CheckBox
    if (-not (Test-WinUtilEditionSupported -Entry $featureEntry)) {
        $note = Get-WinUtilEditionNote -Editions $featureEntry.editions
        Write-Warning "Skipped $($featureEntry.Content): $note"
        Write-WinUtilLog -Level "WARN" -Component "Feature" -Message "Skipped $CheckBox for this edition: $note"
        return
    }

    if ($sync.configs.feature.$CheckBox.feature) {
        foreach ($feature in $sync.configs.feature.$CheckBox.feature) {
            Write-Host "Installing $feature"
            Write-WinUtilLog -Component "Feature" -Message "Enabling Windows optional feature: $feature"
            # Only recorded when the old state can be read: guessing "off" would let Undo All turn
            # off a feature that was already on
            try {
                $state = "$((Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop).State)"
                Register-WinUtilChange -Kind "Feature" -Key $feature -Label "Windows feature $feature" -Before @{ Enabled = ($state -eq "Enabled") } -After @{ Enabled = $true }
            } catch {
                Write-WinUtilLog -Level "WARN" -Component "Feature" -Message "Could not read the state of $feature, so it is not in the change journal: $($_.Exception.Message)"
            }
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction Stop
            Write-WinUtilLog -Component "Feature" -Message "Enabled Windows optional feature: $feature"
        }
    }

    if ($sync.configs.feature.$CheckBox.InvokeScript) {
        foreach ($script in $sync.configs.feature.$CheckBox.InvokeScript) {
            Write-Host "Running Script for $CheckBox"
            Write-WinUtilLog -Component "Feature" -Message "Running feature script for: $CheckBox"
            Invoke-Command -ScriptBlock ([scriptblock]::Create($script)) -ErrorAction Stop
            Write-WinUtilLog -Component "Feature" -Message "Completed feature script for: $CheckBox"
        }
    }
    Write-WinUtilLog -Component "Feature" -Message "Feature action completed: $CheckBox"
}
