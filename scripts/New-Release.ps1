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
    'Setup.cmd', 'Setup.ps1', 'README.md', 'AGENTS.md', 'CLAUDE.md', 'LICENSE',
    '.github\skills\power-platform-setup\SKILL.md',
    '.claude\skills\power-platform-setup\SKILL.md',
    'skills\power-platform-setup\SKILL.md',
    'skills\power-platform-doctor\SKILL.md',
    'skills\power-platform-integrations\SKILL.md',
    'skills\power-platform-connect\SKILL.md',
    'docs\advanced-setup.md',
    'docs\agent-guided-setup-guide.md',
    'docs\power-platform-connect-guide.md',
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
    'docs\images\14-vscode-plugin-catalog.png',
    'docs\images\15-connect-start.png',
    'docs\images\16-connect-environment-url.png',
    'docs\images\17-connect-tenant-id.png',
    'docs\images\18-connect-sign-in-email.png',
    'docs\images\19-connect-nickname.png',
    'docs\images\20-connect-tools.png',
    'docs\images\21-connect-install-cli.png',
    'docs\images\22-connect-sign-in-approval.png',
    'docs\images\23-connect-read-only-checks.png',
    'docs\images\24-connect-private-record.png',
    'docs\images\25-connect-mcp-registration.png',
    'docs\images\26-connect-restart.png',
    'docs\images\27-connect-before-restart.png',
    'docs\images\28-connect-after-restart.png',
    'docs\images\29-agent-guided-prompt.png',
    'docs\images\30-agent-host-selection.png',
    'docs\images\31-agent-short-prompt.png',
    'docs\images\32-agent-choose-app.png',
    'docs\images\33-agent-multi-workload-select.png',
    'docs\images\34-agent-selective-prereq-check.png',
    'docs\images\35-agent-approve-marketplace-links.png',
    'docs\images\36-copilot-app-allow-marketplace.png',
    'docs\images\37-copilot-app-manage-marketplaces-add.png',
    'docs\images\38-copilot-app-adding-marketplace.png',
    'docs\images\39-copilot-app-marketplace-added.png',
    'docs\images\40-copilot-app-return-to-session.png',
    'docs\images\41-agent-confirm-marketplace-added.png',
    'docs\images\42-copilot-app-allow-model-apps.png',
    'docs\images\43-copilot-app-install-model-apps.png',
    'docs\images\44-copilot-app-allow-code-apps.png',
    'docs\images\45-copilot-app-install-code-apps.png',
    'docs\images\46-agent-both-plugins-ready-connect.png',
    'docs\images\47-connect-enter-url-or-discover.png',
    'docs\images\48-connect-ask-account.png',
    'docs\images\49-connect-confirm-pac-signin.png',
    'docs\images\50-connect-pac-device-code-prompt.png',
    'docs\images\51-connect-enter-device-code.png',
    'docs\images\52-connect-approve-signin.png',
    'docs\images\53-connect-pac-signed-in-browser.png',
    'docs\images\54-connect-complete-summary.png'
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
