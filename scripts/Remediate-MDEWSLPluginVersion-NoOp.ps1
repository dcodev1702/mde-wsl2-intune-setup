<#
.SYNOPSIS
    No-op remediation script for the MDE WSL plug-in version inventory package.

.DESCRIPTION
    Use this only if the Intune remediation workflow requires a remediation script.
    The paired inventory detection script exits 0, so this script should normally not run.

.AUTHOR
    dcodev1702 & GitHub Copilot (GPT 5.5)

.DATE
    2026-06-01
#>

$ErrorActionPreference = 'SilentlyContinue'

Write-Output 'No remediation required. Inventory is reported by the detection script.'
exit 0