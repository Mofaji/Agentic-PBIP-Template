# Copilot Execution Prompt: Measure Killer-Style PBIP Test

Use this file as an execution prompt in GitHub Copilot Chat.

## How to run with Copilot

In Copilot Chat, send:

`Execute the instructions in PowerBI_Test.md exactly.`

---

## Hard Requirements

1. Do **not** run Python, Node, or any custom script.
2. Perform a full analysis directly from PBIP/TMDL/JSON files using file reads/searches.
3. Be thorough (take time, inspect all relevant files, do not shortcut).
4. Write final results to `Testing/test_results.md`.
5. Do not modify model/report source files.
6. Use severity visual markers in Markdown findings:
	- `🔴 CRITICAL`
	- `🟠 HIGH`
	- `🟡 MEDIUM`
	- `🟢 LOW`
	- `🔵 INFO`
7. Include BPA (Best Practice Analyzer) assessment from Microsoft rules in the same output markdown.
8. Follow the exact report layout template in `Phase 5B` for neat formatting.

---

## Execution Instructions (for Copilot)

### Phase 1: Discover and validate project artifacts

1. Find the PBIP root by locating:
	- `*.pbip`
	- `*/SemanticModel/definition/` or `*.SemanticModel/definition/`
	- `*/Report/definition/` or `*.Report/definition/`
2. If these are not found, stop and report exactly what is missing.

### Phase 2: Build semantic model inventory (manual analysis)

Read and analyze these files:

- `*.SemanticModel/definition/model.tmdl`
- `*.SemanticModel/definition/relationships.tmdl`
- all `*.SemanticModel/definition/tables/*.tmdl`

Extract and count:

1. Table list
2. Column list per table
3. Calculated columns (`column <name> = ...`)
4. Measure list per table (`measure '<name>' = ...`)
5. Measures with missing `formatString`
6. M query local absolute paths (`File.Contents("...")`)
7. Date/auto-date signals (`LocalDateTable_*`, `DateTableTemplate_*`)
8. Relationships:
	- total count
	- from/to columns
	- bidirectional relationships (`crossFilteringBehavior: bothDirections`)

### Phase 3: Build report inventory (manual analysis)

Read and analyze these files:

- `*.Report/definition/report.json`
- `*.Report/definition/pages/pages.json`
- each page `*.Report/definition/pages/*/page.json`
- each visual `*.Report/definition/pages/*/visuals/*/visual.json`

Extract and count:

1. Total pages and page names
2. Total visuals
3. Visual type distribution
4. Visuals per page
5. Report measure references from visual JSON:
	- `field.Measure.Expression.SourceRef.Entity`
	- `field.Measure.Property`
6. Report column references from visual JSON:
	- `field.Column.Expression.SourceRef.Entity`
	- `field.Column.Property`
7. Additional metadata references where present:
	- `selector.metadata`
	- `queryRef`

### Phase 4: Usage and integrity checks (manual, deterministic)

Using data from Phase 2 + 3, compute:

1. **Unresolved report measure references**
	- referenced by visuals but not found in model measure inventory
2. **Unresolved report column references**
	- referenced by visuals but not found in model column inventory
3. **Unused measures (best-effort static)**
	- start with direct measure refs from visuals
	- expand through transitive measure-to-measure dependencies by scanning DAX `[MeasureName]` usage
	- any model measure not reached is unused candidate
4. **Unused columns (best-effort static)**
	- columns used in visual refs
	- plus columns used in measure DAX (`Table[Column]` patterns)
	- plus columns used in relationships
	- any model column not reached is unused candidate

### Phase 5: Produce final output file

Create or overwrite `Testing/test_results.md` with these sections:

1. `# Measure Killer-Style PBIP Test Results`
2. `## Test Metadata`
	- date/time
	- scope note: local/offline PBIP only
3. `## What Was Checked`
	- executed checks
	- not possible without Power BI Service/Tenant APIs
4. `## Summary Metrics` (table)
	- table_count, column_count, measure_count, calculated_column_count
	- relationship_count, bidirectional_relationship_count
	- page_count, visual_count
	- unresolved_report_measure_refs_count
	- unresolved_report_column_refs_count
	- unused_measure_count
	- unused_column_count
5. `## Findings`
	- unresolved references (full list)
	- unused measures (full list)
	- unused columns (full list)
	- missing format strings (full list)
	- bidirectional relationship details
	- local absolute source paths
	- date table signals
6. `## Visual Inventory`
	- visual type distribution table
	- visuals-per-page table
7. `## Verdict`
	- PASS or WARNING with reasoning
8. `## Notes and Limitations`
	- explicitly list checks requiring service/tenant telemetry

### Phase 5A: Severity and warning style (must match gist-like clarity)

In `## Findings`, every finding must be written as:

`### [SEVERITY] Finding title`

Use this exact style mapping:

- `### 🔴 [CRITICAL] ...`
- `### 🟠 [HIGH] ...`
- `### 🟡 [MEDIUM] ...`
- `### 🟢 [LOW] ...`
- `### 🔵 [INFO] ...`

For each finding include these fields:

- `**Issue:**`
- `**Evidence:**` (file paths, object names, counts)
- `**Impact:**`
- `**Recommendation:**`

Add a top warning banner directly under title:

- If any critical/high exists: `> ⚠️ Overall Risk: HIGH`
- Else if medium exists: `> ⚠️ Overall Risk: MEDIUM`
- Else: `> ✅ Overall Risk: LOW`

Add a severity summary table before detailed findings:

| Severity | Count |
|---|---:|
| 🔴 Critical | X |
| 🟠 High | X |
| 🟡 Medium | X |
| 🟢 Low | X |
| 🔵 Info | X |

Important: Standard Markdown in GitHub does not support literal colored text reliably. Use these emoji severity markers as the visual red/yellow/green equivalent.

### Phase 5B: Neat formatting template (mandatory)

Use this exact section order and style in `Testing/test_results.md`:

1. `# Measure Killer-Style + BPA PBIP Test Results`
2. Risk banner line (`> ⚠️ Overall Risk: ...` or `> ✅ Overall Risk: LOW`)
3. `## Executive Summary` (3-6 bullets max)
4. `## Test Metadata` (small key-value bullet list)
5. `## Scope` with two checklists:
	- `### ✅ Executed`
	- `### 🚫 Not Testable in Local PBIP`
6. `## Summary Metrics` (single compact markdown table)
7. `## Severity Summary` (single compact markdown table)
8. `## Findings (Measure Killer-style)`
9. `## BPA Rules Compliance (Static PBIP Assessment)`
10. `## Unified Verdict`
11. `## Appendix` (large object lists and rule-by-rule full matrix)

Formatting constraints:

- Keep all tables aligned and consistently ordered.
- Keep top sections concise; move long lists to `## Appendix`.
- Use one blank line between headings and content.
- Avoid duplicate findings across sections.
- Sort detailed lists alphabetically unless chronological order is required.
- In findings, always show count in heading, e.g. `### 🟠 [HIGH] Unused Measures (19)`.

### Phase 6: Return concise chat summary

After writing `Testing/test_results.md`, return in chat:

1. Confirmation file was generated
2. Key counts from summary metrics
3. Number of warnings/findings
4. Top 3 highest-impact issues

### Phase 7: BPA assessment in the same markdown file

Read BPA rules from:

- `https://raw.githubusercontent.com/microsoft/Analysis-Services/master/BestPracticeRules/BPARules.json`

Then append to the same output file (`Testing/test_results.md`) a new section:

`## BPA Rules Compliance (Static PBIP Assessment)`

Required BPA output content:

1. Total BPA rules count
2. Rule-by-rule status with one of:
	- `PASS`
	- `FAIL`
	- `NOT_TESTABLE`
3. Category summary (Performance, DAX Expressions, Error Prevention, Maintenance, Naming Conventions, Formatting)
4. Detailed list of failed BPA rules with evidence
5. Detailed list of NOT_TESTABLE rules and reason

BPA severity mapping (mandatory):

- BPA `Severity = 3` → `🔴 [CRITICAL]`
- BPA `Severity = 2` → `🟠 [HIGH]`
- BPA `Severity = 1` → `🟡 [MEDIUM]`
- Non-failing informational notes → `🔵 [INFO]`

BPA finding structure:

For each failed BPA rule, use:

- `### <mapped severity> <Rule ID> - <Rule Name>`
- `**Category:** ...`
- `**Scope:** ...`
- `**Status:** FAIL`
- `**Evidence:** ...`
- `**Recommendation:** ...`

For each not-testable BPA rule, use:

- `### 🔵 [INFO] <Rule ID> - NOT_TESTABLE`
- `**Reason:** ...`
- `**What is missing:** ...`

Required BPA notes:

- Do not claim full Tabular Editor BPA parity for rules that require runtime metadata.
- Mark any rule requiring runtime lineage, VertiPaq stats, role memberships, or service metadata as `NOT_TESTABLE`.

### Phase 8: Unified final verdict

At the end of `Testing/test_results.md`, add:

- `## Unified Verdict`
- one line for Measure Killer-style checks verdict
- one line for BPA static assessment verdict
- one overall combined verdict with rationale

---

## Output Contract

- Primary output file must be: `Testing/test_results.md`
- No scripts should be executed.
- No unrelated files should be changed.
- Findings must include severity markers (`🔴🟠🟡🟢🔵`) exactly as defined above.
- BPA rule results must be included in the same `Testing/test_results.md` file.
- BPA failed rules must use mapped severity levels from BPA numeric severities.
- Final markdown must follow the `Phase 5B` layout exactly.
