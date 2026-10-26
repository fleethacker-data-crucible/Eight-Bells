# Eight Bells walkthrough

Import watch logs, review their quality, and build an evidence-linked turnover for the relieving watchstander.

> **Screenshots:** captured with demo data and scanned by the Chief of Staff (team directive 10).

## Before you start

- Windows PowerShell 5.1 (part of Windows). No administrator rights and no installer.
- Microsoft Edge or Google Chrome.
- Launch: Double-click `Launch-EightBells.bat` (starts a local PowerShell 5.1 service and opens the browser).
- Synthetic, non-sensitive training logs only. Samples are in `samples/`.

## Steps

### 1. First launch

Eight Bells opens on the **Command Center**, empty until you import logs.

*The NON-OPERATIONAL TRAINING BUILD banner at the top of most pages is the app's built-in training-build disclaimer. It is part of the app, not a marking on the data.*

![Eight Bells Command Center on first launch with no logs imported, all counts at 0, and the built-in training-build disclaimer banner.](../assets/walkthrough/01-first-launch.png)

### 2. Import logs

In **Ingestion Studio**, add log files and select **Analyze and securely import**. Text, CSV and JSON exports are parsed. The *SIMULATED / TRAINING ONLY* lines come from the synthetic sample logs themselves.

![Eight Bells Ingestion Studio with an extraction preview of a sample log and three synthetic sample logs in the imported source library.](../assets/walkthrough/02-ingest.png)

### 3. Review quality

**Quality Assurance** flags potential unresolved conditions, repeated content and out-of-sequence times. Select a log and a finding to review its source lines. Here the discrepancy sample log shows its Pump B finding.

![Eight Bells Quality Assurance page for the sample discrepancy log, with the Pump B unresolved-condition finding open next to its source lines.](../assets/walkthrough/03-quality.png)

### 4. Build the turnover

**Watch Turnover** builds a draft briefing for a source log: relevant observations, potentially open conditions and quality findings, each linked to its source lines. Select **Generate draft**; a human must verify it.

![Eight Bells Watch Turnover review draft for the sample discrepancy log, listing observations and the open Pump B condition with source lines.](../assets/walkthrough/04-turnover.png)

### 5. Keep lessons learned

**Operational Memory** keeps lessons learned across watches, drawn from the imported sample logs. Mark a draft lesson reviewed once you have checked it.

![Eight Bells Operational Memory with the sample log sources and a lesson library of two lessons from the sample logs, one draft and one reviewed.](../assets/walkthrough/05-memory.png)

### 6. See it at a glance

The **Command Center** now summarizes the watch.

![Eight Bells Command Center after import: 3 log sources, 5 quality flags, 2 open conditions and 2 memory records, with the recent sample logs.](../assets/walkthrough/06-command-center.png)

### 7. AI and diagnostics

**AI & Diagnostics** holds the optional AI provider for this session and the diagnostics console. AI stays off until you configure a provider.

![Eight Bells AI and Diagnostics page with AI off: placeholder provider URL and model, an empty API key, and the diagnostics console.](../assets/walkthrough/07-settings.png)

## About these images

Images live in [`docs/assets/walkthrough/`](../assets/walkthrough/), named `NN-<screen>.png` after the step they belong to. They are 1440x900 at 100% scale in the Dark (Eight Bells has one theme) theme, and show demo data only.
