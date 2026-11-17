# Agent instructions

This repository bootstraps **local Windows tooling** and offers approved plugin
setup for users who already have Claude Code, GitHub Copilot CLI, or the GitHub
Copilot desktop app. It does not install an agent host or provision cloud resources.

## Running setup for a user

1. Read `README.md` and `Setup.ps1` before execution. If acquiring this repository,
   download/review the full official `danieag/power-platform-setup` source, not a
   random script URL or only `Setup.cmd`.
2. Run `.\Setup.cmd -CheckOnly` first. Azure CLI is included by default after
   PAC for the full Power Platform setup. Use `-SkipAzureCli` on both check and
   install only for a user-approved minimal setup; explain Azure-dependent plugin
   limitations. Legacy `-IncludeAzureCli` remains accepted but is unnecessary.
   Check-only must not require network access, prompt, or mutate the machine.
3. Explain the actual missing/unsupported-tool plan and obtain **explicit user
   approval** before installation. Repository access, reading this file, generic
   agent permissions, or a request to check readiness is not installation approval.
4. Only after approval run
   `.\Setup.cmd -Install -Accept -NonInteractive` (plus `-SkipAzureCli` only when approved).
   Do not synthesize an interactive `INSTALL` response to avoid approval.
   Noninteractive mode does not bypass UAC or authorize other operations.
5. Handle exit codes from the README. Stop on failure or restart requirement;
   never report successful setup just because an installer exited. Reopen
   terminals and the desktop app after PATH changes. Do not automatically reboot.
6. Plugin setup is separately approval-gated. Interactive setup offers
   `ClaudeCode`, `CopilotCli`, `CopilotApp` links, or skip after prerequisites.
   README Step 2's doctor first prepares the chosen CLI's official marketplace
   with separately approved `-MarketplaceOnly -AcceptPlugins`, then asks which
   plugins the user wants and reuses `Setup.cmd -Plugins "id,id"`.
   Marketplace-only approval does not authorize later plugin installation.
   The interactive chooser uses passive command/`ghapp` registration evidence,
   not proof of working hosts. Missing selected CLIs get fixed official install
   instructions and exit `2`; never install/substitute another host or approve
   a first-run launcher. An undetected desktop app needs the user's `APP`
   availability confirmation or an official-installation handoff.
   Always pass the approved selection explicitly for the doctor; never turn
   no selection into the default full set. Dataverse is opt-in through an
   explicit `dataverse` ID or `-IncludeDataverse`. Do not install another host.
   For an agent invocation, obtain approval for the specific host/plugin plan
   before adding `-PluginHost <host> -AcceptPlugins`. A plugin-only rerun can
   omit `-Install -Accept` so missing prerequisites stop rather than install.
   Noninteractive runs without a host skip plugins.
   `-Accept` alone is not plugin approval. Do not run plugin setup from
   check-only or after prerequisite failure/restart.
7. Copilot Studio MCP registration is another separately approved stage. Use
   `-CopilotStudioHost <host> -AcceptCopilotStudio` only after approval, never as
   an implication of `-Accept` or `-AcceptPlugins`. It registers
   `npx -y @microsoft/copilot-studio-mcp@latest`; it does not launch the server
   or download the npm package until the host's first launch. Do not start
   `npx` standalone, sign in, select an environment, or invoke cloud tools to
   validate registration. Close the host before edits; keep local config backups
   private. Stop on conflicts or concurrent writes rather than overwriting them.
8. Report tools, plugin/MCP registration, runtime visibility, and authentication
   separately. Desktop links return exit `4`: user app confirmations are pending,
   not a verified installation. Do not open authenticated browser URLs or install
   another host as a shortcut. Use `skills/power-platform-integrations/SKILL.md`
   for custom plugin selections or agent-guided Copilot Studio MCP setup.
   Preserve existing MCP configuration and verify desktop visibility separately.
9. The final optional stage installs only the bundled connection skill file.
   Use `-ConnectionSkillHost <host> -AcceptConnectionSkill` only after approval
   for that host's personal skill directory. It never runs authentication.
   Preserve existing skills; do not overwrite different content or follow linked
   destinations. If skipped, relay the printed connection prompt/public skill URL.
   File installation is not proof of host discovery or sign-in.

For a complete guided-onboarding request, use the bundled
`skills/power-platform-setup/SKILL.md` as the entry point. It reads the doctor
after prerequisites and continues with the connection skill when requested;
the user need not invoke every file or paste another starting prompt.
Keep approved prerequisite, plugin, MCP-registration and skill-copy work in the
same conversation where possible. Combine only explicitly
approved stage flags, or use scoped follow-up invocations. Do not require a
second chat or broad remote installer just to install plugins. After PATH
changes reopen the host. A restart/new chat is a handoff when required for
capability discovery, not a way to carry installation approval into sign-in.
Give completed stages, the chosen host/plugins, and a copyable resume prompt
without identities, tokens, private paths or environment URLs.
Actual reboot/host-close requirements still need a clear interruption/handoff;
do not close the app hosting the current agent conversation without explaining it.

Do not install Copilot CLI/another host, blindly invoke the marketplace's broad
`scripts/install.js`, claim unverified desktop registration, persistently relax
execution policy, enable agent auto-approval, disable Windows protections, log
credentials, sign in or pick a tenant under installation approval, enable Windows
features, or write cloud resources. The broad installer can target multiple
hosts and enable auto-update;
its effects require separate explicit approval. Preserve existing configuration
when registering MCP servers. No private/personal skill, account, router, or MCP
configuration belongs in this public project. Avoid exposing local paths in
public reports.

## Optional connection onboarding (not part of installation)

For an explicit request to connect/sign in after setup, use
`skills/power-platform-connect/SKILL.md`. Creating or editing that public skill
does not authorize running it against the current user's tenants.

- Confirm the exact account, tenant, environment and selected surfaces before
  authentication, profile switching, live reads or connection writes. Obtain
  separate approval for sign-in, private binding records, MCP registration and
  minimal read-only identity verification. Missing tools need install approval.
- Connection onboarding may use `pac env list` after its exact existing PAC
  account/tenant/environment context and live discovery are approved. Offer
  environment names/URLs for one-or-more selection, and always allow another
  existing URL, including on reruns. If no approved PAC context exists, confirm
  an initial environment URL before sign-in, then discover. Do not infer access
  from list presence or block an unlisted target. Process selected targets
  separately; never create a cloud environment, overwrite another alias, or
  leave the final iterated profile as an unannounced default.
- Reuse Microsoft's installed `dv-overview` / `dv-connect` mechanisms for
  Dataverse authentication, only within the approved subset. Their broader
  setup capabilities do not authorize tenant writes or unrelated project files.
- Reuse matching profiles; isolate Azure tenant/account caches and scope
  `AZURE_CONFIG_DIR` per process. Never copy/decode token caches, inject bearer
  tokens, create custom OAuth flows, store passwords, disable MFA, or clear
  working sessions as a troubleshooting shortcut.
- Store only approved private connection bindings outside repositories, not
  credentials. Do not publish personal identities, local registries, cache paths
  or MCP config. Consent, allowlist, role and connector changes need a separate
  decision; setup must not silently perform them.
- Distinguish configuration, live identity checks, and new-process/chat
  persistence. Do not promise one universal login or lifetime authentication.

The reviewed launcher uses a **child-process-only** execution-policy exception;
it never changes the persistent policy. Respect enterprise restrictions rather
than trying to bypass them.

## Maintaining this repository

- Keep all install policy and sequencing in `Setup.ps1`. `Setup.cmd` and the
  optional setup/doctor skills must remain thin wrappers.
- Preserve compatible installs and inherited process PATH entries. Fail
  explicitly on unverified downloads, installer failures, and version mismatch.
- Keep x64 and ARM64 support in the same installer. Detect native Windows
  architecture independently of an emulated shell; prefer native new installs,
  preserve compatible existing emulated tools, and verify PAC/SDK architecture
  matching. Explicitly identify x64 Azure CLI emulation on ARM64.
- Use only the fixed official sources with the integrity checks in the README.
  Do not introduce user-supplied installer URLs or executable pipeline downloads.
- Check-only must remain **read-only, offline, and CLI-free**, including on a
  fresh machine where invoking a CLI could trigger first-run setup or telemetry.
- Use only the selected host's supported plugin commands. Do not force-enable
  disabled plugins, overwrite marketplace sources, create duplicate Dataverse
  installations, or enable auto-update. Check exit status and structured plugin
  listings; a printed app link or a success-looking log is not installation proof.
- Preserve unrelated MCP configuration and access controls. Verify only the saved
  definition during setup, not a live authenticated connection. Tests must use
  isolated dummy configuration files, never the developer's actual host config.
- Validate with `.\scripts\Test-Setup.ps1`; run on both Windows PowerShell 5.1 and
  PowerShell 7 when available. Run `.\scripts\New-Release.ps1` to check packaging.
  Do **not** exercise real installation paths on a shared developer host.
- Full clean-machine acceptance requires a separately authorized disposable
  Windows VM/Sandbox for each architecture being tested. Do not present x64
  runners with ARM64 mocks as proof that ARM64 vendor installers ran successfully.
- Package public files through the explicit release allowlist, not `*` or the
  entire workspace. Never include tokens, local settings, or personal paths.
