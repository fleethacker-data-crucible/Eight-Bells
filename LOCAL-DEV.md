# Eight Bells — local development (no CAC)

Run `Launch-LocalDev.bat` on your **personal Windows PC** after checking out the feature branch. Do not run on a managed system to evade organization security controls.

## What it does

- Prerequisite: Windows PowerShell 5.1.
- Startup: New -LocalDev mode uses %LOCALAPPDATA%\EightBells-LocalDev for the encrypted DPAPI store and logs, separate from %LOCALAPPDATA%\EightBells. An existing %LOCALAPPDATA%\LogHawk-LocalDev folder is copied forward once and left untouched. Browser UI and import/analysis flows operate against this test database.
- Boundary: AI endpoints remain optional and still require separate credentials. Import only simulated watch logs; no CAC/real operational logs are required.
- Diagnostics / manual check: `powershell.exe -NoProfile -File Start-EightBells.ps1 -LocalDev -Diagnostics`.

## Workflow

```powershell
git fetch origin
git switch feature/local-dev-no-cac-launcher
.\Launch-LocalDev.bat
```

Normal launchers and production authentication remain unchanged. This is **not** an authenticated Navy session. Do not enter CUI, classified material, real credentials or real personnel information during personal-computer testing.

For release, delete the local development launcher from the release branch or leave it out of the release package. Real connections must continue to require approved credentials and authorization.
