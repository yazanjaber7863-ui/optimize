<#
.SYNOPSIS
    Builds Optimize.exe, a launcher with the compiled winutil.ps1 and the Optimize icon inside

.DESCRIPTION
    Uses the C# compiler that comes with Windows (.NET Framework 4), so nothing has to be
    installed. Run Compile.ps1 first: the exe carries whatever winutil.ps1 is at -ScriptPath.

.PARAMETER ScriptPath
    The compiled script to embed. Defaults to winutil.ps1 in the repository root.

.PARAMETER OutFile
    Where to write the exe. Defaults to binary\Optimize.exe, which Git ignores.

.PARAMETER Version
    The version the exe reports, which it compares with the latest GitHub release to offer
    updates. Pass the release tag (e.g. 26.10.22.2). Defaults to the version in the script.
#>
param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "..\..\winutil.ps1"),
    [string]$OutFile = (Join-Path $PSScriptRoot "..\..\binary\Optimize.exe"),
    [string]$Version
)

$ErrorActionPreference = "Stop"

$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).Path
if (-not $Version) {
    $Version = ([regex]::Match((Get-Content -LiteralPath $ScriptPath -Raw), '\$sync\.version\s*=\s*"([\d.]+)"')).Groups[1].Value
}
$parsedVersion = $null
if (-not [Version]::TryParse($Version, [ref]$parsedVersion)) {
    throw "'$Version' is not a version like 26.10.22. Pass -Version with the release tag."
}
$buildInfo = Join-Path ([IO.Path]::GetTempPath()) "optimize-buildinfo-$([guid]::NewGuid().ToString('N')).cs"
Set-Content -LiteralPath $buildInfo -Encoding UTF8 -Value @"
[assembly: System.Reflection.AssemblyVersion("$parsedVersion")]
[assembly: System.Reflection.AssemblyFileVersion("$parsedVersion")]
static class BuildInfo { public const string Version = "$Version"; }
"@
$compiler = Join-Path $env:SystemRoot "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "The .NET Framework 4 C# compiler was not found at $compiler."
}

$outDir = Split-Path -Parent $OutFile
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$OutFile = Join-Path (Resolve-Path -LiteralPath $outDir).Path (Split-Path -Leaf $OutFile)

# An .ico can hold PNG images (Windows Vista and later), so the logo PNGs go in as they are
$iconPath = Join-Path ([IO.Path]::GetTempPath()) "optimize-$([guid]::NewGuid().ToString('N')).ico"
$images = @(
    @{ Size = 32; Bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot "optimize-32.png")) }
    @{ Size = 256; Bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot "optimize-256.png")) }
)
$stream = [IO.File]::Create($iconPath)
$writer = New-Object IO.BinaryWriter($stream)
try {
    $writer.Write([uint16]0)               # reserved
    $writer.Write([uint16]1)               # type: icon
    $writer.Write([uint16]$images.Count)
    $offset = 6 + 16 * $images.Count
    foreach ($image in $images) {
        $dimension = if ($image.Size -ge 256) { 0 } else { $image.Size }   # 0 means 256
        $writer.Write([byte]$dimension)
        $writer.Write([byte]$dimension)
        $writer.Write([byte]0)             # no palette
        $writer.Write([byte]0)             # reserved
        $writer.Write([uint16]1)           # colour planes
        $writer.Write([uint16]32)          # bits per pixel
        $writer.Write([uint32]$image.Bytes.Length)
        $writer.Write([uint32]$offset)
        $offset += $image.Bytes.Length
    }
    foreach ($image in $images) {
        $writer.Write($image.Bytes)
    }
} finally {
    $writer.Dispose()
}

try {
    $arguments = @(
        "/nologo", "/target:winexe", "/optimize+",
        "/out:$OutFile",
        "/win32icon:$iconPath",
        "/win32manifest:$(Join-Path $PSScriptRoot 'Optimize.manifest')",
        "/resource:$ScriptPath,winutil.ps1",
        "/reference:System.Windows.Forms.dll",
        (Join-Path $PSScriptRoot "OptimizeLauncher.cs"),
        $buildInfo
    )
    & $compiler @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "The C# compiler failed with exit code $LASTEXITCODE."
    }
} finally {
    Remove-Item -LiteralPath $iconPath, $buildInfo -Force -ErrorAction SilentlyContinue
}

$exe = Get-Item -LiteralPath $OutFile
Write-Host "Built $($exe.FullName) version $Version ($([math]::Round($exe.Length / 1KB)) KB)" -ForegroundColor Green
