# Eight Bells CLI and API for agents

Everything the browser app can do to your stored records is also a named command, `eightbells <noun> <verb>`. Scripts and agents can run them without a browser. This follows the Fleet "CLI and API parity" convention (Bowerbird's `docs/CLI.md` is the model).

The CLI runs in its own process. It opens no port and starts no server. It reads and writes the **same encrypted store** as the app (`%LOCALAPPDATA%\EightBells\store.v2.dpapi`, Windows DPAPI for the current user), and parses logs with a PowerShell port of the engine (`EightBells-Engine.ps1`) that is held to the JavaScript engine by a golden file.

Synthetic, non-sensitive logs only, as everywhere in Eight Bells.

## Running a command

    eightbells.bat <noun> <verb> [--option value ...] [--json] [--out file] [--yes] [--dry-run]
    eightbells.bat commands [--json]

or, from PowerShell:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\eightbells.ps1 log list --json

| Option | Meaning |
| --- | --- |
| `--json` | Print one JSON object instead of readable text. |
| `--out <file>` | Write the output to a file, UTF-8 without a BOM, instead of the screen. (For `export json` it names the export file.) |
| `--yes` | Required for destructive commands. |
| `--dry-run` | Show the route and the request, then stop without running or writing anything. |
| `--data-dir <folder>` | Use another data folder. Default: `%LOCALAPPDATA%\EightBells`, or `EIGHTBELLS_DATA_DIR` if set. |
| `--local-dev` | Use the LocalDev folder, as `Launch-LocalDev.bat` does. |

Put options after the two command words. A value that starts with `--` is not taken as a value.

## Output

With `--json` every command prints one object:

    {"schema":"eightbells.result/1","command":"log import","ok":true,"result":{...}}
    {"schema":"eightbells.result/1","command":"log show","ok":false,"error":"Log not found: nope","usage":false}

In `--json` mode errors go to standard output as the `ok:false` object. Otherwise they go to standard error.

`commands --json` prints `{"schema":"eightbells.commands/1","commands":[...],"excluded":[...]}`. Each command has `name`, `route` (the server route it mirrors), `summary`, `inputs` (each with `flag`, `type`, `required`, `help` and, for choices, `values`), `destructive` and `writes`. `excluded` lists the server routes that have no command, each with the reason.

| Exit code | Meaning |
| --- | --- |
| 0 | OK |
| 1 | The command ran and failed (log not found, file missing, a server is running for this folder) |
| 2 | Usage error: unknown command or option, missing or invalid option, or a destructive command without `--yes` |

## Commands

| Command | Mirrors | Inputs | Notes |
| --- | --- | --- | --- |
| `status show` | `GET /api/state` | | Counts, data folder, whether a server is running. |
| `log list` | `GET /api/state` | | |
| `log show` | `GET /api/state` | `--id` | Analysis summary, findings and open conditions. |
| `log import` | `POST /api/import` | `--file`, `--name`, `--watch`, `--format auto\|text\|csv\|json`, `--interval` | Parses with the engine port. 1.5 MB and 10,000 entries at most, like the app. |
| `finding list` | `GET /api/state` | `--log` | With review counts. |
| `finding review` | `POST /api/review` | `--log`, `--finding`, `--disposition acknowledged\|follow-up\|false-positive`, `--note` | The source log is not changed. |
| `turnover show` | `GET /api/state` | `--log` | The offline draft. Use `--out` for a file. |
| `lesson list` | `GET /api/state` | | |
| `lesson add` | `POST /api/lesson` | `--title`, `--body`, `--source` | Saved as a draft. |
| `lesson review` | `POST /api/lesson/review` | `--id` | A local mark, not an authenticated approval. |
| `memory candidates` | `GET /api/state` | | Equipment with open conditions in at least two logs. |
| `memory search` | `GET /api/state` | `--q` | |
| `export json` | `GET /api/state` | `--out`, `--yes` | Writes an **unencrypted** file. Destructive in the sense that it removes the encryption. |

## What is deliberately not a command

These server routes have no command, and `tests/Cli-Test.ps1` fails if a new route appears that is neither mirrored nor listed here with a reason:

| Route | Why |
| --- | --- |
| `GET /health`, `POST /api/heartbeat`, `POST /api/shutdown` | The lifecycle of a running server and its tab. Stop a server from the shell with `Stop-EightBells.ps1`. |
| `GET /api/diagnostics` | Reads the running server's log lines. |
| `POST /api/ai/config`, `POST /api/ai/run`, `POST /api/vision` | Session-bound: the endpoint and key live only in the running server's memory, and every request needs consent in the page. |

The browser-only features (voice, PDF reading, the JSON Lines / table / XML adapters, watch-profile rules, the Halyard export) are not in the CLI: they run in the page.

## Writing while the app is open

A command that writes refuses to run while an Eight Bells server is running for the same data folder (exit 1), so two writers cannot overwrite each other. Reading is always allowed. Close the app or run `Stop-EightBells.ps1` first.

## Limits

- The engine port reads text, CSV and JSON. Other formats are imported through the browser.
- The CLI does not check the audit chain; see the audit-trail PR for `GET /api/audit/verify`.
