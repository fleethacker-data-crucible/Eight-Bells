# Eight Bells demo walkthrough (for a screen recording)

A shot-by-shot script for a demo video of about 4 minutes 30 seconds. It uses only the synthetic files in `samples/`, an empty store and the Night watch theme. It says what to click, what to say, and, just as important, what **not** to claim.

Eight Bells is a Windows-first engineering prototype. It is **not accredited**, it is for synthetic training logs only, and it does not replace authoritative watch records. Say so at the start and the end.

## Before you record

| Check | How |
| --- | --- |
| A clean, isolated store | Use the LocalDev folder so the demo never touches real records: `Launch-LocalDev.bat --replace`. Start with an empty store (rename or delete `%LOCALAPPDATA%\EightBells-LocalDev` first). |
| Synthetic data only | Import only files from `samples/`. No real names, units, ships, hostnames or operating parameters, on screen or in the narration. |
| Screen | 1440 x 900 at 100% scale, Edge or Chrome, Night watch theme (sidebar theme button), bookmarks bar hidden, notifications off. The same size as the images in `docs/assets/walkthrough/`. |
| The disclaimer | Leave the built-in training-build banner visible on the first screens. It is part of the app. |
| No secrets | Never type or show an API key, token, endpoint credential or vault passphrase. Do not open Lazarette in the recording. |
| Audio | Record the voice-over separately and keep each scene under 25 seconds. Captions on; the script below doubles as the caption text. |

## The core run (everything here is on `main`)

| Time | Screen | Do | Say |
| --- | --- | --- | --- |
| 0:00 | Title card | Hold a plain card: "Eight Bells. Synthetic training data only. Prototype, not accredited." | "Eight Bells helps the relieving watchstander see what is open, what changed, and where the evidence is. This demo uses synthetic training logs only." |
| 0:20 | Launch | Double-click `Launch-EightBells.bat` (or `-LocalDev`). The browser opens on the Command Center welcome panel. | "It runs as a local service on this PC. The open tab owns the server, so closing the tab stops it." |
| 0:40 | Ingestion Studio | Choose `samples/engineering_discrepancy.txt`. Show the extraction preview (entries, times, the Pump B condition). Title it "Engineering 1200-1600", watch profile Engineering, then **Analyze and securely import**. | "A log goes in as text. The preview shows what was extracted, with source line numbers. It is stored encrypted for this Windows account." |
| 1:15 | Quality Assurance | Select the log, then the unresolved-condition finding. Show the source lines beside it. Choose **follow-up**, type "Synthetic demo: check Pump B maintenance record", record the review. | "Findings are prompts to check the record, not conclusions. A reviewer records a disposition and an explanation. The source is never changed." |
| 1:55 | Watch Turnover | Pick the log, **Generate draft**. Scroll to the open Pump B condition and its source line. | "The turnover draft links each point to a source line. It is a draft: a person verifies it." |
| 2:25 | Operational Memory | Import `samples/multiwatch_history.txt` (back in Ingestion Studio), then open Memory. Show the recurring-condition candidate for Pump B across logs. Click it to draft a lesson, save it, then **Mark reviewed**. | "When the same condition stays open across watches, Eight Bells suggests a lesson. The lesson starts as a draft. Marking it reviewed is a local mark, not an authenticated approval." |
| 3:10 | Command Center | Show the counts and the recent logs. | "One screen for the watch: sources, flags, open conditions and memory records." |
| 3:25 | AI & Diagnostics | Show the page with AI off. Do not configure anything. | "AI is off until someone configures it, and every request needs consent. Nothing leaves this PC otherwise." |
| 3:45 | Close | End card with the limits (below). | "Synthetic data only. Not accredited. Findings are advisory." |

## Optional segments

Each of these exists only once its pull request is merged. Record them only for what is merged on the day, and drop the rest. Time budget: 15 to 20 seconds each, placed between 3:10 and 3:25.

| Segment | Needs | Do | Say |
| --- | --- | --- | --- |
| Command line | CLI PR (stacked on the engine-port PR), `eightbells.bat` | In a terminal: `eightbells.bat log import --file samples\engineering_discrepancy.txt --json`, then `eightbells.bat log list`. Close the app first (writes wait for the server). | "Everything the page does to the records is also a command, so a script or an agent can chain it." |
| Audit check | Audit-trail PR | The check is an authenticated API route, and the session token must not appear on screen. Show the test output instead: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Audit-Test.ps1`. | "Each audit entry carries the hash of the one before, so an edit in the middle is detected. It is tamper-evident, not tamper-proof." |
| PDF text | PDF PR | Choose `samples/synthetic_watch.pdf`. Show the text appear and the "unverified" notice. | "A digital PDF's text layer is read. It is not OCR: a scanned page gives no text, and the text must be checked before import." |
| More log formats | E-log adapters PR | Choose `samples/elog_export.jsonl`, then `samples/elog_export.xml`. | "JSON Lines, delimited tables and XML exports are read the same way. These are generic field names, not a real vendor format." |
| Reading rules | Watch-profile PR | Paste `samples/readings_profile_check.csv`, load `samples/profile_engineering_synthetic.json`, show the new findings. | "A profile you write says which readings a watch must record. Eight Bells ships no limits; this sample is synthetic." |
| Read aloud | Voice PR | Generate a draft, click **Read aloud**. | "It speaks with an on-device Windows voice only. An online voice is refused." |
| Lessons to Halyard | Halyard-export PR | In Memory, mark a lesson reviewed, click **Export reviewed lessons for Halyard**. | "Reviewed lessons become backlog proposals for Halyard's sandbox. Sizing stays to be decided." |

Do **not** record: the Fairlead router or the Lazarette key option (they need live services and a real vault), or any AI draft unless a local model is running and the data is synthetic.

## What you can say, and what you cannot

| You can say | You cannot say |
| --- | --- |
| Local-first: loopback only, no remote calls unless AI is configured and consented per request. | That it is secure for operational use, accredited, or approved. |
| Stored encrypted with Windows DPAPI for the current user. | That it protects against another user of the same account, an administrator, or a shared device. |
| Findings are advisory prompts with source line references. | That it detects falsification, proves a log is complete, or judges anyone's conduct. |
| Reviewer notes are recorded and the source is not changed. | That reviews are tamper-proof or that a person's identity is verified. |
| PDF text-layer reading, tested on synthetic files. | That it does OCR or reads scanned documents or handwriting. |
| The AI output is marked unverified. | That the AI draft is correct or approved. |

## Closing card (text)

- Synthetic training data only.
- Windows-first prototype, not accredited, not an official record.
- Findings, drafts and lessons are for a person to verify.

## After recording

1. Watch it once with the sound off: every scene should be readable from the captions and the on-screen text alone.
2. Check every frame for anything that is not synthetic or not from `samples/`.
3. Check the run against the app: the counts on the Command Center in the last scenes should match what was imported.
4. Name the file `EightBells-demo-YYYYMMDD.mp4` and keep the recording out of the repository (screenshots for the README live in `docs/assets/walkthrough/`).
