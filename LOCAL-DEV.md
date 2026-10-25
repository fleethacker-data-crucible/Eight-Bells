# LOGHAWK — local development (no CAC)

Run `Launch-LocalDev.bat` on your **personal Windows PC** after checking out the feature branch. Do not run on a managed system to evade organization security controls.

## What it does

- Prerequisite: Windows PowerShell 5.1.
- Startup: New -LocalDev mode uses %LOCALAPPDATA%\LogHawk-LocalDev for the encrypted DPAPI store and logs, separate from %LOCALAPPDATA%\LogHawk. Browser UI and import/analysis flows operate against this test database.
- Boundary: AI endpoints remain optional and still require separate credentials. Import only simulated watch logs; no CAC/real operational logs are required.
- Diagnostics / manual check: `powershell.exe -NoProfile -File Start-LogHawk.ps1 -LocalDev -Diagnostics`.
- Lifecycle: the server stops itself shortly after its tab closes. `Launch-LocalDev.bat --stay` keeps it running, `--replace` replaces a running LogHawk without asking, and `Stop-LogHawk.ps1` stops every instance. The runtime file is `%LOCALAPPDATA%\LogHawk-LocalDev\logs\loghawk-server-<pid>.json`.

## Workflow

```powershell
git fetch origin
git switch feature/local-dev-no-cac-launcher
.\Launch-LocalDev.bat
```

Normal launchers and production authentication remain unchanged. This is **not** an authenticated Navy session. Do not enter CUI, classified material, real credentials or real personnel information during personal-computer testing.

For release, delete the local development launcher from the release branch or leave it out of the release package. Real connections must continue to require approved credentials and authorization.
