# Adding an app to Optimize

The exact steps to add an app to the Install tab, test it, and publish it so the one-line
command and `Optimize.exe` get it. Run every command in **PowerShell as administrator**.

## 0. Once per Windows account

Let Git use the repo folder (it was created under another account):

```powershell
git config --global --add safe.directory E:/claude-only/projects/winutil
```

Sign in to GitHub, so releases can be published (follow the browser steps):

```powershell
gh auth login
```

Install the test tool (skip if `Get-Module -ListAvailable Pester` already shows 5.8.0):

```powershell
Install-Module -Name Pester -RequiredVersion 5.8.0 -Repository PSGallery -Scope CurrentUser -Force -SkipPublisherCheck
```

## 1. Open the project

Do this at the start of every PowerShell window. The first line lets scripts run in this
window only; it changes no setting.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
cd E:\claude-only\projects\winutil
```

## 2. Find the app's IDs

```powershell
winget search "Minecraft"
winget show --id Mojang.MinecraftLauncher -e
```

Check that the publisher in `winget show` is the real one. The `Id` is what goes in `"winget"`.

For Chocolatey, search https://community.chocolatey.org/packages. If there is no package, or
it has not been updated in years, use `"na"`.

## 3. Add it to `config/applications.json`

Paste a block like this anywhere between two existing entries (mind the commas):

```json
    "minecraftlauncher": {
        "category": "Games",
        "choco": "na",
        "content": "Minecraft Launcher",
        "description": "One or two sentences on what it is and who it is for.",
        "link": "https://www.minecraft.net/download",
        "winget": "Mojang.MinecraftLauncher",
        "foss": false
    },
```

- **Key** (`"minecraftlauncher"`): lowercase letters and numbers only, not used by another app.
- **category**: one of Browsers, Communications, Development, Document, Games,
  Microsoft Tools, Multimedia Tools, Pro Tools, Selfhosted Tools, Utilities.
- **content**: the name shown in the app.
- **foss**: `true` only if the app is free and open source.

Check the file is still valid JSON (no output means fine):

```powershell
Get-Content config\applications.json -Raw | ConvertFrom-Json | Out-Null
```

## 4. Test it

Check the winget ID really installs, then remove it again:

```powershell
winget install --id Mojang.MinecraftLauncher -e
winget uninstall --id Mojang.MinecraftLauncher -e
```

Build Optimize and run the tests that read the app list:

```powershell
.\Compile.ps1
Import-Module Pester -RequiredVersion 5.8.0 -Force
Invoke-Pester -Path pester\configs.Tests.ps1, pester\install-workflow.Tests.ps1, pester\search-filter.Tests.ps1 -Output Detailed
```

Every test must pass. To run all of them, use `Invoke-Pester -Path pester -Output Detailed`.
The 11 WinOneShot tests only pass in PowerShell 7, so without it they fail; that is expected.

Try it in the app itself:

```powershell
.\Compile.ps1 -Run
```

In the Install tab, search for the app, tick it, click Install and wait for it to finish. Check
it is there with `winget list --id Mojang.MinecraftLauncher`. Close Optimize when done.

## 5. Save it to GitHub

```powershell
git add config/applications.json
git commit -m "Add Minecraft Launcher"
git push
```

Pushing updates the code only. People get the app after the release in step 6.

## 6. Publish a release

The tag is today's date as `yy.MM.dd`. If there is already a release today, add `.2`, `.3`...
See the last ones with:

```powershell
gh release list -R yazanjaber7863-ui/optimize -L 3
```

Then, with your tag in place of `26.11.06`:

```powershell
.\Compile.ps1
.\tools\launcher\Build-OptimizeExe.ps1 -Version 26.11.06
Set-Content -Path $env:TEMP\notes.txt -Value "Added Minecraft Launcher to the Install tab."
gh release create 26.11.06 .\winutil.ps1 .\binary\Optimize.exe -R yazanjaber7863-ui/optimize --target main --latest --notes-file $env:TEMP\notes.txt
```

Write the notes to a file like this: typing them straight into `--notes` breaks on quotes.

## 7. Check the release works

Wait about two minutes: new downloads fail or give the old file for a short while. Then this
should print `True`:

```powershell
(irm https://github.com/yazanjaber7863-ui/optimize/releases/latest/download/winutil.ps1) -match 'Mojang.MinecraftLauncher'
```

An older `Optimize.exe` should now offer to update itself when it opens.

## If something goes wrong

| Problem | Fix |
|---|---|
| `detected dubious ownership` | Run the `safe.directory` command in step 0. |
| `running scripts is disabled` | Run the `Set-ExecutionPolicy -Scope Process` line in step 1. |
| `gh: To get started... gh auth login` | Run `gh auth login`. |
| Windows Defender deletes `Optimize.exe` | Do not turn Defender off. Report it at microsoft.com/wdsi/filesubmission as a false positive. |
