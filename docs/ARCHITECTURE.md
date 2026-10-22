# Architecture and next milestones
## Current
Local loopback PowerShell HttpListener + HTML/JS SPA; file-backed JSON prototype; deterministic parser; quality findings; manual lessons; turnover drafts. Evidence retained in imported content. No LLM requests.

## Planned
1. OCR adapters for image/PDF/TIFF, rotation, table layout, confidence and human verification.
2. Robust import adapters for CSV, JSON, Office, and electronic log exports with canonical schema.
3. SQLCipher database, encrypted content-addressed original vault, schema migrations, backup and recovery.
4. Arc optional key/identity integration, standalone key provider, RBAC, session authentication and CSRF controls.
5. Offline AI provider abstraction; citations to page/line/region; approved model endpoint configuration.
6. Watch-specific validation profiles and required reading intervals; avoid universal false positives.
7. Equipment identity resolution, event linking, graph edges, semantic retrieval, review/approval and revalidation.
8. Audit integrity, controlled export, classification labels and accreditation review.
9. Automated tests, fixture logs, negative test cases, launch diagnostics and CI.

## Trust model
Originals immutable; extraction and inferred findings separate; human-approved knowledge distinct from drafts; every claim should point to evidence. Missing evidence is not proof of wrongdoing. No connection to external AI without explicit authorization. Never use this prototype with operational sensitive records.
