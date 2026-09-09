# AI Context in this Repository

How this template feeds context to a coding agent, and why it is arranged the way it is.

Background reading: Eugene Meidinger's [*A Beginner's Guide to Writing Markdown for AI Context*](https://tabulareditor.com/blog/markdown-and-ai-context-for-beginners) (Tabular Editor). The structure below follows the model it describes.

---

## Why markdown

Markdown is the substrate for agent instructions, and that is not an aesthetic choice:

- **LLMs are saturated in it.** Documentation sites, READMEs, and Stack Overflow are markdown, so models both read and emit it fluently.
- **It is lean.** No packaging, no schema, no closing tags. A rule costs roughly what the rule says, which matters when every session pays for its context.
- **It is plain text.** It diffs, it reviews in a pull request, and it lives in git next to the artifacts it governs — unlike a `.docx`, which is a zip of XML.
- **Humans read it unrendered.** The same file is the agent's instruction and the team's documentation.

## Markdown next to the other formats in a PBIP project

| Format | Where it appears here | Written by | Human-editable |
| --- | --- | --- | --- |
| **Markdown** | `copilot-instructions.md`, `AGENTS.md`, `.claude/skills/*/SKILL.md`, `specs/` | humans and agents | designed for it |
| **JSON** | `Template.Report/definition/**` (PBIR), `report.json`, themes | build scripts | technically yes, painfully — deep nesting, every string quoted, every brace tracked |
| **TMDL** | `Template.SemanticModel/definition/**` | build scripts, Tabular Editor | yes — unquoted strings, indentation instead of braces |
| **YAML** | `.github/workflows/*.yml` | humans | yes, but whitespace-fragile |

JSON, TMDL, and YAML are machine formats that tolerate human editing. Markdown is a human format that machines happen to read well. Use each for what it is: the rules go in markdown, the artifacts stay in their own formats.

---

## The three layers

Borrowed from [Kiro's](https://kiro.dev/docs/) vocabulary, because the three-way split is the useful part.

| | Answers | Lifetime | Loads when | Authority |
| --- | --- | --- | --- | --- |
| **Steering** | *How* do we build, always | Permanent, versioned, maintained | Every session, automatically | Highest |
| **Specs** | *What* are we building, this once | Per deliverable, disposable | Read on demand for one task | Local to its task |
| **Hooks** | *When* does something run | Permanent, code not prose | Fired on harness events | Deterministic — no judgement |

The distinction earns its keep because the three fail in different ways. Steering that grows unbounded stops being read. A spec that gets maintained turns into a second rulebook that contradicts the first. A hook that encodes judgement blocks work it should not have blocked.

### Steering — the rules that always apply

| File | Loaded by | Contains |
| --- | --- | --- |
| `copilot-instructions.md` (root) | **nothing automatically** — it is the rulebook every other steering file points to | The full PBIP authoring rules: schema constraints, visual JSON templates, formatting rules, SVG measure architecture. ~700 lines. |
| `AGENTS.md` | Agents that follow the AGENTS.md convention | The guardrails, the precedence rule, the layer map. A digest. |
| `CLAUDE.md` | Claude Code, every session | `@AGENTS.md` plus the skill inventory, hook table, and fix budget. |
| `.github/copilot-instructions.md` | GitHub Copilot, every session | The same digest, pointing at the root rulebook. |
| `.github/instructions/*.instructions.md` | Copilot, scoped by `applyTo` glob | Topic rules that only load for matching file types (DevOps, RLS, custom visuals). |
| `.claude/skills/*/SKILL.md` | Claude Code, routed by `description` | Procedures — how to verify a render, build a field-parameter page, review a model. |

The digests exist because of a mechanical fact: **a harness only auto-loads the filename it looks for.** Claude Code reads `CLAUDE.md`; Copilot reads `.github/copilot-instructions.md`; the cross-vendor convention is `AGENTS.md`. A 700-line rulebook at a path none of them check is a rulebook that loads only when a human remembers to ask for it. The digests are small on purpose; detail belongs in the rulebook, and duplicated detail rots.

### Specs — what we are building this once

`specs/` holds one file per dashboard or page: the measures, the page grid, the visual-to-field bindings, the exceptions, and a definition of done. Written before the build, not after.

The point is to move decisions in front of the work. Without a spec, a request goes from one sentence of chat straight to generated PBIR JSON, and the first review happens when Power BI Desktop either renders it or refuses to open it.

Specs are disposable and are **not** authority. When a rule in a spec turns out to apply to the next dashboard too, it graduates into `copilot-instructions.md`. See `specs/README.md`.

### Hooks — what runs whether or not anyone remembers

Prose asks. Hooks enforce. Configured in `.claude/settings.json`, implemented in `scripts/hooks/`:

| Event | Script | Enforces |
| --- | --- | --- |
| `SessionStart` | `pbip-session-brief.ps1` | The guardrails and live bridge status are in context before the first prompt |
| `PreToolUse` | `pbip-write-guard.ps1` | No writes to `Proposals/`, `**/.pbi/`, `tests/screenshots/`, `.claude/.pbip-state/` |
| `PostToolUse` | `pbip-validate-hook.ps1` | Every PBIP JSON written parses; TMDL has no BOM, no `//` comments, and no measure/column name collision |
| `Stop` | `pbip-stop-hook.ps1` | The turn does not end until the rendered screenshots have been reviewed |

Two design rules every hook here follows:

- **Fail open.** Every hook exits 0 on anything unexpected. A `Stop` hook that blocks on a broken bridge makes the session impossible to end.
- **Cheap enough to run every time.** `pbip-validate-hook.ps1` parses exactly the one file that was just written; it deliberately does not call `scripts/validate-json.ps1`, which recurses the whole repository. `pbip-session-brief.ps1` reads the bridge's named pipe rather than shelling out to the CLI.

A worked example of choosing the layer: Power BI Desktop refuses to load a project whose model has a measure named the same as a column, and reports it as a modal dialog. The bridge cannot read that dialog — during a failed load there is no report to serve the API, and no bridge method exposes the UI.

That error is plainly visible in the TMDL, so the first answer is a hook: `scripts/Test-PbipSemantics.ps1` finds it at the keystroke and the dialog never appears. **When a machine can decide it, do not spend context asking an agent to remember it.**

The second answer is `scripts/Get-PbipLoadError.ps1`, for the errors static analysis cannot see — a TMDL grammar fault, say. It reads the dialog through UI Automation: the on-screen text, the full diagnostic behind "Copy details to clipboard", and a cropped screenshot as a fallback. It stays the *second* line of defence because it depends on control names a Desktop update could rename, while the source check depends only on the source.

The same script splits its own checks by how transient they are. File-local ones (a collision inside one table) hold no matter what else is half-written, so they run on every edit. Cross-file ones (model-wide duplicate measures, relationship endpoints, unresolved references) would fire constantly during a multi-file build, so they run once in the verify loop, where the model is meant to be complete.

Honest limits: the write guard sees `Write`/`Edit`/`NotebookEdit` only, so shell redirection through Bash or PowerShell goes around it — it is a guardrail, not a sandbox. And hook JSON contracts vary between Claude Code versions; if a hook stops firing after an upgrade, check `/hooks` first.

---

## Which layer does a new rule belong to?

- Will it apply to **every** dashboard from now on? → steering, in `copilot-instructions.md`.
- Is it true only for **this** dashboard? → the spec.
- Can a script decide it without judgement? → a hook. If a machine can check it, do not spend context asking an agent to remember it.
- Is it a **procedure** rather than a rule — a sequence someone follows to get something done? → a skill under `.claude/skills/`, with a `description` that says *when* to use it. That description is the only routing signal the agent gets.

## Documentation that travels with the project

Markdown in the repository ships with the artifacts: clone the repo and the rules, specs, and skills arrive with the PBIP.

One caveat the source article does not raise: **keep project docs in `docs/` and `specs/`, not inside `Template.SemanticModel/` or `Template.Report/`.** Those are Fabric item folders with an expected file inventory, and stray files risk confusing git-sync. The docs still travel — they are in the same repository, one directory over.

For documentation that must live *in* the model rather than beside it, use TMDL's own mechanisms: `///` description lines on measures and tables, which surface in Power BI, in Tabular Editor, and to Copilot and data agents querying the model. Guardrail 10 requires them. An undocumented measure is a measure the next agent will duplicate.
