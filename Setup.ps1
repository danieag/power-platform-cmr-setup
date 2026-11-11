#requires -Version 5.1
<#
.SYNOPSIS
Checks and, only with approval, installs local Power Platform prerequisites and offers host-aware plugin setup.
.EXAMPLE
.\Setup.ps1 -CheckOnly
.EXAMPLE
.\Setup.ps1 -Install -Accept -NonInteractive
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Install,
    [switch]$Accept,
    [switch]$NonInteractive,
    [switch]$IncludeAzureCli,
    [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$PluginHost,
    [switch]$IncludeDataverse,
    [switch]$AcceptPlugins
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SetupArchitecture {
    if ($env:OS -ne 'Windows_NT') { throw 'This installer supports Windows only.' }
    # Machine registry is authoritative even when PowerShell itself runs under emulation.
    $native = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name PROCESSOR_ARCHITECTURE
    switch ($native) {
        'AMD64' { $architecture = 'x64' }
        'ARM64' { $architecture = 'arm64' }
        default { throw 'This release supports x64 and ARM64 Windows only, not 32-bit Windows.' }
    }
    if (-not [Environment]::Is64BitProcess) {
        throw 'Open 64-bit Windows PowerShell or PowerShell and run setup again.'
    }
    $build = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber
    if ([int]$build -lt 19045 -or ($architecture -eq 'arm64' -and [int]$build -lt 22000)) {
        throw 'Use Windows 11 on ARM64, or vendor-supported x64 Windows 11 / Windows 10 22H2 (build 19045 or newer).'
    }
    return $architecture
}

function Get-ExecutableArchitecture {
    param([AllowNull()][string]$Path)
    if (-not $Path) { return $null }
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { return 'unknown' }
        $stream.Position = 0x3C
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 6)) { return 'unknown' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { return 'unknown' }
        switch ($reader.ReadUInt16()) {
            0x8664 { return 'x64' }
            0xAA64 { return 'arm64' }
            0xA641 { return 'arm64' }
            0xA64E { return 'arm64' }
            0x014C { return 'x86' }
            default { return 'unknown' }
        }
    } finally { $reader.Dispose() }
}

function Test-ExecutableArchitecture {
    param([AllowNull()][string]$Actual, [string]$WindowsArchitecture)
    if ($WindowsArchitecture -eq 'arm64') { return $Actual -in @('arm64', 'x64', 'x86') }
    return $Actual -in @('x64', 'x86')
}

function ConvertTo-ToolVersion {
    param([AllowEmptyString()][string]$Text)
    if ($Text -match '(?<!\d)(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return $null
}

function Find-SetupExecutable {
    param([string]$Name, [string[]]$Candidates = @())
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return $null
}

function Get-BinaryVersion {
    param([AllowNull()][string]$Path)
    if (-not $Path) { return $null }
    return ConvertTo-ToolVersion (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion
}

function New-ToolState {
    param([string]$Id, [string]$Name, $Version, [bool]$Ready, [string]$Path, [string]$Requirement, [string]$Architecture)
    [pscustomobject]@{
        Id = $Id; Name = $Name; Version = $Version; Ready = $Ready
        Path = $Path; Requirement = $Requirement; Architecture = $Architecture
    }
}

function Get-SetupState {
    param([switch]$Azure, [ValidateSet('x64', 'arm64')][string]$Architecture = (Get-SetupArchitecture))
    # Read files/registry only: even first-run CLI initialization is excluded.
    $git = Find-SetupExecutable 'git.exe' @(
        "$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
    $version = Get-BinaryVersion $git
    $binaryArchitecture = Get-ExecutableArchitecture $git
    $compatible = Test-ExecutableArchitecture $binaryArchitecture $Architecture
    New-ToolState 'git' 'Git' $version ($compatible -and $null -ne $version -and $version -ge [version]'2.40.0') $git 'Git >= 2.40' $binaryArchitecture

    $node = Find-SetupExecutable 'node.exe' @("$env:ProgramFiles\nodejs\node.exe")
    $version = Get-BinaryVersion $node
    $npmVersion = $null
    if ($node) {
        $nodeRoot = Split-Path -Parent $node
        $npm = Join-Path $nodeRoot 'npm.cmd'
        $npmManifest = Join-Path $nodeRoot 'node_modules\npm\package.json'
        if ((Test-Path -LiteralPath $npm -PathType Leaf) -and (Test-Path -LiteralPath $npmManifest -PathType Leaf)) {
            $npmVersion = ConvertTo-ToolVersion ((Get-Content -LiteralPath $npmManifest -Raw | ConvertFrom-Json).version)
        }
    }
    $nodeSupported = $null -ne $version -and
        (($version.Major -eq 22 -and $version -ge [version]'22.18.0') -or $version.Major -eq 24)
    $binaryArchitecture = Get-ExecutableArchitecture $node
    $ready = $nodeSupported -and (Test-ExecutableArchitecture $binaryArchitecture $Architecture) -and
        $null -ne $npmVersion -and $npmVersion -ge [version]'10.0.0'
    New-ToolState 'node' "Node.js / npm ($npmVersion)" $version $ready $node 'Node 22.18+ or 24 LTS with bundled npm >= 10' $binaryArchitecture

    $dotnet = Find-SetupExecutable 'dotnet.exe' @(
        "$env:ProgramFiles\dotnet\dotnet.exe", "$env:ProgramFiles\dotnet\x64\dotnet.exe")
    $dotnetArchitecture = Get-ExecutableArchitecture $dotnet
    $sdk = $null
    if ($dotnet) {
        $sdkRoot = Join-Path (Split-Path -Parent $dotnet) 'sdk'
        if (Test-Path -LiteralPath $sdkRoot -PathType Container) {
            $sdk = Get-ChildItem -LiteralPath $sdkRoot -Directory |
                Where-Object { $_.Name -match '^10\.0\.\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'dotnet.dll')) } |
                ForEach-Object { [version]$_.Name } | Sort-Object -Descending | Select-Object -First 1
        }
    }
    $sdkReady = $null -ne $sdk -and (Test-ExecutableArchitecture $dotnetArchitecture $Architecture)
    New-ToolState 'dotnet' '.NET SDK' $sdk $sdkReady $dotnet '.NET 10.0 stable SDK (not just runtime)' $dotnetArchitecture

    $pac = Find-SetupExecutable 'pac.exe' @("$env:USERPROFILE\.dotnet\tools\pac.exe")
    $version = Get-BinaryVersion $pac
    $binaryArchitecture = Get-ExecutableArchitecture $pac
    $ready = $sdkReady -and $binaryArchitecture -eq $dotnetArchitecture -and
        $null -ne $version -and $version -ge [version]'1.0.0'
    New-ToolState 'pac' 'Power Platform CLI' $version $ready $pac 'PAC >= 1.0 with a shim matching the selected .NET architecture' $binaryArchitecture

    if ($Azure) {
        $az = Find-SetupExecutable 'az.cmd' @(
            "$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
            "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\CLI2\wbin\az.cmd")
        $version = $null
        foreach ($key in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
            if (Test-Path $key) {
                $entry = Get-ItemProperty $key | Where-Object {
                    $_.PSObject.Properties['DisplayName'] -and
                        $_.DisplayName -match '^Microsoft Azure CLI(?: \((?:32|64)-bit\))?$'
                } | Select-Object -First 1
                if ($entry -and $entry.PSObject.Properties['DisplayVersion']) {
                    $version = ConvertTo-ToolVersion $entry.DisplayVersion
                    if ($version) { break }
                }
            }
        }
        $azArchitecture = $null
        if ($az) {
            $python = Join-Path (Split-Path -Parent (Split-Path -Parent $az)) 'python.exe'
            if (Test-Path -LiteralPath $python -PathType Leaf) { $azArchitecture = Get-ExecutableArchitecture $python }
        }
        $ready = $null -ne $az -and $null -ne $version -and $version -ge [version]'2.60.0' -and
            (Test-ExecutableArchitecture $azArchitecture $Architecture)
        New-ToolState 'azure' 'Azure CLI' $version $ready $az 'Azure CLI MSI >= 2.60 (optional; x64 emulation on ARM64)' $azArchitecture
    }
}

function Show-SetupState {
    param([object[]]$State)
    Write-Host "`nLocal prerequisite readiness (no tenant access):"
    foreach ($tool in $State) {
        $status = if ($tool.Ready) { 'READY' } else { 'NEEDS SETUP' }
        $detected = if ($tool.Version) { $tool.Version.ToString() } else { 'not detected / unrecognized' }
        Write-Host ("  [{0}] {1}: {2}" -f $status, $tool.Name, $detected)
        Write-Host "    Required: $($tool.Requirement)"
        if ($tool.Path) { Write-Host "    Found: $($tool.Path)" }
        if ($tool.Architecture) { Write-Host "    Executable architecture: $($tool.Architecture)" }
    }
    Write-Host "`nDesktop plugins: NOT VERIFIED. Configure separately in the Copilot app; see README."
    Write-Host 'Authentication / environment permissions: NOT CHECKED. Setup never signs you in.'
    Write-Host 'Azure CLI is optional; use -IncludeAzureCli for workflows that require it.'
}

function Update-SetupPath {
    # Preserve inherited process entries, then append newly registered and known locations.
    $paths = @($env:PATH -split ';') +
        @([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';') +
        @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') +
        @("$env:LOCALAPPDATA\Programs\Git\cmd", "$env:ProgramFiles\Git\cmd",
          "$env:ProgramFiles\nodejs", "$env:ProgramFiles\dotnet",
          "$env:USERPROFILE\.dotnet\tools", "$env:ProgramFiles\Microsoft SDKs\Azure\CLI2\wbin")
    $unique = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $paths) {
        if ($path) {
            $expanded = [Environment]::ExpandEnvironmentVariables($path.Trim())
            if (-not $unique.Contains($expanded)) { $unique.Add($expanded) }
        }
    }
    $env:PATH = $unique -join ';'
}

function Assert-OfficialUrl {
    param([string]$Url)
    $uri = [uri]$Url
    $allowed = @('api.github.com', 'github.com', 'nodejs.org',
        'dotnetcli.blob.core.windows.net', 'builds.dotnet.microsoft.com',
        'download.visualstudio.microsoft.com', 'aka.ms')
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or
        $uri.Host -notin $allowed -or $uri.UserInfo -or -not $uri.IsDefaultPort) {
        throw "Refusing an installer source outside the built-in official HTTPS allowlist: $Url"
    }
}

function Get-OfficialJson {
    param([string]$Url)
    Assert-OfficialUrl $Url
    Invoke-RestMethod -Uri $Url -Headers @{ 'User-Agent' = 'power-platform-setup' } -TimeoutSec 60
}

function Get-InstallerSpec {
    param(
        [ValidateSet('git', 'node', 'dotnet', 'azure')][string]$Id,
        [ValidateSet('x64', 'arm64')][string]$Architecture = (Get-SetupArchitecture)
    )
    switch ($Id) {
        'git' {
            $release = Get-OfficialJson 'https://api.github.com/repos/git-for-windows/git/releases/latest'
            $suffix = if ($Architecture -eq 'arm64') { 'arm64' } else { '64-bit' }
            $asset = @($release.assets | Where-Object { $_.name -match "^Git-[\d.]+-$suffix\.exe$" })
            if ($asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
                throw "Git release metadata has no unique $Architecture installer with SHA256 digest. No installer was run."
            }
            $hash = $Matches[1]
            return @{ Url = $asset[0].browser_download_url; File = 'git.exe'; Hash = $hash
                Algorithm = 'SHA256'; Publisher = $null; Admin = $false
                Arguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=`"$env:LOCALAPPDATA\Programs\Git`"" }
        }
        'node' {
            $releases = Get-OfficialJson 'https://nodejs.org/dist/index.json'
            $release = $releases | Where-Object { $_.version -match '^v24\.\d+\.\d+$' -and $_.lts } |
                Select-Object -First 1
            if (-not $release) { throw 'Official metadata contains no stable Node 24 LTS release.' }
            $file = "node-$($release.version)-$Architecture.msi"
            $base = "https://nodejs.org/dist/$($release.version)"
            $checksums = (Invoke-WebRequest -UseBasicParsing -Uri "$base/SHASUMS256.txt" -TimeoutSec 60).Content
            $pattern = '(?m)^([a-fA-F0-9]{64})\s+' + [regex]::Escape($file) + '\s*$'
            if ($checksums -notmatch $pattern) { throw "No SHA256 checksum found for the Node $Architecture MSI." }
            return @{ Url = "$base/$file"; File = 'node.msi'; Hash = $Matches[1]
                Algorithm = 'SHA256'; Publisher = 'OpenJS Foundation|Node\.js Foundation'; Admin = $true
                Arguments = '/qn /norestart' }
        }
        'dotnet' {
            $metadata = Get-OfficialJson 'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/10.0/releases.json'
            $release = $metadata.releases | Where-Object { $_.sdk.version -eq $metadata.'latest-sdk' } |
                Select-Object -First 1
            $asset = @($release.sdk.files | Where-Object { $_.rid -eq "win-$Architecture" -and $_.name -like '*.exe' })
            if ($asset.Count -ne 1 -or $asset[0].hash -notmatch '^[a-fA-F0-9]{128}$') {
                throw "No unique .NET 10 $Architecture SDK installer with SHA512 checksum was found."
            }
            return @{ Url = $asset[0].url; File = 'dotnet.exe'; Hash = $asset[0].hash
                Algorithm = 'SHA512'; Publisher = 'Microsoft Corporation'; Admin = $true
                Arguments = '/install /quiet /norestart' }
        }
        'azure' {
            return @{ Url = 'https://aka.ms/installazurecliwindowsx64'; File = 'azure.msi'
                Hash = $null; Algorithm = $null; Publisher = 'Microsoft Corporation'; Admin = $true
                Arguments = '/qn /norestart' }
        }
    }
}

function Assert-InstallerIntegrity {
    param([string]$Path, [hashtable]$Spec)
    if ($Spec.Hash) {
        $actual = (Get-FileHash -LiteralPath $Path -Algorithm $Spec.Algorithm).Hash
        if ($actual -ne $Spec.Hash) { throw "Checksum mismatch for $($Spec.File). No installer was run." }
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid') {
        throw "Invalid/untrusted Authenticode signature on $($Spec.File): $($signature.Status). No installer was run."
    }
    if ($Spec.Publisher -and $signature.SignerCertificate.Subject -notmatch $Spec.Publisher) {
        throw "Unexpected signer on $($Spec.File). No installer was run."
    }
}

function Invoke-VerifiedInstaller {
    param([string]$Path, [hashtable]$Spec)
    $arguments = $Spec.Arguments
    if ([IO.Path]::GetExtension($Path) -eq '.msi') {
        $executable = "$env:SystemRoot\System32\msiexec.exe"
        $arguments = "/i `"$Path`" $arguments"
    } else { $executable = $Path }
    $parameters = @{ FilePath = $executable; ArgumentList = $arguments; Wait = $true; PassThru = $true }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($Spec.Admin -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $parameters.Verb = 'RunAs'
        Write-Host 'Windows will ask for administrator approval for this prerequisite only.'
    }
    $process = Start-Process @parameters
    if ($process.ExitCode -notin @(0, 1641, 3010)) {
        throw "Installer failed with exit code $($process.ExitCode). Resolve Windows Installer/UAC or policy issues, then rerun."
    }
    return ($process.ExitCode -in @(1641, 3010))
}

function Invoke-SetupNative {
    param([string]$Path, [string[]]$Arguments)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "The expected executable is missing: $Path"
    }
    # Capture stderr without PowerShell 5.1 turning benign native stderr into a terminating error.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    # Native processes update the global value, not a local variable with the same name.
    # A sentinel also catches failure to start, while exit 0 with stderr remains success.
    $global:LASTEXITCODE = -1
    $output = & $Path @Arguments 2>&1
    $exitCode = $global:LASTEXITCODE
    if ($exitCode -ne 0) {
        # Do not echo raw CLI output, which can include private feed configuration.
        throw "Command '$([IO.Path]::GetFileName($Path)) $($Arguments -join ' ')' failed (exit $exitCode). Check connectivity, policy, and package sources."
    }
    return ($output -join "`n")
}

function Install-PacTool {
    $sdk = Get-SetupState | Where-Object Id -eq 'dotnet'
    if (-not $sdk.Ready) { throw '.NET SDK is not discoverable; open a new terminal and rerun setup.' }
    $dotnet = $sdk.Path
    # Run outside the repository so a project global.json/NuGet.Config cannot select the SDK/feed.
    $working = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $working | Out-Null
    Push-Location $working
    try {
        $config = Join-Path $working 'NuGet.Config'
        @'
<?xml version="1.0" encoding="utf-8"?>
<configuration><packageSources><clear /><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources></configuration>
'@ | Set-Content -LiteralPath $config -Encoding UTF8
        $tools = Invoke-SetupNative $dotnet @('tool', 'list', '--global')
        $verb = if ($tools -match '(?im)^microsoft\.powerapps\.cli\.tool\s') { 'update' } else { 'install' }
        $arguments = @('tool', $verb, '--global', 'Microsoft.PowerApps.CLI.Tool', '--configfile', $config)
        if ($verb -eq 'install') { $arguments += @('--arch', $sdk.Architecture) }
        Invoke-SetupNative $dotnet $arguments | Out-Null
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $working -Recurse -Force
    }
}

function Confirm-InstalledTool {
    param([string]$Id, [object[]]$State)
    $tool = $State | Where-Object Id -eq $Id
    if (-not $tool -or -not $tool.Ready) {
        throw "The $Id installer completed, but a compatible installation is not discoverable. Restart the terminal/Copilot app and rerun -CheckOnly. An older PATH entry may be shadowing it."
    }
    switch ($Id) {
        'git' { $output = Invoke-SetupNative $tool.Path @('--version'); $expected = $tool.Version }
        'node' {
            $output = Invoke-SetupNative $tool.Path @('--version'); $expected = $tool.Version
            $npm = Join-Path (Split-Path -Parent $tool.Path) 'npm.cmd'
            $npmVersion = ConvertTo-ToolVersion (Invoke-SetupNative $npm @('--version'))
            if (-not $npmVersion -or $npmVersion -lt [version]'10.0.0') { throw 'npm version verification failed.' }
        }
        'dotnet' {
            $output = Invoke-SetupNative $tool.Path @('--list-sdks')
            if ($output -notmatch '(?m)^10\.0\.\d+\s') { throw '.NET 10 SDK runtime verification failed.' }
            return
        }
        'pac' { $output = Invoke-SetupNative $tool.Path @(); $expected = $tool.Version }
        'azure' {
            $output = Invoke-SetupNative $tool.Path @('version', '--output', 'json')
            $actual = ConvertTo-ToolVersion (($output | ConvertFrom-Json).'azure-cli')
            if (-not $actual -or $actual -lt [version]'2.60.0') { throw 'Azure CLI version verification failed.' }
            return
        }
    }
    if ((ConvertTo-ToolVersion $output) -ne $expected) { throw "$Id executable version verification failed." }
}

function Install-SetupTool {
    param([string]$Id)
    if ($Id -eq 'pac') { Install-PacTool; return $false }
    $spec = Get-InstallerSpec $Id
    Assert-OfficialUrl $spec.Url
    $working = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $working | Out-Null
    try {
        $path = Join-Path $working $spec.File
        Write-Host "Downloading from $($spec.Url)"
        Invoke-WebRequest -UseBasicParsing -Uri $spec.Url -OutFile $path -TimeoutSec 600
        Assert-InstallerIntegrity $path $spec
        return Invoke-VerifiedInstaller $path $spec
    } finally {
        Remove-Item -LiteralPath $working -Recurse -Force
    }
}

function Get-SetupPluginNames {
    param([switch]$IncludeDataverse)
    # Reviewed official catalog: adding future plugins requires a deliberate release.
    @('power-pages', 'model-apps', 'canvas-apps', 'code-apps-preview', 'mobile-app',
      'power-apps-mobile-extension', 'power-automate', 'process-intelligence', 'pcf', 'mcp-apps')
    if ($IncludeDataverse) { 'dataverse' }
}

function Get-PluginProperty {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

function Read-PluginJson {
    param([string]$Path, [string[]]$Arguments)
    $text = Invoke-SetupNative $Path $Arguments
    if (-not $text.Trim().StartsWith('[') -or -not $text.Trim().EndsWith(']')) {
        throw 'Unsupported plugin CLI output: expected a JSON array. Check the installed CLI version; no text-output fallback is used.'
    }
    try { $rows = $text | ConvertFrom-Json } catch {
        throw 'The plugin CLI returned invalid JSON. Inspect its configuration privately; raw output is not logged.'
    }
    foreach ($row in $rows) {
        if ($null -eq $row -or $row -isnot [pscustomobject]) {
            throw 'Unsupported plugin CLI listing entry. Check the installed CLI version.'
        }
        $row
    }
}

function Get-PluginInventory {
    param([string]$Path, [string]$PluginHost)
    foreach ($row in @(Read-PluginJson $Path @('plugin', 'list', '--json'))) {
        $id = Get-PluginProperty $row 'id'
        if ($PluginHost -eq 'CopilotCli') {
            $id = Get-PluginProperty $row 'name'
            $marketplace = Get-PluginProperty $row 'marketplace'
            if ($id -is [string] -and $id -notmatch '@' -and $marketplace) { $id += "@$marketplace" }
        }
        $enabled = Get-PluginProperty $row 'enabled'
        if ($id -isnot [string] -or $id -notmatch '^[a-z0-9][a-z0-9.-]*(?:@[a-z0-9][a-z0-9.-]*)?$' -or
            $enabled -isnot [bool]) {
            throw 'Unsupported plugin identity/status fields. Check the installed CLI version before retrying.'
        }
        [pscustomobject]@{
            Id = $id; Name = ($id -split '@')[0]; Enabled = $enabled
            Scope = Get-PluginProperty $row 'scope'
            Errors = Get-PluginProperty $row 'errors'
        }
    }
}

function Assert-OfficialMarketplace {
    param([object[]]$Marketplaces)
    foreach ($row in $Marketplaces) {
        if ((Get-PluginProperty $row 'name') -isnot [string]) {
            throw 'Unsupported marketplace listing fields. Check the installed CLI version.'
        }
    }
    $matching = @($Marketplaces | Where-Object { $_.name -eq 'power-platform-skills' })
    if ($matching.Count -eq 0) { return $false }
    if ($matching.Count -ne 1) { throw 'Multiple power-platform-skills marketplaces found; resolve the conflict manually.' }
    $row = $matching[0]
    $source = Get-PluginProperty $row 'source'
    $repo = Get-PluginProperty $row 'repo'
    $url = Get-PluginProperty $row 'url'
    if ($source -is [pscustomobject]) {
        $repo = Get-PluginProperty $source 'repo'
        $url = Get-PluginProperty $source 'url'
        $kind = Get-PluginProperty $source 'source'
        if (-not $kind) { $kind = Get-PluginProperty $source 'type' }
        $source = $kind
    }
    $official = @('microsoft/power-platform-skills', 'https://github.com/microsoft/power-platform-skills',
        'https://github.com/microsoft/power-platform-skills.git')
    if ($source -in $official -or ($source -eq 'github' -and $repo -eq $official[0]) -or
        ($source -in @('git', 'url') -and $url -in $official[1..2])) {
        return $true
    }
    throw 'The existing power-platform-skills marketplace source is different or unrecognized. Setup will not overwrite or trust it; review it manually.'
}

function Assert-SetupPlugin {
    param($Plugin, [string]$PluginHost)
    if (-not $Plugin.Enabled -or ($null -ne $Plugin.Errors -and @($Plugin.Errors).Count -gt 0)) {
        throw "Plugin '$($Plugin.Name)' is disabled or has load errors. Resolve this in the selected host; setup will not override policy/settings."
    }
    if ($PluginHost -eq 'ClaudeCode' -and $Plugin.Scope -ne 'user') {
        throw "Plugin '$($Plugin.Name)' exists outside user scope. Review its scope manually rather than creating a duplicate."
    }
}

function Install-SetupPlugins {
    param([string]$Path, [string]$PluginHost, [string[]]$Names)
    $marketplaces = @(Read-PluginJson $Path @('plugin', 'marketplace', 'list', '--json'))
    $registered = Assert-OfficialMarketplace $marketplaces
    $inventory = @(Get-PluginInventory $Path $PluginHost)
    $pending = @()
    foreach ($name in $Names) {
        $existing = @($inventory | Where-Object Name -eq $name)
        if ($existing.Count) {
            if ($existing.Count -ne 1 -or
                ($existing[0].Id -ne "$name@power-platform-skills" -and
                 -not ($name -eq 'dataverse' -and $existing[0].Id -eq 'dataverse@dataverse-skills'))) {
                throw "Plugin '$name' already has another or duplicate source. Review it manually; no duplicate will be installed."
            }
            Assert-SetupPlugin $existing[0] $PluginHost
            Write-Host "Keeping installed plugin: $name"
        } else { $pending += $name }
    }
    if (-not $registered -and $pending.Count) {
        Invoke-SetupNative $Path @('plugin', 'marketplace', 'add', 'microsoft/power-platform-skills') | Out-Null
        if (-not (Assert-OfficialMarketplace @(Read-PluginJson $Path @('plugin', 'marketplace', 'list', '--json')))) {
            throw 'Marketplace registration returned success but the official source could not be verified.'
        }
    }
    foreach ($name in $pending) {
        Write-Host "Installing $name for $PluginHost..."
        $arguments = @('plugin', 'install', "$name@power-platform-skills")
        if ($PluginHost -eq 'ClaudeCode') { $arguments += @('--scope', 'user') }
        Invoke-SetupNative $Path $arguments | Out-Null
        $installed = @(Get-PluginInventory $Path $PluginHost | Where-Object Id -eq "$name@power-platform-skills")
        if ($installed.Count -ne 1) {
            throw "Plugin '$name' install returned success but its installation could not be verified."
        }
        Assert-SetupPlugin $installed[0] $PluginHost
    }
    Write-Host 'Selected host plugin registrations verified. Restart that host and check its actual skills/tools.'
    Write-Host 'Desktop visibility, bundled MCP setup, licensing and authentication are NOT verified.'
}

function Get-CopilotAppPluginLink {
    param([string]$Name)
    if ($Name) {
        if ($Name -notin @(Get-SetupPluginNames -IncludeDataverse)) { throw 'Unknown Power Platform plugin link.' }
        $route = 'ghapp://plugins/install?source=' + [uri]::EscapeDataString("$Name@power-platform-skills")
    } else {
        $route = 'ghapp://plugins/marketplace/add?source=' + [uri]::EscapeDataString('microsoft/power-platform-skills')
    }
    return 'https://github.com/copilot/app/launch?open=' + [uri]::EscapeDataString($route)
}

function Invoke-PluginSetup {
    [CmdletBinding()]
    param(
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$PluginHost,
        [switch]$IncludeDataverse, [switch]$AcceptPlugins, [switch]$NonInteractive
    )
    if (-not $PluginHost) {
        if ($NonInteractive) {
            Write-Host 'Plugin stage skipped. Request it explicitly with -PluginHost and -AcceptPlugins.'
            return 0
        }
        Write-Host "`nOptional next stage: Power Platform plugins (separate approval)."
        Write-Host '1 = Claude Code (claude command); 2 = Copilot CLI; 3 = Copilot desktop app links; Enter = skip.'
        $choice = Read-Host 'Choose the host you already use; no new host will be installed'
        switch ($choice) {
            '' { Write-Host 'Plugin stage skipped. You can run it later or use the integration skill.'; return 0 }
            '1' { $PluginHost = 'ClaudeCode' }
            '2' { $PluginHost = 'CopilotCli' }
            '3' { $PluginHost = 'CopilotApp' }
            default { Write-Host 'Unrecognized host selection. Plugin stage cancelled.'; return 2 }
        }
    }
    if ($PluginHost -eq 'Skip') { Write-Host 'Plugin stage skipped explicitly.'; return 0 }
    if ($NonInteractive -and -not $AcceptPlugins) {
        Write-Host 'Plugin approval missing. Use -AcceptPlugins only after the user approves this separate plan.'
        return 2
    }
    if (-not $NonInteractive -and -not $AcceptPlugins -and -not $IncludeDataverse) {
        $IncludeDataverse = (Read-Host 'Also include Dataverse? Type YES to opt in; Enter = no') -ceq 'YES'
    }
    $names = @(Get-SetupPluginNames -IncludeDataverse:$IncludeDataverse)
    Write-Host "`nPlugin plan for ${PluginHost}: $($names -join ', ')"
    Write-Host 'Source: microsoft/power-platform-skills (Dataverse, if selected, comes from Microsoft/Dataverse-skills).'
    Write-Host 'Plugins may include executable hooks, agents and MCP servers. Review their permissions in your host.'
    Write-Host 'Setup will not enable auto-update, install another host, update prerequisites, or sign in.'
    $path = $null
    if ($PluginHost -ne 'CopilotApp') {
        $command = if ($PluginHost -eq 'ClaudeCode') { 'claude' } else { 'copilot' }
        $path = Find-SetupExecutable $command
        if (-not $path) {
            throw "The selected host command '$command' is not available on PATH. No host was installed. For Copilot desktop only, choose -PluginHost CopilotApp."
        }
        Write-Host "Using existing command: $path"
        Write-Host 'Only this host will be configured, at user scope. Existing plugins/disabled settings will be preserved.'
    } else {
        Write-Host 'Setup will print official app links. Open the marketplace first, then confirm each plugin in the app.'
        Write-Host 'Printing a link does not install a plugin. No browser/app is opened automatically.'
    }
    if (-not $AcceptPlugins) {
        if ((Read-Host 'Type PLUGINS to approve this stage (anything else cancels)') -cne 'PLUGINS') {
            Write-Host 'Plugin stage cancelled. Any completed prerequisite installs are retained.'
            return 2
        }
    }
    if ($PluginHost -eq 'CopilotApp') {
        Write-Host "`nAdd marketplace first:"
        Write-Host (Get-CopilotAppPluginLink)
        foreach ($name in $names) {
            Write-Host "`n${name}:"
            Write-Host (Get-CopilotAppPluginLink $name)
        }
        Write-Host "`nACTION REQUIRED: complete the links in the Copilot app, then check Customize > Installed."
        Write-Host 'Plugin installation is pending, not verified. Copilot Studio MCP/authentication remain separate.'
        return 4
    }
    Install-SetupPlugins $path $PluginHost $names
    return 0
}

function Invoke-Setup {
    param(
        [switch]$CheckOnly, [switch]$Install, [switch]$Accept, [switch]$NonInteractive, [switch]$IncludeAzureCli,
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$PluginHost,
        [switch]$IncludeDataverse, [switch]$AcceptPlugins
    )
    if (($CheckOnly -and ($Install -or $Accept -or $AcceptPlugins)) -or ($Accept -and -not $Install)) {
        Write-Host 'Invalid options: use -CheckOnly alone, or -Install [-Accept] [-NonInteractive].'
        return 2
    }
    if (($AcceptPlugins -and (-not $PluginHost -or $PluginHost -eq 'Skip')) -or
        ($IncludeDataverse -and $PluginHost -eq 'Skip') -or
        ($NonInteractive -and -not $CheckOnly -and
            (($IncludeDataverse -and -not $PluginHost) -or
             ($PluginHost -and $PluginHost -ne 'Skip' -and -not $AcceptPlugins)))) {
        Write-Host 'Specify -PluginHost ClaudeCode, CopilotCli or CopilotApp. Noninteractive plugin setup also requires separate -AcceptPlugins approval.'
        return 2
    }
    try {
        $architecture = Get-SetupArchitecture
        Write-Host "Windows architecture: $architecture (setup process: $env:PROCESSOR_ARCHITECTURE)"
        Write-Host "Missing Git, Node and .NET will use native $architecture installers. PAC will match the selected .NET host."
        if ($architecture -eq 'arm64') {
            Write-Host 'Compatible existing x64/x86 tools are preserved and use Windows 11 emulation.'
            if ($IncludeAzureCli) { Write-Host 'Optional Azure CLI uses the official x64 MSI under Windows 11 emulation, not a native ARM64 build.' }
        }
        $state = @(Get-SetupState -Azure:$IncludeAzureCli -Architecture $architecture)
        Show-SetupState $state
        $pending = @($state | Where-Object { -not $_.Ready })
        if ($CheckOnly) {
            if ($PluginHost -and $PluginHost -ne 'Skip') {
                Write-Host "Requested later plugin stage: $PluginHost. Host/plugin readiness is NOT checked in offline check-only mode."
                Write-Host (@(Get-SetupPluginNames -IncludeDataverse:$IncludeDataverse) -join ', ')
            }
            if ($pending.Count) {
                Write-Host "`nPlanned order: $($pending.Name -join ' -> ')"
                return 1
            }
            return 0
        }
        if ($pending.Count -eq 0) {
            Write-Host "`nAll selected prerequisites are ready. Plugins and authentication still need separate verification."
            return (Invoke-PluginSetup -PluginHost $PluginHost -IncludeDataverse:$IncludeDataverse -AcceptPlugins:$AcceptPlugins -NonInteractive:$NonInteractive)
        }
        Write-Host "`nPlanned order: $($pending.Name -join ' -> ')"
        if ($NonInteractive -and -not ($Install -and $Accept)) {
            Write-Host 'No changes made. Agent installation requires explicit -Install -Accept -NonInteractive approval.'
            return 2
        }
        if (-not ($Install -and $Accept)) {
            Write-Host 'This will download and run official installers, accept their licenses, and may request UAC.'
            Write-Host 'Git is per-user; Node/.NET/Azure are machine-wide. No cloud login or automatic reboot.'
            $answer = Read-Host 'Type INSTALL to approve this plan (anything else cancels)'
            if ($answer -cne 'INSTALL') { Write-Host 'Cancelled. No changes made.'; return 2 }
        }
        # TLS is changed for this approved process only, never persisted.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Update-SetupPath
        foreach ($tool in $pending) {
            Write-Host "`nSetting up $($tool.Name)..."
            $restart = Install-SetupTool $tool.Id
            Update-SetupPath
            if ($restart) {
                Write-Host 'Windows reported a restart requirement. Save your work, restart Windows yourself, then rerun setup.'
                Write-Host 'Setup stopped before installing further prerequisites. No reboot was requested by this script.'
                return 3010
            }
            $state = @(Get-SetupState -Azure:$IncludeAzureCli -Architecture $architecture)
            Confirm-InstalledTool $tool.Id $state
        }
        Show-SetupState $state
        Write-Host "`nPrerequisites ready. Keep this window open for the optional plugin stage."
        Write-Host 'After setup finishes, restart terminals and your chosen host so they inherit the new PATH.'
        Write-Host 'No tenant has been accessed. Copilot Studio MCP registration and intentional sign-in remain separate.'
        return (Invoke-PluginSetup -PluginHost $PluginHost -IncludeDataverse:$IncludeDataverse -AcceptPlugins:$AcceptPlugins -NonInteractive:$NonInteractive)
    } catch {
        Write-Host "`nSetup failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'No later setup steps were run. Resolve the cause and rerun -CheckOnly; completed prerequisite/plugin installations are preserved.'
        return 3
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-Setup -CheckOnly:$CheckOnly -Install:$Install -Accept:$Accept -NonInteractive:$NonInteractive -IncludeAzureCli:$IncludeAzureCli -PluginHost $PluginHost -IncludeDataverse:$IncludeDataverse -AcceptPlugins:$AcceptPlugins)
}
