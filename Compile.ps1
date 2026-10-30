param (
    [switch]$Run
)

$OFS = "`r`n"

# The released script must be plain ASCII. Windows PowerShell 5.1's Invoke-RestMethod reads a
# GitHub download as Latin-1, so a UTF-8 byte order mark turned into three stray characters in
# front of the param block (every argument, such as -Preset, was then ignored) and symbols
# became gibberish.
# Config and XAML text keep their symbols as escapes, which mean the same character once loaded.
function ConvertTo-AsciiEscaped {
    param([string]$Text, [ValidateSet("Json", "Xml")] [string]$As)
    [regex]::Replace($Text, '[\uD800-\uDBFF][\uDC00-\uDFFF]|[^\x00-\x7F]', {
        param($match)
        if ($As -eq "Xml") {
            "&#x{0:X};" -f [char]::ConvertToUtf32($match.Value, 0)
        } else {
            -join ($match.Value.ToCharArray() | ForEach-Object { "\u{0:x4}" -f [int]$_ })
        }
    })
}

# Variable to sync between runspaces
$sync = [Hashtable]::Synchronized(@{})
$sync.configs = @{}

$script = (Get-Content -Path scripts\start.ps1 -Encoding UTF8) -replace '#{replaceme}', (Get-Date -Format 'yy.MM.dd')
$isLocalCompile = -not [string]::Equals($env:GITHUB_ACTIONS, "true", [StringComparison]::OrdinalIgnoreCase)
$script = $script -replace '#{islocalcompile}', $isLocalCompile.ToString().ToLowerInvariant()

$script += Get-ChildItem -Path functions -Recurse -File | ForEach-Object {
    Get-Content -Path $_.FullName -Raw -Encoding UTF8
}

Get-ChildItem config | ForEach-Object {
    $obj = Get-Content -Path $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($_.Name -eq "applications.json") {
        $fixed = [ordered]@{}
        foreach ($p in $obj.PSObject.Properties) {
            $fixed["WPFInstall$($p.Name)"] = $p.Value
        }
        $obj = [pscustomobject]$fixed
    }

    $json = ConvertTo-AsciiEscaped -Text ($obj | ConvertTo-Json -Depth 10) -As Json

    $sync.configs[$_.BaseName] = $obj
    $script += "`$sync.configs.$($_.BaseName) = @'`r`n$json`r`n'@ | ConvertFrom-Json"
}

$xaml = ConvertTo-AsciiEscaped -Text (Get-Content -Path xaml\inputXML.xaml -Raw -Encoding UTF8) -As Xml
$script += "`$inputXML = @'`r`n$xaml`r`n'@"

$autounattendXml = ConvertTo-AsciiEscaped -Text (Get-Content -Path tools\autounattend.xml -Raw -Encoding UTF8) -As Xml
$script += "`$WinUtilAutounattendXml = @'`r`n$autounattendXml`r`n'@"

$script += Get-Content -Path scripts\main.ps1 -Raw -Encoding UTF8

$text = $script -join "`r`n"
$nonAscii = [regex]::Matches($text, '[^\x00-\x7F]')
if ($nonAscii.Count -gt 0) {
    $where = $nonAscii | Select-Object -First 5 | ForEach-Object {
        $lineNumber = ($text.Substring(0, $_.Index) -split "`n").Count
        "U+{0:X4} on line {1}: {2}" -f [int][char]$_.Value, $lineNumber, ($text -split "`n")[$lineNumber - 1].Trim()
    }
    throw "The compiled script must be plain ASCII (see the note at the top of Compile.ps1). Write the character with [char] in PowerShell code:`n$($where -join "`n")"
}
# No byte order mark: plain ASCII reads the same under every encoding
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "winutil.ps1"), $text, (New-Object Text.UTF8Encoding($false)))

if ($Run) {
    .\Winutil.ps1
}
