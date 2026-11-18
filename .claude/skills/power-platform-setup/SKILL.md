---
name: power-platform-setup
description: "Automatically triggered whenever the user asks to set up Power Platform on Windows, install prerequisites or plugins for Model-driven apps, Canvas apps, Code apps, Power Automate flows, Power Pages, Dataverse, PCF controls, Process Intelligence, Mobile apps, MCP apps, or add the Power Platform marketplace."
---

# Power Platform setup (workspace entry)

Read and follow [`skills/power-platform-setup/SKILL.md`](../../../skills/power-platform-setup/SKILL.md), [`AGENTS.md`](../../../AGENTS.md), and [`Setup.ps1`](../../../Setup.ps1) in this repository.

- Speak in plain, non-technical language. Never require the user to know CLI flags or plugin IDs.
- **Allow selecting multiple workloads at once:** never list individual plugins as single-select `ask_user` `choices` (which forces picking only one!). Use `multiSelect: true` only where supported; in single-select `ask_user` hosts (like GitHub Copilot), show the numbered 1–11 workload list and use freeform input (no `choices`) or multi-plugin bundle presets so the user can pick several (e.g. `1, 2, 6` or `Model-driven apps, Power Automate`), then pass `-Plugins "id1,id2,..." -Prerequisites FromPlugins` so `Setup.cmd` resolves the union of their prerequisites.
- **For `CopilotApp` (GitHub Copilot desktop app), wait for confirmation at each in-app step before moving to environment connection:** first run `-PluginHost CopilotApp -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins` and wait (`ask_user`) for the user to confirm `✓ Added power-platform-skills marketplace`; then trigger each selected plugin one at a time with `-PluginHost CopilotApp -Plugins "<single-id>" -SkipMarketplace -Prerequisites FromPlugins -AcceptPlugins` and wait (`ask_user`) for plugin installation confirmation **before** asking about environment connection!
- **For environment connection, always follow `skills/power-platform-connect/SKILL.md` (never bare `pac auth create`):** ask if they want to run connection setup; check which prerequisites (`pac`, `az`, `node`) and whether the `dataverse` plugin are installed; connect relevant PAC and Azure CLI (`AZURE_CONFIG_DIR`) profiles; if `dataverse` plugin is absent, let them skip Dataverse CLI/MCP or install the `dataverse` plugin first; and save the approved token-free `connections\<alias>.json` record for persistent reuse.
- If the user already named one or more workloads (for example *"install the prereqs for model-driven apps and power automate"* -> `model-apps,power-automate`), run `.\Setup.cmd -CheckOnly -Plugins "<ids>" -Prerequisites FromPlugins` immediately, explain what is ready vs missing, and obtain explicit approval before installing anything.
- Otherwise help them choose their Power Platform workload(s) or full setup first so `Setup.cmd` checks and installs **only** the required Windows prerequisites.
