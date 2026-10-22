# Synthetic LogHawk ingestion fixtures
ALL CONTENT IS FICTIONAL. No real ship, personnel, equipment identifiers, operating parameters, or events. Not official Navy forms or procedures.

## Ready for current text importer
- engineering_normal.log — routine watch
- engineering_discrepancy.txt — abnormal condition with unresolved follow-up
- engineering_repetition.log — repeated entries for quality QA
- engineering_chronology.txt — out-of-order timestamps
- quarterdeck_watch.txt — quarterdeck event narrative
- damage_control_watch.txt — simulated DC log
- security_patrol.txt — security watch
- multiwatch_history.txt — recurring equipment condition across watches
- readings.csv — structured tabular data (current importer treats as text, not typed CSV)
- elog_export.json — structured export (current importer treats as text, not JSON records)
- noisy_ocr.txt — intentionally corrupted OCR-like transcript

## Future format adapters / parser regression fixtures
- form_watch.html — printable simulated paper log; can print to PDF or photograph to exercise future OCR
- notes.md — Markdown log
- test_cases.json — expected observations for automated test development

## Testing
Use **Log Ingestion** in the browser. Import the .txt, .log, .csv, .json, or .md samples (current UI accepts these as text). The current parser recognizes HHMM or HH:MM, broad issue keywords, repeated identical lines, and backwards timestamps. It does NOT parse structured CSV/JSON fields, ingest PDF/images, validate equipment limits, or infer true resolution status. Those require future adapters.

Expected behavior: repetition fixture raises a repetition flag; chronology fixture raises a chronology flag; discrepancy fixture raises an unresolved-disposition hint; routine log should not trigger issue keyword flag. Review results manually; the heuristics are deliberately simplistic. These fixtures should never be treated as genuine watchstanding evidence.
