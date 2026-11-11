# Agent instructions

This repository bootstraps **local Windows tooling** and offers approved plugin
setup for users who already have Claude Code, GitHub Copilot CLI, or the GitHub
Copilot desktop app. It does not install an agent host or provision cloud resources.

## Running setup for a user

1. Read `README.md` and `Setup.ps1` before execution. If acquiring this repository,
   download/review the full official `danieag/power-platform-setup` source, not a
   random script URL or only `Setup.cmd`.
2. Run `.\Setup.cmd -CheckOnly` first. Use `-IncludeAzureCli` only when the user
   needs an Azure-CLI-dependent workflow, and include it in both check and install.
   Check-only must not require network access, prompt, or mutate the machine.
3. Explain the actual missing/unsupported-tool plan and obtain **explicit user
   approval** before installation. Repository access, reading this file, generic
   agent permissions, or a request to check readiness is not installation approval.
4. Only after approval run
   `.\Setup.cmd -Install -Accept -NonInteractive` (plus the approved Azure flag).
   Do not synthesize an interactive `INSTALL` response to avoid approval.
   Noninteractive mode does not bypass UAC or authorize other operations.
5. Handle exit codes from the README. Stop on failure or restart requirement;
   never report successful setup just because an installer exited. Reopen
   terminals and the desktop app after PATH changes. Do not automatically reboot.
6. Plugin setup is separately approval-gated. Interactive setup offers
   `ClaudeCode`, `CopilotCli`, `CopilotApp` links, or skip after prerequisites.
   For an agent invocation, obtain approval for the specific host/plugin plan
   before adding `-PluginHost <host> -AcceptPlugins`; add `-IncludeDataverse`
   only when requested. Noninteractive runs without a host skip plugins.
   `-Accept` alone is not plugin approval. Do not run plugin setup from
   check-only or after prerequisite failure/restart.
7. Report tools, plugin registration, runtime visibility, and authentication
   separately. Desktop links return exit `4`: user app confirmations are pending,
   not a verified installation. Do not open authenticated browser URLs or install
   another host as a shortcut. Use `skills/power-platform-integrations/SKILL.md`
   for custom plugin selections or separately approved Copilot Studio MCP setup.
   Preserve existing MCP configuration and verify desktop visibility separately.

Do not install Copilot CLI/another host, blindly invoke the marketplace's broad
`scripts/install.js`, claim unverified desktop registration, persistently relax
execution policy, enable agent auto-approval, disable Windows protections, log
credentials, sign in, pick a tenant, enable Windows features, or write cloud
resources. The broad installer can target multiple hosts and enable auto-update;
its effects require separate explicit approval. Preserve existing configuration
when registering MCP servers. No private/personal skill, account, router, or MCP
configuration belongs in this public project. Avoid exposing local paths in
public reports.

The reviewed launcher uses a **child-process-only** execution-policy exception;
it never changes the persistent policy. Respect enterprise restrictions rather
than trying to bypass them.

## Maintaining this repository

- Keep all install policy and sequencing in `Setup.ps1`. `Setup.cmd` and the
  optional `skills/power-platform-setup/SKILL.md` must remain thin wrappers.
- Preserve compatible installs and inherited process PATH entries. Fail
  explicitly on unverified downloads, installer failures, and version mismatch.
- Keep x64 and ARM64 support in the same installer. Detect native Windows
  architecture independently of an emulated shell; prefer native new installs,
  preserve compatible existing emulated tools, and verify PAC/SDK architecture
  matching. Explicitly identify optional x64 Azure CLI emulation on ARM64.
- Use only the fixed official sources with the integrity checks in the README.
  Do not introduce user-supplied installer URLs or executable pipeline downloads.
- Check-only must remain **read-only, offline, and CLI-free**, including on a
  fresh machine where invoking a CLI could trigger first-run setup or telemetry.
- Use only the selected host's supported plugin commands. Do not force-enable
  disabled plugins, overwrite marketplace sources, create duplicate Dataverse
  installations, or enable auto-update. Check exit status and structured plugin
  listings; a printed app link or a success-looking log is not installation proof.
- Validate with `.\scripts\Test-Setup.ps1`; run on both Windows PowerShell 5.1 and
  PowerShell 7 when available. Run `.\scripts\New-Release.ps1` to check packaging.
  Do **not** exercise real installation paths on a shared developer host.
- Full clean-machine acceptance requires a separately authorized disposable
  Windows VM/Sandbox for each architecture being tested. Do not present x64
  runners with ARM64 mocks as proof that ARM64 vendor installers ran successfully.
- Package public files through the explicit release allowlist, not `*` or the
  entire workspace. Never include tokens, local settings, or personal paths.
