# Eight Bells v2 — Implementation and Security Architecture

## Trust boundaries
1. Browser interface loads only from `http://127.0.0.1:<ephemeral-port>`.
2. PowerShell 5.1 opens a `TcpListener` directly bound to loopback on an OS-assigned port; it never creates a public HttpListener URL reservation.
3. The browser receives a per-process random token in the *URL fragment*. The server requires it in `X-EightBells-Token` on every API request. The token is **not** stored in the encrypted database.
4. State is serialized into a versioned JSON object **before** encryption with Windows DPAPI CurrentUser. Backup and replacement are atomic at the file level. This is not a shared-shipboard identity architecture.
5. Local logs and diagnostic traces exclude source content and bearer credentials. A local user with access to the account's files can still delete records or modify the application. No system-wide tamper resistance is claimed.
6. External AI is OFF until manually configured. Per-call consent is required. Vision images are uploaded only to the explicitly entered AI endpoint; retention by the upstream provider is outside Eight Bells' control.

## Source evidence pipeline
- `web/engine.js` (UMD, runs in browser and in Node tests): format-adapter selection; RFC-like quoted CSV parsing; JSON object/array entry mapping; timestamp recognition; source line/row mapping; elementary entity matching; deterministic QA flags; cross-watch recurrence candidates; and conservative turnover generation.
- `web/app.js`: UI state, authenticated API requests, preview and source verification, reviewer dispositions, turnover generation, memory search, diagnostics and opt-in AI workflow.
- `Start-EightBells.ps1`: loopback HTTP host, authenticated API, storage, reviews, drafts, safe AI proxy.
- `web/styles.css`: standalone responsive design system, no CDN or external JavaScript.

The browser posts extracted entries and QA findings along with source text, and the server stores all values. This is appropriate for a **single-user prototype**. A production-grade implementation MUST do parsing and verification in a trusted backend and enforce schema validation before persisting results.

## Current limitations of the quality engine
- Repeated *identical normalized narratives* and repeated readings are candidates for inspection, **not falsification findings**.
- Resolution and outstanding condition inference are heuristic. Entities may be missing; a generic `restored` statement cannot be safely assumed to resolve a named fault.
- Crossing midnight can be legitimate; small timestamp regressions are flagged while large rollover is treated as possible watch transition.
- Watch-specific reading requirements must be configured manually in the UI. Limits and form requirements are not yet validated against authoritative data.
- Every finding must be reviewed against actual source documents, equipment, procedures and contemporaneous records.

## Future schema
`SourceDocument(id,sha256,mime,classification,origin,retention)` →
`ExtractedRegion(id,source_id,page,bounds,text,confidence,verified_by)` →
`WatchEntry(id,source_id,watch_profile,time,asset_id,narrative)` →
`Event(id,entry_ids,type,state)` →
`Finding(id,event_ids,rule,confidence,review_status)` →
`Turnover(id,watch_id,evidence_ids,approvals)` →
`Lesson(id,event_ids,status,reviewers,supersedes,expiry)`

Use explicit stable IDs, provenance and versioning; never silently rewrite originals.

## Recommended next engineering milestones
1. Replace browser-trusted parser with a signed/offline-capable .NET/PowerShell parser plus schema validation and an immutable raw document vault.
2. Add approved offline image/PDF text and handwriting OCR with evidence bounding boxes, confidence, and correction UI. Do not claim OCR is reliable when not tested.
3. Add SQLCipher or equivalent approved encrypted relational storage with transaction journal, safe backup and recovery, and records retention.
4. Integrate approved Lazarette credential/key APIs only after verifying actual vault interfaces; no fabricated Lazarette module calls or insecure token scraping. Provide manual and Lazarette-managed modes.
5. Add local RBAC/SSO appropriate to shipboard deployment and signed review/approval workflows.
6. Develop watch-profile rules from actual approved requirements; model timestamps, asset identities, units and expected intervals.
7. Add supervised event correlation and semantic retrieval over reviewed lessons, with evaluation against synthetic and approved de-identified test corpora.
8. Red-team application security, AI prompt injection, model exfiltration, HTTP parsing, power loss, concurrency, and malformed files before any live deployment.

## Operational policy
This code is **not** authorized for classified, CUI, OPSEC-sensitive, maintenance-control, or official shipboard logs without appropriate approvals. A local-first prototype is not equivalent to a certified security boundary or accredited system.
