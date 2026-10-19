function Show-WinUtilStartupPicker {
    <#
    .SYNOPSIS
        Shows the startup apps with a checkbox each and returns the indexes left ticked as
        "ok:0,2,5", or $null when cancelled

    .PARAMETER Entries
        What Get-WinUtilStartupApps returned. Only Name, Command, Scope and Enabled are read.
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries
    )

    if (-not (Test-WinUtilUIAlive)) {
        Write-WinUtilLog -Level "WARN" -Component "Dialog" -Message "No window for the startup apps picker"
        return $null
    }

    # Plain hashtables so the values cross into the interface runspace as data
    $rows = @(for ($index = 0; $index -lt $Entries.Count; $index++) {
        @{ Name = $Entries[$index].Name; Command = $Entries[$index].Command; Scope = $Entries[$index].Scope; Enabled = [bool]$Entries[$index].Enabled }
    })

    $result = Invoke-WPFUIThread -PassThru -Parameters @{ Rows = $rows } -ScriptBlock {
        param($Rows)
        $resources = $sync.Form.Resources

        $window = New-Object Windows.Window
        $window.Title = "Startup Apps"
        $window.Width = 520
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
        $heading.Text = "What should start with Windows?"
        $heading.Foreground = $resources["LabelboxForegroundColor"]
        $heading.FontFamily = $resources["HeaderFontFamily"]
        $heading.FontSize = 18
        $panel.Children.Add($heading) | Out-Null

        $hint = New-Object Windows.Controls.TextBlock
        $hint.Text = "Untick an app to stop it from opening when the PC starts. Nothing is uninstalled, and you can tick it again any time. Fewer startup apps = faster boot."
        $hint.TextWrapping = "Wrap"
        $hint.Margin = [Windows.Thickness]::new(0, 4, 0, 12)
        $hint.Foreground = $resources["MainForegroundColor"]
        $hint.FontFamily = $resources["FontFamily"]
        $hint.Opacity = 0.75
        $panel.Children.Add($hint) | Out-Null

        $list = New-Object Windows.Controls.StackPanel
        $boxes = New-Object System.Collections.ArrayList
        if ($Rows.Count -eq 0) {
            $empty = New-Object Windows.Controls.TextBlock
            $empty.Text = "No startup apps found."
            $empty.Foreground = $resources["MainForegroundColor"]
            $list.Children.Add($empty) | Out-Null
        }
        foreach ($row in $Rows) {
            $box = New-Object Windows.Controls.CheckBox
            $box.IsChecked = $row.Enabled
            $box.Margin = [Windows.Thickness]::new(0, 0, 0, 8)
            $box.Foreground = $resources["MainForegroundColor"]
            $box.VerticalContentAlignment = "Top"

            $text = New-Object Windows.Controls.StackPanel
            $title = New-Object Windows.Controls.TextBlock
            $title.Text = $row.Name
            $title.FontFamily = $resources["HeaderFontFamily"]
            $title.FontSize = 13
            $title.Foreground = $resources["MainForegroundColor"]
            $detail = New-Object Windows.Controls.TextBlock
            $detail.Text = "For $($row.Scope) - $($row.Command)"
            $detail.TextTrimming = "CharacterEllipsis"
            $detail.ToolTip = $row.Command
            $detail.MaxWidth = 430
            $detail.Opacity = 0.6
            $detail.FontSize = 11
            $detail.FontFamily = $resources["FontFamily"]
            $detail.Foreground = $resources["MainForegroundColor"]
            $text.Children.Add($title) | Out-Null
            $text.Children.Add($detail) | Out-Null
            $box.Content = $text

            $list.Children.Add($box) | Out-Null
            $null = $boxes.Add($box)
        }

        $scroll = New-Object Windows.Controls.ScrollViewer
        $scroll.MaxHeight = 420
        $scroll.VerticalScrollBarVisibility = "Auto"
        $scroll.Content = $list
        $scroll.Margin = [Windows.Thickness]::new(0, 0, 0, 16)
        $panel.Children.Add($scroll) | Out-Null

        $buttons = New-Object Windows.Controls.StackPanel
        $buttons.Orientation = "Horizontal"
        $buttons.HorizontalAlignment = "Right"

        $saveButton = New-Object Windows.Controls.Button
        $saveButton.Content = "Save"
        $saveButton.Width = 120
        $saveButton.Height = 30
        $saveButton.Margin = [Windows.Thickness]::new(0, 0, 8, 0)
        $saveButton.IsDefault = $true
        $saveButton.Background = $resources["ButtonBackgroundSelectedColor"]
        $saveButton.Foreground = [Windows.Media.Brushes]::White
        $buttons.Children.Add($saveButton) | Out-Null

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
        $window.Resources["StartupBoxes"] = $boxes

        $saveButton.Add_Click({
            param($eventSender)
            $owner = [Windows.Window]::GetWindow($eventSender)
            $startupBoxes = $owner.Resources["StartupBoxes"]
            $ticked = for ($index = 0; $index -lt $startupBoxes.Count; $index++) {
                if ($startupBoxes[$index].IsChecked) { $index }
            }
            $owner.Tag = "ok:" + ($ticked -join ",")
            $owner.Close()
        })

        $null = $window.ShowDialog()
        $window.Tag
    }

    if ([string]::IsNullOrWhiteSpace("$result")) { return $null }
    return "$result"
}
