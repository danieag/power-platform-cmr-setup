# Illustrated agent-guided setup walkthrough

[Back to the main README](../README.md)

This walkthrough shows what happens when you open the extracted
`power-platform-setup` folder in the **GitHub Copilot desktop app** and send
one short prompt—choosing multiple Power Platform workloads, checking only
their combined Windows prerequisites, adding Microsoft's official marketplace,
installing your chosen plugins step by step, and optionally connecting to a
Power Platform environment.

Any branch or personal identifiers in user-reported screenshots have been
redacted; public marketplace URIs (`microsoft/power-platform-skills`) are kept
as-is.

---

## 1. Open the extracted folder and paste the short prompt

Add/open the extracted folder in the GitHub Copilot desktop app (**+ > Add local
folder or repository**), then paste the short prompt from the
[README](../README.md#alternative-b-download-this-folder-and-run-one-prompt-in-your-agent)
(or ask directly in plain English, such as *"Install the prerequisites and
plugins for Model-driven apps and Code apps"*):

> Help me set up Power Platform using this folder. Ask which app I use and let me choose one or multiple workloads, check and install only the combined prerequisites they need with my approval, help me add the plugins, and then ask if I want to connect to an environment.

![GitHub Copilot desktop app with the power-platform-setup folder attached and the short prompt in the composer](images/31-agent-short-prompt.png)

---

## 2. Choose which app you use

The workspace skill (`power-platform-setup`) loads automatically and asks which
app should receive the Power Platform plugins (**GitHub Copilot desktop app**,
**GitHub Copilot CLI**, **Claude Code**, or **VS Code Copilot**). Choosing a
host only scopes the plan—it does not install anything yet.

![Agent asking which app you use for Power Platform plugins](images/32-agent-choose-app.png)

---

## 3. Select one or multiple workloads

Next, the agent presents all 11 official Power Platform workloads as a numbered
list so you can pick **several at once** in a single reply (for example `1,3`
for **Model-driven apps** + **Code apps**, `all`, or `marketplace` for
marketplace only):

![Agent presenting the 11 Power Platform workloads with 1,3 entered in the freeform box](images/33-agent-multi-workload-select.png)

---

## 4. Check only the combined Windows prerequisites

`Setup.cmd -CheckOnly -Plugins "..." -Prerequisites FromPlugins` computes the
exact union of Windows tools required by your chosen workloads (for example,
`Model-driven apps + Code apps` resolves `git, node, dotnet, pac, azure`;
whereas `Canvas apps + Code apps` resolves only `git, node, dotnet`) and runs an
offline, read-only check:

![Agent mapping 1,3 to Model-driven apps and Code apps and running the read-only prerequisite check](images/34-agent-selective-prereq-check.png)

If any required prerequisites are missing, the agent explains the exact plan
and asks for your approval before installing anything. When all required tools
are already `[READY]`, nothing is downloaded or reinstalled.

---

## 5. Approve adding the Power Platform marketplace

Before opening any plugin prompts in the GitHub Copilot desktop app, the agent
asks for separate marketplace/plugin approval:

![Agent reporting prerequisites ready and asking permission before opening the Copilot desktop app prompts](images/35-agent-approve-marketplace-links.png)

---

## 6. Confirm the marketplace inside the Copilot desktop app

Once approved, `Setup.cmd -PluginHost CopilotApp -MarketplaceOnly` triggers the
local `ghapp://plugins/marketplace/add?source=microsoft%2Fpower-platform-skills`
handler directly—opening the native **Add plugin marketplace?** dialog inside
the Copilot app without opening a web browser. Click **Allow**:

![Copilot desktop app dialog asking to allow adding the microsoft/power-platform-skills marketplace](images/36-copilot-app-allow-marketplace.png)

In **Manage marketplaces**, `microsoft/power-platform-skills` is pre-filled.
Click **Add**:

![Manage marketplaces dialog with microsoft/power-platform-skills pre-filled and the Add button highlighted](images/37-copilot-app-manage-marketplaces-add.png)

Wait a few seconds while Copilot adds the catalog (`Adding marketplace...`):

![Manage marketplaces dialog showing Adding marketplace progress](images/38-copilot-app-adding-marketplace.png)

Confirm that **`✓ Added power-platform-skills marketplace.`** (`11 plugins · microsoft`)
appears under **Marketplaces**:

![Manage marketplaces dialog showing Added power-platform-skills marketplace with 11 plugins](images/39-copilot-app-marketplace-added.png)

---

## 7. Switch back to your setup session and confirm each selected plugin

Adding a marketplace or plugin opens the **Customize** view in the GitHub
Copilot desktop app. Click back on your active setup session in the left
sidebar under **Sessions** (marked with the yellow question icon indicating the
agent is waiting for your confirmation):

![Left sidebar highlighting the active Power platform setup session to return to after Customize](images/40-copilot-app-return-to-session.png)

Select **Marketplace added** and click **Continue**:

![Agent waiting for confirmation that Added power-platform-skills marketplace appeared](images/41-agent-confirm-marketplace-added.png)

The agent now opens the install prompt for **each workload you chose at the
start**, one at a time, so dialogs never stack on top of each other. First,
`model-apps@power-platform-skills` opens—click **Allow**:

![Install plugin confirmation dialog for model-apps@power-platform-skills](images/42-copilot-app-allow-model-apps.png)

Then click **Install** in the Customize modal, return to your setup session in
the sidebar, and confirm **`model-apps installed`**:

![Install plugin modal with model-apps@power-platform-skills pre-filled and the Install button](images/43-copilot-app-install-model-apps.png)

Next, the agent opens your second chosen plugin,
`code-apps-preview@power-platform-skills`—click **Allow**:

![Install plugin confirmation dialog for code-apps-preview@power-platform-skills](images/44-copilot-app-allow-code-apps.png)

Click **Install**, return to your setup session in the sidebar, and confirm
**`code-apps-preview installed`**:

![Install plugin modal with code-apps-preview@power-platform-skills pre-filled and the Install button](images/45-copilot-app-install-code-apps.png)

---

## 8. Optional: connect to your Power Platform environment

Only **after** all selected plugins are confirmed in place does the agent ask
whether you want to connect to a Power Platform environment (sensitive
environment URLs, admin emails, organization names, device codes, and local
paths below have been redacted):

![Agent confirming both plugins are in place and asking whether to connect to an environment](images/46-agent-both-plugins-ready-connect.png)

1. **Enter your environment URL (or type `discover`):** enter an existing
   Dataverse URL (such as `https://yourorg.crm.dynamics.com`) or type `discover`
   to list environments after signing in:

   ![Prompt asking for the target environment URL or discover](images/47-connect-enter-url-or-discover.png)

2. **Provide your work/school sign-in email and approve PAC sign-in:** the agent
   confirms the exact account and target environment URL before running any
   authentication command:

   ![Prompt asking which work or school email to sign in with for the redacted environment URL](images/48-connect-ask-account.png)

   ![Confirmation card verifying the redacted account email and environment URL before PAC sign-in](images/49-connect-confirm-pac-signin.png)

3. **Complete interactive / device-code sign-in in your browser:** PAC CLI
   displays a one-time device code for `https://login.microsoft.com/device` (or
   opens your browser). Enter the code and approve sign-in with your Microsoft
   Entra account:

   ![Agent running PAC device-code sign-in and displaying the redacted one-time code](images/50-connect-pac-device-code-prompt.png)

   ![Microsoft browser prompt to enter the one-time device code](images/51-connect-enter-device-code.png)

   ![Microsoft Entra prompt confirming sign-in to Power Platform CLI - pac](images/52-connect-approve-signin.png)

   ![Browser confirmation that Power Platform CLI - pac sign-in succeeded](images/53-connect-pac-signed-in-browser.png)

4. **Review the completion summary:** the agent reports prerequisites, confirmed
   plugins, and your active PAC profile separately, and reminds you to reopen
   your terminal/app if `PATH` changed during this session:

   ![Final summary reporting prerequisites, confirmed plugins, and the redacted PAC connection profile](images/54-connect-complete-summary.png)

For multi-surface setup (Dataverse CLI, Dataverse MCP registration, and
tenant-isolated Azure CLI caches), see the companion
[Power Platform Connect guide](power-platform-connect-guide.md).
