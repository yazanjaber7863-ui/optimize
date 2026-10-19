function Show-WinUtilTimeZonePicker {
    <#
    .SYNOPSIS
        Lets the user pick a time zone and returns its Id, or $null when cancelled

    .DESCRIPTION
        A small themed window with every Windows time zone in UTC order, the current one
        preselected, and a live preview of the local time in the selected zone. Marshals onto
        the interface thread so it can be called from a job body, and returns $null when there
        is no window.
    #>

    if (-not (Test-WinUtilUIAlive)) {
        Write-WinUtilLog -Level "WARN" -Component "Dialog" -Message "No window for the time zone picker"
        return $null
    }

    $result = Invoke-WPFUIThread -PassThru -ScriptBlock {
        $resources = $sync.Form.Resources

        $window = New-Object Windows.Window
        $window.Title = "Fix Clock"
        $window.Width = 460
        $window.SizeToContent = "Height"
        $window.WindowStartupLocation = "CenterOwner"
        $window.Owner = $sync.Form
        $window.ResizeMode = "NoResize"
        $window.WindowStyle = "ToolWindow"
        $window.Background = $resources["MainBackgroundColor"]
        $window.Tag = $null

        $panel = New-Object Windows.Controls.StackPanel
        $panel.Margin = [Windows.Thickness]::new(20)

        $heading = New-Object Windows.Controls.TextBlock
        $heading.Text = "Which time zone are you in?"
        $heading.Foreground = $resources["LabelboxForegroundColor"]
        $heading.FontFamily = $resources["HeaderFontFamily"]
        $heading.FontSize = 18
        $panel.Children.Add($heading) | Out-Null

        $hint = New-Object Windows.Controls.TextBlock
        $hint.Text = "Pick your UTC offset and city. Type to jump to a city."
        $hint.Margin = [Windows.Thickness]::new(0, 4, 0, 12)
        $hint.Foreground = $resources["MainForegroundColor"]
        $hint.FontFamily = $resources["FontFamily"]
        $hint.Opacity = 0.75
        $panel.Children.Add($hint) | Out-Null

        $combo = New-Object Windows.Controls.ComboBox
        $combo.Height = 30
        $combo.FontSize = 13
        $combo.IsTextSearchEnabled = $true
        $combo.DisplayMemberPath = "DisplayName"
        $zones = [TimeZoneInfo]::GetSystemTimeZones() | Sort-Object { $_.BaseUtcOffset }, DisplayName
        foreach ($zone in $zones) { $combo.Items.Add($zone) | Out-Null }
        $current = [TimeZoneInfo]::Local.Id
        $combo.SelectedItem = $zones | Where-Object { $_.Id -eq $current } | Select-Object -First 1
        $panel.Children.Add($combo) | Out-Null

        $preview = New-Object Windows.Controls.TextBlock
        $preview.Margin = [Windows.Thickness]::new(0, 14, 0, 4)
        $preview.Foreground = $resources["MainForegroundColor"]
        $preview.FontFamily = $resources["HeaderFontFamily"]
        $preview.FontSize = 26
        $panel.Children.Add($preview) | Out-Null

        $previewNote = New-Object Windows.Controls.TextBlock
        $previewNote.Text = "This is what your clock will show (from internet time once synced)."
        $previewNote.Foreground = $resources["MainForegroundColor"]
        $previewNote.FontFamily = $resources["FontFamily"]
        $previewNote.Opacity = 0.75
        $previewNote.Margin = [Windows.Thickness]::new(0, 0, 0, 18)
        $panel.Children.Add($previewNote) | Out-Null

        $buttons = New-Object Windows.Controls.StackPanel
        $buttons.Orientation = "Horizontal"
        $buttons.HorizontalAlignment = "Right"

        $applyButton = New-Object Windows.Controls.Button
        $applyButton.Content = "Fix my clock"
        $applyButton.Width = 120
        $applyButton.Height = 30
        $applyButton.Margin = [Windows.Thickness]::new(0, 0, 8, 0)
        $applyButton.IsDefault = $true
        $applyButton.Background = $resources["ButtonBackgroundSelectedColor"]
        $applyButton.Foreground = [Windows.Media.Brushes]::White
        $buttons.Children.Add($applyButton) | Out-Null

        $cancelButton = New-Object Windows.Controls.Button
        $cancelButton.Content = "Cancel"
        $cancelButton.Width = 90
        $cancelButton.Height = 30
        $cancelButton.IsCancel = $true
        $cancelButton.Background = $resources["ButtonBackgroundColor"]
        $cancelButton.Foreground = $resources["ButtonForegroundColor"]
        $buttons.Children.Add($cancelButton) | Out-Null

        $panel.Children.Add($buttons) | Out-Null
        $window.Content = $panel

        # Controls travel on the window's Resources so handlers need no captured variables
        $window.Resources["ZoneCombo"] = $combo
        $window.Resources["ZonePreview"] = $preview

        $updatePreview = {
            param($eventSender)
            $owner = [Windows.Window]::GetWindow($eventSender)
            if ($null -eq $owner) { return }
            $zone = $owner.Resources["ZoneCombo"].SelectedItem
            if ($zone) {
                $now = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $zone)
                $owner.Resources["ZonePreview"].Text = $now.ToString("HH:mm:ss  ddd d MMM")
            }
        }
        $combo.Add_SelectionChanged($updatePreview)

        $applyButton.Add_Click({
            param($eventSender)
            $owner = [Windows.Window]::GetWindow($eventSender)
            $owner.Tag = $owner.Resources["ZoneCombo"].SelectedItem.Id
            $owner.Close()
        })

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(1)
        $timer.Tag = @{ Combo = $combo; Preview = $preview }
        $timer.Add_Tick({
            param($eventSender)
            $state = ([System.Windows.Threading.DispatcherTimer]$eventSender).Tag
            $zone = $state.Combo.SelectedItem
            if ($zone) {
                $now = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $zone)
                $state.Preview.Text = $now.ToString("HH:mm:ss  ddd d MMM")
            }
        })
        $window.Resources["PreviewTimer"] = $timer
        $window.Add_Closed({
            param($eventSender)
            ([Windows.Window]$eventSender).Resources["PreviewTimer"].Stop()
        })

        $window.Add_Loaded({
            param($eventSender)
            $owner = [Windows.Window]$eventSender
            $zone = $owner.Resources["ZoneCombo"].SelectedItem
            if ($zone) {
                $now = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $zone)
                $owner.Resources["ZonePreview"].Text = $now.ToString("HH:mm:ss  ddd d MMM")
            }
            $owner.Resources["PreviewTimer"].Start()
        })

        $null = $window.ShowDialog()
        $window.Tag
    }

    if ([string]::IsNullOrWhiteSpace("$result")) { return $null }
    return "$result"
}
