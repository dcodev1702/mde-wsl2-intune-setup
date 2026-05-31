<#
.SYNOPSIS
    Intune remediation detection script - reports the installed MDE WSL plug-in version.

.DESCRIPTION
    Report-only inventory script for Microsoft Defender for Endpoint plug-in for WSL.
    It writes one compact JSON object to STDOUT and always exits 0 so the remediation
    package stays inventory-only.

    Preferred version source:
      1. Standard uninstall registry DisplayVersion
      2. DefenderforEndpointPlug-in.dll ProductVersion
      3. DefenderforEndpointPlug-in.dll FileVersion
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$appDisplayName = 'Microsoft Defender for Endpoint plug-in for WSL'
$pluginDllPath = Join-Path $env:ProgramFiles 'Microsoft Defender for Endpoint plug-in for WSL\plug-in\DefenderforEndpointPlug-in.dll'
$timestampUtc = (Get-Date).ToUniversalTime().ToString('o')

function Get-CleanString {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $stringValue = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
        return $null
    }

    return $stringValue
}

function Get-MDEWSLPluginUninstallEntry {
    $registryRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $uninstallEntries = foreach ($registryRoot in $registryRoots) {
        Get-ItemProperty -Path $registryRoot -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -eq $appDisplayName -or
            $_.DisplayName -like '*Defender*Endpoint*plug-in*WSL*'
        }
    }

    $exactMatch = $uninstallEntries | Where-Object { $_.DisplayName -eq $appDisplayName } | Select-Object -First 1
    if ($exactMatch) {
        return $exactMatch
    }

    return ($uninstallEntries | Select-Object -First 1)
}

$uninstallEntry = Get-MDEWSLPluginUninstallEntry
$registryDisplayVersion = Get-CleanString $uninstallEntry.DisplayVersion
$registryDisplayName = Get-CleanString $uninstallEntry.DisplayName
$registryPublisher = Get-CleanString $uninstallEntry.Publisher
$productCode = Get-CleanString $uninstallEntry.PSChildName

$dllExists = Test-Path -LiteralPath $pluginDllPath -PathType Leaf
$dllFileVersion = $null
$dllProductVersion = $null

if ($dllExists) {
    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($pluginDllPath)
    $dllFileVersion = Get-CleanString $versionInfo.FileVersion
    $dllProductVersion = Get-CleanString $versionInfo.ProductVersion
}

$reportedVersion = $registryDisplayVersion
$versionSource = 'UninstallRegistry'

if ([string]::IsNullOrWhiteSpace($reportedVersion)) {
    $reportedVersion = $dllProductVersion
    $versionSource = 'DllProductVersion'
}

if ([string]::IsNullOrWhiteSpace($reportedVersion)) {
    $reportedVersion = $dllFileVersion
    $versionSource = 'DllFileVersion'
}

if ([string]::IsNullOrWhiteSpace($reportedVersion)) {
    $versionSource = 'NotFound'
}

$result = [ordered]@{
    AppName = $appDisplayName
    Installed = [bool]($uninstallEntry -or $dllExists)
    Version = $reportedVersion
    VersionSource = $versionSource
    RegistryDisplayName = $registryDisplayName
    RegistryDisplayVersion = $registryDisplayVersion
    RegistryPublisher = $registryPublisher
    ProductCode = $productCode
    DllPath = $pluginDllPath
    DllExists = $dllExists
    DllProductVersion = $dllProductVersion
    DllFileVersion = $dllFileVersion
    TimestampUtc = $timestampUtc
}

$result | ConvertTo-Json -Compress -Depth 4
exit 0