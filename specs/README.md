# Specs

A spec is what we are building **this once**. The rulebook (`copilot-instructions.md`) is how we build **always**. Keeping them apart is the whole point of this folder.

Without a spec, a dashboard request goes straight from a sentence in chat to generated PBIR JSON, and the first time anyone sees what was actually decided is when Power BI Desktop either renders it or refuses to open it. A spec moves the decisions — which measures, which visuals, which fields, which page grid — in front of the build, where they are cheap to change.

## When a spec is required

- A new dashboard, or a new page on an existing one
- A new fact table, or a new set of measures that pages will share
- Any rebuild of an existing page that changes its data, not just its styling

Not required for: a colour tweak, a label fix, a measure rename, or anything the rulebook already fully determines.

## Lifecycle

```
copy TEMPLATE.md → fill in → build against it → verify renders → fold durable rules into the rulebook → let the spec go stale
```

Specs are **disposable**. They record one decision at one moment; they are not maintained. Once the page is built and verified, a spec's remaining value is as a record of *why* — so leave it in the repo, but do not update it to match later changes and never treat it as authority. If a rule in a spec turns out to apply to the next dashboard too, that rule belongs in `copilot-instructions.md`, not here. That fold-back step is what stops this folder from silently becoming a second rulebook that disagrees with the first.

## Naming

`specs/<dashboard-or-page-name>.md`, kebab-case. Prefix with `EXAMPLE-` only for the worked examples that ship with the template.

## How this differs from `tests/prompts/`

`tests/prompts/*.md` are **execution prompts** — standing instructions you paste into a chat to run a repeatable job ("execute the instructions in `PowerBI_Test.md` exactly"). They are reused unchanged, and they live in the testing layer.

A spec is written once, for one deliverable, and describes *that* deliverable. Different purpose, different lifetime.

## Definition of done

Every spec ends with the same closing section, and it is not satisfied by valid JSON:

1. `scripts\validate-json.ps1`, `scripts\validate-pbip.ps1`, and `scripts\Test-PbipSemantics.ps1` pass.
2. The PBIP **opens in Power BI Desktop without an error dialog**. If the window stays on *Untitled*, the file did not load — that is a build error to fix, not a prompt to click *continue with errors*.
3. `powerbi-desktop status` reports the project path against a running instance.
4. The verification loop has run and every page screenshot has been reviewed against `.claude/skills/powerbi-visual-verify/SKILL.md`.
5. Findings, if any, are reported by page display name.
