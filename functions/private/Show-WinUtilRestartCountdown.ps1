function Show-WinUtilRestartCountdown {
    <#
    .SYNOPSIS
        Shows a live restart countdown and returns "Restart" or "Cancel"

    .DESCRIPTION
        A small themed window that counts down once per second, with buttons to restart
        straight away or cancel. Reaching zero counts as "Restart". Closing the window counts as
        "Cancel". Marshals onto the interface thread so it can be called from a job body, and
        returns "Cancel" when there is no window, so an unattended run never restarts on its own.

    .PARAMETER Seconds
        Length of the countdown

    .PARAMETER Reason
        Line shown above the countdown, saying why the restart is needed
    #>
    param(
        [int]$Seconds = 15,
        [string]$Reason = "Restarting to finish applying changes."
    )

    if (-not (Test-WinUtilUIAlive)) {
        Write-WinUtilLog -Level "WARN" -Component "Dialog" -Message "No window for the restart countdown, not restarting"
        return "Cancel"
    }

    $result = Invoke-WPFUIThread -PassThru -Parameters @{ Seconds = $Seconds; Reason = $Reason } -ScriptBlock {
        param($Seconds, $Reason)

        $resources = $sync.Form.Resources

        $window = New-Object Windows.Window
        $window.Title = "Restart"
        $window.Width = 380
        $window.SizeToContent = "Height"
        $window.WindowStartupLocation = "CenterOwner"
        $window.Owner = $sync.Form
        $window.ResizeMode = "NoResize"
        $window.WindowStyle = "ToolWindow"
        $window.Topmost = $true
        $window.Background = $resources["MainBackgroundColor"]
        $window.Tag = "Cancel"

        $panel = New-Object Windows.Controls.StackPanel
        $panel.Margin = [Windows.Thickness]::new(20)

        $reasonText = New-Object Windows.Controls.TextBlock
        $reasonText.Text = $Reason
        $reasonText.TextWrapping = "Wrap"
        $reasonText.Foreground = $resources["MainForegroundColor"]
        $reasonText.FontFamily = $resources["FontFamily"]
        $reasonText.FontSize = 13
        $panel.Children.Add($reasonText) | Out-Null

        $countText = New-Object Windows.Controls.TextBlock
        $countText.Text = "Restarting in $Seconds seconds"
        $countText.Margin = [Windows.Thickness]::new(0, 14, 0, 18)
        $countText.Foreground = $resources["LabelboxForegroundColor"]
        $countText.FontFamily = $resources["HeaderFontFamily"]
        $countText.FontSize = 22
        $panel.Children.Add($countText) | Out-Null

        $buttons = New-Object Windows.Controls.StackPanel
        $buttons.Orientation = "Horizontal"
        $buttons.HorizontalAlignment = "Right"

        $restartButton = New-Object Windows.Controls.Button
        $restartButton.Content = "Restart now"
        $restartButton.Width = 110
        $restartButton.Height = 30
        $restartButton.Margin = [Windows.Thickness]::new(0, 0, 8, 0)
        $restartButton.Background = $resources["ButtonBackgroundSelectedColor"]
        $restartButton.Foreground = [Windows.Media.Brushes]::White
        $restartButton.Add_Click({
            param($eventSender)
            $owner = [Windows.Window]::GetWindow($eventSender)
            $owner.Tag = "Restart"
            $owner.Close()
        })
        $buttons.Children.Add($restartButton) | Out-Null

        $cancelButton = New-Object Windows.Controls.Button
        $cancelButton.Content = "Cancel"
        $cancelButton.Width = 90
        $cancelButton.Height = 30
        $cancelButton.IsCancel = $true
        $cancelButton.Background = $resources["ButtonBackgroundColor"]
        $cancelButton.Foreground = $resources["ButtonForegroundColor"]
        $cancelButton.Add_Click({
            param($eventSender)
            $owner = [Windows.Window]::GetWindow($eventSender)
            $owner.Tag = "Cancel"
            $owner.Close()
        })
        $buttons.Children.Add($cancelButton) | Out-Null

        $panel.Children.Add($buttons) | Out-Null
        $window.Content = $panel

        # State travels on the timer's Tag, matching how the rest of this codebase handles ticks
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(1)
        $timer.Tag = @{ Window = $window; Label = $countText; Remaining = $Seconds }
        $timer.Add_Tick({
            param($eventSender)
            $ticked = [System.Windows.Threading.DispatcherTimer]$eventSender
            $state = $ticked.Tag
            $state.Remaining--
            if ($state.Remaining -le 0) {
                $ticked.Stop()
                $state.Window.Tag = "Restart"
                $state.Window.Close()
                return
            }
            $unit = if ($state.Remaining -eq 1) { "second" } else { "seconds" }
            $state.Label.Text = "Restarting in $($state.Remaining) $unit"
        })
        $window.Resources["CountdownTimer"] = $timer
        $window.Add_Closed({
            param($eventSender)
            ([Windows.Window]$eventSender).Resources["CountdownTimer"].Stop()
        })

        $timer.Start()
        $null = $window.ShowDialog()
        $window.Tag
    }

    if ("$result" -eq "Restart") { return "Restart" }
    return "Cancel"
}
