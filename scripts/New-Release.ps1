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
    'skills\power-platform-connect\SKILL.md',
    'skills\power-platform-router\SKILL.md',
    'docs\advanced-setup.md',
    'docs\agent-guided-setup-guide.md',
    'docs\media-bank.md',
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
    'docs\images\54-connect-complete-summary.png',
    'docs\images\55-connect-add-dataverse-plugin.png',
    'docs\images\56-connect-approve-dataverse-cli-npm.png',
    'docs\images\57-connect-approve-dataverse-cli-signin.png',
    'docs\images\58-connect-dataverse-cli-ready-offer-mcp.png',
    'docs\images\59-connect-approve-mcp-config.png',
    'docs\images\60-connect-mcp-config-saved.png',
    'docs\images\61-connect-mcp-server-customize-installed.png',
    'docs\images\62-connect-mcp-live-verify-tools.png',
    'docs\images\63-connect-all-surfaces-summary.png',
    'docs\images\64-connect-persistence-verified.png',
    'docs\media-bank\01-github-repo-code-menu-download-or-open.png',
    'docs\media-bank\02-copilot-app-new-session-add-menu.png',
    'docs\media-bank\03-copilot-app-add-from-github-search.png',
    'docs\media-bank\04-copilot-app-paste-short-onboarding-prompt.png',
    'docs\media-bank\05-setup-skill-loaded-choose-target-app.png',
    'docs\media-bank\06-select-multiple-power-platform-workloads.png',
    'docs\media-bank\07-approve-installing-only-missing-pac-and-azure-cli.png',
    'docs\media-bank\08-prerequisites-ready-approve-marketplace-and-plugins.png',
    'docs\media-bank\09-copilot-app-allow-marketplace-modal-and-wait-gate.png',
    'docs\media-bank\10-copilot-app-install-model-apps-plugin-modal.png',
    'docs\media-bank\11-copilot-app-install-canvas-apps-plugin-modal.png',
    'docs\media-bank\12-all-selected-plugins-confirmed-offer-connection.png',
    'docs\media-bank\13-approve-personal-connect-and-router-skills.png',
    'docs\media-bank\14-four-plugin-confirmation-log-and-reopen-handoff.png',
    'docs\media-bank\15-copilot-customize-installed-enable-skills-toggles.png',
    'docs\media-bank\16-reopen-copilot-and-paste-connection-resume-prompt.png',
    'docs\media-bank\17-connect-choose-discovery-saved-or-manual-url.png',
    'docs\media-bank\18-connect-enter-work-or-school-signin-email.png',
    'docs\media-bank\19-connect-enter-microsoft-entra-tenant-id.png',
    'docs\media-bank\20-connect-approve-local-pac-and-registry-inspection.png',
    'docs\media-bank\21-connect-enter-initial-environment-url-context.png',
    'docs\media-bank\22-connect-approve-pac-profile-and-device-code-signin.png',
    'docs\media-bank\23-connect-pac-device-code-output-and-signin-confirm.png',
    'docs\media-bank\24-connect-pac-signed-in-offer-environment-discovery.png',
    'docs\media-bank\25-connect-select-surfaces-and-optional-dataverse-plugin.png',
    'docs\media-bank\26-connect-dataverse-cli-detected-propose-nickname.png',
    'docs\media-bank\27-connect-enter-custom-demo-env-nickname.png',
    'docs\media-bank\28-connect-approve-dataverse-mcp-config-entry.png',
    'docs\media-bank\29-connect-approve-saving-private-demo-env-json.png',
    'docs\media-bank\30-connect-approve-fresh-process-cli-and-azure-checks.png',
    'docs\media-bank\31-connect-cli-checks-passed-approve-mcp-verify-after-reload.png',
    'docs\media-bank\32-connect-saved-reopen-copilot-for-mcp-verification.png',
    'docs\media-bank\33-connect-post-reload-dataverse-mcp-verified.png',
    'docs\media-bank\34-flowagent-install-power-automate-plugin-normally.png',
    'docs\media-bank\35-flowagent-mcp-detected-approve-readonly-whoami-check.png',
    'docs\media-bank\36-flowagent-identity-matched-offer-registry-link.png',
    'docs\media-bank\37-flowagent-linked-in-connection-registry-json.png',
    'docs\media-bank\38-copilot-studio-mcp-approve-registration-while-closed.png',
    'docs\media-bank\39-copilot-studio-mcp-verified-offer-registry-link.png',
    'docs\media-bank\40-copilot-studio-mcp-linked-in-registry-summary.png',
    'docs\media-bank\41-router-skill-all-six-clis-and-mcps-verified.png'
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
