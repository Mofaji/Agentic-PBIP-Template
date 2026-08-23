# Alert Email Report — Build Instructions
## General Template for Any DB · Outlook-Safe HTML · Python

---

## 1. Project Structure

```
db_alert/
├── alert.py          ← main script

```

**requirements.txt**
```
pyodbc
pandas
python-dotenv
```

---

## 2. Credentials — Store in `.env`

Never hardcode passwords in the script. Use a `.env` file.

**.env**
```
DB_SERVER=your-db-host
DB_NAME=your-database
DB_USER=your-username
DB_PASSWORD=your-password
DB_DRIVER=ODBC Driver 17 for SQL Server

SMTP_EMAIL=no-reply@org.com
SMTP_PASSWORD=myapppassword
```

**.gitignore**
```
.env
*.pyc
__pycache__/
```

**Load in Python**
```python
from dotenv import load_dotenv
import os

load_dotenv()

SERVER        = os.environ['DB_SERVER']
DATABASE      = os.environ['DB_NAME']
USERNAME      = os.environ['DB_USER']
PASSWORD      = os.environ['DB_PASSWORD']
DRIVER        = os.environ['DB_DRIVER']
SMTP_EMAIL    = os.environ['SMTP_EMAIL']
SMTP_PASSWORD = os.environ['SMTP_PASSWORD']
```

---

## 3. Script Skeleton — 5 Phases

Every alert script follows this exact 5-phase pattern:

```
PHASE 1 — CONFIG          (constants, labels, color palette)
PHASE 2 — DB CONNECTION   (get_conn)
PHASE 3 — FETCH           (fetch_*)
PHASE 4 — BUILD HTML      (build_html)
PHASE 5 — SEND EMAIL      (send_email)
PHASE 6 — MAIN            (main)
```

---

## 4. Phase 1 — Config Block

```python
import os, pyodbc, pandas as pd, warnings, traceback, smtplib
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from dotenv import load_dotenv

load_dotenv()
warnings.filterwarnings('ignore', category=UserWarning, module='pandas')

# ── DB ────────────────────────────────────────────────────────────────────────
SERVER   = os.environ['DB_SERVER']
DATABASE = os.environ['DB_NAME']
USERNAME = os.environ['DB_USER']
PASSWORD = os.environ['DB_PASSWORD']
DRIVER   = os.environ['DB_DRIVER']

# ── Email ─────────────────────────────────────────────────────────────────────
SMTP_EMAIL    = os.environ['SMTP_EMAIL']
SMTP_PASSWORD = os.environ['SMTP_PASSWORD']
TO_LIST = [
   
]

# ── Report period ─────────────────────────────────────────────────────────────
CY        = datetime.now().year
YTD_START = f'{CY}0101'
TODAY     = datetime.now().strftime('%Y%m%d')

# ── Domain constants (adjust per report) ─────────────────────────────────────
# Example: tracked categories, thresholds, labels
TRACKED_TYPES = ['TYPE_A', 'TYPE_B']
TYPE_LABELS   = {
    'TYPE_A': 'Human-readable label A',
    'TYPE_B': 'Human-readable label B',
}

# ── Color palette ─────────────────────────────────────────────────────────────
C_DARK    = '#0d3b6e'    # header / footer / section bars
C_MID     = '#1e5ba8'    # secondary header elements
C_ACCENT  = '#90caf9'    # subtitle text, table accents
C_GREEN   = '#2e7d32'    # all-clear / positive
C_RED     = '#c62828'    # alert / negative
C_AMBER   = '#f57f17'    # warning / medium
C_TEXT    = '#333333'    # body text
C_ROW_ALT = '#f8f6f3'    # alternating table row
C_ROW_WHT = '#ffffff'
```

---

## 5. Phase 2 — DB Connection

**SQL Server (pyodbc)**
```python
def get_conn():
    cs = (f'DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={DATABASE};'
          f'UID={USERNAME};PWD={PASSWORD}')
    return pyodbc.connect(cs, timeout=60)
```

**PostgreSQL (psycopg2)**
```python
import psycopg2
def get_conn():
    return psycopg2.connect(
        host=SERVER, dbname=DATABASE, user=USERNAME, password=PASSWORD
    )
```

**MySQL (mysql-connector)**
```python
import mysql.connector
def get_conn():
    return mysql.connector.connect(
        host=SERVER, database=DATABASE, user=USERNAME, password=PASSWORD
    )
```

> Always call `conn.close()` in a `finally` block (see Phase 6).

---

## 6. Phase 3 — Fetch Functions

One function per logical dataset. Always return a `pd.DataFrame`.

```python
def fetch_mismatches(conn) -> pd.DataFrame:
    sql = """
    SELECT
        col1,
        col2,
        SUM(amount) AS total_amount
    FROM my_schema.my_table
    WHERE date_col >= :start
      AND date_col <= :end
    GROUP BY col1, col2
    ORDER BY total_amount DESC
    """
    # For pyodbc — pass params as tuple after sql
    sql_pyodbc = sql.replace(':start', '?').replace(':end', '?')
    return pd.read_sql(sql_pyodbc, conn, params=(YTD_START, TODAY))
```

> `pd.read_sql` works with pyodbc connections directly.
> Wrap in `warnings.filterwarnings('ignore')` to suppress the SQLAlchemy warning.

---

## 7. Phase 4 — Build HTML

### 7.1 Severity Logic

Always classify the alert before building HTML — drives the badge color and subject line.

```python
if total_issues == 0:
    severity_color = C_GREEN
    severity_label = 'ALL CLEAR'
    severity_icon  = '✔'
elif total_issues <= 20:
    severity_color = C_AMBER
    severity_label = 'WARNING'
    severity_icon  = '⚠'
else:
    severity_color = C_RED
    severity_label = 'ALERT'
    severity_icon  = '✖'
```

---

### 7.2 Outlook-Safe HTML Rules

| ❌ Do NOT use | ✅ Use instead |
|---|---|
| `background:` shorthand | `background-color:` inline |
| `background: linear-gradient(...)` | flat `background-color` only |
| `border-radius:` | skip — ignored by Outlook |
| `box-shadow:` | skip — not supported |
| `display:flex` / `display:grid` | `<table>` layout only |
| `<div>` for colored backgrounds | `<td bgcolor="...">` |
| `max-width:` on `<table>` | `width="720"` HTML attribute |

---

### 7.3 Email Outer Wrapper

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Alert Title</title>
</head>
<body style="margin:0;padding:0;background-color:#f0f2f5;
             font-family:'Segoe UI',Arial,sans-serif;">

<table width="100%" cellpadding="0" cellspacing="0" border="0"
       bgcolor="#f0f2f5" style="background-color:#f0f2f5;">
<tr><td align="center" style="padding:16px 8px;">

  <table width="720" cellpadding="0" cellspacing="0" border="0"
         style="width:720px;max-width:720px;">
    <!-- ALL SECTIONS GO HERE -->
  </table>

</td></tr></table>
</body>
</html>
```

---

### 7.4 Header Strip

```html
<tr>
  <td bgcolor="{C_DARK}"
      style="background-color:{C_DARK};padding:22px 28px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td>
          <div style="font-size:20px;font-weight:700;color:#ffffff;letter-spacing:.5px;">
            AAA &mdash; Report Title
          </div>
          <div style="font-size:12px;color:{C_ACCENT};margin-top:3px;">
            Subtitle | Period | Generated at {now_str}
          </div>
        </td>
        <td align="right">
          <!-- Severity badge -->
          <div style="background-color:{severity_color};color:#ffffff;
                      padding:6px 18px;font-size:13px;font-weight:700;
                      display:inline-block;letter-spacing:.5px;">
            {severity_icon}&nbsp; {severity_label}
          </div>
        </td>
      </tr>
    </table>
  </td>
</tr>
```

---

### 7.5 KPI Cards (4-card row, equal height)

Each card uses a nested `<table>` with `bgcolor` on the inner `<td>`. Never use `<div>` for card backgrounds.

```python
def kpi(label, value, color, bg, border):
    return (
        f'<td width="25%" style="padding:6px;" valign="top">'
        f'<table width="100%" cellpadding="0" cellspacing="0" border="0" style="height:100%;">'
        f'<tr>'
        f'<td bgcolor="{bg}" style="background-color:{bg};border:1px solid {border};'
        f'padding:14px 10px;text-align:center;height:100%;">'
        f'<div style="font-size:10px;color:#777;text-transform:uppercase;'
        f'letter-spacing:.5px;font-weight:600;margin-bottom:6px;">{label}</div>'
        f'<div style="font-size:22px;font-weight:800;color:{color};letter-spacing:-.5px;">'
        f'{value}</div>'
        f'</td></tr></table></td>'
    )
```

```html
<!-- KPI Row in the HTML template -->
<tr>
  <td bgcolor="#ffffff" style="background-color:#ffffff;padding:4px 10px 8px 10px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr style="height:100px;">
        {kpi('Card 1', value1, color1, bg1, border1)}
        {kpi('Card 2', value2, color2, bg2, border2)}
        {kpi('Card 3', value3, color3, bg3, border3)}
        {kpi('Card 4', value4, color4, bg4, border4)}
      </tr>
    </table>
  </td>
</tr>
```

**Standard KPI Card Color Sets**

| Card | Value Color | BG | Border |
|---|---|---|---|
| Positive / Total | `#0d3b6e` | `#eef3fb` | `#c8d8eb` |
| Warning Count | `#f57f17` | `#fffde7` | `#ffe082` |
| Error / Missing | `#c62828` | `#fdf2f2` | `#f0c8c8` |
| All-Clear / OK | `#2e7d32` | `#eef8f0` | `#b8dcc0` |

---

### 7.6 Summary Table (grouped by category)

```python
def build_summary_table(df_grouped):
    rows_html = ''
    for i, row in df_grouped.iterrows():
        bg = C_ROW_WHT if i % 2 == 0 else C_ROW_ALT
        diff_color = C_RED if row['gap'] > 0 else C_GREEN
        rows_html += (
            f'<tr style="background-color:{bg};">'
            f'<td style="padding:8px 12px;font-weight:700;color:{C_DARK};">{row["category"]}</td>'
            f'<td style="padding:8px 12px;text-align:right;">{row["count"]:,}</td>'
            f'<td style="padding:8px 12px;text-align:right;color:{diff_color};font-weight:700;">'
            f'{row["gap"]:,.2f}</td>'
            f'</tr>'
        )
    return f"""
    <table width="100%" cellpadding="0" cellspacing="0"
           style="border-collapse:collapse;font-size:12px;margin-bottom:24px;">
      <thead>
        <tr bgcolor="{C_DARK}" style="background-color:{C_DARK};color:#ffffff;">
          <th style="padding:9px 12px;text-align:left;">Category</th>
          <th style="padding:9px 12px;text-align:right;">Count</th>
          <th style="padding:9px 12px;text-align:right;">Gap (SAR)</th>
        </tr>
      </thead>
      <tbody>{rows_html}</tbody>
    </table>"""
```

---

### 7.7 Detail Table (per-record rows)

```python
def build_detail_table(df_sub, title, total_gap):
    rows_html = ''
    for j, r in df_sub.iterrows():
        bg = C_ROW_WHT if j % 2 == 0 else C_ROW_ALT
        rows_html += (
            f'<tr style="background-color:{bg};">'
            f'<td style="padding:7px 11px;font-family:monospace;">{r["id"]}</td>'
            f'<td style="padding:7px 11px;">{r["description"]}</td>'
            f'<td style="padding:7px 11px;text-align:right;">{r["value"]:,.2f}</td>'
            f'</tr>'
        )
    return f"""
    <div style="margin-bottom:28px;">
      <!-- Section title bar -->
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
        <tr>
          <td bgcolor="{C_DARK}"
              style="background-color:{C_DARK};padding:9px 14px;color:#ffffff;
                     font-weight:700;font-size:13px;">
            {title}
            <span style="float:right;font-size:11px;font-weight:400;">
              {len(df_sub):,} records &nbsp;|&nbsp; Gap: SAR {total_gap:,.2f}
            </span>
          </td>
        </tr>
      </table>
      <!-- Table -->
      <table width="100%" cellpadding="0" cellspacing="0"
             style="border-collapse:collapse;font-size:12px;border:1px solid #ddd;border-top:none;">
        <thead>
          <tr bgcolor="#d0e8f0" style="background-color:#d0e8f0;">
            <th style="padding:8px 11px;text-align:left;">ID</th>
            <th style="padding:8px 11px;text-align:left;">Description</th>
            <th style="padding:8px 11px;text-align:right;">Value (SAR)</th>
          </tr>
        </thead>
        <tbody>{rows_html}</tbody>
        <tfoot>
          <tr bgcolor="#eef2f6" style="background-color:#eef2f6;font-weight:700;">
            <td colspan="2" style="padding:8px 11px;text-align:right;">Total</td>
            <td style="padding:8px 11px;text-align:right;color:{C_RED};">{total_gap:,.2f}</td>
          </tr>
        </tfoot>
      </table>
    </div>"""
```

---

### 7.8 Section Header Bar

```python
def section_header(title):
    return f"""
    <tr>
      <td bgcolor="{C_DARK}"
          style="background-color:{C_DARK};padding:8px 24px;">
        <span style="color:#ffffff;font-size:12px;font-weight:700;letter-spacing:.5px;">
          &#9632; {title}
        </span>
      </td>
    </tr>"""
```

---

### 7.9 Note Strip

```html
<tr>
  <td bgcolor="#e8f4fd"
      style="background-color:#e8f4fd;padding:10px 24px;border-top:1px solid #bee3f8;">
    <span style="font-size:11px;color:#1565c0;">
      <strong>&#128206; Note:</strong> Data sourced from PRD SQL Server.
      Excludes cancelled documents. Currency: SAR.
    </span>
  </td>
</tr>
```

---

### 7.10 Footer

```html
<tr>
  <td bgcolor="{C_DARK}"
      style="background-color:{C_DARK};padding:14px 28px;text-align:center;">
    <div style="font-size:11px;color:#90caf9;margin-bottom:4px;">
      For any changes contact:
      <a href="mailto:itsm@org.com"
         style="color:#64b5f6;text-decoration:none;font-weight:700;">itsm@org.com</a>
      &nbsp;|&nbsp; &copy; 2026 org &mdash; Automated Report
    </div>
    <div style="font-size:9px;color:#5c8ab8;">
      Source: PRD.TABLE_NAME &nbsp;|&nbsp; Currency: USD &nbsp;|&nbsp; {now_str}
    </div>
  </td>
</tr>
```

---

## 8. Phase 5 — Send Email

```python
def send_email(html: str, subject: str):
    msg = MIMEMultipart('alternative')
    msg['Subject'] = subject
    msg['From']    = SMTP_EMAIL
    msg['To']      = SMTP_EMAIL          # sender in To, recipients in Bcc
    msg['Bcc']     = ', '.join(TO_LIST)
    msg.attach(MIMEText(html, 'html'))

    with smtplib.SMTP('smtp.office365.com', 587) as server:
        server.ehlo()
        server.starttls()
        server.ehlo()
        server.login(SMTP_EMAIL, SMTP_PASSWORD)
        server.sendmail(SMTP_EMAIL, TO_LIST, msg.as_string())
```

**Subject line pattern**
```python
subject = (
    f'⚠ [Alert] Report Name — {datetime.now():%d %b %Y}'
    if total_issues > 0
    else f'✔ Report Name OK — {datetime.now():%d %b %Y}'
)
```

---

## 9. Phase 6 — Main

```python
def main():
    t0 = datetime.now()
    print(f'[{t0:%Y-%m-%d %H:%M:%S}] Starting ...')

    # 1. Connect
    try:
        conn = get_conn()
        print('  [OK] Connected.')
    except Exception as e:
        print(f'  [ERROR] DB connection failed: {e}')
        traceback.print_exc()
        return

    # 2. Fetch
    try:
        df = fetch_mismatches(conn)
        print(f'  [OK] {len(df):,} rows fetched.')
    except Exception as e:
        print(f'  [ERROR] Query failed: {e}')
        traceback.print_exc()
        return
    finally:
        conn.close()

    # 3. Skip if no issues (optional — remove if you always send)
    if df.empty:
        print('  No issues found. Email skipped.')
        return

    # 4. Build HTML
    try:
        html = build_html(df)
    except Exception as e:
        print(f'  [ERROR] HTML build failed: {e}')
        traceback.print_exc()
        return

    # 5. Preview mode
    import sys
    if '--preview' in sys.argv:
        out = Path(__file__).parent / f'preview_{datetime.now():%Y%m%d}.html'
        out.write_text(html, encoding='utf-8')
        print(f'  Preview saved: {out}')
        return

    # 6. Send
    try:
        subject = f'⚠ Alert — {datetime.now():%d %b %Y}'
        send_email(html, subject)
        print('  [OK] Email sent.')
    except Exception as e:
        print(f'  [ERROR] Send failed: {e}')
        traceback.print_exc()

    print(f'  Done in {(datetime.now() - t0).total_seconds():.1f}s')


if __name__ == '__main__':
    main()
```

---

## 10. Format Helpers

Always define these at the top of the script:

```python
def fmt(v, decimals=0):
    """Format number with commas. Always absolute value."""
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return '—'
    return f'{abs(v):,.{decimals}f}'

def fmt_pct(v, decimals=1):
    """Format 0.185 → 18.5%"""
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return '—'
    return f'{v * 100:,.{decimals}f}%'

def fmt_date(v):
    """Format date to DD-MMM-YYYY."""
    if pd.isna(v):
        return '—'
    try:
        return pd.to_datetime(v).strftime('%d-%b-%Y')
    except Exception:
        return str(v)

def safe_div(a, b):
    """Safe division — returns 0.0 if b is zero or None."""
    if not b:
        return 0.0
    return a / b
```

---

## 11. Color Reference

| Usage | Hex |
|---|---|
| Header / footer / section bars | `#0d3b6e` |
| Secondary header button | `#1e5ba8` |
| Subtitle / accent text | `#90caf9` |
| Footer secondary text | `#5c8ab8` |
| Positive / all-clear green | `#2e7d32` |
| Alert red | `#c62828` |
| Warning amber | `#f57f17` |
| Body text | `#333333` |
| Alternating row | `#f8f6f3` |
| Page background | `#f0f2f5` |
| Note strip background | `#e8f4fd` |
| Note strip border | `#bee3f8` |
| Note strip text | `#1565c0` |

---

## 12. Quick Checklist Before Sending

- [ ] Credentials in `.env`, not hardcoded
- [ ] `.env` in `.gitignore`
- [ ] All `<table>` layouts — no `<div>` for backgrounds
- [ ] `bgcolor="..."` attribute on every colored `<td>` alongside `style="background-color:..."`
- [ ] No `border-radius`, `box-shadow`, `flexbox`, `grid`
- [ ] Email `width="720"` fixed
- [ ] `conn.close()` inside `finally`
- [ ] `--preview` flag works before scheduling
- [ ] Subject line reflects severity (✔ / ⚠)
- [ ] `TO_LIST` set correctly; `msg['To']` = sender, `msg['Bcc']` = recipients
