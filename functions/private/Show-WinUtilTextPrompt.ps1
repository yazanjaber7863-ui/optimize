function Show-WinUtilTextPrompt {
    <#
    .SYNOPSIS
        Asks for one line of text in a themed window and returns it, or $null when cancelled

    .PARAMETER Title
        Window title and heading

    .PARAMETER Message
        Explanation under the heading

    .PARAMETER Default
        Text the box starts with
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Message = "",

        [string]$Default = ""
    )

    if (-not (Test-WinUtilUIAlive)) {
        Write-WinUtilLog -Level "WARN" -Component "Dialog" -Message "No window for the '$Title' prompt"
        return $null
    }

    $result = Invoke-WPFUIThread -PassThru -Parameters @{ Title = $Title; Message = $Message; Default = $Default } -ScriptBlock {
        param($Title, $Message, $Default)
        $resources = $sync.Form.Resources

        $window = New-Object Windows.Window
        $window.Title = $Title
        $window.Width = 420
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
        $heading.Text = $Title
        $heading.Foreground = $resources["LabelboxForegroundColor"]
        $heading.FontFamily = $resources["HeaderFontFamily"]
        $heading.FontSize = 18
        $panel.Children.Add($heading) | Out-Null

        if ($Message) {
            $hint = New-Object Windows.Controls.TextBlock
            $hint.Text = $Message
            $hint.TextWrapping = "Wrap"
            $hint.Margin = [Windows.Thickness]::new(0, 4, 0, 0)
            $hint.Opacity = 0.75
            $hint.Foreground = $resources["MainForegroundColor"]
            $hint.FontFamily = $resources["FontFamily"]
            $panel.Children.Add($hint) | Out-Null
        }

        $textBox = New-Object Windows.Controls.TextBox
        $textBox.Text = $Default
        $textBox.Height = 30
        $textBox.FontSize = 14
        $textBox.VerticalContentAlignment = "Center"
        $textBox.Margin = [Windows.Thickness]::new(0, 12, 0, 16)
        $textBox.Background = $resources["ComboBoxBackgroundColor"]
        $textBox.Foreground = $resources["MainForegroundColor"]
        $textBox.CaretBrush = $resources["MainForegroundColor"]
        $textBox.BorderBrush = $resources["BorderColor"]
        $panel.Children.Add($textBox) | Out-Null

        $buttons = New-Object Windows.Controls.StackPanel
        $buttons.Orientation = "Horizontal"
        $buttons.HorizontalAlignment = "Right"

        $okButton = New-Object Windows.Controls.Button
        $okButton.Content = "OK"
        $okButton.Width = 100
        $okButton.Height = 30
        $okButton.Margin = [Windows.Thickness]::new(0, 0, 8, 0)
        $okButton.IsDefault = $true
        $okButton.Background = $resources["ButtonBackgroundSelectedColor"]
        $okButton.Foreground = [Windows.Media.Brushes]::White
        $buttons.Children.Add($okButton) | Out-Null

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

        # The box travels on the window's Resources so the handler needs no captured variables
        $window.Resources["PromptBox"] = $textBox
        $okButton.Add_Click({
            param($eventSender)
            $owner = [Windows.Window]::GetWindow($eventSender)
            $owner.Tag = "ok:" + $owner.Resources["PromptBox"].Text
            $owner.Close()
        })
        $window.Add_ContentRendered({
            param($eventSender)
            $box = ([Windows.Window]$eventSender).Resources["PromptBox"]
            $box.Focus() | Out-Null
            $box.SelectAll()
        })

        $null = $window.ShowDialog()
        $window.Tag
    }

    if ("$result" -notlike "ok:*") { return $null }
    return ("$result".Substring(3)).Trim()
}
