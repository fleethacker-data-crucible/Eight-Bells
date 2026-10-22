# LogHawk
Local-first Naval watchstanding log intelligence prototype.

## Start
On Windows, right-click `Start-LogHawk.ps1` and run with PowerShell, or run `powershell -NoProfile -File .\Start-LogHawk.ps1`. Opens a localhost browser UI on a dynamically selected port. Requires Windows PowerShell 5.1+.

## Implemented
- Local browser UI for importing text, CSV, JSON, and text-extractable logs; original file preserved in local data directory.
- Structured entry detection, log quality checks, missing intervals, repeated readings, and unresolved issue hints.
- Turnover draft generation and human-reviewed lessons learned with persistent local JSON data.
- Evidence excerpts and timestamps, audit log, search, and JSON export.
- Zero external network calls, no installation required.

## Important limitations
This is an operational prototype, **not an accredited Navy system**. Do not ingest CUI, classified, or other sensitive operational records. JSON data is **not encrypted**; production must implement authenticated access, approved encryption, authorization, and audit protections. OCR/handwriting, PDF/Office ingestion, Arc, SQLCipher, and AI model integration are not yet implemented. The heuristic engine does not prove falsification and must not make disciplinary judgments. Never use generated turnover drafts in place of required official logs or procedures.

## Architecture
`Start-LogHawk.ps1` hosts a loopback-only HTTP service, exposes static UI and local API, and stores imported records under `data/`. The UI is in `web/index.html`. The service requires no cloud access. Log schema and feature backlog in `docs/ARCHITECTURE.md`.
