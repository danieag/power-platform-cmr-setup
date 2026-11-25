#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$archive = Join-Path $destination 'power-platform-cmr-setup-windows.zip'
# Explicit public-file allowlist: never package workspace state, personal configuration, or screenshot media.
$files = @(
    'Setup.cmd', 'Setup.ps1', 'README.md', 'AGENTS.md', 'CLAUDE.md', 'LICENSE',
    '.github\skills\power-platform-setup\SKILL.md',
    '.claude\skills\power-platform-setup\SKILL.md',
    'skills\power-platform-setup\SKILL.md',
    'skills\power-platform-connect\SKILL.md',
    'skills\power-platform-router\SKILL.md',
    'docs\advanced-setup.md',
    'docs\media-bank.md'
)
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$temporary = Join-Path $destination ([guid]::NewGuid().ToString('N') + '.zip')
try {
    $zip = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, (Join-Path $root $file), $file.Replace('\', '/'),
                [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $zip.Dispose() }
    Move-Item -LiteralPath $temporary -Destination $archive -Force
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}
Get-FileHash -LiteralPath $archive -Algorithm SHA256 |
    ForEach-Object { "$($_.Hash.ToLowerInvariant())  power-platform-cmr-setup-windows.zip" } |
    Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII
Write-Host "Created $archive and its SHA256 checksum."
