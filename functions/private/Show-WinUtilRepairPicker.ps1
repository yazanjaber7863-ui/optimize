function Show-WinUtilRepairPicker {
    <#
    .SYNOPSIS
        Asks which repair steps to run and returns them as a comma list ("Disk,DISM,SFC"),
        or $null when cancelled

    .DESCRIPTION
        A small themed window with a checkbox per step, how long each one takes, and a warning
        that the whole thing is slow. Marshals onto the interface thread so it can be called from
        a job body, and returns $null when there is no window.
    #>

    if (-not (Test-WinUtilUIAlive)) {
        Write-WinUtilLog -Level "WARN" -Component "Dialog" -Message "No window for the repair picker"
        return $null
    }

    $result = Invoke-WPFUIThread -PassThru -ScriptBlock {
        $resources = $sync.Form.Resources

        $window = New-Object Windows.Window
        $window.Title = "Repair System Files"
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
        $heading.Text = "What should be repaired?"
        $heading.Foreground = $resources["LabelboxForegroundColor"]
        $heading.FontFamily = $resources["HeaderFontFamily"]
        $heading.FontSize = 18
        $heading.Margin = [Windows.Thickness]::new(0, 0, 0, 12)
        $panel.Children.Add($heading) | Out-Null

        $options = @(
            @{ Key = "Disk"; Title = "Check the disk (chkdsk)";  Detail = "Looks for disk errors first. About 2-5 minutes." }
            @{ Key = "DISM"; Title = "Repair the Windows image (DISM)"; Detail = "Downloads clean copies from Windows Update. 15-40 minutes, often looks stuck around 60%." }
            @{ Key = "SFC";  Title = "Scan system files (SFC)"; Detail = "Finds and fixes broken Windows files. 10-20 minutes." }
        )

        $boxes = @{}
        foreach ($option in $options) {
            $box = New-Object Windows.Controls.CheckBox
            $box.IsChecked = $true
            $box.Margin = [Windows.Thickness]::new(0, 0, 0, 10)
            $box.Foreground = $resources["MainForegroundColor"]
            $box.VerticalContentAlignment = "Top"

            $text = New-Object Windows.Controls.StackPanel
            $title = New-Object Windows.Controls.TextBlock
            $title.Text = $option.Title
            $title.FontFamily = $resources["HeaderFontFamily"]
            $title.FontSize = 13
            $title.Foreground = $resources["MainForegroundColor"]
            $detail = New-Object Windows.Controls.TextBlock
            $detail.Text = $option.Detail
            $detail.TextWrapping = "Wrap"
            $detail.MaxWidth = 380
            $detail.Opacity = 0.75
            $detail.FontFamily = $resources["FontFamily"]
            $detail.Foreground = $resources["MainForegroundColor"]
            $text.Children.Add($title) | Out-Null
            $text.Children.Add($detail) | Out-Null
            $box.Content = $text

            $panel.Children.Add($box) | Out-Null
            $boxes[$option.Key] = $box
        }

        $warning = New-Object Windows.Controls.TextBlock
        $warning.Text = "Heads up: with everything ticked this takes 30-60 minutes. You can keep using the PC, but don't close Optimize until it finishes."
        $warning.TextWrapping = "Wrap"
        $warning.Margin = [Windows.Thickness]::new(0, 6, 0, 18)
        $warning.Foreground = $resources["ProgressBarWarningColor"]
        $warning.FontFamily = $resources["FontFamily"]
        $panel.Children.Add($warning) | Out-Null

        $buttons = New-Object Windows.Controls.StackPanel
        $buttons.Orientation = "Horizontal"
        $buttons.HorizontalAlignment = "Right"

        $startButton = New-Object Windows.Controls.Button
        $startButton.Content = "Start repair"
        $startButton.Width = 120
        $startButton.Height = 30
        $startButton.Margin = [Windows.Thickness]::new(0, 0, 8, 0)
        $startButton.IsDefault = $true
        $startButton.Background = $resources["ButtonBackgroundSelectedColor"]
        $startButton.Foreground = [Windows.Media.Brushes]::White
        $buttons.Children.Add($startButton) | Out-Null

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

        # Checkboxes travel on the window's Resources so the handler needs no captured variables
        $window.Resources["RepairBoxes"] = $boxes
        $window.Resources["StartButton"] = $startButton

        # Start is only clickable while at least one step is ticked
        $refresh = {
            param($eventSender)
            $owner = [Windows.Window]::GetWindow($eventSender)
            if ($null -eq $owner) { return }
            $any = @($owner.Resources["RepairBoxes"].Values | Where-Object { $_.IsChecked }).Count -gt 0
            $owner.Resources["StartButton"].IsEnabled = $any
        }
        foreach ($box in $boxes.Values) {
            $box.Add_Checked($refresh)
            $box.Add_Unchecked($refresh)
        }

        $startButton.Add_Click({
            param($eventSender)
            $owner = [Windows.Window]::GetWindow($eventSender)
            $chosen = foreach ($key in "Disk", "DISM", "SFC") {
                if ($owner.Resources["RepairBoxes"][$key].IsChecked) { $key }
            }
            $owner.Tag = ($chosen -join ",")
            $owner.Close()
        })

        $null = $window.ShowDialog()
        $window.Tag
    }

    if ([string]::IsNullOrWhiteSpace("$result")) { return $null }
    return "$result"
}
