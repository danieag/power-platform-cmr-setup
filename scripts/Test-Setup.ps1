#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = 0
$passed = 0

function Assert-Equal {
    param($Actual, $Expected)
    if ($Actual -cne $Expected) { throw "Expected '$Expected', got '$Actual'." }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return
    }
    throw "Expected an exception matching '$Pattern'."
}

function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    $casePath = $env:PATH
    try {
        # Isolate all function mocks in a child scope. No installed tools are executed.
        & {
            . (Join-Path $root 'Setup.ps1')
            & $Action 6>$null
        }
        $script:passed++
        Write-Host "PASS $Name"
    } catch {
        $script:failures++
        Write-Host "FAIL $Name - $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        $env:PATH = $casePath
    }
}

function New-TestState {
    param([string[]]$Ready = @(), [switch]$Azure)
    $ids = @('git', 'node', 'dotnet', 'pac')
    if ($Azure) { $ids += 'azure' }
    foreach ($id in $ids) {
        [pscustomobject]@{
            Id = $id; Name = $id; Ready = $id -in $Ready
            Version = [version]'24.1.0'; Path = "C:\test\$id.exe"; Requirement = 'test'; Architecture = 'x64'
        }
    }
}

function New-TestAgentHosts {
    param([string[]]$Detected = @('ClaudeCode', 'CopilotCli', 'CopilotApp'))
    foreach ($id in @('ClaudeCode', 'CopilotCli', 'CopilotApp')) {
        [pscustomobject]@{ Id = $id; Name = $id; Detected = $id -in $Detected; Path = $null }
    }
}

function Reset-TestPluginCli {
    $script:pluginHost = 'CopilotCli'
    $script:pluginRows = @()
    $script:marketplaceRows = @()
    $script:pluginCalls = @()
    $script:failPlugin = ''
    $script:omitPluginRecord = $false
}

function Invoke-TestPluginCli {
    param($Path, $Arguments)
    $script:pluginCalls += [pscustomobject]@{ Path = $Path; Arguments = $Arguments }
    if (($Arguments -join ' ') -eq 'plugin marketplace list --json') {
        return ConvertTo-Json -InputObject @($script:marketplaceRows) -Depth 10 -Compress
    }
    if (($Arguments -join ' ') -eq 'plugin list --json') {
        return ConvertTo-Json -InputObject @($script:pluginRows) -Depth 10 -Compress
    }
    if ($Arguments[1] -eq 'marketplace' -and $Arguments[2] -eq 'add') {
        $script:marketplaceRows = @([pscustomobject]@{
            name = 'power-platform-skills'; source = 'github'; repo = 'microsoft/power-platform-skills'
        })
        return
    }
    if ($Arguments[1] -eq 'install') {
        if ($Arguments[2] -eq $script:failPlugin) { throw 'Mock plugin installation failed.' }
        if ($script:omitPluginRecord) { return }
        if ($script:pluginHost -eq 'ClaudeCode') {
            $script:pluginRows += [pscustomobject]@{ id = $Arguments[2]; scope = 'user'; enabled = $true }
        } else {
            $script:pluginRows += [pscustomobject]@{ name = ($Arguments[2] -split '@')[0]; marketplace = 'power-platform-skills'; enabled = $true }
        }
        return
    }
    throw "Unexpected mock CLI operation: $($Arguments -join ' ')"
}

Test-Case 'all PowerShell files parse' {
    foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse) {
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count) { throw ($errors.Message -join '; ') }
    }
}

Test-Case 'version parsing handles vendor suffixes and rejects garbage' {
    Assert-Equal (ConvertTo-ToolVersion 'git version 2.56.0.windows.4') ([version]'2.56.0')
    Assert-Equal (ConvertTo-ToolVersion '2.11.2+g47bc199') ([version]'2.11.2')
    Assert-Equal (ConvertTo-ToolVersion 'unknown') $null
}

Test-Case 'architecture gate rejects unsupported operating systems' {
    $old = $env:OS
    try {
        $env:OS = 'not-windows'
        Assert-Throws { Get-SetupArchitecture } 'Windows only'
    } finally { $env:OS = $old }
}

Test-Case 'architecture detection uses native Windows metadata even in an emulated process' {
    $script:nativeArchitecture = 'ARM64'
    $script:windowsBuild = 26100
    function Get-ItemPropertyValue {
        param($LiteralPath, $Name)
        if ($Name -eq 'PROCESSOR_ARCHITECTURE') { return $script:nativeArchitecture }
        return $script:windowsBuild
    }
    $old = $env:PROCESSOR_ARCHITECTURE
    try {
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        Assert-Equal (Get-SetupArchitecture) 'arm64'
        $script:nativeArchitecture = 'AMD64'
        Assert-Equal (Get-SetupArchitecture) 'x64'
        $script:windowsBuild = 19045
        Assert-Equal (Get-SetupArchitecture) 'x64'
        $script:nativeArchitecture = 'ARM64'
        Assert-Throws { Get-SetupArchitecture } 'Windows 11 on ARM64'
        $script:nativeArchitecture = 'x86'
        Assert-Throws { Get-SetupArchitecture } '32-bit Windows'
        $script:nativeArchitecture = 'AMD64'
        $script:windowsBuild = 18363
        Assert-Throws { Get-SetupArchitecture } '19045'
    } finally { $env:PROCESSOR_ARCHITECTURE = $old }
}

Test-Case 'binary architecture reads PE headers without executing code and rejects malformed files' {
    $path = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N') + '.bin')
    try {
        foreach ($case in @(
            @{ Machine = 0x8664; Architecture = 'x64' },
            @{ Machine = 0xAA64; Architecture = 'arm64' },
            @{ Machine = 0xA641; Architecture = 'arm64' },
            @{ Machine = 0x014C; Architecture = 'x86' },
            @{ Machine = 0xFFFF; Architecture = 'unknown' })) {
            $bytes = New-Object byte[] 128
            [BitConverter]::GetBytes([uint16]0x5A4D).CopyTo($bytes, 0)
            [BitConverter]::GetBytes([int]64).CopyTo($bytes, 0x3C)
            [BitConverter]::GetBytes([uint32]0x00004550).CopyTo($bytes, 64)
            [BitConverter]::GetBytes([uint16]$case.Machine).CopyTo($bytes, 68)
            [IO.File]::WriteAllBytes($path, $bytes)
            Assert-Equal (Get-ExecutableArchitecture $path) $case.Architecture
        }
        [IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))
        Assert-Equal (Get-ExecutableArchitecture $path) 'unknown'
        [BitConverter]::GetBytes([int]9999).CopyTo($bytes, 0x3C)
        [IO.File]::WriteAllBytes($path, $bytes)
        Assert-Equal (Get-ExecutableArchitecture $path) 'unknown'
    } finally {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}

Test-Case 'binary compatibility preserves emulated tools only on compatible Windows architectures' {
    Assert-Equal (Test-ExecutableArchitecture 'arm64' 'arm64') $true
    Assert-Equal (Test-ExecutableArchitecture 'x64' 'arm64') $true
    Assert-Equal (Test-ExecutableArchitecture 'x86' 'arm64') $true
    Assert-Equal (Test-ExecutableArchitecture 'arm64' 'x64') $false
    Assert-Equal (Test-ExecutableArchitecture 'unknown' 'arm64') $false
    Assert-Equal (Test-ExecutableArchitecture $null 'x64') $false
}

Test-Case 'check-only cannot reach mutating, network or prompt operations' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState {
        param([switch]$Azure)
        Assert-Equal $Azure.IsPresent $true
        New-TestState -Azure:$Azure
    }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Update-SetupPath { throw 'PATH CHANGE FORBIDDEN' }
    function Invoke-WebRequest { throw 'DOWNLOAD FORBIDDEN' }
    function Invoke-RestMethod { throw 'NETWORK FORBIDDEN' }
    function Start-Process { throw 'PROCESS FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function New-Item { throw 'WRITE FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    $pathBefore = $env:PATH
    Assert-Equal (Invoke-Setup -CheckOnly) 1
    Assert-Equal $env:PATH $pathBefore
}

Test-Case 'real local inventory never invokes a CLI or a network/write operation' {
    function Invoke-WebRequest { throw 'DOWNLOAD FORBIDDEN' }
    function Invoke-RestMethod { throw 'NETWORK FORBIDDEN' }
    function Start-Process { throw 'PROCESS FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function New-Item { throw 'WRITE FORBIDDEN' }
    $state = @(Get-SetupState -Azure)
    Assert-Equal ($state.Id -join ',') 'git,node,dotnet,pac,azure'
}

Test-Case 'inventory recognizes compatible binaries, bundled npm and the SDK rather than runtime' {
    function Find-SetupExecutable { param($Name, $Candidates) "C:\fixture\$Name" }
    function Get-ExecutableArchitecture { 'x64' }
    function Get-BinaryVersion {
        param($Path)
        if ($Path -like '*git.exe') { return [version]'2.56.0' }
        if ($Path -like '*node.exe') { return [version]'22.18.0' }
        if ($Path -like '*pac.exe') { return [version]'2.11.2' }
    }
    function Test-Path { $true }
    function Get-Content { '{"version":"10.9.0"}' }
    function Get-ChildItem {
        [pscustomobject]@{ Name = '10.0.100'; FullName = 'C:\fixture\sdk\10.0.100' }
        [pscustomobject]@{ Name = '11.0.100'; FullName = 'C:\fixture\sdk\11.0.100' }
        [pscustomobject]@{ Name = '10.0.200-preview'; FullName = 'C:\fixture\sdk\10.0.200-preview' }
    }
    $state = @(Get-SetupState)
    Assert-Equal (@($state | Where-Object { -not $_.Ready }).Count) 0
    Assert-Equal ($state | Where-Object Id -eq 'dotnet').Version ([version]'10.0.100')
}

Test-Case 'inventory rejects unsupported Node majors, absent npm, and runtime-only dotnet' {
    function Find-SetupExecutable { param($Name, $Candidates) "C:\fixture\$Name" }
    function Get-ExecutableArchitecture { 'x64' }
    function Get-BinaryVersion { [version]'25.0.0' }
    function Test-Path { $false }
    $state = @(Get-SetupState)
    Assert-Equal ($state | Where-Object Id -eq 'node').Ready $false
    Assert-Equal ($state | Where-Object Id -eq 'dotnet').Ready $false
}

Test-Case 'PAC must be strictly newer than 2.10.0 and older versions never upgrade without approval' {
    function Get-SetupArchitecture { $script:pacWindowsArchitecture }
    function Find-SetupExecutable { param($Name, $Candidates) "C:\fixture\$Name" }
    function Get-ExecutableArchitecture {
        param($Path)
        if ($Path -like '*python.exe') { return 'x64' }
        return $script:pacWindowsArchitecture
    }
    function Get-BinaryVersion {
        param($Path)
        if ($Path -like '*git.exe') { return [version]'2.56.0' }
        if ($Path -like '*node.exe') { return [version]'24.10.0' }
        if ($Path -like '*pac.exe') { return $script:pacUnderTest }
    }
    function Test-Path { $true }
    function Get-Content { '{"version":"11.0.0"}' }
    function Get-ChildItem { [pscustomobject]@{ Name = '10.0.404'; FullName = 'C:\fixture\sdk\10.0.404' } }
    function Get-ItemProperty { [pscustomobject]@{ DisplayName = 'Microsoft Azure CLI (64-bit)'; DisplayVersion = '2.93.0' } }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Update-SetupPath { throw 'PATH CHANGE FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Invoke-WebRequest { throw 'DOWNLOAD FORBIDDEN' }
    function Invoke-RestMethod { throw 'NETWORK FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    foreach ($architecture in @('x64', 'arm64')) {
        $script:pacWindowsArchitecture = $architecture
        foreach ($case in @(
            @{ Version = $null; Ready = $false },
            @{ Version = '1.0.0'; Ready = $false },
            @{ Version = '2.9.9'; Ready = $false },
            @{ Version = '2.10.0'; Ready = $false },
            @{ Version = '2.10.1'; Ready = $true },
            @{ Version = '2.11.2'; Ready = $true })) {
            $script:pacUnderTest = if ($null -eq $case.Version) { $null } else { [version]$case.Version }
            Assert-Equal (Get-SetupState -Architecture $architecture | Where-Object Id -eq 'pac').Ready $case.Ready
            $expectedCheck = if ($case.Ready) { 0 } else { 1 }
            $expectedRun = if ($case.Ready) { 0 } else { 2 }
            Assert-Equal (Invoke-Setup -CheckOnly) $expectedCheck
            Assert-Equal (Invoke-Setup -NonInteractive) $expectedRun
        }
    }
}

Test-Case 'Node compatibility enforces approved majors and bundled npm' {
    function Find-SetupExecutable { param($Name, $Candidates) "C:\fixture\$Name" }
    function Get-ExecutableArchitecture { 'x64' }
    function Get-BinaryVersion { $script:nodeUnderTest }
    function Test-Path { $true }
    function Get-Content { '{"version":"' + $script:npmUnderTest + '"}' }
    function Get-ChildItem {}
    foreach ($case in @(
        @{ Version = '22.17.0'; Npm = '10.9.0'; Ready = $false },
        @{ Version = '22.18.0'; Npm = '10.9.0'; Ready = $true },
        @{ Version = '24.0.0'; Npm = '11.0.0'; Ready = $true },
        @{ Version = '25.0.0'; Npm = '11.0.0'; Ready = $false },
        @{ Version = '26.0.0'; Npm = '11.0.0'; Ready = $true },
        @{ Version = '26.1.0'; Npm = '11.0.0'; Ready = $true },
        @{ Version = '26.13.0'; Npm = '11.20.0'; Ready = $true },
        @{ Version = '26.1.0'; Npm = '9.9.4'; Ready = $false },
        @{ Version = '99.0.0'; Npm = '11.0.0'; Ready = $false })) {
        $script:nodeUnderTest = [version]$case.Version
        $script:npmUnderTest = $case.Npm
        $node = Get-SetupState | Where-Object Id -eq 'node'
        Assert-Equal $node.Ready $case.Ready
    }
}

Test-Case 'Node 26 is skipped on x64 and ARM64 in offline checks and approved setup' {
    function Get-SetupArchitecture { $script:windowsUnderTest }
    function Find-SetupExecutable { param($Name, $Candidates) "C:\fixture\$Name" }
    function Get-ExecutableArchitecture {
        param($Path)
        if ($Path -like '*python.exe') { return 'x64' }
        return $script:windowsUnderTest
    }
    function Get-BinaryVersion {
        param($Path)
        if ($Path -like '*git.exe') { return [version]'2.56.0' }
        if ($Path -like '*node.exe') { return [version]'26.13.0' }
        if ($Path -like '*pac.exe') { return [version]'2.15.1' }
    }
    function Test-Path { $true }
    function Get-Content { '{"version":"11.20.0"}' }
    function Get-ChildItem { [pscustomobject]@{ Name = '10.0.404'; FullName = 'C:\fixture\sdk\10.0.404' } }
    function Get-ItemProperty { [pscustomobject]@{ DisplayName = 'Microsoft Azure CLI (64-bit)'; DisplayVersion = '2.93.0' } }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Update-SetupPath { throw 'PATH CHANGE FORBIDDEN' }
    function Invoke-WebRequest { throw 'DOWNLOAD FORBIDDEN' }
    function Invoke-RestMethod { throw 'NETWORK FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    foreach ($architecture in @('x64', 'arm64')) {
        $script:windowsUnderTest = $architecture
        Assert-Equal (Invoke-Setup -CheckOnly) 0
        Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 0
    }
}

Test-Case 'ARM64 inventory preserves compatible x64 tools but requires PAC to match its SDK host' {
    function Find-SetupExecutable { param($Name, $Candidates) "C:\fixture\$Name" }
    $script:pacArchitecture = 'x64'
    function Get-ExecutableArchitecture {
        param($Path)
        if ($Path -like '*pac.exe') { return $script:pacArchitecture }
        return 'x64'
    }
    function Get-BinaryVersion {
        param($Path)
        if ($Path -like '*git.exe') { return [version]'2.56.0' }
        if ($Path -like '*node.exe') { return [version]'24.10.0' }
        return [version]'2.11.2'
    }
    function Test-Path { $true }
    function Get-Content { '{"version":"11.0.0"}' }
    function Get-ChildItem { [pscustomobject]@{ Name = '10.0.100'; FullName = 'C:\fixture\sdk\10.0.100' } }
    $state = @(Get-SetupState -Architecture arm64)
    Assert-Equal (@($state | Where-Object { -not $_.Ready }).Count) 0
    Assert-Equal ($state | Where-Object Id -eq 'pac').Architecture 'x64'
    $script:pacArchitecture = 'arm64'
    Assert-Equal (Get-SetupState -Architecture arm64 | Where-Object Id -eq 'pac').Ready $false
}

Test-Case 'Azure inventory reads the bundled Python architecture without launching it' {
    function Find-SetupExecutable { param($Name, $Candidates) "C:\fixture\wbin\$Name" }
    function Get-ExecutableArchitecture { 'x64' }
    function Get-BinaryVersion { [version]'24.10.0' }
    function Test-Path { $true }
    function Get-Content { '{"version":"11.0.0"}' }
    function Get-ChildItem {}
    function Get-ItemProperty { [pscustomobject]@{ DisplayName = 'Microsoft Azure CLI (64-bit)'; DisplayVersion = '2.91.0' } }
    $azure = Get-SetupState -Azure -Architecture arm64 | Where-Object Id -eq 'azure'
    Assert-Equal $azure.Architecture 'x64'
    Assert-Equal $azure.Ready $true
}

Test-Case 'noninteractive mode requires both install and accept' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { New-TestState }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    Assert-Equal (Invoke-Setup -NonInteractive) 2
    Assert-Equal (Invoke-Setup -Install -NonInteractive) 2
    Assert-Equal (Invoke-Setup -Accept -NonInteractive) 2
    Assert-Equal (Invoke-Setup -CheckOnly -Install -Accept) 2
}

Test-Case 'interactive initial launch requires exact explicit approval' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { New-TestState }
    function Read-Host { 'yes' }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    Assert-Equal (Invoke-Setup) 2
}

Test-Case 'default approved installation includes Azure after PAC and verifies each tool' {
    $script:installed = @()
    $script:verified = @()
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { param([switch]$Azure) New-TestState -Ready $script:installed -Azure:$Azure }
    function Update-SetupPath {}
    function Install-SetupTool { param($Id) $script:installed += $Id; return $false }
    function Confirm-InstalledTool { param($Id, $State) $script:verified += $Id }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 0
    Assert-Equal ($script:installed -join ',') 'git,node,dotnet,pac,azure'
    Assert-Equal ($script:verified -join ',') 'git,node,dotnet,pac,azure'
}

Test-Case 'ARM64 default installation includes Azure after PAC and forwards architecture' {
    $script:installed = @()
    $script:observedArchitecture = @()
    function Get-SetupArchitecture { 'arm64' }
    function Get-SetupState {
        param([switch]$Azure, $Architecture)
        $script:observedArchitecture += $Architecture
        New-TestState -Ready $script:installed -Azure:$Azure
    }
    function Update-SetupPath {}
    function Install-SetupTool { param($Id) $script:installed += $Id; $false }
    function Confirm-InstalledTool {}
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 0
    Assert-Equal ($script:installed -join ',') 'git,node,dotnet,pac,azure'
    Assert-Equal (@($script:observedArchitecture | Where-Object { $_ -ne 'arm64' }).Count) 0
}

Test-Case 'safe rerun preserves compatible Azure and the other default tools' {
    $script:installed = @('git', 'node', 'dotnet', 'pac', 'azure')
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { param([switch]$Azure) New-TestState -Ready $script:installed -Azure:$Azure }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Update-SetupPath { throw 'PATH CHANGE FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    Assert-Equal (Invoke-Setup -CheckOnly) 0
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 0
}

Test-Case 'partial rerun installs only missing tools' {
    $script:installed = @('git', 'dotnet')
    $script:added = @()
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { param([switch]$Azure) New-TestState -Ready $script:installed -Azure:$Azure }
    function Update-SetupPath {}
    function Install-SetupTool { param($Id) $script:installed += $Id; $script:added += $Id; $false }
    function Confirm-InstalledTool {}
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 0
    Assert-Equal ($script:added -join ',') 'node,pac,azure'
}

Test-Case 'an existing core setup plans missing Azure by default but still requires installation approval' {
    $script:installed = @('git','node','dotnet','pac')
    $script:added = @()
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { param([switch]$Azure) New-TestState -Ready $script:installed -Azure:$Azure }
    function Update-SetupPath {}
    function Install-SetupTool { param($Id) $script:installed += $Id; $script:added += $Id; $false }
    function Confirm-InstalledTool {}
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    Assert-Equal (Invoke-Setup -CheckOnly) 1
    Assert-Equal (Invoke-Setup -NonInteractive) 2
    Assert-Equal $script:added.Count 0
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 0
    Assert-Equal ($script:added -join ',') 'azure'
}

Test-Case 'explicit minimal opt-out skips Azure for both check-only and approved installation' {
    $script:installed = @()
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState {
        param([switch]$Azure)
        Assert-Equal $Azure.IsPresent $false
        New-TestState -Ready $script:installed -Azure:$Azure
    }
    function Update-SetupPath {}
    function Install-SetupTool { param($Id) $script:installed += $Id; $false }
    function Confirm-InstalledTool {}
    Assert-Equal (Invoke-Setup -CheckOnly -SkipAzureCli) 1
    Assert-Equal $script:installed.Count 0
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive -SkipAzureCli) 0
    Assert-Equal ($script:installed -join ',') 'git,node,dotnet,pac'
}

Test-Case 'legacy Azure opt-in still works and contradictory Azure switches fail before changes' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState {
        param([switch]$Azure)
        Assert-Equal $Azure.IsPresent $true
        New-TestState -Ready @('git','node','dotnet','pac','azure') -Azure:$Azure
    }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    Assert-Equal (Invoke-Setup -CheckOnly -IncludeAzureCli) 0
    function Get-SetupArchitecture { throw 'SHOULD VALIDATE FIRST' }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive -IncludeAzureCli -SkipAzureCli) 2
}

Test-Case 'PAC failure or restart prevents the default Azure download and all later integrations' {
    $script:attempted = @()
    function Get-SetupArchitecture { 'arm64' }
    function Get-SetupState {
        param([switch]$Azure)
        New-TestState -Ready @('git','node','dotnet') -Azure:$Azure
    }
    function Update-SetupPath {}
    function Invoke-SetupIntegrations { throw 'INTEGRATIONS FORBIDDEN' }
    function Install-SetupTool {
        param($Id)
        $script:attempted += $Id
        if ($Id -ne 'pac') { throw 'AZURE MUST NOT START' }
        throw 'PAC failure'
    }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 3
    Assert-Equal ($script:attempted -join ',') 'pac'
    $script:attempted = @()
    function Install-SetupTool { param($Id) $script:attempted += $Id; $true }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 3010
    Assert-Equal ($script:attempted -join ',') 'pac'
}

Test-Case 'first failure prevents later installations' {
    $script:attempted = @()
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { New-TestState }
    function Update-SetupPath {}
    function Install-SetupTool { param($Id) $script:attempted += $Id; throw 'simulated failure' }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 3
    Assert-Equal ($script:attempted -join ',') 'git'
}

Test-Case 'restart requirement stops the chain without reboot' {
    $script:attempted = @()
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { New-TestState }
    function Update-SetupPath {}
    function Install-SetupTool { param($Id) $script:attempted += $Id; $true }
    function Confirm-InstalledTool { throw 'VERIFY BEFORE RESTART FORBIDDEN' }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive) 3010
    Assert-Equal ($script:attempted -join ',') 'git'
}

Test-Case 'PATH refresh preserves inherited entries and does not persist changes' {
    $old = $env:PATH
    try {
        $env:PATH = 'C:\unique-inherited;C:\second'
        Update-SetupPath
        Assert-Equal ($env:PATH.StartsWith('C:\unique-inherited;C:\second;')) $true
        Assert-Equal (($env:PATH -split ';') -contains "$env:USERPROFILE\.dotnet\tools") $true
    } finally { $env:PATH = $old }
}

Test-Case 'URL allowlist rejects untrusted, HTTP and credential-bearing sources' {
    Assert-OfficialUrl 'https://nodejs.org/dist/index.json'
    Assert-Throws { Assert-OfficialUrl 'https://example.com/installer.exe' } 'Refusing'
    Assert-Throws { Assert-OfficialUrl 'http://nodejs.org/installer.exe' } 'Refusing'
    Assert-Throws { Assert-OfficialUrl 'https://user:pass@nodejs.org/installer.exe' } 'Refusing'
    Assert-Throws { Assert-OfficialUrl 'https://nodejs.org:8443/installer.exe' } 'Refusing'
}

Test-Case 'Git metadata without checksum fails closed' {
    function Get-OfficialJson {
        [pscustomobject]@{ assets = @([pscustomobject]@{
            name = 'Git-2.56.0-64-bit.exe'; digest = ''; browser_download_url = 'https://github.com/test'
        }) }
    }
    Assert-Throws { Get-InstallerSpec 'git' -Architecture x64 } 'SHA256'
}

Test-Case 'Git metadata selects only the x64 installer and its SHA256' {
    function Get-OfficialJson {
        [pscustomobject]@{ assets = @(
            [pscustomobject]@{ name = 'Git-2.56.0.4-arm64.exe'; digest = 'ignored'; browser_download_url = 'ignored' },
            [pscustomobject]@{
                name = 'Git-2.56.0.4-64-bit.exe'; digest = ('sha256:' + ('a' * 64))
                browser_download_url = 'https://github.com/git-for-windows/git/releases/download/test/git.exe'
            }) }
    }
    $spec = Get-InstallerSpec 'git' -Architecture x64
    Assert-Equal $spec.Hash ('a' * 64)
    Assert-Equal $spec.Admin $false
}

Test-Case 'Node metadata selects stable 24 LTS and checksums for its exact MSI' {
    function Get-OfficialJson {
        @(
            [pscustomobject]@{ version = 'v26.1.0'; lts = 'Lithium' },
            [pscustomobject]@{ version = 'v24.10.0'; lts = 'Krypton' },
            [pscustomobject]@{ version = 'v22.18.0'; lts = 'Jod' })
    }
    function Invoke-WebRequest {
        [pscustomobject]@{ Content = (('b' * 64) + '  node-v24.10.0-x64.msi') }
    }
    $spec = Get-InstallerSpec 'node' -Architecture x64
    Assert-Equal $spec.Url 'https://nodejs.org/dist/v24.10.0/node-v24.10.0-x64.msi'
    Assert-Equal $spec.Hash ('b' * 64)
    function Invoke-WebRequest { [pscustomobject]@{ Content = 'no checksum' } }
    Assert-Throws { Get-InstallerSpec 'node' -Architecture x64 } 'No SHA256'
}

Test-Case '.NET metadata selects the latest SDK installer rather than a runtime' {
    function Get-OfficialJson {
        [pscustomobject]@{
            'latest-sdk' = '10.0.100'
            releases = @([pscustomobject]@{
                sdk = [pscustomobject]@{
                    version = '10.0.100'
                    files = @(
                        [pscustomobject]@{ rid = 'win-x64'; name = 'dotnet-sdk-win-x64.exe'; hash = ('c' * 128); url = 'https://builds.dotnet.microsoft.com/sdk.exe' },
                        [pscustomobject]@{ rid = 'win-arm64'; name = 'dotnet-sdk-win-arm64.exe'; hash = ('d' * 128); url = 'https://builds.dotnet.microsoft.com/arm.exe' })
                }
            })
        }
    }
    $spec = Get-InstallerSpec 'dotnet' -Architecture x64
    Assert-Equal $spec.Url 'https://builds.dotnet.microsoft.com/sdk.exe'
    Assert-Equal $spec.Hash ('c' * 128)
    Assert-Equal $spec.Algorithm 'SHA512'
    $arm = Get-InstallerSpec 'dotnet' -Architecture arm64
    Assert-Equal $arm.Url 'https://builds.dotnet.microsoft.com/arm.exe'
    Assert-Equal $arm.Hash ('d' * 128)
}

Test-Case 'ARM64 selects native Git and Node MSI assets with exact official checksums' {
    function Get-OfficialJson {
        param($Url)
        if ($Url -like '*git/releases/latest') {
            return [pscustomobject]@{ assets = @(
                [pscustomobject]@{ name = 'Git-2.56.0.4-64-bit.exe'; digest = ('sha256:' + ('a' * 64)); browser_download_url = 'x64' },
                [pscustomobject]@{ name = 'Git-2.56.0.4-arm64.exe'; digest = ('sha256:' + ('b' * 64)); browser_download_url = 'arm64' }) }
        }
        return @([pscustomobject]@{ version = 'v24.10.0'; lts = 'Krypton' })
    }
    function Invoke-WebRequest {
        [pscustomobject]@{ Content = (('c' * 64) + '  node-v24.10.0-arm64.msi') }
    }
    $git = Get-InstallerSpec 'git' -Architecture arm64
    Assert-Equal $git.Url 'arm64'
    Assert-Equal $git.Hash ('b' * 64)
    $node = Get-InstallerSpec 'node' -Architecture arm64
    Assert-Equal $node.Url 'https://nodejs.org/dist/v24.10.0/node-v24.10.0-arm64.msi'
    Assert-Equal $node.Hash ('c' * 64)
    function Invoke-WebRequest {
        [pscustomobject]@{ Content = (('c' * 64) + '  node-v24.10.0-x64.msi') }
    }
    Assert-Throws { Get-InstallerSpec 'node' -Architecture arm64 } 'Node arm64 MSI'
}

Test-Case 'ARM64 never silently substitutes x64 Git or SDK when native assets are absent' {
    function Get-OfficialJson {
        param($Url)
        if ($Url -like '*git/releases/latest') {
            return [pscustomobject]@{ assets = @(
                [pscustomobject]@{ name = 'Git-2.56.0.4-64-bit.exe'; digest = ('sha256:' + ('a' * 64)); browser_download_url = 'x64' }) }
        }
        return [pscustomobject]@{
            'latest-sdk' = '10.0.100'
            releases = @([pscustomobject]@{ sdk = [pscustomobject]@{
                version = '10.0.100'
                files = @([pscustomobject]@{ rid = 'win-x64'; name = 'sdk.exe'; hash = ('a' * 128); url = 'x64' })
            } })
        }
    }
    Assert-Throws { Get-InstallerSpec 'git' -Architecture arm64 } 'arm64 installer'
    Assert-Throws { Get-InstallerSpec 'dotnet' -Architecture arm64 } 'arm64 SDK'
    $azure = Get-InstallerSpec 'azure' -Architecture arm64
    Assert-Equal $azure.Url 'https://aka.ms/installazurecliwindowsx64'
}

Test-Case 'PAC installation uses the selected SDK and requests its architecture only on install' {
    $script:registered = $false
    $script:toolCalls = @()
    function Get-SetupState {
        [pscustomobject]@{ Id = 'dotnet'; Path = 'C:\fixture\dotnet.exe'; Ready = $true; Architecture = 'arm64' }
    }
    function Invoke-SetupNative {
        param($Path, $Arguments)
        $script:toolCalls += [pscustomobject]@{ Path = $Path; Arguments = $Arguments }
        if ($Arguments[1] -eq 'list' -and $script:registered) { return 'microsoft.powerapps.cli.tool 2.11.2 pac' }
    }
    Install-PacTool
    Assert-Equal $script:toolCalls[1].Path 'C:\fixture\dotnet.exe'
    Assert-Equal ((($script:toolCalls[1].Arguments) -join ' ') -match '--arch arm64') $true
    Assert-Equal (Test-Path -LiteralPath $script:toolCalls[1].Arguments[5]) $false
    $script:registered = $true
    Install-PacTool
    Assert-Equal $script:toolCalls[3].Arguments[1] 'update'
    Assert-Equal ($script:toolCalls[3].Arguments -contains '--arch') $false
}

Test-Case 'checksum and signature verification fail closed' {
    function Get-FileHash { [pscustomobject]@{ Hash = 'wrong' } }
    Assert-Throws { Assert-InstallerIntegrity 'unused' @{ Hash = 'expected'; Algorithm = 'SHA256'; File = 'test' } } 'Checksum mismatch'
    function Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'NotSigned' } }
    Assert-Throws { Assert-InstallerIntegrity 'unused' @{ Hash = $null; File = 'test' } } 'signature'
    function Get-AuthenticodeSignature {
        [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'Wrong signer' } }
    }
    Assert-Throws { Assert-InstallerIntegrity 'unused' @{ Hash = $null; File = 'test'; Publisher = 'Microsoft Corporation' } } 'Unexpected signer'
}

Test-Case 'successful installer exit still requires actual usable version' {
    Assert-Throws { Confirm-InstalledTool 'git' @(New-TestState) } 'not discoverable'
    function Invoke-SetupNative { 'git version 1.0.0' }
    Assert-Throws { Confirm-InstalledTool 'git' @(New-TestState -Ready 'git') } 'version verification failed'
}

Test-Case 'installer process checks exit status, propagates restart, and never invokes reboot' {
    $script:processCode = 0
    $script:lastProcess = $null
    function Invoke-InstallerProcess {
        param($Parameters, $Label)
        Assert-Equal $Parameters.Wait $true
        Assert-Equal $Parameters.PassThru $true
        $script:lastProcess = @{ File = $Parameters.FilePath; Arguments = $Parameters.ArgumentList }
        return $script:processCode
    }
    $spec = @{ Arguments = '/qn /norestart'; Admin = $true }
    Assert-Equal (Invoke-VerifiedInstaller 'C:\fixture with spaces\node.msi' $spec) $false
    Assert-Equal $script:lastProcess.File "$env:SystemRoot\System32\msiexec.exe"
    Assert-Equal $script:lastProcess.Arguments '/i "C:\fixture with spaces\node.msi" /qn /norestart'
    $script:processCode = 3010
    Assert-Equal (Invoke-VerifiedInstaller 'C:\fixture\sdk.exe' $spec) $true
    $script:processCode = 1641
    Assert-Equal (Invoke-VerifiedInstaller 'C:\fixture\sdk.exe' $spec) $true
    $script:processCode = 1603
    Assert-Throws { Invoke-VerifiedInstaller 'C:\fixture\sdk.exe' $spec } 'exit code 1603'
}

Test-Case 'installer heartbeat reports a real wait and preserves process exit codes without installing tools' {
    $engine = (Get-Process -Id $PID).Path
    $information = @()
    $code = Invoke-InstallerProcess -Parameters @{
        FilePath = $engine
        ArgumentList = '-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 2; exit 7"'
        Wait = $true
        PassThru = $true
        WindowStyle = 'Hidden'
    } -Label 'harmless test process' -HeartbeatSeconds 1 -InformationVariable information
    Assert-Equal $code 7
    $text = $information -join "`n"
    Assert-Equal ($text.Contains('Still waiting for harmless test process installer')) $true
    Assert-Equal ($text.Contains('No completion result yet')) $true
    Assert-Equal ($text.Contains('installer exited after')) $true
}

Test-Case 'installer startup failures surface instead of being reported as success' {
    Assert-Throws {
        Invoke-InstallerProcess -Parameters @{
            FilePath = 'C:\nonexistent-setup-test\missing-installer.exe'
            Wait = $true
            PassThru = $true
        } -Label 'missing test process' -HeartbeatSeconds 1
    } '.+'
}

Test-Case 'native command exit status is captured correctly' {
    Assert-Throws { Invoke-SetupNative $env:ComSpec @('/d', '/c', 'exit 7') } 'exit 7.*exit 7'
    Assert-Equal (Invoke-SetupNative $env:ComSpec @('/d', '/c', 'echo harmless')) 'harmless'
    Assert-Equal (Invoke-SetupNative $env:ComSpec @('/d', '/c', 'echo harmless-stderr 1>&2 & exit /b 0')).Trim() 'harmless-stderr'
}

Test-Case 'plugin stage runs only after prerequisites finish and never after failure or restart' {
    $script:installed = @()
    $script:pluginStages = 0
    $script:mcpStages = 0
    function Get-SetupArchitecture { 'arm64' }
    function Get-SetupState { New-TestState -Ready $script:installed }
    function Update-SetupPath {}
    function Install-SetupTool { param($Id) $script:installed += $Id; $false }
    function Confirm-InstalledTool {}
    function Invoke-PluginSetup {
        if (($script:installed -join ',') -ne 'git,node,dotnet,pac') { throw 'Prerequisites incomplete' }
        $script:pluginStages++
        return 0
    }
    function Invoke-CopilotStudioSetup { $script:mcpStages++; return 0 }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive -PluginHost ClaudeCode -AcceptPlugins -CopilotStudioHost CopilotApp -AcceptCopilotStudio) 0
    Assert-Equal $script:pluginStages 1
    Assert-Equal $script:mcpStages 1
    $script:installed = @()
    function Install-SetupTool { $true }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive -PluginHost ClaudeCode -AcceptPlugins -CopilotStudioHost CopilotApp -AcceptCopilotStudio) 3010
    function Install-SetupTool { throw 'Mock failure' }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive -PluginHost ClaudeCode -AcceptPlugins -CopilotStudioHost CopilotApp -AcceptCopilotStudio) 3
    Assert-Equal $script:pluginStages 1
    Assert-Equal $script:mcpStages 1
}

Test-Case 'explicit plugin selections are normalized and never expand into the standard set' {
    Assert-Equal ((Get-SetupPluginNames -Plugins ' Dataverse,Model-Apps,dataverse ' ) -join ',') 'dataverse,model-apps'
    Assert-Equal ((Get-SetupPluginNames -Plugins 'model-apps' -IncludeDataverse) -join ',') 'model-apps,dataverse'
    Assert-Equal ((Get-SetupPluginNames -Plugins 'dataverse' -IncludeDataverse) -join ',') 'dataverse'
    Assert-Equal ((Get-SetupPluginNames -Plugins 'model-apps') -join ',') 'model-apps'
}

Test-Case 'invalid or unscoped selections fail before inventory, installations or host access' {
    function Get-SetupArchitecture { throw 'INVENTORY FORBIDDEN' }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    foreach ($selection in @('', ' ', 'model-apps,', ',dataverse', 'unknown',
        'All,dataverse', 'dataverse@other', 'https://example.com/plugin', 'model-apps;whoami')) {
        Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotCli -Plugins $selection -AcceptPlugins) 2
    }
    Assert-Equal (Invoke-Setup -NonInteractive -Plugins 'model-apps' -AcceptPlugins) 2
    Assert-Equal (Invoke-Setup -PluginHost Skip -Plugins 'model-apps') 2
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost ClaudeCode -Plugins 'dataverse') 2
}

Test-Case 'doctor plugin-only approval never installs a newly missing prerequisite' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState {
        param([switch]$Azure)
        New-TestState -Ready @('git','dotnet','pac','azure') -Azure:$Azure
    }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Update-SetupPath { throw 'PATH CHANGE FORBIDDEN' }
    function Invoke-PluginSetup { throw 'PLUGINS FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotCli -Plugins 'dataverse,model-apps' -AcceptPlugins) 2
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotCli -MarketplaceOnly -AcceptPlugins) 2
}

Test-Case 'marketplace-only preparation installs no plugins before a separately approved selection in either CLI' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState {
        param([switch]$Azure)
        New-TestState -Ready @('git','node','dotnet','pac','azure') -Azure:$Azure
    }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    function Update-SetupPath { $script:pathRefreshed = $true }
    function Find-SetupExecutable {
        param($Name)
        $expected = if ($script:pluginHost -eq 'ClaudeCode') { 'claude' } else { 'copilot' }
        Assert-Equal $Name $expected
        "C:\fixture\$expected.exe"
    }
    function Invoke-SetupNative {
        param($Path, $Arguments)
        Assert-Equal $script:pathRefreshed $true
        Invoke-TestPluginCli $Path $Arguments
    }
    foreach ($hostName in @('CopilotCli', 'ClaudeCode')) {
        Reset-TestPluginCli
        $script:pluginHost = $hostName
        $script:pathRefreshed = $false
        Assert-Equal (Invoke-Setup -NonInteractive -PluginHost $hostName -MarketplaceOnly -AcceptPlugins) 0
        Assert-Equal $script:pluginRows.Count 0
        Assert-Equal $script:pluginCalls.Count 3
        Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments[1] -ne 'marketplace' }).Count) 0
        $script:pluginCalls = @()
        Assert-Equal (Invoke-Setup -NonInteractive -PluginHost $hostName -MarketplaceOnly -AcceptPlugins) 0
        Assert-Equal $script:pluginCalls.Count 1
        $script:pluginCalls = @()
        Assert-Equal (Invoke-Setup -NonInteractive -PluginHost $hostName -Plugins 'dataverse,model-apps' -AcceptPlugins) 0
        $installs = @($script:pluginCalls | Where-Object { $_.Arguments[1] -eq 'install' })
        Assert-Equal (($installs | ForEach-Object { $_.Arguments[2] }) -join ',') 'dataverse@power-platform-skills,model-apps@power-platform-skills'
        Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments -contains 'add' }).Count) 0
    }
}

Test-Case 'marketplace-only rejects missing consent, mixed selections and skipped hosts before inventory' {
    function Get-SetupArchitecture { throw 'INVENTORY FORBIDDEN' }
    function Update-SetupPath { throw 'PATH CHANGE FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotCli -MarketplaceOnly) 2
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotApp -MarketplaceOnly) 2
    Assert-Equal (Invoke-Setup -NonInteractive -MarketplaceOnly -AcceptPlugins) 2
    Assert-Equal (Invoke-Setup -PluginHost Skip -MarketplaceOnly) 2
    Assert-Equal (Invoke-Setup -PluginHost CopilotCli -MarketplaceOnly -Plugins 'dataverse' -AcceptPlugins) 2
    Assert-Equal (Invoke-Setup -PluginHost ClaudeCode -MarketplaceOnly -IncludeDataverse -AcceptPlugins) 2
}

Test-Case 'desktop marketplace-only triggers local ghapp marketplace URI without opening a browser and prints official link' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { New-TestState -Ready @('git') }
    function Find-SetupExecutable { throw 'CLI DISCOVERY FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Test-Path { param($LiteralPath) $LiteralPath -eq 'Registry::HKEY_CLASSES_ROOT\ghapp' }
    function Get-ItemProperty { [pscustomobject]@{ 'URL Protocol' = '' } }
    $script:launchedUris = @()
    function Start-Process { param($FilePath) $script:launchedUris += $FilePath }
    $information = @()
    $result = Invoke-Setup -NonInteractive -PluginHost CopilotApp -MarketplaceOnly -Prerequisites FromPlugins -AcceptPlugins -InformationVariable information
    Assert-Equal $result 4
    Assert-Equal ($script:launchedUris -join ',') 'ghapp://plugins/marketplace/add?source=microsoft%2Fpower-platform-skills'
    $output = $information -join "`n"
    Assert-Equal ($output.Contains((Get-CopilotAppPluginLink))) $true
    Assert-Equal ($output.Contains('plugins%2Finstall')) $false
}

Test-Case 'plugin catalog maps all 11 plugins and Resolve-SetupPrerequisites enforces canonical order and dependencies' {
    $catalog = @(Get-SetupPluginCatalog)
    Assert-Equal $catalog.Count 11
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -MarketplaceOnly) -join ',') 'git'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -Plugins 'canvas-apps') -join ',') 'git,dotnet'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -Plugins 'canvas-apps,code-apps-preview') -join ',') 'git,node,dotnet'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -Plugins 'canvas-apps,power-automate') -join ',') 'git,node,dotnet,azure'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -Plugins 'canvas-apps' -IncludeCopilotStudioMcp) -join ',') 'git,node,dotnet'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -Plugins 'code-apps-preview') -join ',') 'git,node'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -Plugins 'power-automate') -join ',') 'git,node,azure'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -Plugins 'mcp-apps') -join ',') 'git,node,dotnet,pac'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -Plugins 'model-apps') -join ',') 'git,node,dotnet,pac,azure'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'FromPlugins' -Plugins 'dataverse') -join ',') 'git,node,dotnet,pac,azure'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'pac') -join ',') 'dotnet,pac'
    Assert-Equal ((Resolve-SetupPrerequisites -Prerequisites 'azure,git') -join ',') 'git,azure'
    Assert-Throws { Resolve-SetupPrerequisites -Prerequisites '' } 'empty'
    Assert-Throws { Resolve-SetupPrerequisites -Prerequisites 'python' } 'Unsupported prerequisite selection'
    Assert-Throws { Resolve-SetupPrerequisites -Prerequisites 'azure' -SkipAzureCli } 'Do not combine -SkipAzureCli'
}

Test-Case 'selective check-only and install evaluate and install only prerequisites required by chosen plugins' {
    function Get-SetupArchitecture { 'arm64' }
    $script:readyTools = @('git', 'node')
    function Get-SetupState {
        param([switch]$Azure)
        New-TestState -Ready $script:readyTools -Azure:$Azure
    }
    $script:installedTools = @()
    function Install-SetupTool {
        param($Id)
        $script:installedTools += $Id
        $script:readyTools += $Id
        return $false
    }
    function Confirm-InstalledTool { param($Id) Assert-Equal $Id 'dotnet' }
    function Update-SetupPath {}
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    Assert-Equal (Invoke-Setup -CheckOnly -Plugins 'code-apps-preview' -Prerequisites FromPlugins) 0
    Assert-Equal (Invoke-Setup -CheckOnly -Plugins 'model-apps' -Prerequisites FromPlugins) 1
    Assert-Equal (Invoke-Setup -CheckOnly -Plugins 'canvas-apps' -Prerequisites FromPlugins) 1
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive -Plugins 'canvas-apps' -Prerequisites FromPlugins) 0
    Assert-Equal ($script:installedTools -join ',') 'dotnet'
}

Test-Case 'interactive setup mode supports selective plugin prerequisites and full workstation mode' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupAgentHosts { New-TestAgentHosts }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Start-Process {
        param($FilePath)
        Assert-Equal $FilePath 'ghapp://plugins/marketplace/add?source=microsoft%2Fpower-platform-skills'
    }
    function Get-SetupState {
        param([switch]$Azure)
        # PAC is intentionally NOT ready; canvas-apps + power-automate must not require PAC.
        New-TestState -Ready @('git', 'node', 'dotnet', 'azure') -Azure:$Azure
    }
    $script:modeAnswers = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in @('1', '3 7', '4', '', '')) { $script:modeAnswers.Enqueue($answer) }
    function Read-Host { $script:modeAnswers.Dequeue() }
    Assert-Equal (Invoke-Setup) 0
    Assert-Equal $script:modeAnswers.Count 0

    foreach ($answer in @('1', '3, 4, 7', '4', '', '')) { $script:modeAnswers.Enqueue($answer) }
    Assert-Equal (Invoke-Setup) 0
    Assert-Equal $script:modeAnswers.Count 0

    foreach ($answer in @('1', 'M', '3', 'MARKETPLACE', '', '')) { $script:modeAnswers.Enqueue($answer) }
    function Get-SetupState { New-TestState -Ready @('git') }
    $information = @()
    Assert-Equal (Invoke-Setup -InformationVariable information) 4
    Assert-Equal $script:modeAnswers.Count 0
    Assert-Equal (($information -join "`n").Contains((Get-CopilotAppPluginLink))) $true

    foreach ($answer in @('2', '', '', '')) { $script:modeAnswers.Enqueue($answer) }
    function Get-SetupState {
        param([switch]$Azure)
        New-TestState -Ready @('git', 'node', 'dotnet', 'pac', 'azure') -Azure:$Azure
    }
    Assert-Equal (Invoke-Setup) 0
    Assert-Equal $script:modeAnswers.Count 0
}

Test-Case 'interactive marketplace-only approval cannot be replaced by plugin approval' {
    Reset-TestPluginCli
    function Find-SetupExecutable { 'C:\fixture\copilot.exe' }
    function Read-Host { 'PLUGINS' }
    function Update-SetupPath { throw 'PATH CHANGE FORBIDDEN' }
    function Invoke-SetupNative { param($Path, $Arguments) Invoke-TestPluginCli $Path $Arguments }
    Assert-Equal (Invoke-PluginSetup -PluginHost CopilotCli -MarketplaceOnly) 2
    Assert-Equal $script:pluginCalls.Count 0
    function Read-Host { 'MARKETPLACE' }
    function Update-SetupPath {}
    Assert-Equal (Invoke-PluginSetup -PluginHost CopilotCli -MarketplaceOnly) 0
    Assert-Equal $script:pluginRows.Count 0
}

Test-Case 'doctor installs only approved plugins in either selected CLI and safely reuses them' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState {
        param([switch]$Azure)
        New-TestState -Ready @('git','node','dotnet','pac','azure') -Azure:$Azure
    }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Update-SetupPath {}
    function Start-Process { throw 'PROCESS FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    function Find-SetupExecutable {
        param($Name)
        $expected = if ($script:pluginHost -eq 'ClaudeCode') { 'claude' } else { 'copilot' }
        Assert-Equal $Name $expected
        return "C:\fixture\$expected.exe"
    }
    function Invoke-SetupNative { param($Path, $Arguments) Invoke-TestPluginCli $Path $Arguments }
    foreach ($hostName in @('CopilotCli', 'ClaudeCode')) {
        Reset-TestPluginCli
        $script:pluginHost = $hostName
        $script:pluginRows = @(
            if ($hostName -eq 'ClaudeCode') {
                [pscustomobject]@{ id = 'power-pages@power-platform-skills'; scope = 'user'; enabled = $false }
            } else {
                [pscustomobject]@{ name = 'power-pages'; marketplace = 'power-platform-skills'; enabled = $false }
            })
        Assert-Equal (Invoke-Setup -NonInteractive -PluginHost $hostName -Plugins 'dataverse,model-apps' -AcceptPlugins) 0
        $installs = @($script:pluginCalls | Where-Object { $_.Arguments[1] -eq 'install' })
        Assert-Equal (($installs | ForEach-Object { $_.Arguments[2] }) -join ',') 'dataverse@power-platform-skills,model-apps@power-platform-skills'
        Assert-Equal (@($script:pluginCalls | Where-Object { ($_.Arguments -join ' ') -eq 'plugin marketplace add microsoft/power-platform-skills' }).Count) 1
        Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments[0] -ne 'plugin' }).Count) 0
        if ($hostName -eq 'ClaudeCode') {
            Assert-Equal (@($installs | Where-Object { ($_.Arguments -join ' ') -notmatch '--scope user$' }).Count) 0
        }
        Assert-Equal @($script:pluginRows).Count 3
        Assert-Equal $script:pluginRows[0].enabled $false
        $script:pluginCalls = @()
        Assert-Equal (Invoke-Setup -NonInteractive -PluginHost $hostName -Plugins 'dataverse,model-apps' -AcceptPlugins) 0
        Assert-Equal $script:pluginCalls.Count 2
        $script:pluginRows[1].enabled = $false
        $script:pluginCalls = @()
        Assert-Equal (Invoke-Setup -NonInteractive -PluginHost $hostName -Plugins 'dataverse,model-apps' -AcceptPlugins) 3
        Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments -notcontains 'list' }).Count) 0
    }
}

Test-Case 'check-only with a plugin plan stays offline, CLI-free and prompt-free' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { New-TestState -Ready @('git','node','dotnet','pac') }
    function Invoke-PluginSetup { throw 'PLUGIN STAGE FORBIDDEN' }
    function Find-SetupExecutable { throw 'HOST DISCOVERY FORBIDDEN' }
    function Get-SetupAgentHosts { throw 'HOST INVENTORY FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Invoke-WebRequest { throw 'NETWORK FORBIDDEN' }
    function Update-SetupPath { throw 'PATH CHANGE FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    Assert-Equal (Invoke-Setup -CheckOnly -PluginHost CopilotCli -IncludeDataverse) 0
    Assert-Equal (Invoke-Setup -CheckOnly -PluginHost CopilotCli -Plugins 'dataverse,model-apps') 0
    Assert-Equal (Invoke-Setup -CheckOnly -PluginHost ClaudeCode -MarketplaceOnly) 0
}

Test-Case 'plugin opt-in is separate from prerequisite approval and rejected early when inconsistent' {
    function Get-SetupArchitecture { throw 'SHOULD VALIDATE FIRST' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    Assert-Equal (Invoke-Setup -Install -Accept -NonInteractive -PluginHost CopilotCli) 2
    Assert-Equal (Invoke-Setup -NonInteractive -AcceptPlugins) 2
    Assert-Equal (Invoke-Setup -NonInteractive -IncludeDataverse) 2
    Assert-Equal (Invoke-Setup -PluginHost Skip -IncludeDataverse) 2
    Assert-Equal (Invoke-Setup -CheckOnly -AcceptPlugins -PluginHost CopilotApp) 2
}

Test-Case 'plain noninteractive runs and explicit skip do not touch hosts or prompt' {
    function Find-SetupExecutable { throw 'DISCOVERY FORBIDDEN' }
    function Get-SetupAgentHosts { throw 'HOST INVENTORY FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    Assert-Equal (Invoke-PluginSetup -NonInteractive) 0
    Assert-Equal (Invoke-PluginSetup -PluginHost Skip) 0
}

Test-Case 'interactive host chooser offers skip without running another host' {
    function Get-SetupAgentHosts { New-TestAgentHosts }
    function Find-SetupExecutable { throw 'DISCOVERY FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Read-Host { '' }
    Assert-Equal (Invoke-PluginSetup) 0
    function Read-Host { 'unexpected' }
    Assert-Equal (Invoke-PluginSetup) 2
}

Test-Case 'interactive plugin approval cannot be replaced by prerequisite acceptance' {
    function Find-SetupExecutable { 'C:\fixture\claude.exe' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Read-Host { 'INSTALL' }
    Assert-Equal (Invoke-PluginSetup -PluginHost ClaudeCode) 2
}

Test-Case 'absent chosen CLI returns its official handoff without installing a host or using the other CLI' {
    function Find-SetupExecutable {
        param($Name)
        Assert-Equal $Name 'claude'
        $null
    }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Start-Process { throw 'PROCESS FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    $information = @()
    $result = Invoke-PluginSetup -PluginHost ClaudeCode -AcceptPlugins -NonInteractive -InformationVariable information
    Assert-Equal $result 2
    Assert-Equal (($information -join "`n").Contains('https://code.claude.com/docs/en/setup')) $true
}

Test-Case 'host discovery reads only command candidates and ghapp URL registration without invoking a CLI' {
    function Find-SetupExecutable {
        param($Name)
        if ($Name -eq 'copilot') { return 'C:\fixture\copilot-launcher.exe' }
        Assert-Equal $Name 'claude'
        return $null
    }
    function Test-Path {
        param($LiteralPath)
        Assert-Equal $LiteralPath 'Registry::HKEY_CLASSES_ROOT\ghapp'
        return $true
    }
    function Get-ItemProperty {
        param($LiteralPath)
        Assert-Equal $LiteralPath 'Registry::HKEY_CLASSES_ROOT\ghapp'
        [pscustomobject]@{ 'URL Protocol' = '' }
    }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Start-Process { throw 'PROCESS FORBIDDEN' }
    function Invoke-WebRequest { throw 'NETWORK FORBIDDEN' }
    function Invoke-RestMethod { throw 'NETWORK FORBIDDEN' }
    function New-Item { throw 'WRITE FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    $hosts = @(Get-SetupAgentHosts)
    Assert-Equal ($hosts | Where-Object Id -eq 'CopilotCli').Detected $true
    Assert-Equal ($hosts | Where-Object Id -eq 'ClaudeCode').Detected $false
    Assert-Equal ($hosts | Where-Object Id -eq 'CopilotApp').Detected $true
    function Get-ItemProperty { [pscustomobject]@{ 'Not a URL protocol' = '' } }
    Assert-Equal (Get-SetupAgentHosts | Where-Object Id -eq 'CopilotApp').Detected $false
    function Get-ItemProperty { throw 'Registry access denied' }
    Assert-Throws { Get-SetupAgentHosts } 'Registry access denied'
}

Test-Case 'no detected hosts gives the chosen official installation handoff before plugin questions' {
    function Get-SetupAgentHosts { New-TestAgentHosts -Detected @() }
    function Find-SetupExecutable { $null }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Update-SetupPath { throw 'PATH CHANGE FORBIDDEN' }
    function Start-Process { throw 'PROCESS FORBIDDEN' }
    $script:answers = [Collections.Generic.Queue[string]]::new()
    $script:answers.Enqueue('2')
    function Read-Host { $script:answers.Dequeue() }
    $information = @()
    $result = Invoke-PluginSetup -InformationVariable information
    Assert-Equal $result 2
    Assert-Equal $script:answers.Count 0
    Assert-Equal (($information -join "`n").Contains('https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli')) $true
}

Test-Case 'missing-host handoff stops later MCP and personal skill writes while keeping prerequisites' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState {
        param([switch]$Azure)
        New-TestState -Ready @('git','node','dotnet','pac','azure') -Azure:$Azure
    }
    function Find-SetupExecutable {
        param($Name)
        Assert-Equal $Name 'copilot'
        $null
    }
    function Install-SetupTool { throw 'INSTALL FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Invoke-CopilotStudioSetup { throw 'MCP WRITE FORBIDDEN' }
    function Invoke-ConnectionSkillSetup { throw 'SKILL WRITE FORBIDDEN' }
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotCli -MarketplaceOnly -AcceptPlugins) 2
}

Test-Case 'an undetected desktop app needs user confirmation or gets its official install handoff' {
    function Get-SetupAgentHosts { New-TestAgentHosts -Detected @() }
    function Find-SetupExecutable { throw 'CLI DISCOVERY FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Test-Path { $false }
    function Start-Process { throw 'APP/BROWSER LAUNCH FORBIDDEN WHEN GHAPP UNREGISTERED' }
    $script:answers = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in @('3', '')) { $script:answers.Enqueue($answer) }
    function Read-Host { $script:answers.Dequeue() }
    $information = @()
    $result = Invoke-PluginSetup -InformationVariable information
    Assert-Equal $result 2
    Assert-Equal (($information -join "`n").Contains('https://github.com/features/ai/github-app')) $true
    foreach ($answer in @('3', 'APP', 'YES', 'PLUGINS')) { $script:answers.Enqueue($answer) }
    $information = @()
    $result = Invoke-PluginSetup -InformationVariable information
    Assert-Equal $result 4
    Assert-Equal $script:answers.Count 0
    Assert-Equal (($information -join "`n").Contains((Get-CopilotAppPluginLink))) $true
}

Test-Case 'Copilot CLI plugin install is scoped, fully verified, and skips existing plugins on rerun' {
    Reset-TestPluginCli
    function Invoke-SetupNative { param($Path, $Arguments) Invoke-TestPluginCli $Path $Arguments }
    Install-SetupPlugins 'C:\fixture\copilot.exe' 'CopilotCli' @('canvas-apps','model-apps')
    Assert-Equal @($script:pluginRows).Count 2
    Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments[1] -eq 'install' }).Count) 2
    Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments[0] -ne 'plugin' }).Count) 0
    $script:pluginCalls = @()
    Install-SetupPlugins 'C:\fixture\copilot.exe' 'CopilotCli' @('canvas-apps','model-apps')
    Assert-Equal $script:pluginCalls.Count 2
}

Test-Case 'Claude plugin installation uses explicit user scope and the selected command only' {
    Reset-TestPluginCli
    $script:pluginHost = 'ClaudeCode'
    function Invoke-SetupNative { param($Path, $Arguments) Invoke-TestPluginCli $Path $Arguments }
    function Find-SetupExecutable {
        param($Name)
        if ($Name -ne 'claude') { throw 'Wrong host selected' }
        'C:\fixture\claude.exe'
    }
    Assert-Equal (Invoke-PluginSetup -PluginHost ClaudeCode -AcceptPlugins -NonInteractive -IncludeDataverse) 0
    $installs = @($script:pluginCalls | Where-Object { $_.Arguments[1] -eq 'install' })
    Assert-Equal ($installs.Count -gt 1) $true
    Assert-Equal (@($installs | Where-Object { ($_.Arguments -join ' ') -notmatch '--scope user$' }).Count) 0
    Assert-Equal (@($installs | Where-Object { $_.Arguments[2] -eq 'dataverse@power-platform-skills' }).Count) 1
    Assert-Equal (@($script:pluginCalls | Where-Object Path -ne 'C:\fixture\claude.exe').Count) 0
}

Test-Case 'existing external Dataverse is preserved without installing a duplicate' {
    Reset-TestPluginCli
    $script:pluginHost = 'ClaudeCode'
    $script:pluginRows = @([pscustomobject]@{ id = 'dataverse@dataverse-skills'; scope = 'user'; enabled = $true })
    function Invoke-SetupNative { param($Path, $Arguments) Invoke-TestPluginCli $Path $Arguments }
    Install-SetupPlugins 'C:\fixture\claude.exe' 'ClaudeCode' @('dataverse')
    Assert-Equal $script:pluginCalls.Count 4
    Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments[1] -eq 'install' }).Count) 0
}

Test-Case 'marketplace collisions, disabled plugins and other sources stop before any install' {
    Reset-TestPluginCli
    $script:marketplaceRows = @([pscustomobject]@{ name = 'power-platform-skills'; source = 'github'; repo = 'untrusted/repo' })
    function Invoke-SetupNative { param($Path, $Arguments) Invoke-TestPluginCli $Path $Arguments }
    Assert-Throws { Install-SetupPlugins 'fixture' 'CopilotCli' @('canvas-apps') } 'source is different or unrecognized'
    Assert-Equal $script:pluginCalls.Count 1
    $script:marketplaceRows = @()
    $script:pluginRows = @([pscustomobject]@{ name = 'canvas-apps'; marketplace = 'power-platform-skills'; enabled = $false })
    Assert-Throws { Install-SetupPlugins 'fixture' 'CopilotCli' @('canvas-apps') } 'disabled'
    $script:pluginRows = @([pscustomobject]@{ name = 'canvas-apps'; marketplace = 'different'; enabled = $true })
    Assert-Throws { Install-SetupPlugins 'fixture' 'CopilotCli' @('canvas-apps') } 'another or duplicate source'
    Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments -notcontains 'list' }).Count) 0
}

Test-Case 'official marketplace source formats are accepted without trusting a misleading URL' {
    Assert-Equal (Assert-OfficialMarketplace @([pscustomobject]@{
        name = 'power-platform-skills'; source = 'microsoft/power-platform-skills'
    })) $true
    Assert-Equal (Assert-OfficialMarketplace @([pscustomobject]@{
        name = 'power-platform-skills'
        source = [pscustomobject]@{ type = 'github'; repo = 'microsoft/power-platform-skills' }
    })) $true
    Assert-Equal (Assert-OfficialMarketplace @([pscustomobject]@{
        name = 'power-platform-skills'; source = 'git'; url = 'https://github.com/microsoft/power-platform-skills.git'
    })) $true
    Assert-Throws { Assert-OfficialMarketplace @([pscustomobject]@{
        name = 'power-platform-skills'; source = 'github'; repo = 'untrusted/repo'
        url = 'https://github.com/microsoft/power-platform-skills.git'
    }) } 'source is different or unrecognized'
}

Test-Case 'load errors and unexpected Claude scopes stop rather than enabling or duplicating plugins' {
    Reset-TestPluginCli
    $script:pluginHost = 'ClaudeCode'
    function Invoke-SetupNative { param($Path, $Arguments) Invoke-TestPluginCli $Path $Arguments }
    $script:pluginRows = @([pscustomobject]@{
        id = 'canvas-apps@power-platform-skills'; scope = 'user'; enabled = $true; errors = @('load failed')
    })
    Assert-Throws { Install-SetupPlugins 'fixture' 'ClaudeCode' @('canvas-apps') } 'load errors'
    $script:pluginRows = @([pscustomobject]@{
        id = 'canvas-apps@power-platform-skills'; scope = 'project'; enabled = $true
    })
    Assert-Throws { Install-SetupPlugins 'fixture' 'ClaudeCode' @('canvas-apps') } 'outside user scope'
    Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments -notcontains 'list' }).Count) 0
}

Test-Case 'plugin install failure stops the chain and does not become a success-shaped fallback' {
    Reset-TestPluginCli
    $script:failPlugin = 'canvas-apps@power-platform-skills'
    function Invoke-SetupNative { param($Path, $Arguments) Invoke-TestPluginCli $Path $Arguments }
    Assert-Throws { Install-SetupPlugins 'fixture' 'CopilotCli' @('canvas-apps','model-apps') } 'Mock plugin installation failed'
    Assert-Equal (@($script:pluginCalls | Where-Object { $_.Arguments[1] -eq 'install' }).Count) 1
}

Test-Case 'exit zero alone is insufficient to confirm plugin installation' {
    Reset-TestPluginCli
    $script:omitPluginRecord = $true
    function Invoke-SetupNative { param($Path, $Arguments) Invoke-TestPluginCli $Path $Arguments }
    Assert-Throws { Install-SetupPlugins 'fixture' 'CopilotCli' @('canvas-apps') } 'could not be verified'
}

Test-Case 'malformed or unsupported listing schemas fail closed without leaking raw output' {
    function Invoke-SetupNative { 'private output that must not be echoed' }
    Assert-Throws { Read-PluginJson 'fixture' @('plugin','list','--json') } '^Unsupported plugin CLI output:'
    function Invoke-SetupNative { '[invalid secret]' }
    Assert-Throws { Read-PluginJson 'fixture' @('plugin','list','--json') } '^The plugin CLI returned invalid JSON\.'
    function Invoke-SetupNative { '[{"name":"canvas-apps","enabled":"true"}]' }
    Assert-Throws { Get-PluginInventory 'fixture' 'CopilotCli' } 'Unsupported plugin identity/status'
}

Test-Case 'desktop route hands off official links, excludes Dataverse by default, and reports pending' {
    function Find-SetupExecutable { throw 'CLI DISCOVERY FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Test-Path { param($LiteralPath) $LiteralPath -eq 'Registry::HKEY_CLASSES_ROOT\ghapp' }
    function Get-ItemProperty { [pscustomobject]@{ 'URL Protocol' = '' } }
    $script:desktopLaunched = @()
    function Start-Process {
        param($FilePath)
        Assert-Equal $FilePath 'ghapp://plugins/marketplace/add?source=microsoft%2Fpower-platform-skills'
        $script:desktopLaunched += $FilePath
    }
    $information = @()
    $result = Invoke-PluginSetup -PluginHost CopilotApp -AcceptPlugins -NonInteractive -InformationVariable information
    Assert-Equal $result 4
    Assert-Equal $script:desktopLaunched.Count 1
    $output = $information -join "`n"
    Assert-Equal ($output.Contains('dataverse%2540power-platform-skills')) $false
    Assert-Equal ($output.Contains('ACTION REQUIRED')) $true
    Assert-Equal (Get-CopilotAppPluginLink) 'https://github.com/copilot/app/launch?open=ghapp%3A%2F%2Fplugins%2Fmarketplace%2Fadd%3Fsource%3Dmicrosoft%252Fpower-platform-skills'
    Assert-Equal (Get-CopilotAppPluginLink 'canvas-apps') 'https://github.com/copilot/app/launch?open=ghapp%3A%2F%2Fplugins%2Finstall%3Fsource%3Dcanvas-apps%2540power-platform-skills'
    $information = @()
    Assert-Equal (Invoke-PluginSetup -PluginHost CopilotApp -AcceptPlugins -NonInteractive -IncludeDataverse -InformationVariable information) 4
    Assert-Equal $script:desktopLaunched.Count 2
    Assert-Equal (($information -join "`n").Contains('dataverse%2540power-platform-skills')) $true
}

Test-Case 'interactive app selection requires separate approval, Dataverse opt-in, and can step through plugin prompts after marketplace confirmation' {
    function Get-SetupAgentHosts { New-TestAgentHosts }
    function Test-Path { param($LiteralPath) $LiteralPath -eq 'Registry::HKEY_CLASSES_ROOT\ghapp' }
    function Get-ItemProperty { [pscustomobject]@{ 'URL Protocol' = '' } }
    $script:answers = [System.Collections.Generic.Queue[string]]::new()
    foreach ($answer in @('3', 'YES', 'PLUGINS', 'LINKS')) { $script:answers.Enqueue($answer) }
    function Read-Host { $script:answers.Dequeue() }
    $script:appLaunched = @()
    function Start-Process { param($FilePath) $script:appLaunched += $FilePath }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    $information = @()
    Assert-Equal (Invoke-PluginSetup -InformationVariable information) 4
    Assert-Equal $script:answers.Count 0
    Assert-Equal ($script:appLaunched -join ',') 'ghapp://plugins/marketplace/add?source=microsoft%2Fpower-platform-skills'
    Assert-Equal (($information -join "`n").Contains('dataverse%2540power-platform-skills')) $true

    $script:appLaunched = @()
    foreach ($answer in @('PLUGINS', '', '', '')) { $script:answers.Enqueue($answer) }
    Assert-Equal (Invoke-PluginSetup -PluginHost CopilotApp -Plugins 'model-apps,code-apps-preview') 4
    Assert-Equal $script:answers.Count 0
    Assert-Equal ($script:appLaunched -join ',') 'ghapp://plugins/marketplace/add?source=microsoft%2Fpower-platform-skills,ghapp://plugins/install?source=model-apps%40power-platform-skills,ghapp://plugins/install?source=code-apps-preview%40power-platform-skills'
}

Test-Case 'CopilotApp -SkipMarketplace triggers one plugin install dialog at a time after marketplace confirmation' {
    function Get-SetupArchitecture { 'x64' }
    function Get-SetupState { New-TestState -Ready @('git', 'node') }
    function Find-SetupExecutable { throw 'CLI DISCOVERY FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Test-Path { param($LiteralPath) $LiteralPath -eq 'Registry::HKEY_CLASSES_ROOT\ghapp' }
    function Get-ItemProperty { [pscustomobject]@{ 'URL Protocol' = '' } }
    $script:pluginUris = @()
    function Start-Process { param($FilePath) $script:pluginUris += $FilePath }
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotCli -Plugins 'code-apps-preview' -SkipMarketplace -AcceptPlugins) 2
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotApp -MarketplaceOnly -SkipMarketplace -AcceptPlugins) 2
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotApp -Plugins 'model-apps,code-apps-preview' -SkipMarketplace -Prerequisites FromPlugins -AcceptPlugins) 2
    $information = @()
    Assert-Equal (Invoke-Setup -NonInteractive -PluginHost CopilotApp -Plugins 'code-apps-preview' -SkipMarketplace -Prerequisites FromPlugins -AcceptPlugins -InformationVariable information) 4
    Assert-Equal ($script:pluginUris -join ',') 'ghapp://plugins/install?source=code-apps-preview%40power-platform-skills'
    Assert-Equal (($information -join "`n").Contains((Get-CopilotAppPluginLink 'code-apps-preview'))) $true
}

Test-Case 'Copilot Studio approval is independent and validated before any prerequisite changes' {
    function Get-SetupArchitecture { throw 'SHOULD VALIDATE FIRST' }
    Assert-Equal (Invoke-Setup -NonInteractive -CopilotStudioHost CopilotApp) 2
    Assert-Equal (Invoke-Setup -AcceptCopilotStudio) 2
    Assert-Equal (Invoke-Setup -CopilotStudioHost Skip -AcceptCopilotStudio) 2
    Assert-Equal (Invoke-Setup -CheckOnly -CopilotStudioHost CopilotCli -AcceptCopilotStudio) 2
}

Test-Case 'MCP stage cannot run from check-only and ordinary noninteractive runs skip it' {
    function Get-SetupArchitecture { 'arm64' }
    function Get-SetupState { New-TestState -Ready @('git','node','dotnet','pac') }
    function Get-CopilotStudioConfigPath { throw 'CONFIG ACCESS FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    Assert-Equal (Invoke-Setup -CheckOnly -CopilotStudioHost CopilotApp) 0
    Assert-Equal (Invoke-Setup -NonInteractive) 0
    Assert-Equal (Invoke-CopilotStudioSetup -CopilotStudioHost Skip) 0
}

Test-Case 'default COPILOT_HOME is accepted for both Copilot hosts without clearing the variable' {
    $previousProfile = $env:USERPROFILE
    $previousHome = $env:COPILOT_HOME
    try {
        $env:USERPROFILE = 'C:\fixture\copilot-user'
        foreach ($homeValue in @(
            $null,
            'C:\fixture\copilot-user\.copilot',
            'C:\FIXTURE\copilot-user\.copilot\',
            'C:/fixture/copilot-user/.copilot/.',
            '%USERPROFILE%\.copilot')) {
            $env:COPILOT_HOME = $homeValue
            foreach ($hostName in @('CopilotApp', 'CopilotCli')) {
                Assert-Equal (Get-CopilotStudioConfigPath $hostName) 'C:\fixture\copilot-user\.copilot\mcp-config.json'
                Assert-Equal (Get-ConnectionSkillDirectory $hostName) 'C:\fixture\copilot-user\.copilot\skills\power-platform-connect'
            }
            Assert-Equal $env:COPILOT_HOME $homeValue
        }
    } finally {
        $env:USERPROFILE = $previousProfile
        $env:COPILOT_HOME = $previousHome
    }
}

Test-Case 'truly custom or relative COPILOT_HOME values still fail before config or skill writes' {
    $previousProfile = $env:USERPROFILE
    $previousHome = $env:COPILOT_HOME
    try {
        $env:USERPROFILE = 'C:\fixture\copilot-user'
        foreach ($homeValue in @('C:\fixture\other-home', '.copilot', 'C:\fixture\copilot-user\.copilot-other', 'C:relative')) {
            $env:COPILOT_HOME = $homeValue
            Assert-Throws { Get-CopilotStudioConfigPath 'CopilotApp' } 'custom location'
            Assert-Throws { Get-ConnectionSkillDirectory 'CopilotCli' } 'custom location'
            Assert-Equal $env:COPILOT_HOME $homeValue
        }
    } finally {
        $env:USERPROFILE = $previousProfile
        $env:COPILOT_HOME = $previousHome
    }
}

Test-Case 'default Copilot home permits MCP and skill installation together in a disposable profile only' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $previousProfile = $env:USERPROFILE
    $previousHome = $env:COPILOT_HOME
    try {
        $env:USERPROFILE = $directory
        $env:COPILOT_HOME = Join-Path $directory '.copilot'
        function Invoke-SetupNative { throw 'CLI OR AUTH EXECUTION FORBIDDEN' }
        function Start-Process { throw 'HOST LAUNCH FORBIDDEN' }
        Assert-Equal (Invoke-CopilotStudioSetup -CopilotStudioHost CopilotApp -AcceptCopilotStudio -NonInteractive) 0
        Assert-Equal (Invoke-ConnectionSkillSetup -ConnectionSkillHost CopilotApp -AcceptConnectionSkill -NonInteractive) 0
        Assert-Equal (Test-CopilotStudioRegistration (Read-McpUserConfig (Get-CopilotStudioConfigPath 'CopilotApp'))) $true
        $skillPath = Join-Path (Get-ConnectionSkillDirectory 'CopilotApp') 'SKILL.md'
        $routerPath = Join-Path (Get-ConnectionSkillDirectory 'CopilotApp' 'power-platform-router') 'SKILL.md'
        Assert-Equal (Get-FileHash -LiteralPath $skillPath -Algorithm SHA256).Hash (Get-FileHash -LiteralPath (Join-Path $root 'skills\power-platform-connect\SKILL.md') -Algorithm SHA256).Hash
        Assert-Equal (Get-FileHash -LiteralPath $routerPath -Algorithm SHA256).Hash (Get-FileHash -LiteralPath (Join-Path $root 'skills\power-platform-router\SKILL.md') -Algorithm SHA256).Hash
    } finally {
        $env:USERPROFILE = $previousProfile
        $env:COPILOT_HOME = $previousHome
        if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
    }
}

Test-Case 'MCP interactive approval does not accept INSTALL or PLUGINS' {
    function Get-CopilotStudioConfigPath { 'C:\fixture\mcp-config.json' }
    function Read-McpUserConfig { throw 'CONFIG READ FORBIDDEN' }
    function Read-Host { 'PLUGINS' }
    Assert-Equal (Invoke-CopilotStudioSetup -CopilotStudioHost CopilotApp) 2
    function Read-Host { 'INSTALL' }
    Assert-Equal (Invoke-CopilotStudioSetup -CopilotStudioHost CopilotApp) 2
}

Test-Case 'integration sequence keeps pending app action and stops MCP on plugin failure/cancellation' {
    $script:mcpCalls = 0
    $script:pluginCode = 4
    function Invoke-PluginSetup { $script:pluginCode }
    function Invoke-CopilotStudioSetup { $script:mcpCalls++; 0 }
    Assert-Equal (Invoke-SetupIntegrations -NonInteractive) 4
    Assert-Equal $script:mcpCalls 1
    foreach ($code in @(2,3,3010)) {
        $script:pluginCode = $code
        Assert-Equal (Invoke-SetupIntegrations -NonInteractive) $code
    }
    Assert-Equal $script:mcpCalls 1
    $script:pluginCode = 0
    function Invoke-CopilotStudioSetup { 2 }
    Assert-Equal (Invoke-SetupIntegrations -NonInteractive) 2
}

Test-Case 'MCP config merge preserves all unrelated text, creates a backup, and is safe on rerun' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $script:mcpFixturePath = Join-Path $directory 'mcp-config.json'
    New-Item -ItemType Directory -Path $directory | Out-Null
    try {
        $original = '{"largeNumber":123456789012345678901234567890,"custom":{"text":"a } brace and \"quote\""},"mcpServers":{"existing":{"command":"fixture","env":{"SECRET":"dummy-private-value"}}}}'
        [IO.File]::WriteAllText($script:mcpFixturePath, $original, [Text.UTF8Encoding]::new($false))
        function Get-CopilotStudioConfigPath { $script:mcpFixturePath }
        function Start-Process { throw 'PROCESS LAUNCH FORBIDDEN' }
        function Invoke-SetupNative { throw 'CLI/SERVER LAUNCH FORBIDDEN' }
        $information = @()
        Assert-Equal (Invoke-CopilotStudioSetup -CopilotStudioHost CopilotApp -AcceptCopilotStudio -NonInteractive -InformationVariable information) 0
        $updated = [IO.File]::ReadAllText($script:mcpFixturePath)
        Assert-Equal ($updated.Contains('"largeNumber":123456789012345678901234567890')) $true
        Assert-Equal ($updated.Contains('"existing":{"command":"fixture","env":{"SECRET":"dummy-private-value"}}')) $true
        Assert-Equal (($information -join "`n").Contains('dummy-private-value')) $false
        $backups = @(Get-ChildItem -LiteralPath $directory -Filter '*.setup-backup-*')
        Assert-Equal $backups.Count 1
        Assert-Equal ([IO.File]::ReadAllText($backups[0].FullName)) $original
        $config = Read-McpUserConfig $script:mcpFixturePath
        Assert-Equal (Test-CopilotStudioRegistration $config) $true
        Assert-Equal ($config.Data.mcpServers.'copilot-studio'.args -join ' ') '-y @microsoft/copilot-studio-mcp@latest'
        Assert-Equal (Invoke-CopilotStudioSetup -CopilotStudioHost CopilotApp -AcceptCopilotStudio -NonInteractive) 0
        Assert-Equal ([IO.File]::ReadAllText($script:mcpFixturePath)) $updated
        Assert-Equal (@(Get-ChildItem -LiteralPath $directory -Filter '*.setup-backup-*').Count) 1
    } finally { Remove-Item -LiteralPath $directory -Recurse -Force }
}

Test-Case 'MCP configuration creates only the target entry when the user has no config yet' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $path = Join-Path $directory 'mcp-config.json'
    try {
        $config = Read-McpUserConfig $path
        Save-CopilotStudioConfig $path $config
        $saved = Read-McpUserConfig $path
        Assert-Equal (Test-CopilotStudioRegistration $saved) $true
        Assert-Equal @($saved.Data.PSObject.Properties).Count 1
        Assert-Equal @($saved.Data.mcpServers.PSObject.Properties).Count 1
    } finally {
        if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
    }
}

Test-Case 'MCP insertion handles missing/empty server maps, escaped keys and nested JSON safely' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    $path = Join-Path $directory 'mcp-config.json'
    try {
        foreach ($text in @(
            '{}',
            '{"settings":[{"x":1},2]}',
            '{"mcpServers":{}}',
            '{"mcp\u0053ervers":{"other":{"command":"fixture","args":["}", "{"]}},"tail":{"a":1}}')) {
            [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($true))
            Save-CopilotStudioConfig $path (Read-McpUserConfig $path)
            Assert-Equal (Test-CopilotStudioRegistration (Read-McpUserConfig $path)) $true
            Assert-Equal ([IO.File]::ReadAllBytes($path)[0]) 0xEF
        }
    } finally { Remove-Item -LiteralPath $directory -Recurse -Force }
}

Test-Case 'MCP malformed, duplicate, nonobject and non-UTF8 configs fail closed' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    $path = Join-Path $directory 'mcp-config.json'
    try {
        foreach ($text in @(
            '{invalid}', '[]', '{"mcpServers":null}', '{"mcpServers":[]}',
            '{"mcpServers":{},"mcpServers":{}}',
            '{"mcpServers":{"same":{},"same":{}}}', '{"mcpservers":{}}')) {
            [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
            try { Assert-Throws { Read-McpUserConfig $path } 'JSON|object|Duplicate|casing' } catch {
                throw "Invalid fixture was not rejected correctly: $text - $($_.Exception.Message)"
            }
            Assert-Equal ([IO.File]::ReadAllText($path)) $text
        }
        [IO.File]::WriteAllBytes($path, [byte[]]@(0xFF,0xFE,0,0))
        Assert-Throws { Read-McpUserConfig $path } 'UTF-8'
    } finally { Remove-Item -LiteralPath $directory -Recurse -Force }
}

Test-Case 'MCP pinned/conflicting definitions fail without overwrite while matching aliases are reused' {
    foreach ($json in @(
        '{"mcpServers":{"copilot-studio":{"command":"different"}}}',
        '{"mcpServers":{"pinned":{"command":"npx","args":["-y","@microsoft/copilot-studio-mcp@1.2.3"]}}}')) {
        $config = [pscustomobject]@{ Data = $json | ConvertFrom-Json }
        Assert-Throws { Test-CopilotStudioRegistration $config } 'will not overwrite or duplicate'
    }
    $config = [pscustomobject]@{ Data = '{"mcpServers":{"my-studio":{"command":"npx.cmd","args":["-y","@microsoft/copilot-studio-mcp@latest"],"disabled":true,"tools":["restricted"]}}}' | ConvertFrom-Json }
    Assert-Equal (Test-CopilotStudioRegistration $config) $true
}

Test-Case 'MCP concurrent edits and concurrent new-file creation are never silently discarded' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    $path = Join-Path $directory 'mcp-config.json'
    try {
        $newFile = Read-McpUserConfig $path
        [IO.File]::WriteAllText($path, '{"changed":true}')
        Assert-Throws { Save-CopilotStudioConfig $path $newFile } 'was created while setup'
        $existing = Read-McpUserConfig $path
        [IO.File]::WriteAllText($path, '{"changed":2}')
        Assert-Throws { Save-CopilotStudioConfig $path $existing } 'changed while setup'
        Assert-Equal ([IO.File]::ReadAllText($path)) '{"changed":2}'
        Assert-Equal (@(Get-ChildItem -LiteralPath $directory -Filter '*.setup-tmp').Count) 0
    } finally { Remove-Item -LiteralPath $directory -Recurse -Force }
}

Test-Case 'Claude MCP registration uses user-scope CLI arguments and verifies the saved definition without launch' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    $script:claudeMcpFixturePath = Join-Path $directory '.claude.json'
    try {
        function Get-CopilotStudioConfigPath { $script:claudeMcpFixturePath }
        function Find-SetupExecutable { 'C:\fixture\claude.exe' }
        function Invoke-SetupNative {
            param($Path, $Arguments)
            Assert-Equal $Path 'C:\fixture\claude.exe'
            Assert-Equal ($Arguments -join ' ') 'mcp add --scope user --transport stdio copilot-studio -- npx -y @microsoft/copilot-studio-mcp@latest'
            [IO.File]::WriteAllText($script:claudeMcpFixturePath, '{"mcpServers":{"copilot-studio":{"type":"stdio","command":"npx","args":["-y","@microsoft/copilot-studio-mcp@latest"]}}}')
        }
        Assert-Equal (Invoke-CopilotStudioSetup -CopilotStudioHost ClaudeCode -AcceptCopilotStudio -NonInteractive) 0
        Remove-Item -LiteralPath $script:claudeMcpFixturePath
        function Invoke-SetupNative {}
        Assert-Throws { Invoke-CopilotStudioSetup -CopilotStudioHost ClaudeCode -AcceptCopilotStudio -NonInteractive } 'registration could not be verified'
    } finally { Remove-Item -LiteralPath $directory -Recurse -Force }
}

Test-Case 'connection skill opt-in is independent and rejected before prerequisite changes' {
    function Get-SetupArchitecture { throw 'SHOULD VALIDATE FIRST' }
    Assert-Equal (Invoke-Setup -NonInteractive -ConnectionSkillHost CopilotApp) 2
    Assert-Equal (Invoke-Setup -AcceptConnectionSkill) 2
    Assert-Equal (Invoke-Setup -ConnectionSkillHost Skip -AcceptConnectionSkill) 2
    Assert-Equal (Invoke-Setup -CheckOnly -ConnectionSkillHost CopilotCli -AcceptConnectionSkill) 2
}

Test-Case 'check-only never reads or writes user skill directories and the skip path prints next steps' {
    function Get-SetupArchitecture { 'arm64' }
    function Get-SetupState { New-TestState -Ready @('git','node','dotnet','pac') }
    function Get-ConnectionSkillDirectory { throw 'USER SKILL DIRECTORY ACCESS FORBIDDEN' }
    function Install-ConnectionSkill { throw 'SKILL WRITE FORBIDDEN' }
    function Read-Host { throw 'PROMPT FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    Assert-Equal (Invoke-Setup -CheckOnly -ConnectionSkillHost CopilotApp) 0
    $information = @()
    Assert-Equal (Invoke-ConnectionSkillSetup -NonInteractive -InformationVariable information) 0
    Assert-Equal (($information -join "`n").Contains('NEXT STEP:')) $true
    Assert-Equal (($information -join "`n").Contains('https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-connect/SKILL.md')) $true
    Assert-Equal (Invoke-ConnectionSkillSetup -ConnectionSkillHost Skip) 0
}

Test-Case 'skill installation follows integrations and keeps the desktop pending result' {
    $script:stageCalls = @()
    function Invoke-PluginSetup { $script:stageCalls += 'plugins'; 4 }
    function Invoke-CopilotStudioSetup { $script:stageCalls += 'mcp'; 0 }
    function Invoke-ConnectionSkillSetup { $script:stageCalls += 'skill'; 0 }
    Assert-Equal (Invoke-SetupIntegrations -NonInteractive) 4
    Assert-Equal ($script:stageCalls -join ',') 'plugins,mcp,skill'
    $script:stageCalls = @()
    function Invoke-CopilotStudioSetup { $script:stageCalls += 'mcp'; 2 }
    Assert-Equal (Invoke-SetupIntegrations -NonInteractive) 2
    Assert-Equal ($script:stageCalls -join ',') 'plugins,mcp'
}

Test-Case 'skill file installation is verified, idempotent and uses isolated destination only' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $source = Join-Path $root 'skills\power-platform-connect\SKILL.md'
    $destination = Join-Path $directory 'skills\power-platform-connect'
    try {
        function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
        function Start-Process { throw 'SERVER OR AUTH LAUNCH FORBIDDEN' }
        Install-ConnectionSkill $source $destination
        $target = Join-Path $destination 'SKILL.md'
        Assert-Equal (Get-FileHash $target -Algorithm SHA256).Hash (Get-FileHash $source -Algorithm SHA256).Hash
        $timestamp = (Get-Item $target).LastWriteTimeUtc
        Install-ConnectionSkill $source $destination
        Assert-Equal (Get-Item $target).LastWriteTimeUtc $timestamp
        Assert-Equal (@(Get-ChildItem (Split-Path -Parent $destination) -Directory -Filter '.setup-skill-*').Count) 0
    } finally { if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force } }
}

Test-Case 'different skill content and occupied directories are not overwritten' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    $source = Join-Path $root 'skills\power-platform-connect\SKILL.md'
    $destination = Join-Path $directory 'power-platform-connect'
    New-Item -ItemType Directory -Path $destination | Out-Null
    $target = Join-Path $destination 'SKILL.md'
    try {
        Assert-Throws { Install-ConnectionSkill $source $destination } 'will not overwrite'
        [IO.File]::WriteAllText($target, 'custom skill')
        Assert-Throws { Install-ConnectionSkill $source $destination } 'will not overwrite'
        Assert-Equal ([IO.File]::ReadAllText($target)) 'custom skill'
        Assert-Throws { Install-ConnectionSkill (Join-Path $directory 'missing.md') (Join-Path $directory 'new-skill') } 'Bundled connection skill is missing'
    } finally { Remove-Item -LiteralPath $directory -Recurse -Force }
}

Test-Case 'a linked skill destination is rejected without following its target' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $real = Join-Path $directory 'real'
    $linked = Join-Path $directory 'linked'
    New-Item -ItemType Directory -Path $real -Force | Out-Null
    New-Item -ItemType Junction -Path $linked -Target $real | Out-Null
    try {
        Assert-Throws { Install-ConnectionSkill (Join-Path $root 'skills\power-platform-connect\SKILL.md') (Join-Path $linked 'power-platform-connect') } 'linked directory'
        Assert-Equal (@(Get-ChildItem -LiteralPath $real -Force).Count) 0
    } finally {
        [IO.Directory]::Delete($linked)
        Remove-Item -LiteralPath $directory -Recurse -Force
    }
}

Test-Case 'skill staging never overwrites a concurrent install and cleans only its own staging directory' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $script:skillFixtureDestination = Join-Path $directory 'power-platform-connect'
    try {
        function Copy-Item {
            param($LiteralPath, $Destination)
            [IO.File]::Copy($LiteralPath, $Destination)
            New-Item -ItemType Directory -Path $script:skillFixtureDestination | Out-Null
            [IO.File]::WriteAllText((Join-Path $script:skillFixtureDestination 'SKILL.md'), 'concurrent skill')
        }
        Assert-Throws { Install-ConnectionSkill (Join-Path $root 'skills\power-platform-connect\SKILL.md') $script:skillFixtureDestination } 'Move'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $script:skillFixtureDestination 'SKILL.md'))) 'concurrent skill'
        Assert-Equal (@(Get-ChildItem -LiteralPath $directory -Directory -Filter '.setup-skill-*').Count) 0
    } finally { if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force } }
}

Test-Case 'interactive skill setup requires SKILL approval and uses the selected host only' {
    $script:skillAnswers = [System.Collections.Generic.Queue[string]]::new()
    foreach ($answer in @('3', 'SKILL')) { $script:skillAnswers.Enqueue($answer) }
    $script:skillInstallCalls = @()
    function Read-Host { $script:skillAnswers.Dequeue() }
    function Get-ConnectionSkillDirectory {
        param($HostName, $SkillName = 'power-platform-connect')
        Assert-Equal $HostName 'CopilotApp'
        "C:\fixture\$SkillName"
    }
    function Install-ConnectionSkill {
        param($Source, $Destination, $ExpectedSkillName = 'power-platform-connect')
        Assert-Equal (Test-Path -LiteralPath $Source -PathType Leaf) $true
        Assert-Equal $Destination "C:\fixture\$ExpectedSkillName"
        $script:skillInstallCalls += $ExpectedSkillName
    }
    Assert-Equal (Invoke-ConnectionSkillSetup) 0
    Assert-Equal ($script:skillInstallCalls -join ',') 'power-platform-connect,power-platform-router'
    function Read-Host { 'MCP' }
    Assert-Equal (Invoke-ConnectionSkillSetup -ConnectionSkillHost CopilotApp) 2
    Assert-Equal ($script:skillInstallCalls -join ',') 'power-platform-connect,power-platform-router'
}

Test-Case 'step 4 installs for each host in disposable profiles and survives a new process without touching real user skills' {
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $engine = (Get-Process -Id $PID).Path
    $connectSource = Join-Path $root 'skills\power-platform-connect\SKILL.md'
    $routerSource = Join-Path $root 'skills\power-platform-router\SKILL.md'
    $setup = Join-Path $root 'Setup.ps1'
    $installScript = @'
$ErrorActionPreference = 'Stop'
$env:USERPROFILE = '__PROFILE__'
$env:COPILOT_HOME = Join-Path $env:USERPROFILE '.copilot'
$env:CLAUDE_CONFIG_DIR = $null
. '__SETUP__'
function Invoke-SetupNative { throw 'CLI OR AUTH EXECUTION FORBIDDEN' }
function Find-SetupExecutable { throw 'HOST DISCOVERY FORBIDDEN' }
function Start-Process { throw 'SERVER OR AUTH LAUNCH FORBIDDEN' }
function Read-Host { throw 'PROMPT FORBIDDEN' }
$result = Invoke-ConnectionSkillSetup -ConnectionSkillHost '__HOST__' -AcceptConnectionSkill -NonInteractive
if ($result -ne 0) { throw "Skill installation failed: $result" }
'@
    try {
        foreach ($hostName in @('CopilotApp', 'CopilotCli', 'ClaudeCode')) {
            $profile = Join-Path $directory $hostName
            $script = $installScript.Replace('__PROFILE__', $profile.Replace("'", "''")).
                Replace('__SETUP__', $setup.Replace("'", "''")).Replace('__HOST__', $hostName)
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
            $output = & $engine -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Isolated $hostName skill install failed: $($output -join "`n")" }
            $hostDirectory = if ($hostName -eq 'ClaudeCode') { '.claude' } else { '.copilot' }
            $connectTarget = Join-Path $profile "$hostDirectory\skills\power-platform-connect\SKILL.md"
            $routerTarget = Join-Path $profile "$hostDirectory\skills\power-platform-router\SKILL.md"
            Assert-Equal (Get-FileHash -LiteralPath $connectTarget -Algorithm SHA256).Hash (Get-FileHash -LiteralPath $connectSource -Algorithm SHA256).Hash
            Assert-Equal (Get-FileHash -LiteralPath $routerTarget -Algorithm SHA256).Hash (Get-FileHash -LiteralPath $routerSource -Algorithm SHA256).Hash
            $connectTimestamp = (Get-Item -LiteralPath $connectTarget).LastWriteTimeUtc
            $routerTimestamp = (Get-Item -LiteralPath $routerTarget).LastWriteTimeUtc
            $output = & $engine -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Isolated $hostName skill rerun failed: $($output -join "`n")" }
            Assert-Equal (Get-Item -LiteralPath $connectTarget).LastWriteTimeUtc $connectTimestamp
            Assert-Equal (Get-Item -LiteralPath $routerTarget).LastWriteTimeUtc $routerTimestamp
            Assert-Equal (@(Get-ChildItem -LiteralPath $profile -Recurse -File -Force).Count) 2
        }
    } finally {
        if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
    }
    Assert-Equal (Test-Path -LiteralPath $directory) $false
}

Test-Case 'installed connection and router skills are standalone and router maps per-environment MCP servers cleanly' {
    foreach ($standaloneRelative in @('skills\power-platform-connect\SKILL.md', 'skills\power-platform-router\SKILL.md')) {
        $skill = Get-Content -LiteralPath (Join-Path $root $standaloneRelative) -Raw
        $blocks = [regex]::Matches($skill, '(?s)```powershell\s*\r?\n(.*?)\r?\n```')
        if (-not $blocks.Count) { throw "No PowerShell examples were found to validate in $standaloneRelative." }
        foreach ($block in $blocks) {
            $tokens = $null
            $errors = $null
            [Management.Automation.Language.Parser]::ParseInput($block.Groups[1].Value, [ref]$tokens, [ref]$errors) | Out-Null
            if ($errors.Count) { throw ($errors.Message -join '; ') }
        }
        # Only SKILL.md is installed. Relative references to unbundled files would break.
        foreach ($link in [regex]::Matches($skill, '\[[^\]]+\]\(([^)]+)\)')) {
            if ($link.Groups[1].Value -notmatch '^(https://|#)') {
                throw "Standalone skill $standaloneRelative references an unbundled file: $($link.Groups[1].Value)"
            }
        }
    }
    $connectSkill = Get-Content -LiteralPath (Join-Path $root 'skills\power-platform-connect\SKILL.md') -Raw
    $record = [regex]::Match($connectSkill, '(?s)```json\s*\r?\n(.*?)\r?\n```').Groups[1].Value | ConvertFrom-Json
    Assert-Equal $record.schemaVersion 1
    Assert-Equal ($record.PSObject.Properties.Name -contains 'azureConfigDir') $true
    Assert-Equal ($record.PSObject.Properties.Name -contains 'mcpServers') $true
    Assert-Equal (@($record.PSObject.Properties | Where-Object { $null -eq $_.Value }).Count) 0

    # Verify router open mcpServers map supports arbitrary future MCPs, zero null placeholders, and legacy records.
    $routerSkill = Get-Content -LiteralPath (Join-Path $root 'skills\power-platform-router\SKILL.md') -Raw
    $readerBlock = ([regex]::Matches($routerSkill, '(?s)```powershell\s*\r?\n(.*?)\r?\n```')[0]).Groups[1].Value
    $tokens = $null; $errors = $null
    $readerAst = [Management.Automation.Language.Parser]::ParseInput($readerBlock, [ref]$tokens, [ref]$errors)
    Assert-Equal $errors.Count 0
    $tempLocal = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $previousLocal = $env:LOCALAPPDATA
    try {
        $connDir = Join-Path $tempLocal 'PowerPlatformSetup\connections'
        New-Item -ItemType Directory -Path $connDir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $connDir 'env-x.json'), '{"schemaVersion":1,"alias":"env-x","environmentUrl":"https://envx.crm.dynamics.com","environmentId":"11111111-1111-1111-1111-111111111111","organizationId":"22222222-2222-2222-2222-222222222222","tenantId":"33333333-3333-3333-3333-333333333333","account":"maker@example.com","defaultSolution":"LaunchpadSolution","pacProfile":"env-x","dataverseProfile":"env-x","azureConfigDir":"C:\\fixture\\az-x","mcpServers":{"dataverse":"dataverse-env-x","flowagent":"flowagent-env-x","copilotStudio":"copilot-studio","canvas":"canvas-env-x"}}')
        [IO.File]::WriteAllText((Join-Path $connDir 'env-y.json'), '{"schemaVersion":1,"alias":"env-y","environmentUrl":"https://envy.crm.dynamics.com","environmentId":"44444444-4444-4444-4444-444444444444","organizationId":"55555555-5555-5555-5555-555555555555","tenantId":"33333333-3333-3333-3333-333333333333","account":"maker@example.com","pacProfile":"env-y","dataverseProfile":"env-y","azureConfigDir":"C:\\fixture\\az-x","mcpServers":{"dataverse":"dataverse-env-y","copilotStudio":"copilot-studio"}}')
        [IO.File]::WriteAllText((Join-Path $connDir 'z-legacy.json'), '{"schemaVersion":1,"alias":"legacy","environmentUrl":"https://legacy.crm.dynamics.com","environmentId":"66666666-6666-6666-6666-666666666666","organizationId":"77777777-7777-7777-7777-777777777777","tenantId":"33333333-3333-3333-3333-333333333333","account":"maker@example.com","dataverseMcpServer":"dataverse-legacy"}')
        $env:LOCALAPPDATA = $tempLocal
        $rows = @(& ($readerAst.GetScriptBlock()))
        Assert-Equal $rows.Count 3
        Assert-Equal $rows[0].Alias 'env-x'
        Assert-Equal $rows[0].DefaultSolution 'LaunchpadSolution'
        Assert-Equal $rows[0].McpServers.dataverse 'dataverse-env-x'
        Assert-Equal $rows[0].McpServers.flowagent 'flowagent-env-x'
        Assert-Equal $rows[0].McpServers.canvas 'canvas-env-x'
        Assert-Equal $rows[1].Alias 'env-y'
        Assert-Equal $rows[1].McpServers.dataverse 'dataverse-env-y'
        Assert-Equal ($null -eq $rows[1].McpServers.PSObject.Properties['flowagent']) $true
        Assert-Equal $rows[2].Alias 'legacy'
        Assert-Equal $rows[2].McpServers.dataverse 'dataverse-legacy'
    } finally {
        $env:LOCALAPPDATA = $previousLocal
        if (Test-Path -LiteralPath $tempLocal) { Remove-Item -LiteralPath $tempLocal -Recurse -Force }
    }
}

Test-Case 'connection Azure scope is restored across multiple environment records and failures with a mocked CLI' {
    $skill = Get-Content -LiteralPath (Join-Path $root 'skills\power-platform-connect\SKILL.md') -Raw
    $matches = @([regex]::Matches($skill, '(?s)```powershell\s*\r?\n(.*?)\r?\n```') |
        Where-Object { $_.Groups[1].Value -match '\$previousAzureConfigDir' })
    Assert-Equal $matches.Count 1
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($matches[0].Groups[1].Value, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors.Message -join '; ') }
    foreach ($command in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true)) {
        if ($command.GetCommandName() -ne 'az') {
            throw 'Azure example contains a command this isolated test does not mock. Review the test before executing it.'
        }
    }
    $example = $ast.GetScriptBlock()
    $connections = @(
        [pscustomobject]@{ alias = 'first-env'; azureConfigDir = 'C:\fixture\shared-tenant-cache' },
        [pscustomobject]@{ alias = 'second-env'; azureConfigDir = 'C:\fixture\shared-tenant-cache' },
        [pscustomobject]@{ alias = 'other-tenant-env'; azureConfigDir = 'C:\fixture\other-tenant-cache' })
    $previous = $env:AZURE_CONFIG_DIR
    $script:azureExampleCalls = 0
    function az {
        Assert-Equal $env:AZURE_CONFIG_DIR $connection.azureConfigDir
        Assert-Equal ($args -join ' ') 'account show --query {tenant:tenantId,user:user.name} --output json'
        $script:azureExampleCalls++
        if ($script:failAzureExample) { throw 'Mock authentication check failed' }
        '{"tenant":"fixture-tenant","user":"fixture-user"}'
    }
    try {
        foreach ($connection in $connections) {
            foreach ($inherited in @($null, 'C:\fixture\previous-azure-cache')) {
                foreach ($fail in @($false, $true)) {
                    $env:AZURE_CONFIG_DIR = $inherited
                    $script:failAzureExample = $fail
                    if ($fail) {
                        Assert-Throws { & $example } 'Mock authentication check failed'
                    } else { & $example | Out-Null }
                    Assert-Equal $env:AZURE_CONFIG_DIR $inherited
                }
            }
        }
        Assert-Equal $script:azureExampleCalls ($connections.Count * 4)
    } finally { $env:AZURE_CONFIG_DIR = $previous }
}

Test-Case 'Node maintenance proposes only published, active stable LTS majors and flags existing EOL versions' {
    . (Join-Path $root 'scripts\Update-NodeSupport.ps1')
    $releases = @(
        [pscustomobject]@{ version = 'v28.10.0'; date = '2028-11-01'; lts = 'Fixture' },
        [pscustomobject]@{ version = 'v28.11.0'; date = '2028-11-02'; lts = 'Fixture' },
        [pscustomobject]@{ version = 'v30.0.0-rc.1'; date = '2028-11-01'; lts = 'Fixture' },
        [pscustomobject]@{ version = 'v29.0.0'; date = '2028-11-01'; lts = $false },
        [pscustomobject]@{ version = 'v32.0.0'; date = '2028-11-01'; lts = 'Fixture' },
        [pscustomobject]@{ version = 'v34.0.0'; date = '2028-11-01'; lts = 'Fixture' },
        [pscustomobject]@{ version = 'v36.0.0'; date = '2028-12-01'; lts = 'Fixture' })
    $schedule = @'
{
  "v22": {"start":"2024-04-24","lts":"2024-10-29","end":"2027-04-30"},
  "v24": {"start":"2025-05-06","lts":"2025-10-28","end":"2028-04-30"},
  "v26": {"start":"2026-05-05","lts":"2026-10-28","end":"2029-04-30"},
  "v28": {"start":"2028-05-01","lts":"2028-10-28","end":"2031-04-30"},
  "v32": {"start":"2028-05-01","lts":"2028-12-01","end":"2031-04-30"},
  "v34": {"start":"2026-05-01","lts":"2026-10-28","end":"2028-11-17"}
}
'@ | ConvertFrom-Json
    $proposal = Get-NodeSupportProposal -CurrentMajors @(22,24,26) -Releases $releases -Schedule $schedule -AsOf ([datetime]'2028-11-17')
    Assert-Equal ($proposal.AddedMajors -join ',') '28'
    Assert-Equal ($proposal.ProposedMajors -join ',') '22,24,26,28'
    Assert-Equal ($proposal.EndOfLifeMajors -join ',') '22,24'
    Assert-Equal $proposal.Changed $true
}

Test-Case 'Node maintenance fails closed on empty, missing or malformed support metadata' {
    . (Join-Path $root 'scripts\Update-NodeSupport.ps1')
    $releases = @([pscustomobject]@{ version = 'v28.10.0'; date = '2028-11-01'; lts = 'Fixture' })
    $schedule = '{"v28":{"start":"2028-05-01","lts":"2028-10-28","end":"2031-04-30"}}' | ConvertFrom-Json
    Assert-Throws { Get-NodeSupportProposal -CurrentMajors @(28) -Releases @() -Schedule $schedule } 'empty'
    Assert-Throws { Get-NodeSupportProposal -CurrentMajors @(28) -Releases $releases -Schedule ([pscustomobject]@{}) } 'no LTS entry'
    $schedule.v28.lts = 'not-a-date'
    Assert-Throws { Get-NodeSupportProposal -CurrentMajors @(28) -Releases $releases -Schedule $schedule } 'invalid release/support date'
    $schedule.v28.lts = '2032-01-01'
    Assert-Throws { Get-NodeSupportProposal -CurrentMajors @(28) -Releases $releases -Schedule $schedule } 'date ordering'
    Assert-Throws { Get-NodeSupportMajors 'unexpected source structure' } 'Expected one literal'
}

Test-Case 'Node maintenance preview uses fixed metadata sources without writing or installing' {
    . (Join-Path $root 'scripts\Update-NodeSupport.ps1')
    $majors = @(Get-NodeSupportMajors ([IO.File]::ReadAllText((Join-Path $root 'Setup.ps1'))))
    $script:maintenanceSchedule = [pscustomobject]@{}
    $script:maintenanceReleases = @()
    foreach ($major in $majors) {
        $script:maintenanceSchedule | Add-Member -NotePropertyName "v$major" -NotePropertyValue ([pscustomobject]@{
            start = [datetime]::UtcNow.AddYears(-2).ToString('yyyy-MM-dd')
            lts = [datetime]::UtcNow.AddYears(-1).ToString('yyyy-MM-dd')
            end = [datetime]::UtcNow.AddYears(2).ToString('yyyy-MM-dd')
        })
        $script:maintenanceReleases += [pscustomobject]@{
            version = "v$major.0.0"; date = [datetime]::UtcNow.AddDays(-1).ToString('yyyy-MM-dd'); lts = 'Fixture'
        }
    }
    $script:metadataCalls = @()
    function Invoke-RestMethod {
        param($Uri, $TimeoutSec)
        $script:metadataCalls += $Uri
        switch ($Uri) {
            'https://nodejs.org/dist/index.json' { return $script:maintenanceReleases }
            'https://raw.githubusercontent.com/nodejs/Release/main/schedule.json' { return $script:maintenanceSchedule }
            default { throw 'UNEXPECTED NETWORK DESTINATION' }
        }
    }
    function Update-NodeSupportFiles { throw 'WRITE FORBIDDEN' }
    function Invoke-SetupNative { throw 'CLI FORBIDDEN' }
    function Start-Process { throw 'PROCESS FORBIDDEN' }
    $proposal = Invoke-NodeSupportMaintenance -Root $root
    Assert-Equal $proposal.Changed $false
    Assert-Equal $script:metadataCalls.Count 2
}

Test-Case 'Node maintenance updates only guarded source, docs and cases and the proposed runtime accepts new majors' {
    . (Join-Path $root 'scripts\Update-NodeSupport.ps1')
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $files = @('Setup.ps1', 'README.md', 'docs\advanced-setup.md', 'scripts\Test-Setup.ps1')
    try {
        foreach ($file in $files) {
            $path = Join-Path $temporary $file
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $root $file) -Destination $path
        }
        $current = @(Get-NodeSupportMajors ([IO.File]::ReadAllText((Join-Path $temporary 'Setup.ps1'))))
        $next = ($current | Measure-Object -Maximum).Maximum + 2
        $proposal = [pscustomobject]@{
            Changed = $true; CurrentMajors = [int[]]$current
            AddedMajors = [int[]]@($next, ($next + 2)); ProposedMajors = [int[]]@($current + $next + ($next + 2))
        }
        $original = [IO.File]::ReadAllText((Join-Path $temporary 'Setup.ps1'))
        $readmePath = Join-Path $temporary 'README.md'
        $readme = [IO.File]::ReadAllText($readmePath)
        [IO.File]::WriteAllText($readmePath, 'unexpected documentation structure')
        Assert-Throws { Update-NodeSupportFiles -Root $temporary -Proposal $proposal } 'Expected one compatibility marker'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $temporary 'Setup.ps1'))) $original
        [IO.File]::WriteAllText($readmePath, $readme)
        Update-NodeSupportFiles -Root $temporary -Proposal $proposal
        $updated = [IO.File]::ReadAllText((Join-Path $temporary 'Setup.ps1'))
        Assert-Equal ((Get-NodeSupportMajors $updated) -join ',') ($proposal.ProposedMajors -join ',')
        foreach ($file in $files) {
            $text = [IO.File]::ReadAllText((Join-Path $temporary $file))
            if ($file -ne 'scripts\Test-Setup.ps1') {
                Assert-Equal ($text.Contains((Format-NodeSupportLabel $proposal.ProposedMajors))) $true
            } else {
                foreach ($major in $proposal.AddedMajors) {
                    Assert-Equal ($text.Contains("Version = '${major}.0.0'; Npm = '11.20.0'; Ready = " + '$true')) $true
                }
            }
            if ($file.EndsWith('.ps1')) {
                $tokens = $null; $errors = $null
                [Management.Automation.Language.Parser]::ParseFile((Join-Path $temporary $file), [ref]$tokens, [ref]$errors) | Out-Null
                Assert-Equal $errors.Count 0
            }
        }
        Update-NodeSupportFiles -Root $temporary -Proposal ([pscustomobject]@{ Changed = $false })
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $temporary 'Setup.ps1'))) $updated
        . (Join-Path $temporary 'Setup.ps1')
        function Get-SetupArchitecture { 'x64' }
        function Find-SetupExecutable { param($Name, $Candidates) "C:\fixture\$Name" }
        function Get-ExecutableArchitecture { 'x64' }
        function Get-BinaryVersion { [version]"$next.0.0" }
        function Test-Path { $true }
        function Get-Content { '{"version":"11.20.0"}' }
        function Get-ChildItem {}
        Assert-Equal (Get-SetupState | Where-Object Id -eq 'node').Ready $true
    } finally {
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
}

Test-Case 'skill command examples parse without executing plugin or prerequisite installation' {
    foreach ($skillRelative in @(
        'skills\power-platform-setup\SKILL.md',
        'skills\power-platform-router\SKILL.md',
        '.github\skills\power-platform-setup\SKILL.md',
        '.claude\skills\power-platform-setup\SKILL.md')) {
        $text = Get-Content -LiteralPath (Join-Path $root $skillRelative) -Raw
        Assert-Equal ($text -match '(?s)^---\s*\r?\nname: [a-z0-9-]+\r?\ndescription: [^\r\n]+\r?\n---') $true
        foreach ($block in [regex]::Matches($text, '(?s)```powershell\r?\n(.*?)```')) {
            $tokens = $null; $errors = $null
            [Management.Automation.Language.Parser]::ParseInput($block.Groups[1].Value, [ref]$tokens, [ref]$errors) | Out-Null
            Assert-Equal $errors.Count 0
        }
    }
}

Test-Case 'public documentation resolves all local links and screenshot files' {
    foreach ($relative in @('README.md', 'AGENTS.md', 'CLAUDE.md',
        'docs\advanced-setup.md', 'docs\media-bank.md',
        'skills\power-platform-setup\SKILL.md',
        '.github\skills\power-platform-setup\SKILL.md',
        '.claude\skills\power-platform-setup\SKILL.md')) {
        $path = Join-Path $root $relative
        $text = Get-Content -LiteralPath $path -Raw
        foreach ($match in [regex]::Matches($text, '\[[^\]]*\]\(([^)]+)\)')) {
            $target = $match.Groups[1].Value
            if ($target -match '^(https?://|#)') { continue }
            $file = ($target -split '#')[0].Replace('/', '\')
            $resolved = Join-Path (Split-Path -Parent $path) $file
            if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
                throw "Broken local documentation link in ${relative}: $target"
            }
        }
    }
}

Test-Case 'release packaging and gitattributes exclude screenshot media from ZIP downloads' {
    $releaseScript = Get-Content -LiteralPath (Join-Path $root 'scripts\New-Release.ps1') -Raw
    Assert-Equal ($releaseScript -notmatch '\.(png|jpg|jpeg|gif|webp|mp4)') $true
    $attributes = Get-Content -LiteralPath (Join-Path $root '.gitattributes') -Raw
    Assert-Equal ($attributes -match '(?m)^docs/media-bank/\*\.png\s+export-ignore\r?$') $true
    Assert-Equal ($attributes -match '(?m)^docs/media-bank/\*\.webp\s+export-ignore\r?$') $true
    Assert-Equal (Test-Path -LiteralPath (Join-Path $root 'docs\images')) $false
}

Test-Case 'launcher forwards arguments to the same script and preserves exit code' {
    $launcher = Get-Content -LiteralPath (Join-Path $root 'Setup.cmd') -Raw
    Assert-Equal ($launcher.Contains('-File "%~dp0Setup.ps1" %*')) $true
    Assert-Equal ($launcher.Contains('exit /b %setup_exit%')) $true
}

Write-Host "`n$passed passed; $failures failed."
if ($failures) { exit 1 }
