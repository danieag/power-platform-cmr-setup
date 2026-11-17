---
name: power-platform-setup
description: Guide one approval-gated Windows installation session for prerequisites, Power Platform plugins, optional Copilot Studio MCP and the connection skill on an existing Claude Code or Copilot host; hand off sign-in to a fresh chat afterward.
---

# Power Platform setup

Use the reviewed public repository
<https://github.com/danieag/power-platform-setup>.
This skill is an instruction wrapper, not another installer. A repository URL
does not automatically register this skill in the desktop app.

## One guided installation, then a connection chat

Stay in the **same installation conversation** for approved prerequisites,
Power Platform plugins, optional Copilot Studio MCP registration, and the
connection-skill file. Do not finish after prerequisites by telling the user
to open another session and run a separate plugin installer. Execute supported
setup commands with the agent's terminal tools after approval.

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

Collect the separate approvals below, one decision at a time. Then run the
script with **only** the approved flags. If all installation stages for one
host were approved, this is a combined example (set `$selectedHost` to the
user-confirmed `ClaudeCode`, `CopilotCli`, or `CopilotApp` and `$selectedPlugins`
to the approved comma-separated IDs first):

```powershell
.\Setup.cmd -Install -Accept -NonInteractive `
    -PluginHost $selectedHost -Plugins $selectedPlugins -AcceptPlugins `
    -CopilotStudioHost $selectedHost -AcceptCopilotStudio `
    -ConnectionSkillHost $selectedHost -AcceptConnectionSkill
```

For CLI users, read `skills/power-platform-doctor/SKILL.md` as README **Step 2**
to ask which plugins they want and plan the selected host's marketplace/plugin
changes. Do not silently use the full catalog. `All` is only for an explicitly
approved standard full set; Dataverse requires an explicit `dataverse` ID in
`-Plugins` or the separately requested `-IncludeDataverse` flag.
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

When installation is complete, explain pending desktop link confirmations or
host discovery, then **restart the host/open a fresh chat for
`power-platform-connect`**. Do not run that authentication workflow under the
installation approvals.

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
6. For Power Platform plugins, use Step 2's doctor for CLI plugin selection.
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
9. If the user explicitly requests sign-in or persistent connections afterward,
   use `skills/power-platform-connect/SKILL.md` as a separate approval-gated
   workflow. Installation approval never authorizes authenticating, selecting a
   tenant, or inspecting that tenant's data.
   To make that skill available locally first, obtain approval for
   `-ConnectionSkillHost <host> -AcceptConnectionSkill` in the final setup stage.
   This copies instructions only; relay the final chat prompt and do not start
   onboarding under skill-installation approval. If installation is skipped or
   host discovery is pending, the user can ask the agent to read the public link.

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
in, choose an environment, or create cloud resources. The integration skill can
use supported commands on an already available CLI or documented shared MCP
configuration; it must not install another host. Never infer plugin or auth
readiness from the presence of executables.
