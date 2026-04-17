# Copilot Execution Prompt: Python Data Value Validation

Use this prompt when you want instruction-only guidance for building a custom Python SQL validator for dashboard values.

## How to run with Copilot

In Copilot Chat, send:

`Execute the instructions in Python_Data_Value_Test.md exactly.`

---

## Objective

Provide step-by-step instructions for users to create their own preferred Python CLI validator script for dashboard value checks.

Example target:
- Show sales of branch `ABV` in `March 2026`.

---

## Hard Requirements

1. Read PBIP semantic model and report metadata before creating SQL.
2. Detect if the report already has a visual related to **Sales by Branch**.
3. If yes, detect measure(s) used by that visual and use the measure as the base for SQL validation.
4. Do not create or modify Python implementation files automatically.
5. Provide a clear implementation blueprint so users can build their preferred script themselves.
6. Do not modify report/semantic model source content.
7. Save validation output under `tests/results/`.

---

## Execution Steps

### Phase 1: Discover PBIP artifacts

Locate:
- `*.pbip`
- `*.Report/definition/`
- `*.SemanticModel/definition/`

If missing, stop and report missing artifact(s).

### Phase 2: Inspect semantic model

Read semantic model files:
- `*.SemanticModel/definition/model.tmdl`
- `*.SemanticModel/definition/**/*.tmdl`

Extract:
- measures
- measure expressions
- table and column names

### Phase 3: Inspect report visuals

Read:
- `*.Report/definition/report.json`
- `*.Report/definition/pages/pages.json`
- `*.Report/definition/pages/*/visuals/*/visual.json`

Find visuals that indicate sales-by-branch context.

### Phase 4: Resolve base measure

Priority:
1. Measure referenced by sales-by-branch visual
2. Measure name containing both sales and branch
3. Any measure containing sales

### Phase 5: Provide custom validator blueprint (instruction-only)

Do not generate implementation files by default.

Provide:
- recommended file location options in `tests/python/`
- CLI argument contract (`--branch`, `--month`, `--year`, optional `--dry-run`)
- SQL generation logic design
- result output contract in `tests/results/`
- dependency options (for example `pyodbc`, SQLAlchemy, connector-specific drivers)

Behavior required:
- accepts branch, month, year args
- infers SQL mapping from base measure expression where possible
- runs SQL through `pyodbc`
- prints generated SQL and validated value in CLI
- writes output to:
  - `tests/results/python_value_validation.md`
  - `tests/results/python_value_validation.json`
  - `tests/results/history/python_value_validation_<timestamp>.md`

### Phase 6: Provide execution examples (template commands)

Run:

```powershell
python tests/python/<your_script_name>.py --branch ABV --month March --year 2026
```

If database credentials are unavailable, run with:

```powershell
python tests/python/<your_script_name>.py --branch ABV --month March --year 2026 --dry-run
```

### Phase 7: Return concise summary in chat

Return:
1. Instruction package generated confirmation
2. Base measure selected
3. SQL pattern proposed
4. CLI execution template shared
5. Result file paths

---

## Output Contract

- Primary output: implementation instructions for user-owned script creation
- Primary result files: under `tests/results/`
- No model/report content changes
