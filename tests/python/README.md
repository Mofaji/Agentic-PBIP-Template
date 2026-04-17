# Python Data Value Validation Instructions

This folder intentionally does not include a fixed Python validator implementation.

Use this area as a build-your-own testing space so each team can create a validator that matches its database, SQL conventions, and governance standards.

## Recommended Approach

1. Read and execute prompt guidance from `tests/prompts/Python_Data_Value_Test.md`.
2. Create your preferred script in this folder, for example:
	- `tests/python/validate_values.py`
	- `tests/python/validate_sales_by_branch.py`
3. Make sure your script can validate scenarios like:
	- sales of branch `ABV` in March 2026
4. Write outputs to `tests/results/` so the test evidence is preserved.

## Suggested Script Capabilities

- Parse PBIP artifacts (`*.pbip`, `definition.pbir`)
- Read semantic model (`*.SemanticModel/definition/**/*.tmdl`)
- Read report visuals (`*.Report/definition/pages/*/visuals/*/visual.json`)
- Detect a Sales-by-Branch visual if present
- Extract measure(s) used and use them as base logic
- Generate SQL and print value in CLI
- Support dry-run mode when credentials are unavailable

## Example Command Pattern

```powershell
python tests/python/<your_script_name>.py --branch ABV --month March --year 2026
```

## Dependencies

Create your own dependency file based on implementation choice, for example:

```powershell
pip install pyodbc
```
