# Claude Code workspace instructions

Read and follow [`AGENTS.md`](AGENTS.md) and [`skills/power-platform-setup/SKILL.md`](skills/power-platform-setup/SKILL.md) before running any setup or prerequisite commands in this folder.

All Windows prerequisite, marketplace, plugin, MCP registration, and skill-copy policy lives in `Setup.ps1` (invoked through `.\Setup.cmd`). Treat short prompts (*"start"*, *"set up"*, *"start setup"*, *"start set up with this repo"*, *"help me get set up"*) and plain-English maker requests (such as *"set up Copilot Managed Runtime"*, *"install the prereqs for model-driven apps"*, or *"set up Power Platform"*) as immediate triggers for the guided onboarding flow using selective `-Prerequisites FromPlugins` checks first, obtaining explicit user approval before each installation stage.
