# CLAUDE.md

@AGENTS.md

Everything in `AGENTS.md` applies. Below is what is specific to running this repo in Claude Code.

## Skills

Auto-discovered from `.claude/skills/`. Reach for them by name rather than re-deriving:

| Skill | Use it when |
| --- | --- |
| `powerbi-visual-verify` | Reviewing rendered screenshots; whenever the Stop hook blocks a turn |
| `powerbi-modeling` | Measures, star schema, relationships, RLS, model performance |
| `powerbi-fieldparameter` | Building a field-parameter page (table + bar chart, bookmarks, toggles) |
| `powerbi-dashboard-header` | Header band, page chrome, aligning pages to the reference layout |
| `power-bi-model-design-review` | Auditing an existing model |
| `power-bi-performance-troubleshooting` | Slow report, slow visual, slow refresh |

## Hooks

Configured in `.claude/settings.json`, implemented in `scripts/hooks/`. All of them **fail open** — a hook that blocks on a broken bridge makes the session impossible to end.

| Event | Script | What it does |
| --- | --- | --- |
| `SessionStart` | `pbip-session-brief.ps1` | Injects the guardrails digest and the current Desktop Bridge status |
| `PreToolUse` | `pbip-write-guard.ps1` | Blocks Write/Edit to `Proposals/`, `.pbi/` caches, `tests/screenshots/`, `.claude/.pbip-state/` |
| `PostToolUse` | `pbip-validate-hook.ps1` | Parses every PBIP JSON you write; rejects TMDL with a BOM, `//` comments, or a measure/column name collision |
| `Stop` | `pbip-stop-hook.ps1` | Runs the visual verification loop and blocks until screenshots are reviewed |

The write guard only sees `Write`/`Edit`/`NotebookEdit`. Shell redirection through Bash or PowerShell bypasses it — it is a guardrail, not a sandbox.

## The Stop hook's fix budget

**One round.** Round 1 you review the screenshots and fix. Round 2 you review the confirmation screenshots and **report only — no further edits**. Say plainly what is still wrong instead of starting another cycle.

Change detection is by content hash, not by tool call, because this repo writes PBIP files from Python build scripts. Nothing changed means Power BI is never touched, so "reviewed, nothing to fix" costs nothing.

## Useful commands

```powershell
powershell -NoProfile -File scripts\Test-PbipBridge.ps1                    # preflight: version, pipe, CLIs, instance, PBIR
powershell -NoProfile -File scripts\Invoke-PbipVerify.ps1 -Mode Review     # run the loop by hand
powerbi-desktop status                                                     # which instance has which file open
powershell -NoProfile -File scripts\Test-PbipSemantics.ps1                  # load-time errors, found in source
powershell -NoProfile -File scripts\Invoke-PbipRefresh.ps1                  # refresh data (bridge has no refresh method)
```

If Desktop shows an "Issues were found" dialog and the window stays on *Untitled*, the project did not load. The bridge cannot see that dialog, but two things can:

- `Test-PbipSemantics.ps1` finds most of that class of error in the source, before Desktop is involved.
- `Get-PbipLoadError.ps1` reads the dialog itself when one is up — its text, the "Copy details to clipboard" diagnostic (which names the offending file and line), and a cropped PNG. The verify loop runs it automatically on `load_failed`.

On `load_failed` the loop recovers by itself: capture the dialog → dismiss it → close the spent instance → reopen → retry. The order matters, because `powerbi-desktop open` starts a new instance rather than reusing the running one. Two guarantees: the reopen is **net-zero on failure** (the running-instance count returns to what it was, and anything it starts it also closes), and it only ever closes an instance it started or one that was showing a load-error dialog — a rejected definition never loaded a document, so there is nothing in it to lose. `-NoReopen` disables the recovery.

## House style

- Reference files as clickable paths, and report rendering findings by page **display name**.
- PBIP files are written by Python build scripts (UTF-8, no BOM). Prefer editing the build script over hand-patching generated JSON when a script owns the file.

