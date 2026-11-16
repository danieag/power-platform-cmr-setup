#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$archive = Join-Path $destination 'power-platform-setup-windows.zip'
# Explicit public-file allowlist: never package workspace state or personal configuration.
$files = @(
    'Setup.cmd', 'Setup.ps1', 'README.md', 'AGENTS.md', 'LICENSE',
    'skills\power-platform-setup\SKILL.md',
    'skills\power-platform-integrations\SKILL.md',
    'skills\power-platform-connect\SKILL.md',
    'docs\advanced-setup.md',
    'docs\images\01-download-zip.png',
    'docs\images\02-extracted-folder.png',
    'docs\images\03-open-setup.png',
    'docs\images\04-approve-install.png',
    'docs\images\05-dotnet-download.png',
    'docs\images\06-dotnet-error.png',
    'docs\images\07-dotnet-ready.png',
    'docs\images\08-approve-plugins.png',
    'docs\images\09-add-local-folder.png',
    'docs\images\10-agent-setup-prompt.png',
    'docs\images\11-vscode-configure-marketplaces.png',
    'docs\images\12-vscode-add-marketplace.png',
    'docs\images\13-vscode-marketplace-source.png',
    'docs\images\14-vscode-plugin-catalog.png'
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
    ForEach-Object { "$($_.Hash.ToLowerInvariant())  power-platform-setup-windows.zip" } |
    Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII
Write-Host "Created $archive and its SHA256 checksum."
