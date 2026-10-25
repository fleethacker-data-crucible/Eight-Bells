# LogHawk v2 — Local-First Watchstanding Intelligence

**Status:** Windows-first engineering prototype, **not accredited** for sensitive or operational Navy data. **Use synthetic, non-sensitive training logs only.** The system does not replace authoritative watch records, qualified watch relief, or approved procedures.

LogHawk ingests log text and structured exports, highlights possible quality deficiencies, drafts watch turnover, preserves event histories, and supports evidence-linked lessons learned.

## Quick start (Windows)

1. Clone: `git clone https://github.com/ashable2/loghawk.git`
2. Double-click **`LogHawk.bat`**. This starts a hidden PowerShell 5.1 service, selects a free localhost port on the same bound socket, opens your browser with a temporary session token, and shows a startup status.
3. Use **`LogHawk-CLI.bat`** for an interactive terminal with diagnostics and the same GUI.
4. Closing the LogHawk tab stops the server on its own (about 5 s after the tab closes, or 20 s after the last heartbeat). Use **End session** in the sidebar to stop it immediately.

### Session lifecycle

- **Tab owns the server.** The open tab sends `POST /api/heartbeat` every 5 s and a `navigator.sendBeacon` leaving signal when it closes. The server stops 20 s after the last heartbeat, or 5 s after a leaving signal with no newer heartbeat; a reload or a second tab keeps it running. A request that is still running (save, import, AI call) always finishes first.
- **One instance.** Launching again while LogHawk runs asks *stop it and start fresh?*. `LogHawk.bat --replace` answers yes; `LogHawk.bat --stay` keeps the server running after the tab closes. Both options also work with `LogHawk-CLI.bat` and `Launch-LocalDev.bat` (or `-Replace` / `-Stay` on `Start-LogHawk.ps1`).
- **Off switch.** Set `LOGHAWK_AUTO_STOP=0` in the environment to turn auto-stop off (LogHawk has no env/config file).
- **Stop from the shell.** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Stop-LogHawk.ps1` stops every running LogHawk server without knowing its PID.
- **Runtime file.** Each server writes `%LOCALAPPDATA%\LogHawk\logs\loghawk-server-<pid>.json` (pid, port, url, startedAt; never the session token) beside its existing store, and deletes it on stop. `-LocalDev` uses `%LOCALAPPDATA%\LogHawk-LocalDev\logs`. Stale files (dead pid) are removed by the launcher and `Stop-LogHawk.ps1`.

Process-scoped `-ExecutionPolicy Bypass` is used only to launch the script without changing machine policy. It cannot override Group Policy, AppLocker, or WDAC restrictions.

### Try sample files

Browse the synthetic fixtures under [samples](samples/README.md).
- `engineering_normal.log` — routine entries without expected quality flags.
- `engineering_discrepancy.txt` — unresolved equipment condition.
- `engineering_repetition.log` — suspiciously repeated content.
- `engineering_chronology.txt` — out-of-sequence timestamp.
- `readings.csv` — actual CSV header/row parsing.
- `elog_export.json` — actual JSON event parsing.
- `noisy_ocr.txt` — transcription corruption.
- `form_watch.html` — printable simulated paper form, suitable for a synthetic photograph.

## Implemented in v2

| Capability | Implementation |
| --- | --- |
| Local server | Loopback-only raw TCP HTTP service (no HttpListener, URLACL or administrator requirement) |
| Launch | Process-only execution policy; GUI/background and visible CLI launchers; OS-assigned port |
| Session | Random per-process bearer token in browser URL fragment; authenticated API; Host and Origin checks |
| Storage | User-scoped Windows DPAPI encrypted store under `%LOCALAPPDATA%\LogHawk\store.v2.dpapi` |
| Formats | Text/LOG/Markdown, structured CSV and JSON, pasted transcriptions |
| Images | Local preview; manual transcript or explicit opt-in remote vision transcription (PNG/JPEG/WebP, 2MB max) |
| PDF | **Manual transcription only; no PDF extraction engine** |
| Quality | Timestamp regression, configurable reading interval gaps, copy-forward candidates, missing dispositions |
| Evidence | Source line references for entries and quality findings |
| Review | Append-only-in-application reviewer dispositions, explanations and timestamps |
| Turnover | Offline deterministic draft with source line references, suspected unresolved conditions |
| Memory | Local searchable log/lesson store, recurring equipment candidates across separate logs |
| AI | Manually configured OpenAI-compatible chat endpoint, optional key held **in process memory only** |
| Privacy | No remote calls unless manually configured and explicitly authorized for each AI request |
| Diagnostics | Local service logs (excluding log content and AI keys), GUI diagnostics and status |
| Testing | Node parsing QA regression tests and Windows PowerShell 5.1 authenticated service smoke test |

**Important qualifiers:** "Append-only-in-application" is not tamper-proof; users with filesystem/control of the same Windows account may still affect the store. DPAPI protects data at rest for a Windows user, **not** cross-account sharing, administrator compromise, or enterprise access control. The application has no identity proofing for the person marking a lesson "reviewed." AI outputs are not automatically approved or trusted.

## Data boundaries

- The encrypted database is in the user's local AppData directory, not the Git repository.
- The original imported text is stored within the encrypted record; **image files themselves are not stored**. The user must review and save their transcription.
- Exporting JSON explicitly creates an **unencrypted** file. Handle or remove exported files appropriately.
- Old `data/records.json` from v1 is **not automatically migrated**; it remains an unencrypted legacy file and should not contain sensitive data.
- The server listens only on `127.0.0.1`; network access to other workstations is not enabled.
- No background or automatic AI analysis is performed.

## AI configuration

Go to **AI & Diagnostics**, enter a specific approved HTTPS `/chat/completions` endpoint (or HTTP loopback for a local model), model name and optional session-only bearer key. The AI path expects OpenAI-compatible JSON response structure. Arc credentials are **not integrated in this build**; do not copy production secrets into an unapproved environment. Vision transcription requires a model that accepts image_url data payloads. Every request requires affirmative consent at the point of use.

## Testing

Windows:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Smoke-Test.ps1
```

Node.js:
```bash
node tests/engine.test.js
node tests/lifecycle.test.js
```

The GitHub Actions workflow validates PowerShell syntax, fixture parsing, and an isolated Windows end-to-end smoke flow. CI should be checked before claiming a Windows build is verified.

## Outstanding for controlled operational deployment

Dedicated electronic-log adapters, offline OCR, secure shared-device identity/RBAC, interoperable Arc credential vault integration, approved SQLCipher backend, immutable audit chain, file-based original-document vault, model governance and evaluation, records retention, accreditation and cyber authorization. These are explicit engineering requirements, not claimed completed features.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for architecture, security boundaries and roadmap.
