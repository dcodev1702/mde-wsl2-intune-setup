# Intune Build Checklist — MDE WSL2 Plug-in (WSL-aware deployment)

Use this as the step-by-step runbook to package and deploy the Defender for Endpoint plug-in for WSL
so it provisions **only** on devices where WSL2 is present.

---

## Phase 0 — Prerequisites

- [ ] Target devices are Windows 10 2004+ (build 19044+) or Windows 11, **x64** (not ARM64, not multi-session).
- [ ] Host is **onboarded to Defender for Endpoint** and the sensor is in **Active** mode.
- [ ] WSL2 is at **version 2.0.7.0+** (`wsl --version`); update with `wsl --update` if needed.
- [ ] For VMs: **nested virtualization** is enabled (required for WSL2's Hyper-V boundary). On the **Hyper-V host**, with the guest VM **powered off**, expose virtualization extensions to the CPU and enable MAC address spoofing so the nested WSL2 VM gets network connectivity:
      ```powershell
      # Run on the Hyper-V HOST in an elevated PowerShell session; VM must be OFF
      $VMName = '<your-vm-name>'

      # 1. Expose virtualization extensions to the guest CPU (enables nested virtualization)
      Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
      Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true

      # 2. Enable MAC address spoofing on the VM's network interface (required for nested VM networking)
      Get-VMNetworkAdapter -VMName $VMName | Set-VMNetworkAdapter -MacAddressSpoofing On

      # 3. (Recommended) Give the guest enough memory and disable dynamic memory
      Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes 8GB

      # 4. Start the VM and verify
      Start-VM -Name $VMName
      Get-VMProcessor -VMName $VMName | Select-Object Name, ExposeVirtualizationExtensions
      ```
- [ ] You have an **Intune Administrator** (or equivalent) role.
- [ ] A target **Microsoft Entra device group** exists for assignment.

## Phase 1 — Obtain the installer

- [ ] Go to **Defender portal > Settings > Endpoints > Onboarding**.
- [ ] Operating system: **Windows Subsystem for Linux 2 (plug-in)**.
- [ ] Download `DefenderPlugin-x64-<version>.msi`.
- [ ] Place the MSI in a clean source folder (only the MSI in it).
- [ ] Do not commit the MSI, `IntuneWinAppUtil.exe`, or generated `.intunewin` package to the public repo.

## Phase 2 — Package as .intunewin

- [ ] Download the **Microsoft Win32 Content Prep Tool** (`IntuneWinAppUtil.exe`).
- [ ] Run:
      ```
      IntuneWinAppUtil.exe -c <source-folder> -s DefenderPlugin-x64.msi -o <output-folder>
      ```
- [ ] Confirm `DefenderPlugin-x64.intunewin` was produced.

## Phase 3 — Create the Win32 app in Intune

- [ ] **Apps > All apps > Add > Windows app (Win32)**.
- [ ] Upload the `.intunewin`.
- [ ] **App information**: Name = `MDE Plug-in for WSL`, Publisher = `Microsoft`, add description.

### Program tab
- [ ] Install command: `msiexec /i "DefenderPlugin-x64.msi" /qn /norestart`
- [ ] Uninstall command: `msiexec /x "DefenderPlugin-x64.msi" /qn /norestart`
- [ ] Install behavior: **System**
- [ ] Device restart behavior: **No specific action**

### Requirements tab
- [ ] Operating system architecture: **x64**
- [ ] Minimum operating system: set your floor (e.g., Windows 10 2004 / Windows 11).
- [ ] **Add > More requirement rules > Script**:
      - [ ] Upload **`scripts/Detect-WSL2.ps1`**
  - [ ] Run script as 32-bit: **No**
  - [ ] Enforce signature check: **No**
  - [ ] Select output data type: **String**
  - [ ] Operator: **Equals**
  - [ ] Value: **`WSL2_Detected`**

### Detection rules tab
- [ ] **Manually configure detection rules > Add > File**
  - [ ] Path: `%ProgramFiles%\Microsoft Defender for Endpoint plug-in for WSL\plug-in`
  - [ ] File: `DefenderforEndpointPlug-in.dll`
  - [ ] Detection method: **File or folder exists**
- [ ] Do **not** use a fixed MSI ProductCode detection rule. Windows Update servicing can register a
      newer plug-in build under a different ProductCode, causing Intune to report **Not installed** even
      when the plug-in is healthy on disk.

### Dependencies / Supersedence
- [ ] Dependencies: none required.
- [ ] Supersedence: optionally configure when replacing an older plug-in MSI.

### Assignments
- [ ] Add the target device group under **Required**.
- [ ] (Optional) Add availability/notification preferences.

- [ ] **Review + create**.

## Phase 4 — Validate on a pilot device

- [ ] Force an IME sync (or wait for the next check-in).
- [ ] Confirm the app shows **Applicable** only where WSL2 exists (check a no-WSL device shows "Not applicable").
- [ ] On the WSL2 device, confirm install:
      `%ProgramFiles%\Microsoft Defender for Endpoint plug-in for WSL\plug-in\DefenderforEndpointPlug-in.dll` exists.
- [ ] Run health check:
      ```
      wsl
      cd "%ProgramFiles%\Microsoft Defender for Endpoint plug-in for WSL\tools"
      .\healthcheck.exe
      ```
- [ ] If "Waiting for telemetry" / "Launch WSL distro with 'bash'" → wait 5 min, re-run.
- [ ] Within ~30 min, confirm a **Linux logical device tagged `WSL2`** appears in the Defender portal,
      linked to the Windows host via `HostDeviceId`.

## Phase 5 — Fleet verification (optional)

- [ ] In **Defender portal > Advanced hunting**, run the gap query to find WSL devices still missing the plug-in:
      ```kql
      let WSLDevices =
          DeviceProcessEvents
          | where ActionType == "ProcessCreated"
          | where ProcessVersionInfoOriginalFileName == "wsl.exe"
              and ProcessVersionInfoFileDescription has "Windows Subsystem for Linux"
          | summarize by DeviceName;
      WSLDevices
      | join kind=leftanti (
          DeviceTvmSoftwareInventory
          | where SoftwareName has "microsoft_defender_for_endpoint_plug-in_for_wsl"
          | summarize by DeviceName
      ) on DeviceName
      ```
- [ ] Track the count trending to zero as the deployment rolls out.

## Common pitfalls

- [ ] Wrong MSI — `IntuneWSLPluginInstaller.msi` is the **Intune compliance** plug-in, NOT the MDE security plug-in.
- [ ] Custom kernel configured → plug-in fatal error; block custom kernels via the WSL settings catalog.
- [ ] Requirement value mismatch — the Intune rule value must be exactly `WSL2_Detected`.
- [ ] Distro never launched (`--no-launch`) → may not be detected until first launch (Group A checks mitigate this).
- [ ] ProductCode-based uninstall commands can drift after self-update; resolve the current ProductCode
      at uninstall time or document that the command targets only the originally uploaded MSI.
