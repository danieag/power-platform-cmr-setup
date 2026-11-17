#requires -Version 5.1
<#
.SYNOPSIS
Checks and, only with approval, installs local Power Platform prerequisites and offers plugin/MCP setup.
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
    [switch]$SkipAzureCli,
    [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$PluginHost,
    [switch]$IncludeDataverse,
    [switch]$AcceptPlugins,
    [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$CopilotStudioHost,
    [switch]$AcceptCopilotStudio,
    [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$ConnectionSkillHost,
    [switch]$AcceptConnectionSkill
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
        (($version.Major -eq 22 -and $version -ge [version]'22.18.0') -or $version.Major -in @(24, 26))
    $binaryArchitecture = Get-ExecutableArchitecture $node
    $ready = $nodeSupported -and (Test-ExecutableArchitecture $binaryArchitecture $Architecture) -and
        $null -ne $npmVersion -and $npmVersion -ge [version]'10.0.0'
    New-ToolState 'node' "Node.js / npm ($npmVersion)" $version $ready $node 'Node 22.18+ (22.x), 24 or 26 with bundled npm >= 10' $binaryArchitecture

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
        New-ToolState 'azure' 'Azure CLI' $version $ready $az 'Azure CLI MSI >= 2.60 (x64 emulation on ARM64)' $azArchitecture
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
    Write-Host 'Azure CLI is included after PAC by default. -SkipAzureCli is for minimal setups without Azure-dependent plugins.'
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

function Invoke-InstallerProcess {
    [CmdletBinding()]
    param(
        [hashtable]$Parameters,
        [string]$Label,
        [ValidateRange(1, 3600)][int]$HeartbeatSeconds = 30
    )
    # Keep Start-Process -Wait's process-tree semantics while the caller prints heartbeat output.
    $runner = [PowerShell]::Create()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $runner.AddScript({
            param($StartParameters)
            $ErrorActionPreference = 'Stop'
            $process = Start-Process @StartParameters
            $process.ExitCode
        }).AddArgument($Parameters) | Out-Null
        Write-Host "Starting $Label installer. Check for any Windows permission prompt; keep this window open."
        $operation = $runner.BeginInvoke()
        while (-not $operation.AsyncWaitHandle.WaitOne($HeartbeatSeconds * 1000)) {
            Write-Host ("Still waiting for {0} installer ({1:hh\:mm\:ss} elapsed). No completion result yet; do not start another installer." -f $Label, $clock.Elapsed)
        }
        $result = @($runner.EndInvoke($operation))
        if ($runner.HadErrors) { throw $runner.Streams.Error[0].Exception }
        if ($result.Count -ne 1 -or $result[0] -isnot [int]) {
            throw "The $Label installer did not return a usable exit code."
        }
        Write-Host ("{0} installer exited after {1:hh\:mm\:ss}; checking its exit code and installed version." -f $Label, $clock.Elapsed)
        return $result[0]
    } finally {
        $clock.Stop()
        $runner.Dispose()
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
    $exitCode = Invoke-InstallerProcess -Parameters $parameters -Label ([IO.Path]::GetFileName($Path))
    if ($exitCode -notin @(0, 1641, 3010)) {
        throw "Installer failed with exit code $exitCode. Resolve Windows Installer/UAC or policy issues, then rerun."
    }
    return ($exitCode -in @(1641, 3010))
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

function Get-CopilotSetupHome {
    $default = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.copilot')).TrimEnd('\', '/')
    if ($env:COPILOT_HOME) {
        $configured = [Environment]::ExpandEnvironmentVariables($env:COPILOT_HOME)
        if ($configured -notmatch '^(?:[a-zA-Z]:[\\/]|\\\\)' -or
            -not [IO.Path]::GetFullPath($configured).TrimEnd('\', '/').Equals($default, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'COPILOT_HOME points to a custom location rather than the default user .copilot directory. Review registration/skill installation through that host explicitly; setup will not guess another location.'
        }
    }
    return $default
}

function Get-CopilotStudioConfigPath {
    param([string]$HostName)
    if ($HostName -eq 'ClaudeCode') {
        if ($env:CLAUDE_CONFIG_DIR) { throw 'Custom CLAUDE_CONFIG_DIR is set. Register the server through that host explicitly; setup will not guess its user config location.' }
        return Join-Path $env:USERPROFILE '.claude.json'
    }
    return Join-Path (Get-CopilotSetupHome) 'mcp-config.json'
}

function Read-McpUserConfig {
    param([string]$Path)
    $bytes = $null
    $text = '{}'
    if (Test-Path -LiteralPath $Path) {
        if ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'MCP configuration is a link/reparse point. Review it manually; setup will not replace it.'
        }
        $bytes = [IO.File]::ReadAllBytes($Path)
        try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes).TrimStart([char]0xFEFF) } catch {
            throw 'MCP configuration is not valid UTF-8. Review it privately; setup will not rewrite its encoding.'
        }
    }
    try { $data = $text | ConvertFrom-Json } catch {
        throw 'MCP configuration contains invalid JSON. No configuration was replaced; inspect the file privately.'
    }
    if (-not $text.TrimStart().StartsWith('{') -or $data -isnot [pscustomobject]) {
        throw 'MCP configuration must be a JSON object; no configuration was replaced.'
    }
    $servers = Get-PluginProperty $data 'mcpServers'
    if ($data.PSObject.Properties['mcpServers'] -and $servers -isnot [pscustomobject]) {
        throw 'The mcpServers value must be a JSON object; no configuration was replaced.'
    }
    # Locate insertion points without reserializing unrelated settings, numbers or secrets.
    $depth = 0
    $serverStart = -1
    $serverEnd = -1
    $rootKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $serverKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt $text.Length; $i++) {
        $character = $text[$i]
        if ($character -eq '"') {
            $start = $i
            for ($i++; $i -lt $text.Length; $i++) {
                if ($text[$i] -eq '\') { $i++; continue }
                if ($text[$i] -eq '"') { break }
            }
            $after = $i + 1
            while ($after -lt $text.Length -and [char]::IsWhiteSpace($text[$after])) { $after++ }
            if ($after -lt $text.Length -and $text[$after] -eq ':') {
                $key = @(('[' + $text.Substring($start, $i - $start + 1) + ']') | ConvertFrom-Json)[0]
                if ($depth -eq 1) {
                    if (-not $rootKeys.Add($key)) { throw 'Duplicate root configuration keys are unsupported; review the file privately.' }
                    if ($key -ceq 'mcpServers') {
                        $serverStart = $after + 1
                        while ([char]::IsWhiteSpace($text[$serverStart])) { $serverStart++ }
                        if ($text[$serverStart] -ne '{') { throw 'The mcpServers value must be a JSON object.' }
                    } elseif ($key -ieq 'mcpServers') {
                        throw 'Use the exact mcpServers key casing before running setup.'
                    }
                } elseif ($depth -eq 2 -and $serverStart -ge 0 -and $serverEnd -lt 0) {
                    if (-not $serverKeys.Add($key)) { throw 'Duplicate MCP server keys are unsupported; review the file privately.' }
                }
            }
        } elseif ($character -in @('{', '[')) {
            $depth++
        } elseif ($character -in @('}', ']')) {
            if ($depth -eq 2 -and $serverStart -ge 0 -and $serverEnd -lt 0) { $serverEnd = $i }
            $depth--
        } elseif ($character -eq '/') {
            throw 'Comments in MCP JSON are unsupported; review the file privately.'
        } elseif ($character -eq ',') {
            $after = $i + 1
            while ($after -lt $text.Length -and [char]::IsWhiteSpace($text[$after])) { $after++ }
            if ($text[$after] -in @('}', ']')) { throw 'Trailing commas in MCP JSON are unsupported.' }
        }
    }
    [pscustomobject]@{ Bytes = $bytes; Text = $text; Data = $data; ServerEnd = $serverEnd }
}

function Test-CopilotStudioRegistration {
    param($Config)
    $servers = Get-PluginProperty $Config.Data 'mcpServers'
    if ($null -eq $servers) { return $false }
    $found = $false
    foreach ($property in $servers.PSObject.Properties) {
        $entry = $property.Value
        $arguments = @(Get-PluginProperty $entry 'args')
        $isStudio = @($arguments | Where-Object { $_ -is [string] -and $_ -match '^@microsoft/copilot-studio-mcp(?:@|$)' }).Count -gt 0
        if ($property.Name -ieq 'copilot-studio' -or $isStudio) {
            if ($found) { throw 'Multiple Copilot Studio MCP definitions found. Resolve duplicates manually.' }
            $command = Get-PluginProperty $entry 'command'
            $type = Get-PluginProperty $entry 'type'
            if ($command -notin @('npx', 'npx.cmd') -or
                ($type -and $type -notin @('local', 'stdio')) -or
                ($arguments -join "`n") -cne "-y`n@microsoft/copilot-studio-mcp@latest") {
                throw 'An existing Copilot Studio MCP definition differs (possibly a pinned version). Setup will not overwrite or duplicate it.'
            }
            $found = $true
        }
    }
    return $found
}

function Save-CopilotStudioConfig {
    param([string]$Path, $Config)
    $entry = '"copilot-studio":{"type":"local","command":"npx","args":["-y","@microsoft/copilot-studio-mcp@latest"],"tools":["*"]}'
    $servers = Get-PluginProperty $Config.Data 'mcpServers'
    if ($null -ne $servers) {
        $position = $Config.ServerEnd
        $separator = if (@($servers.PSObject.Properties).Count) { ',' } else { '' }
        $insertion = $separator + "`n" + $entry + "`n"
    } else {
        $position = $Config.Text.LastIndexOf('}')
        $separator = if (@($Config.Data.PSObject.Properties).Count) { ',' } else { '' }
        $insertion = $separator + "`n`"mcpServers`":{" + $entry + "}`n"
    }
    $content = $Config.Text.Insert($position, $insertion)
    $parent = Split-Path -Parent $Path
    if ((Test-Path -LiteralPath $parent) -and
        ((Get-Item -LiteralPath $parent).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'MCP config directory is a link/reparse point. Review it manually before registration.'
    }
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ([guid]::NewGuid().ToString('N') + '.setup-tmp')
    $backup = $Path + '.setup-backup-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($temporary, [byte[]]@())
        if ($null -ne $Config.Bytes) {
            $acl = Get-Acl -LiteralPath $Path
            Set-Acl -LiteralPath $temporary -AclObject $acl
        }
        $hadBom = $null -ne $Config.Bytes -and $Config.Bytes.Length -ge 3 -and
            $Config.Bytes[0] -eq 0xEF -and $Config.Bytes[1] -eq 0xBB -and $Config.Bytes[2] -eq 0xBF
        [IO.File]::WriteAllText($temporary, $content, [Text.UTF8Encoding]::new($hadBom, $true))
        if ($null -ne $Config.Bytes) {
            $live = [IO.File]::ReadAllBytes($Path)
            if ([Convert]::ToBase64String($live) -cne [Convert]::ToBase64String($Config.Bytes)) {
                throw 'MCP configuration changed while setup was preparing the update. No replacement was made; close the host and retry explicitly.'
            }
            [IO.File]::Replace($temporary, $Path, $backup)
            if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backup)) -cne [Convert]::ToBase64String($Config.Bytes)) {
                throw "A concurrent config replacement was detected. Its displaced content is preserved in $backup. Stop and reconcile it before using the host."
            }
            Write-Host "Previous MCP configuration preserved in $backup (may contain secrets; keep private)."
        } else {
            # Move without overwrite: a concurrently created config must not be discarded.
            if (Test-Path -LiteralPath $Path) {
                throw 'MCP configuration was created while setup was preparing the update. No replacement was made; close the host and retry explicitly.'
            }
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Invoke-CopilotStudioSetup {
    [CmdletBinding()]
    param(
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$CopilotStudioHost,
        [switch]$AcceptCopilotStudio, [switch]$NonInteractive
    )
    if (-not $CopilotStudioHost) {
        if ($NonInteractive) { Write-Host 'Copilot Studio MCP stage skipped (no explicit host/approval).'; return 0 }
        Write-Host "`nOptional Copilot Studio MCP registration: 1 = Claude Code; 2 = Copilot CLI; 3 = Copilot desktop; Enter = skip."
        switch (Read-Host 'Choose the host for Copilot Studio MCP') {
            '' { Write-Host 'Copilot Studio MCP stage skipped.'; return 0 }
            '1' { $CopilotStudioHost = 'ClaudeCode' }
            '2' { $CopilotStudioHost = 'CopilotCli' }
            '3' { $CopilotStudioHost = 'CopilotApp' }
            default { Write-Host 'Unrecognized host. Copilot Studio MCP stage cancelled.'; return 2 }
        }
    }
    if ($CopilotStudioHost -eq 'Skip') { return 0 }
    if ($NonInteractive -and -not $AcceptCopilotStudio) { Write-Host 'Separate -AcceptCopilotStudio approval is required.'; return 2 }
    $path = Get-CopilotStudioConfigPath $CopilotStudioHost
    Write-Host "`nCopilot Studio MCP plan for ${CopilotStudioHost}: user-scope registration in $path"
    Write-Host 'Launch command: npx -y @microsoft/copilot-studio-mcp@latest'
    Write-Host 'The host downloads/caches the package on first launch; @latest allows future package updates.'
    Write-Host 'This stage saves configuration only: no server launch, sign-in, tenant selection or cloud operations.'
    Write-Host 'New Copilot entries expose the server tools to the host without enabling automatic approval.'
    Write-Host 'Close the selected host before approval to avoid concurrent config writes. Existing definitions/settings are preserved.'
    if (-not $AcceptCopilotStudio -and (Read-Host 'Type MCP to approve registration (anything else cancels)') -cne 'MCP') {
        Write-Host 'Copilot Studio MCP stage cancelled. Earlier installations are retained.'
        return 2
    }
    $config = Read-McpUserConfig $path
    if (Test-CopilotStudioRegistration $config) {
        Write-Host 'Matching user-scope Copilot Studio MCP definition already exists; left unchanged (including tool restrictions/disabled settings).'
    } elseif ($CopilotStudioHost -eq 'ClaudeCode') {
        $claude = Find-SetupExecutable 'claude'
        if (-not $claude) { throw 'Claude Code command not found. No host was installed and no configuration was changed.' }
        Invoke-SetupNative $claude @('mcp', 'add', '--scope', 'user', '--transport', 'stdio', 'copilot-studio', '--',
            'npx', '-y', '@microsoft/copilot-studio-mcp@latest') | Out-Null
    } else {
        Save-CopilotStudioConfig $path $config
    }
    if (-not (Test-CopilotStudioRegistration (Read-McpUserConfig $path))) {
        throw 'Copilot Studio MCP registration could not be verified in the user configuration.'
    }
    Write-Host 'Copilot Studio MCP: CONFIGURED, NOT RUNTIME-VERIFIED. Restart the host and inspect its MCP list/permissions.'
    Write-Host 'Project/plugin/managed definitions can override this user config; runtime visibility, authentication and environment access remain unverified.'
    return 0
}

function Invoke-SetupIntegrations {
    param(
        [string]$PluginHost, [switch]$IncludeDataverse, [switch]$AcceptPlugins, [switch]$NonInteractive,
        [string]$CopilotStudioHost, [switch]$AcceptCopilotStudio,
        [string]$ConnectionSkillHost, [switch]$AcceptConnectionSkill
    )
    $plugins = Invoke-PluginSetup -PluginHost $PluginHost -IncludeDataverse:$IncludeDataverse -AcceptPlugins:$AcceptPlugins -NonInteractive:$NonInteractive
    if ($plugins -notin @(0, 4)) { return $plugins }
    $mcp = Invoke-CopilotStudioSetup -CopilotStudioHost $CopilotStudioHost -AcceptCopilotStudio:$AcceptCopilotStudio -NonInteractive:$NonInteractive
    if ($mcp -ne 0) { return $mcp }
    $skill = Invoke-ConnectionSkillSetup -ConnectionSkillHost $ConnectionSkillHost -AcceptConnectionSkill:$AcceptConnectionSkill -NonInteractive:$NonInteractive
    if ($skill -ne 0) { return $skill }
    return $plugins
}

function Get-ConnectionSkillDirectory {
    param([string]$HostName)
    if ($HostName -eq 'ClaudeCode') {
        if ($env:CLAUDE_CONFIG_DIR) { throw 'Custom CLAUDE_CONFIG_DIR is set. Install the connection skill through that host explicitly; setup will not guess its personal skill directory.' }
        return Join-Path $env:USERPROFILE '.claude\skills\power-platform-connect'
    }
    return Join-Path (Get-CopilotSetupHome) 'skills\power-platform-connect'
}

function Assert-SkillDirectoryChain {
    param([string]$Path)
    $directory = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Path))
    while ($null -ne $directory) {
        if (Test-Path -LiteralPath $directory.FullName) {
            $item = Get-Item -LiteralPath $directory.FullName -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'The skill destination includes a file or linked directory. Review the location manually; nothing will be overwritten.'
            }
        }
        $directory = $directory.Parent
    }
}

function Install-ConnectionSkill {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw 'Bundled connection skill is missing. Download/extract the full setup ZIP; do not run just the launcher/script.'
    }
    $text = Get-Content -LiteralPath $Source -Raw
    if ($text -notmatch '(?s)^---\s*\r?\nname: power-platform-connect\r?\ndescription: [^\r\n]+\r?\n---' -or
        $text -match '(?m)^allowed-tools:') {
        throw 'The bundled connection skill has an unexpected definition. Review the full source before installing it.'
    }
    Assert-SkillDirectoryChain $Destination
    $expectedHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $target = Join-Path $Destination 'SKILL.md'
    if (Test-Path -LiteralPath $Destination) {
        if ((Test-Path -LiteralPath $target -PathType Leaf) -and
            -not ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $expectedHash) {
            Write-Host 'Matching connection skill already exists; left unchanged.'
            return
        }
        throw 'The connection skill directory already contains a different definition or other content. Review/update it manually; setup will not overwrite it.'
    }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $staging = Join-Path $parent ('.setup-skill-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging | Out-Null
    try {
        $stagedFile = Join-Path $staging 'SKILL.md'
        Copy-Item -LiteralPath $Source -Destination $stagedFile
        if ((Get-FileHash -LiteralPath $stagedFile -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'The bundled skill changed during copy. No skill was installed; retry after reviewing the source.'
        }
        # A concurrent installation must not be overwritten.
        [IO.Directory]::Move($staging, $Destination)
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'The installed skill no longer matches the reviewed bundle. Stop and inspect the destination.'
        }
        Write-Host "Connection skill saved to $target"
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
}

function Show-ConnectionNextStep {
    Write-Host "`nNEXT STEP: restart your chosen host or open a fresh chat, then ask:"
    Write-Host '"Use the power-platform-connect skill to connect my selected Dataverse/PAC/Azure CLIs and MCP.'
    Write-Host 'Check existing profiles first, confirm my account/tenant/environment, and ask before sign-in or configuration changes."'
    Write-Host 'If the skill is not installed/visible, ask the agent to read:'
    Write-Host 'https://github.com/danieag/power-platform-setup/blob/main/skills/power-platform-connect/SKILL.md'
    Write-Host 'Remove unneeded surfaces from the request. Skill installation does not sign you in or grant tenant access.'
}

function Invoke-ConnectionSkillSetup {
    [CmdletBinding()]
    param(
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$ConnectionSkillHost,
        [switch]$AcceptConnectionSkill, [switch]$NonInteractive
    )
    if (-not $ConnectionSkillHost -and -not $NonInteractive) {
        Write-Host "`nOptional final step: install the bundled power-platform-connect skill for your user."
        Write-Host '1 = Claude Code; 2 = Copilot CLI; 3 = Copilot desktop; Enter = skip and show next-step instructions.'
        switch (Read-Host 'Choose the skill host (no authentication will run)') {
            '' { $ConnectionSkillHost = 'Skip' }
            '1' { $ConnectionSkillHost = 'ClaudeCode' }
            '2' { $ConnectionSkillHost = 'CopilotCli' }
            '3' { $ConnectionSkillHost = 'CopilotApp' }
            default { Write-Host 'Unrecognized host. Connection skill stage cancelled.'; return 2 }
        }
    }
    if (-not $ConnectionSkillHost -or $ConnectionSkillHost -eq 'Skip') {
        Write-Host 'Connection skill installation skipped.'
        Show-ConnectionNextStep
        return 0
    }
    if ($NonInteractive -and -not $AcceptConnectionSkill) {
        Write-Host 'Separate -AcceptConnectionSkill approval is required.'
        return 2
    }
    $destination = Get-ConnectionSkillDirectory $ConnectionSkillHost
    Write-Host "`nConnection skill plan for ${ConnectionSkillHost}: $destination"
    Write-Host 'Copy the bundled instructions into the documented personal skills directory; no CLI, server or sign-in is started.'
    Write-Host 'This makes the instructions available across projects. Existing definitions are never overwritten.'
    Write-Host 'Host discovery/policy must still be checked after restart; no auto-approval permissions will be enabled.'
    if (-not $AcceptConnectionSkill -and (Read-Host 'Type SKILL to approve installation (anything else cancels)') -cne 'SKILL') {
        Write-Host 'Connection skill installation cancelled. Earlier setup is retained.'
        Show-ConnectionNextStep
        return 2
    }
    Install-ConnectionSkill -Source (Join-Path $PSScriptRoot 'skills\power-platform-connect\SKILL.md') -Destination $destination
    Write-Host 'Skill file installation verified. Host discovery and authentication are NOT verified.'
    Show-ConnectionNextStep
    return 0
}

function Invoke-Setup {
    param(
        [switch]$CheckOnly, [switch]$Install, [switch]$Accept, [switch]$NonInteractive, [switch]$IncludeAzureCli, [switch]$SkipAzureCli,
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$PluginHost,
        [switch]$IncludeDataverse, [switch]$AcceptPlugins,
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$CopilotStudioHost,
        [switch]$AcceptCopilotStudio,
        [ValidateSet('', 'Skip', 'ClaudeCode', 'CopilotCli', 'CopilotApp')][string]$ConnectionSkillHost,
        [switch]$AcceptConnectionSkill
    )
    if (($CheckOnly -and ($Install -or $Accept -or $AcceptPlugins -or $AcceptCopilotStudio -or $AcceptConnectionSkill)) -or ($Accept -and -not $Install)) {
        Write-Host 'Invalid options: use -CheckOnly alone, or -Install [-Accept] [-NonInteractive].'
        return 2
    }
    if ($IncludeAzureCli -and $SkipAzureCli) {
        Write-Host 'Do not combine -IncludeAzureCli and -SkipAzureCli. Azure CLI is included by default.'
        return 2
    }
    $includeAzure = -not $SkipAzureCli
    if (($AcceptConnectionSkill -and (-not $ConnectionSkillHost -or $ConnectionSkillHost -eq 'Skip')) -or
        ($NonInteractive -and -not $CheckOnly -and $ConnectionSkillHost -and $ConnectionSkillHost -ne 'Skip' -and -not $AcceptConnectionSkill)) {
        Write-Host 'Choose -ConnectionSkillHost ClaudeCode, CopilotCli or CopilotApp and provide separate -AcceptConnectionSkill approval for noninteractive skill installation.'
        return 2
    }
    if (($AcceptCopilotStudio -and (-not $CopilotStudioHost -or $CopilotStudioHost -eq 'Skip')) -or
        ($NonInteractive -and -not $CheckOnly -and $CopilotStudioHost -and $CopilotStudioHost -ne 'Skip' -and -not $AcceptCopilotStudio)) {
        Write-Host 'Choose -CopilotStudioHost ClaudeCode, CopilotCli or CopilotApp and provide separate -AcceptCopilotStudio approval for noninteractive registration.'
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
            if ($includeAzure) { Write-Host 'Azure CLI uses the official x64 MSI under Windows 11 emulation, not a native ARM64 build.' }
        }
        if ($SkipAzureCli) { Write-Host 'Azure CLI skipped explicitly; Azure-dependent plugin workflows may need it installed later.' }
        $state = @(Get-SetupState -Azure:$includeAzure -Architecture $architecture)
        Show-SetupState $state
        $pending = @($state | Where-Object { -not $_.Ready })
        if ($CheckOnly) {
            if ($ConnectionSkillHost -and $ConnectionSkillHost -ne 'Skip') {
                Write-Host "Requested later connection skill installation: $ConnectionSkillHost (no user skill directory inspected or changed)."
            }
            if ($CopilotStudioHost -and $CopilotStudioHost -ne 'Skip') {
                Write-Host "Requested later Copilot Studio MCP stage: $CopilotStudioHost (configuration/runtime not inspected in offline check-only mode)."
            }
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
            return (Invoke-SetupIntegrations -PluginHost $PluginHost -IncludeDataverse:$IncludeDataverse -AcceptPlugins:$AcceptPlugins -NonInteractive:$NonInteractive -CopilotStudioHost $CopilotStudioHost -AcceptCopilotStudio:$AcceptCopilotStudio -ConnectionSkillHost $ConnectionSkillHost -AcceptConnectionSkill:$AcceptConnectionSkill)
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
            $state = @(Get-SetupState -Azure:$includeAzure -Architecture $architecture)
            Confirm-InstalledTool $tool.Id $state
        }
        Show-SetupState $state
        Write-Host "`nPrerequisites ready. Keep this window open for the optional plugin stage."
        Write-Host 'After setup finishes, restart terminals and your chosen host so they inherit the new PATH.'
        Write-Host 'No tenant has been accessed. Optional MCP registration needs its own approval; intentional sign-in remains separate.'
        return (Invoke-SetupIntegrations -PluginHost $PluginHost -IncludeDataverse:$IncludeDataverse -AcceptPlugins:$AcceptPlugins -NonInteractive:$NonInteractive -CopilotStudioHost $CopilotStudioHost -AcceptCopilotStudio:$AcceptCopilotStudio -ConnectionSkillHost $ConnectionSkillHost -AcceptConnectionSkill:$AcceptConnectionSkill)
    } catch {
        Write-Host "`nSetup failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'No later setup steps were run. Resolve the cause and rerun -CheckOnly; completed prerequisite/plugin installations are preserved.'
        return 3
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Invoke-Setup -CheckOnly:$CheckOnly -Install:$Install -Accept:$Accept -NonInteractive:$NonInteractive -IncludeAzureCli:$IncludeAzureCli -SkipAzureCli:$SkipAzureCli -PluginHost $PluginHost -IncludeDataverse:$IncludeDataverse -AcceptPlugins:$AcceptPlugins -CopilotStudioHost $CopilotStudioHost -AcceptCopilotStudio:$AcceptCopilotStudio -ConnectionSkillHost $ConnectionSkillHost -AcceptConnectionSkill:$AcceptConnectionSkill)
}
