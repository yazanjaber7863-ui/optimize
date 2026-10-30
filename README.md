# Optimize

[![Latest Release](https://img.shields.io/github/v/release/yazanjaber7863-ui/optimize?color=%230567ff&label=Latest%20Release&style=for-the-badge)](https://github.com/yazanjaber7863-ui/optimize/releases/latest)

Optimize is a one-stop Windows tool. It installs your apps, removes bloat, speeds up gaming, checks your PC's health and backs up your setup. It keeps a record of everything it changes, so you can undo any of it later or reapply it after a Windows update.

---

## Quick Start

> **Optimize needs to run as Administrator** because it changes system-wide settings.

Open PowerShell or Terminal as admin, then run:

```ps1
irm https://github.com/yazanjaber7863-ui/optimize/releases/latest/download/winutil.ps1 | iex
```

**Or use the app:** download `Optimize.exe` from the [latest release](https://github.com/yazanjaber7863-ui/optimize/releases/latest) and double-click it. It asks for admin rights itself and offers to update when a new version is out.

### How to open an admin terminal

- **Start menu:** Right-click Start → *Terminal (Admin)* or *Windows PowerShell (Admin)*
- **Search:** Press the `Windows key`, type `PowerShell`, then press `Ctrl + Shift + Enter`

---

## What's Inside

| Tab | What it does |
|-----|--------------|
| **Install** | Installs and updates apps with winget, including 7-Zip, VLC, VS Code, Python, Spotify, Java 21 + Prism Launcher and RustDesk. If an app needs Chocolatey, Optimize asks first and offers to remove Chocolatey afterwards. |
| **Tweaks** | Applies privacy, debloat and performance tweaks, including Chrome and Firefox debloat, Hardware-Accelerated GPU Scheduling and Game Bar. Tweaks that don't apply to your Windows edition (Home, Pro, Enterprise) are greyed out with the reason. |
| **Gaming** | Gaming Mode, ping test, speed test, DNS switcher, PC-wide ad blocking (asks first) and LuaMacros for macro keyboards. |
| **Health** | PC info, What's Using My PC, disk health, temperatures and an optional weekly health check that notifies you only when something is wrong. |
| **Maintenance** | One-click clean-up, startup apps, driver updates, restore points, a big-files finder and Windows Update settings. Also **See What Optimize Changed**, **Reapply Optimize Changes** and **Undo All Optimize Changes**. |
| **Backup** | Backs up and restores your apps, drivers and Wi-Fi networks; saves and loads your whole Optimize setup to move it to another PC. |
| **Win11 Creator** | Builds your own Windows 11 ISO or USB from an official ISO: keep one edition, add updates, remove parts of Windows (Copilot, Widgets, OneDrive, Teams...), turn on features, add your drivers, skip the Microsoft account, and have Optimize apply your preset and apps on first login. |
| **Config** | Fixes the clock, internet and system files (SFC / DISM), and turns on Windows features such as Hyper-V, WSL, Windows Sandbox and .NET. |

### Safety

- **Change journal:** every change is recorded in `%ProgramData%\Optimize\changes.json` with its value before and after. You can undo it all, or reapply it after a big Windows update resets things.
- **Automatic restore point:** made before big changes, at most one a day.

---

## Presets

Apply a ready-made setup without clicking through the tabs:

```powershell
& ([ScriptBlock]::Create((irm https://github.com/yazanjaber7863-ui/optimize/releases/latest/download/winutil.ps1))) -Preset Recommended
```

| Preset | Description |
|--------|-------------|
| `Recommended` | Safe defaults, adjusted to your Windows edition |
| `MySetup` | My personal setup |
| `Advanced` | Deeper tweaks for power users |
| `FullSetup` | Everything in one go: apps and tweaks |

To see exactly what each preset does, read [config/preset.json](config/preset.json).

---

## Build It Yourself

```powershell
.\Compile.ps1          # builds winutil.ps1
.\Compile.ps1 -Run     # builds it and opens it
```

To build `Optimize.exe`, run `tools\launcher\Build-OptimizeExe.ps1`.

---

## Credits

Optimize is a fork of [Chris Titus Tech's Windows Utility (WinUtil)](https://github.com/ChrisTitusTech/winutil), released under the MIT License. Many thanks to Chris Titus and all the WinUtil contributors for the base this is built on.
