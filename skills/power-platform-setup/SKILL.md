---
name: power-platform-setup
description: Guide one Windows onboarding conversation through prerequisites, the official marketplace, selected Power Platform plugins and separately approved connection onboarding. Coordinate the repo's script, doctor and connection skills; pause with a resume prompt only when a restart or capability reload is needed.
---

# Power Platform setup

Use the reviewed public repository
<https://github.com/danieag/power-platform-setup>.
This skill is an instruction wrapper, not another installer. A repository URL
does not automatically register this skill in the desktop app.

## One entry point for the guided flow

Read this file when the user provides the complete repo/extracted folder and
asks to be guided from setup through connection. It is the front door:
**prerequisites > marketplace > plugin choices > connection onboarding**.
Read the other repo skills when their stage is reached; do not make the user
find and invoke each one separately.

Stay in the same conversation where possible and execute approved work with
terminal tools. **One starting prompt is not blanket approval.** Installation,
marketplace registration, selected plugins, optional personal skill/MCP writes,
sign-in and live identity checks retain their separate approval boundaries.
Do not execute the flow for a documentation-only or explanation request.

### Step 1: prerequisites

Read `AGENTS.md`, `README.md`, and `Setup.ps1` from the reviewed full source.
Run `.\Setup.cmd -CheckOnly`. Explain the missing/unsupported-tool plan and
obtain explicit approval before running
`.\Setup.cmd -Install -Accept -NonInteractive`. Omit optional host flags in
this first invocation; plugins, MCP registration and skill-copy stages then
skip rather than interrupt the guided sequence with a full-set install.
Compatible prerequisites need no reinstall.

If Windows reports a reboot requirement or an installer fails, stop; no later
stage may run. If PATH changed, arrange the required host/terminal restart
before connection work. Approved marketplace/plugin commands can be completed
first when no Windows restart is required: their script process refreshes its
own PATH without replacing the parent host's environment.

### Step 2: marketplace first, then plugin choices

For the already confirmed Copilot CLI or Claude Code host, read and follow
`skills/power-platform-doctor/SKILL.md` in this same conversation. It checks
the chosen CLI, requests approval to add/reuse the official marketplace, and
**only then asks which plugins the user wants**. Marketplace-only preparation
uses `-MarketplaceOnly -AcceptPlugins`; that approval does not authorize later
plugin installation. Reuse an existing matching marketplace without replacing
its source.

The doctor then shows the chosen plugin delta, asks for its own approval, and
runs `-Plugins "id,id" -AcceptPlugins`. Do not choose every plugin by default,
install into the other CLI, add another host, or run the broad remote installer.
If the user chooses none, leave the already approved marketplace in place and
install no plugins.

For a native VS Code/Copilot desktop route without the CLI, follow the
integration skill's supported manual route instead; do not pretend CLI flags
configure those separate hosts.

### Step 3: continue with the connection skill

When the initial request includes connection onboarding, read
`skills/power-platform-connect/SKILL.md` from this same repo and follow it;
the user need not paste a second setup prompt. If the user asked only for
installation, ask whether they want to connect before initiating this stage.
The skill file can be read directly; a personal copy is optional and still
requires its own installation approval.

Confirm the actual host, sign-in identity, Tenant ID, Environment URL, nickname
and selected tools as the connection skill requires. Reuse supplied details
without asking again, but never infer a tenant from the active profile.
Ask before additional software, profile changes, private binding records,
authentication, MCP registration/startup and bounded live identity checks.
Do not install Dataverse CLI just because its plugin was selected; check first
and ask only when the selected connection needs it and it is missing.

Read the installed `dv-overview` / `dv-connect` resources through their supported
locations when needed. If freshly installed plugin resources or callable MCP
tools are not available in the current host, use the pause/resume procedure
below. Reading an instruction file is not proof that its MCP tools are loaded.
Do not duplicate the connection skill's auth implementation or invent tokens,
OAuth flows, client IDs, server commands or host configuration locations.

### Restart and resume only at a real boundary

Do not require a separate chat merely to move from tools to marketplace to
plugin selection. However, **do not promise zero restarts**: changed PATH,
new plugin discovery, new MCP registration, a host-close requirement or a
Windows reboot can require a pause. A new chat alone may not reload MCP servers;
use the actual selected host's documented reload/restart mechanism.

Before any required pause, list completed stages, the chosen host, selected
plugin IDs and the next pending action. Do not close the app for the user.
Give a copyable, filled-in resume prompt shaped like:

> Continue guided Power Platform onboarding from the same extracted repo.
> Read `AGENTS.md` and `skills/power-platform-setup/SKILL.md`.
> My chosen host is Copilot CLI. Prerequisites and the official marketplace
> are ready; the selected plugins are dataverse and model-apps.
> I have restarted the host. Verify what is present without reinstalling
> working components, then continue with power-platform-connect.
> Confirm the target and ask before sign-in, configuration changes or live checks.

Replace the example host/plugins/stage with the actual situation. Include
no email, tenant/environment IDs or URLs, local cache paths, tokens or passwords
in a generic handoff. Do not claim that earlier approvals authorize new actions
after a resume. Once MCP is loaded, complete the connection skill's approved
post-restart identity verification rather than stopping at "definition saved."

Ask which existing host the user wants if it is not already clear:

| Chosen host | Script host value | Plugin route |
|---|---|---|
| Claude Code, including a supported local desktop Code tab | `ClaudeCode` | Existing `claude` command; install for the user. Ordinary Claude chat/Cowork is not this host. |
| Copilot CLI | `CopilotCli` | Existing `copilot` command; install for that host. |
| Copilot desktop app without a CLI command | `CopilotApp` | Official app links; guide the user through marketplace/plugin confirmations. This part is not unattended. |

Use the **chosen host**, not whichever CLI happens to be found first. If both
CLIs exist, do not configure both unless the user separately requests both.
Never install a CLI/another host as a shortcut for the desktop app.

The official quick installer's CLI dependency is **not a requirement to use
skills/plugins in an IDE or app**. If the user means **VS Code Copilot agent
mode**, do not label it Copilot CLI or pass an invented `VSCode` host flag.
The current script's plugin host values cover the three routes above; use the
integration skill's documented native VS Code marketplace path for that IDE
instead. Copilot desktop confirmation links do not install plugins in VS Code.

**A command on PATH can be an install launcher, not the full CLI.** The
`Install GitHub Copilot CLI? [y/N]` message means it is not ready for plugin
management yet. Do not silently answer `y`, start an AI session, or infer
readiness from `Get-Command` alone. Inspect supported local installation
metadata first; if readiness is uncertain, explain that before invoking the
script's CLI plugin route. A listing/verification failure must not be reported
as a successful installation.

If the user has only Copilot desktop, explain the two choices before plugin
setup: proceed with **CopilotApp** confirmation links (no additional host
needed), or pause while the user independently installs the optional CLI using
[GitHub's official instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli).
Do not install that host for them under prerequisite/plugin approval. If they
choose to install it themselves, explain its current requirements and policy,
then recheck readiness before proposing **CopilotCli**. If they decline, continue
with approved **CopilotApp** links rather than abandoning installation or
pretending the terminal route is available. If no suitable desktop app is
available either, report that prerequisite and keep the remaining setup pending.

CLI download/installation and plugin-management subcommands do not themselves
submit an AI prompt. Using the CLI's agent/model features and this guiding
chat can consume the user's AI allowance and requires the appropriate
plan/authentication and organizational policy. Do not open a CLI AI session
just to install plugins, promise unlimited/free AI usage, or purchase credits.

Collect separate approvals one decision at a time, then run only the approved
flags. The default CLI sequence above prepares the marketplace before asking
for plugin choices; do not collapse it into a full-set install.
`All` is only for an explicitly approved standard full set; Dataverse requires
an explicit `dataverse` ID in `-Plugins` or requested `-IncludeDataverse`.
For a plugin-only follow-up with ready prerequisites, omit `-Install -Accept`;
`-NonInteractive -PluginHost <host> -Plugins "id,id" -AcceptPlugins` stops if a
prerequisite has become missing instead of installing unapproved software.

Omit an optional stage's host and
acceptance flags when not requested; noninteractive setup skips it. If the
user approves stages later, run another scoped invocation **in this same chat**;
the script rechecks/skips compatible existing tools. Never invent consent just
to make a combined command possible.

Stop on an actual failure or restart requirement. An app-close requirement may
also need a handoff: do not close the app hosting the current chat without
explaining that it ends the session. If necessary, give the reviewed approved
setup command to run in a separate terminal while that app is closed, then
resume after reopening. Do not promise zero interruptions from Windows/UAC.

When installation is complete, explain pending desktop confirmations and host
discovery. Continue to Step 3 if requested and the necessary capabilities are
available; otherwise give the restart/resume handoff. Never run authentication
under installation approvals.

## Checks and separate approval gates

1. Read the repository's `AGENTS.md`, `README.md`, and `Setup.ps1`. Obtain the full
   source if it is not already available locally. Do not run unreviewed downloads.
2. Run `.\Setup.cmd -CheckOnly` in that folder. Azure CLI is included by default
   after PAC. Use `-SkipAzureCli` only for a user-approved minimal setup without
   Azure-dependent workflows. This mode is offline and read-only.
   Use the same launcher on x64 and ARM64 Windows 11; it detects native Windows
   architecture even in an emulated terminal. Explain any existing emulated
   tools and x64 Azure CLI emulation shown in the plan. Do not replace
   the script with ad hoc architecture-specific installation commands.
3. Summarize the plan and ask the user to explicitly approve installing the
   missing/unsupported tools and accepting the applicable software licenses.
4. After approval, run
   `.\Setup.cmd -Install -Accept -NonInteractive`, with the same approved
   `-SkipAzureCli` flag if applicable. This still permits Windows UAC to require
   human action.
5. Respect exit codes, stop on failure/restart requirement, and explain any
   terminal/Copilot restart needed. Report binaries, desktop plugins, and
   authentication separately.
6. For Power Platform plugins, use Step 2's doctor for marketplace preparation
   followed by CLI plugin selection.
   Obtain separate approval for `ClaudeCode`, `CopilotCli`, or `CopilotApp` and
   the actual selection, then append `-PluginHost <host> -Plugins "id,id"
   -AcceptPlugins`. Dataverse is opt-in by explicit ID or `-IncludeDataverse`.
   CLI hosts must already be on PATH; no new host is
   installed. The app route prints official confirmation links and returns
   `4`, meaning pending user action, not verified installation. Do not retry
   installations solely because the app handoff returns that code.
7. For Copilot Studio MCP, obtain independent approval for the chosen host and
   append `-CopilotStudioHost <host> -AcceptCopilotStudio`. The script saves the
   launch command but does not start the server; the package downloads/caches
   at the host's first launch. Do not run `npx` standalone or claim runtime/auth
   readiness from a saved JSON entry.
8. Use `skills/power-platform-doctor/SKILL.md` for CLI plugin choices and
   `skills/power-platform-integrations/SKILL.md` for manual/native routes or
   agent-guided MCP setup. Reuse existing registrations.
   Stop on configuration conflicts; keep any local backup private.
9. For connection onboarding requested in the starting prompt or afterward,
   continue with `skills/power-platform-connect/SKILL.md` as a separately
   approval-gated stage. Installation approval never authorizes authenticating, selecting a
   tenant, or inspecting that tenant's data.
   To make that skill available locally first, obtain approval for
   `-ConnectionSkillHost <host> -AcceptConnectionSkill` in the final setup stage.
   This copies instructions only. It is not required to read the bundled file
   and does not authorize onboarding; use the independently requested Step 3
   flow and its target/approval checks.

## The official quick-install command is an alternative, not another stage

On Windows, `curl.exe` is the native curl program; plain `curl` can resolve to
PowerShell's `Invoke-WebRequest` alias. For a reviewed PowerShell download,
`Invoke-WebRequest -UseBasicParsing` avoids HTML-parsing prompts. Neither
download command installs a plugin by itself.

The official remote `install.js` command targets existing Claude Code/Copilot
CLI installations; it is not a universal Copilot desktop installer. It can
configure both detected CLIs, install/update prerequisites, and enable plugin
auto-updates. This skill uses Setup.cmd's scoped host commands instead.
Do not append `curl.exe ... | node ...` or the downloaded installer as another
required step: that can repeat/broaden changes already approved for Setup.cmd.
If the user explicitly chooses the official broad installer as an alternative,
follow the integration skill's review/approval rules before execution.

Never install Copilot CLI/another agent host, enable auto-approval, change
persistent execution policy, blindly run the broad marketplace installer, sign
in or select a profile without the confirmed target and separate approval,
or create cloud resources. The integration skill can
use supported commands on an already available CLI or documented shared MCP
configuration; it must not install another host. Never infer plugin or auth
readiness from the presence of executables.
