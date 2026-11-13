---
name: power-platform-setup
description: Check and, after explicit user approval, install local Windows prerequisites and optionally set up Power Platform plugins for an existing Claude Code, Copilot CLI, or Copilot desktop host.
---

# Power Platform setup

Use the reviewed public repository
<https://github.com/danieag/power-platform-setup>.
This skill is an instruction wrapper, not another installer. A repository URL
does not automatically register this skill in the desktop app.

1. Read the repository's `AGENTS.md`, `README.md`, and `Setup.ps1`. Obtain the full
   source if it is not already available locally. Do not run unreviewed downloads.
2. Run `.\Setup.cmd -CheckOnly` in that folder. Add `-IncludeAzureCli` only if the
   requested workflow needs it. This mode is offline and read-only.
   Use the same launcher on x64 and ARM64 Windows 11; it detects native Windows
   architecture even in an emulated terminal. Explain any existing emulated
   tools and optional x64 Azure CLI emulation shown in the plan. Do not replace
   the script with ad hoc architecture-specific installation commands.
3. Summarize the plan and ask the user to explicitly approve installing the
   missing/unsupported tools and accepting the applicable software licenses.
4. After approval, run
   `.\Setup.cmd -Install -Accept -NonInteractive`, with the same approved Azure
   flag if applicable. This still permits Windows UAC to require human action.
5. Respect exit codes, stop on failure/restart requirement, and explain any
   terminal/Copilot restart needed. Report binaries, desktop plugins, and
   authentication separately.
6. If the user wants the reviewed Power Platform plugin set, obtain separate
   approval for `ClaudeCode`, `CopilotCli`, or `CopilotApp`, then append
   `-PluginHost <host> -AcceptPlugins`. Dataverse also requires
   `-IncludeDataverse`. CLI hosts must already be on PATH; no new host is
   installed. The app route prints official confirmation links and returns
   `4`, meaning pending user action, not verified installation. Do not retry
   installations solely because the app handoff returns that code.
7. For Copilot Studio MCP, obtain independent approval for the chosen host and
   append `-CopilotStudioHost <host> -AcceptCopilotStudio`. The script saves the
   launch command but does not start the server; the package downloads/caches
   at the host's first launch. Do not run `npx` standalone or claim runtime/auth
   readiness from a saved JSON entry.
8. For custom plugin selections or agent-guided MCP setup, read
   `skills/power-platform-integrations/SKILL.md`. Reuse existing registrations.
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

Never install Copilot CLI/another agent host, enable auto-approval, change
persistent execution policy, blindly run the broad marketplace installer, sign
in, choose an environment, or create cloud resources. The integration skill can
use supported commands on an already available CLI or documented shared MCP
configuration; it must not install another host. Never infer plugin or auth
readiness from the presence of executables.
