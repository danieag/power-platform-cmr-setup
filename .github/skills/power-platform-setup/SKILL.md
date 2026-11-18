---
name: power-platform-setup
description: "Automatically triggered whenever the user asks to set up Power Platform on Windows, install prerequisites or plugins for Model-driven apps, Canvas apps, Code apps, Power Automate flows, Power Pages, Dataverse, PCF controls, Process Intelligence, Mobile apps, MCP apps, or add the Power Platform marketplace."
---

# Power Platform setup (workspace entry)

Read and follow [`skills/power-platform-setup/SKILL.md`](../../../skills/power-platform-setup/SKILL.md), [`AGENTS.md`](../../../AGENTS.md), and [`Setup.ps1`](../../../Setup.ps1) in this repository.

- Speak in plain, non-technical language. Never require the user to know CLI flags or plugin IDs.
- If the user already named a workload (for example *"install the prereqs for model-driven apps"* -> `model-apps`), run `.\Setup.cmd -CheckOnly -Plugins "<ids>" -Prerequisites FromPlugins` immediately, explain what is ready vs missing, and obtain explicit approval before installing anything.
- Otherwise help them choose their Power Platform workload(s) or full setup first so `Setup.cmd` checks and installs **only** the required Windows prerequisites.
