function Show-WinUtilReport {
    <#
    .SYNOPSIS
        Shows a themed window with rows of label / value pairs and a Close button

    .PARAMETER Title
        The window title and heading

    .PARAMETER Rows
        Hashtables with Label and Value. A row with no Value is drawn as a section heading.
        Status = "Good", "Warn" or "Bad" colours the value.

    .PARAMETER Note
        Optional text under the rows
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [object[]]$Rows,

        [string]$Note = ""
    )

    if (-not (Test-WinUtilUIAlive)) {
        # No window, e.g. a headless run: print the same rows to the console instead
        Write-Host "`n=== $Title ===" -ForegroundColor Cyan
        foreach ($row in $Rows) {
            if ($null -eq $row.Value) { Write-Host "`n$($row.Label)" -ForegroundColor Cyan } else { Write-Host ("  {0,-22} {1}" -f $row.Label, $row.Value) }
        }
        if ($Note) { Write-Host "`n$Note" }
        return
    }

    # Plain hashtables so the values cross into the interface runspace as data
    $plainRows = @($Rows | ForEach-Object { @{ Label = "$($_.Label)"; Value = $(if ($null -eq $_.Value) { $null } else { "$($_.Value)" }); Status = "$($_.Status)" } })

    Invoke-WPFUIThread -Parameters @{ Title = $Title; Rows = $plainRows; Note = $Note } -ScriptBlock {
        param($Title, $Rows, $Note)
        $resources = $sync.Form.Resources

        $window = New-Object Windows.Window
        $window.Title = $Title
        $window.Width = 560
        $window.SizeToContent = "Height"
        $window.WindowStartupLocation = "CenterOwner"
        $window.Owner = $sync.Form
        $window.ResizeMode = "NoResize"
        $window.WindowStyle = "ToolWindow"
        $window.Background = $resources["MainBackgroundColor"]

        $panel = New-Object Windows.Controls.StackPanel
        $panel.Margin = [Windows.Thickness]::new(20)

        $heading = New-Object Windows.Controls.TextBlock
        $heading.Text = $Title
        $heading.Foreground = $resources["LabelboxForegroundColor"]
        $heading.FontFamily = $resources["HeaderFontFamily"]
        $heading.FontSize = 18
        $heading.Margin = [Windows.Thickness]::new(0, 0, 0, 8)
        $panel.Children.Add($heading) | Out-Null

        $grid = New-Object Windows.Controls.Grid
        $labelColumn = New-Object Windows.Controls.ColumnDefinition
        $labelColumn.Width = [Windows.GridLength]::new(170)
        $valueColumn = New-Object Windows.Controls.ColumnDefinition
        $valueColumn.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
        $grid.ColumnDefinitions.Add($labelColumn)
        $grid.ColumnDefinitions.Add($valueColumn)

        $statusColours = @{ Good = "#22C55E"; Warn = "#F59E0B"; Bad = "#EF4444" }
        $rowIndex = 0
        foreach ($row in $Rows) {
            $grid.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition)) | Out-Null

            $label = New-Object Windows.Controls.TextBlock
            $label.Text = $row.Label
            $label.FontFamily = $resources["FontFamily"]
            $label.Foreground = $resources["MainForegroundColor"]
            [Windows.Controls.Grid]::SetRow($label, $rowIndex)

            if ($null -eq $row.Value) {
                # Section heading across both columns
                $label.FontFamily = $resources["HeaderFontFamily"]
                $label.FontSize = 14
                $label.Foreground = $resources["LabelboxForegroundColor"]
                $label.Margin = [Windows.Thickness]::new(0, 12, 0, 4)
                [Windows.Controls.Grid]::SetColumnSpan($label, 2)
                $grid.Children.Add($label) | Out-Null
            } else {
                $label.Opacity = 0.7
                $label.Margin = [Windows.Thickness]::new(0, 2, 8, 2)
                # Long app names would be cut mid-word by the fixed column
                $label.TextTrimming = "CharacterEllipsis"
                $label.ToolTip = $row.Label
                $grid.Children.Add($label) | Out-Null

                $value = New-Object Windows.Controls.TextBlock
                $value.Text = $row.Value
                $value.TextWrapping = "Wrap"
                $value.FontFamily = $resources["FontFamily"]
                $value.Margin = [Windows.Thickness]::new(0, 2, 0, 2)
                if ($statusColours.ContainsKey($row.Status)) {
                    $value.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($statusColours[$row.Status])
                    $value.FontWeight = "SemiBold"
                } else {
                    $value.Foreground = $resources["MainForegroundColor"]
                }
                [Windows.Controls.Grid]::SetRow($value, $rowIndex)
                [Windows.Controls.Grid]::SetColumn($value, 1)
                $grid.Children.Add($value) | Out-Null
            }
            $rowIndex++
        }

        $scroll = New-Object Windows.Controls.ScrollViewer
        $scroll.MaxHeight = 520
        $scroll.VerticalScrollBarVisibility = "Auto"
        $scroll.Content = $grid
        $panel.Children.Add($scroll) | Out-Null

        if ($Note) {
            $noteBlock = New-Object Windows.Controls.TextBlock
            $noteBlock.Text = $Note
            $noteBlock.TextWrapping = "Wrap"
            $noteBlock.Opacity = 0.75
            $noteBlock.Margin = [Windows.Thickness]::new(0, 12, 0, 0)
            $noteBlock.FontFamily = $resources["FontFamily"]
            $noteBlock.Foreground = $resources["MainForegroundColor"]
            $panel.Children.Add($noteBlock) | Out-Null
        }

        $closeButton = New-Object Windows.Controls.Button
        $closeButton.Content = "Close"
        $closeButton.Width = 100
        $closeButton.Height = 30
        $closeButton.Margin = [Windows.Thickness]::new(0, 16, 0, 0)
        $closeButton.HorizontalAlignment = "Right"
        $closeButton.IsCancel = $true
        $closeButton.IsDefault = $true
        $closeButton.Background = $resources["ButtonBackgroundSelectedColor"]
        $closeButton.Foreground = [Windows.Media.Brushes]::White
        $panel.Children.Add($closeButton) | Out-Null

        $window.Content = $panel
        $null = $window.ShowDialog()
    }
}
