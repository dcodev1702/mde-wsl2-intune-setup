<#
.SYNOPSIS
    Intune Win32 app REQUIREMENT script — detects whether WSL2 is present on the device.

.DESCRIPTION
    Runs in SYSTEM context as a custom requirement rule for the MDE WSL2 plug-in Win32 app.
    Emits the token "WSL2_Detected" to STDOUT only when WSL2 is present, otherwise emits nothing.
    This gates app applicability so the Defender for Endpoint plug-in for WSL installs ONLY on
    machines that actually have WSL2.

.INTUNE REQUIREMENT RULE CONFIG
    Select output data type : String
    Operator                : Equals
    Value                   : WSL2_Detected

.NOTES
    The device emits "WSL2_Detected" only when BOTH are true:

      [WSL present]  (EITHER condition group):
        A) Virtual Machine Platform feature enabled
           AND (WSL feature enabled OR Store-based WSL app installed)
           AND wsl.exe binary present
        B) At least one registered distro found in the machine hive or any loaded user hive
        Group A catches "WSL installed but not yet launched"; Group B confirms an active distro.

      [MDE host ready]:
        Sense service running AND OnboardingState = 1 in the ATP Status key.
        This enforces the install ordering: the host MUST be onboarded to Defender
        for Endpoint before the WSL plug-in is provisioned. A WSL machine that is not
        yet onboarded stays "Not applicable" until its sensor is live.
#>

$ErrorActionPreference = 'SilentlyContinue'

# 1) Virtual Machine Platform feature (mandatory for WSL2)
$vmp = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State -eq 'Enabled'

# 2) WSL feature enabled OR Store-based WSL app installed
$wslFeature = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State -eq 'Enabled'
$wslApp     = [bool](Get-AppxPackage -AllUsers -Name 'MicrosoftCorporationII.WindowsSubsystemForLinux')

# 3) wsl.exe present (inbox or Store path)
$wslExe = (Test-Path "$env:SystemRoot\System32\wsl.exe") -or (Test-Path "$env:ProgramFiles\WSL\wsl.exe")

# 4) At least one registered distro (machine hive + every loaded user hive)
$distro    = $false
$lxssRoots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss')
Get-ChildItem 'Registry::HKEY_USERS' | ForEach-Object {
    $p = "Registry::$($_.Name)\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss"
    if (Test-Path $p) { $lxssRoots += $p }
}
foreach ($r in $lxssRoots) {
    if (Get-ChildItem $r | Where-Object { $_.PSChildName -match '^{' }) { $distro = $true; break }
}

$wslPresent = ($vmp -and ($wslFeature -or $wslApp) -and $wslExe) -or $distro

# 5) MDE host readiness — the plug-in's hard precondition.
#    Host must be onboarded to Defender for Endpoint AND the Sense sensor running.
$mdeOnboarded = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status').OnboardingState -eq 1
$senseRunning = (Get-Service -Name Sense).Status -eq 'Running'
$mdeReady     = $mdeOnboarded -and $senseRunning

# Applicable only when WSL2 is present AND the host MDE sensor is live.
if ($wslPresent -and $mdeReady) {
    Write-Output 'WSL2_Detected'
}

exit 0