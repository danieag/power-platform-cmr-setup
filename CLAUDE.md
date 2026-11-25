# Claude Code workspace instructions

Read and follow [`AGENTS.md`](AGENTS.md) and [`skills/power-platform-setup/SKILL.md`](skills/power-platform-setup/SKILL.md) before running any setup or prerequisite commands in this folder.

All Windows prerequisite, marketplace, plugin, MCP registration, and skill-copy policy lives in `Setup.ps1` (invoked through `.\Setup.cmd`). Map plain-English maker requests (such as *"set up Copilot Managed Runtime"*, *"install the prereqs for model-driven apps"*, or *"set up Power Platform"*) to selective `-Prerequisites FromPlugins` checks first and obtain explicit user approval before each installation stage.
