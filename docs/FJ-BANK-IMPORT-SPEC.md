# FJ Bank Import Specification

> **Purpose**: Standalone specification for implementing bank statement import in FJ.
>
> **Context**: This is Phase 3 of the Strategic AI Advisor roadmap. See `VISION-STRATEGIC-AI-ADVISOR.md` for the full vision.
>
> **Target**: FJ project (Zig/Zap backend)

---

## Table of Contents

1. [Context & Vision](#context--vision)
2. [Phase 3 Deliverables](#phase-3-deliverables)
3. [CSV Import Format](#csv-import-format)
4. [Transaction Data Model](#transaction-data-model)
5. [Storage Structure](#storage-structure)
6. [CLI Interface](#cli-interface)
7. [API Specification](#api-specification)
8. [Use Cases Enabled](#use-cases-enabled)
9. [Future Integration Points](#future-integration-points)

---

## Context & Vision

### The Three-Layer Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         THE COMPLETE PICTURE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                      OMS (Work Layer)                               │   │
│   │   "What am I doing?"                                                │   │
│   │   • Activities, Logs, Projects, Time patterns                       │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                      FJ (Billing Layer)                             │   │
│   │   "What have I billed?"                                             │   │
│   │   • Invoices, Offers, Clients, Rates                                │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                      Bank (Reality Layer)  ◄── THIS PHASE           │   │
│   │   "What actually happened?"                                         │   │
│   │   • Incoming payments (verified revenue)                            │   │
│   │   • Outgoing payments (real expenses)                               │   │
│   │   • Cash position (actual money in account)                         │   │
│   │   • Payment timing and patterns                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why Bank Data Matters

The bank layer provides **ground truth** for financial decisions:

| Without Bank Data | With Bank Data |
|-------------------|----------------|
| "Invoice marked as paid in FJ" | "€4,250 actually hit the account on Nov 20" |
| "Revenue this month: €12,450 (estimated)" | "Revenue received: €8,200 (bank-verified)" |
| "Client usually pays on time" | "Client pays in 14 days avg (12/12 on-time)" |
| "Expenses seem normal" | "AWS bill 89% higher than 6-month average" |

### Roadmap Position

```
Phase 1: FJ Core API                    ✅ DONE
Phase 2: OMS + FJ Integration           ✅ DONE
Phase 3: Bank Import (FJ)               ◄── THIS SPEC
Phase 4: Reconciliation Engine (FJ)
Phase 5: Bank Dashboard (FJ)
Phase 6: Full AI Integration (OMS)
```

---

## Phase 3 Deliverables

This phase delivers:

1. **CLI Command**: `fj import bank <csv-file>`
2. **Data Storage**: Normalized transactions in `bank/transactions.json`
3. **API Endpoint**: `GET /api/v1/transactions`

### What This Phase Does NOT Include

- Automatic invoice reconciliation (Phase 4)
- Bank dashboard UI (Phase 5)
- AI tools for bank data (Phase 6)

---

## CSV Import Format

### Source: BAWAG (Austrian Bank)

**File Characteristics:**
- **Delimiter**: Semicolon (`;`)
- **Encoding**: ISO-8859-1 (Latin-1) - contains German umlauts
- **Header Row**: None (data starts on line 1)
- **Date Format**: DD.MM.YYYY
- **Number Format**: German (`1.234,56` = 1234.56, comma decimal, dot thousands)

### Column Structure

| Index | Field | Example | Description |
|-------|-------|---------|-------------|
| 0 | IBAN | `AT00XXXX00001234567890` | Account IBAN |
| 1 | Description | `Abbuchung Echtzeitüberweisung FE/000000006\|GIBAATWWXXX AT00YYYY00009876543210 Max Mustermann\|Rechnung 2025-042 Beratung` | Multi-part description with pipe separators |
| 2 | Booking Date | `10.06.2025` | When transaction was booked |
| 3 | Value Date | `10.06.2025` | When transaction took effect |
| 4 | Amount | `-1.800,00` or `+5.000,00` | Amount with sign prefix |
| 5 | Currency | `EUR` | Always EUR |

### Sample Rows

```csv
AT00XXXX00001234567890;MC/000000007|Monatliches Kartenentgelt für Karte 001;02.07.2025;02.07.2025;-2,63;EUR
AT00XXXX00001234567890;Abbuchung Echtzeitüberweisung FE/000000006|GIBAATWWXXX AT00YYYY00009876543210 Max Mustermann|Rechnung 2025-042 Beratung;10.06.2025;10.06.2025;-1.800,00;EUR
AT00XXXX00001234567890;Einzahlung FE/000000002|REVOLT21XXX LT00ZZZZ00005555666677 Erika Musterfrau|Stammeinlage;30.04.2025;30.04.2025;+5.000,00;EUR
```

### Description Field Parsing

The description field contains pipe-separated (`|`) segments:

```
Segment 0: Transaction type + reference code
           e.g., "Abbuchung Echtzeitüberweisung FE/000000006"

Segment 1: Counterparty BIC + IBAN + Name
           e.g., "GIBAATWWXXX AT00YYYY00009876543210 Max Mustermann"

Segment 2: Reference/Purpose
           e.g., "Rechnung 2025-042 Beratung"
```

**Reference Code Prefixes:**
- `MC/` - Mastercard (card payments, fees)
- `FE/` - Echtzeitüberweisung (instant SEPA transfer, outgoing)
- `BG/` - Bankgebühr (bank fees)
- `VD/` - Incoming payment (invoice payments received)
- `VB/` - Outgoing bank transfer (non-instant)
- `OG/` - Direct debit (e.g., AWS, recurring services)

**MC/ Transaction Sub-types:**
- `E-COMM` - E-Commerce (online purchases)
- `POS` - Point of Sale (physical card payment)
- Plain text - Bank fees (e.g., "Monatliches Kartenentgelt")

### Amount Parsing

```
Input           → Cents (integer)
"-2,63"         → -263
"+5.000,00"     → 500000
"-1.800,00"     → -180000
```

**Algorithm:**
1. Remove `+` prefix if present
2. Remove thousand separators (`.`)
3. Replace decimal comma with dot (`,` → `.`)
4. Parse as float, multiply by 100, convert to integer

### Foreign Currency Transactions

Some card transactions are in foreign currency (USD). The description contains exchange rate info:

```
SPESEN: 1,12  KURS: 1,155284  VOM:31.10.2025
```

- `SPESEN` = Fee in EUR
- `KURS` = Exchange rate
- `VOM` = Rate date

**The CSV amount column is already in EUR** (converted by the bank). For record-keeping, optionally parse and store:

```json
{
    "amount": -458,
    "original_currency": "USD",
    "original_amount": -400,
    "exchange_rate": 1.155284,
    "exchange_fee": 112
}
```

For Phase 3, storing the converted EUR amount is sufficient. Original currency details are nice-to-have.

---

## Transaction Data Model

### Normalized Transaction

```json
{
    "id": "fe000000006",
    "ref_code": "FE/000000006",
    "date": "2025-06-10",
    "amount": -180000,
    "currency": "EUR",
    "description": "Abbuchung Echtzeitüberweisung FE/000000006|GIBAATWWXXX AT00YYYY00009876543210 Max Mustermann|Rechnung 2025-042 Beratung",
    "counterparty": {
        "name": "Max Mustermann",
        "iban": "AT00YYYY00009876543210",
        "bic": "GIBAATWWXXX"
    },
    "reference": "Rechnung 2025-042 Beratung",
    "type": "outgoing",
    "category": null,
    "source": {
        "file": "BAWAG_Umsatzliste_20251128_1430.csv",
        "line": 2,
        "imported_at": "2025-11-28T14:30:00Z"
    },
    "reconciliation": {
        "invoice_id": null,
        "matched_at": null,
        "confidence": null
    }
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique ID from bank reference code (e.g., "fe000000006") |
| `ref_code` | string | Original reference code (e.g., "FE/000000006") |
| `date` | date | Transaction date (ISO 8601) |
| `amount` | int | Amount in cents. Positive = incoming, Negative = outgoing |
| `currency` | string | Always "EUR" for now |
| `description` | string | Raw description from bank |
| `counterparty.name` | string | Parsed counterparty name (nullable) |
| `counterparty.iban` | string | Parsed IBAN (nullable) |
| `counterparty.bic` | string | Parsed BIC (nullable) |
| `reference` | string | Payment reference/purpose (nullable) |
| `type` | enum | "incoming" or "outgoing" |
| `category` | string | Expense category (nullable, for future use) |
| `source.file` | string | Original CSV filename |
| `source.line` | int | Line number in source file |
| `source.imported_at` | datetime | When imported |
| `reconciliation` | object | For Phase 4 - invoice matching |

---

## Storage Structure

```
fj-home/
└── bank/
    ├── imports/                          # Archived raw CSV files
    │   ├── 2025-07-08_BAWAG_Umsatzliste_20250708_2034.csv
    │   └── 2025-11-28_BAWAG_Umsatzliste_20251128_1430.csv
    │
    ├── transactions.json                 # All normalized transactions
    │
    └── config.json                       # Import configuration (optional)
```

### transactions.json Format

```json
{
    "version": 1,
    "last_updated": "2025-11-28T14:30:00Z",
    "account_iban": "AT00XXXX00001234567890",
    "transactions": [
        { /* transaction object */ },
        { /* transaction object */ }
    ]
}
```

### Deduplication

**Important**: Bank CSV exports typically contain "the last 6 months" of transactions. Regular imports will have **significant overlap** with previously imported data. Robust deduplication is critical.

**Primary Key: Reference Code**

Each transaction has a unique sequential reference code (e.g., `FE/000000006`, `MC/000000083`, `VD/000000089`). This is the most reliable deduplication key.

**Deduplication Algorithm:**
1. Extract reference code from description (regex: `(MC|FE|BG|VD|VB|OG)/\d+`)
2. Check if reference code exists in `transactions.json`
3. If exists → skip (duplicate)
4. If new → add to transactions

**Fallback** (if no reference code found):
- Hash of: date + amount + description (first 100 chars)

**Import Output:**
```
Importing bank transactions...
  Total rows: 90
  New transactions: 15
  Duplicates skipped: 75 (already imported)

✓ Imported 15 new transactions
```

**Edge Case**: Same reference code with different amounts (bank correction)
- Log warning but import as new transaction with suffix: `FE/000000006_corrected`

---

## CLI Interface

### Command: `fj import bank <file>`

```bash
# Basic usage
fj import bank ~/Downloads/BAWAG_Umsatzliste_20250708_2034.csv

# Output
Importing bank transactions from BAWAG_Umsatzliste_20250708_2034.csv...
  Encoding: ISO-8859-1 (auto-detected)
  Format: BAWAG (auto-detected)

  Parsed 7 transactions:
    + 2 incoming   (+€5,000.00)
    - 5 outgoing   (-€1,862.89)
    = Net:         +€3,137.11

  Skipped 0 duplicates

✓ Imported 7 transactions
  Archived to: bank/imports/2025-11-28_BAWAG_Umsatzliste_20250708_2034.csv
```

### Options

```bash
fj import bank <file> [options]

Options:
  --dry-run       Parse and show what would be imported, don't save
  --format=BAWAG  Force format (auto-detected by default)
  --encoding=...  Force encoding (auto-detected by default)
```

### Error Handling

```bash
# File not found
fj import bank missing.csv
Error: File not found: missing.csv

# Parse error
fj import bank bad.csv
Error: Failed to parse line 5: Invalid amount format "abc"

# All duplicates
fj import bank already_imported.csv
Warning: All 7 transactions already exist (duplicates)
No new transactions imported.
```

---

## API Specification

### GET /api/v1/transactions

Get bank transactions with optional filtering.

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `from` | date | (none) | Start date (inclusive) |
| `to` | date | (none) | End date (inclusive) |
| `type` | enum | `all` | Filter: `incoming`, `outgoing`, `all` |
| `limit` | int | 100 | Max results |
| `offset` | int | 0 | Pagination offset |

**Example Request:**

```bash
GET /api/v1/transactions?from=2025-01-01&to=2025-12-31&type=incoming
Authorization: Bearer fj_sk_xxx
```

**Response:**

```json
{
    "transactions": [
        {
            "id": "fe000000002",
            "ref_code": "FE/000000002",
            "date": "2025-04-30",
            "amount": 500000,
            "currency": "EUR",
            "description": "Einzahlung FE/000000002|...",
            "counterparty": {
                "name": "Erika Musterfrau",
                "iban": "LT00ZZZZ00005555666677",
                "bic": "REVOLT21XXX"
            },
            "reference": "Stammeinlage",
            "type": "incoming",
            "category": null
        }
    ],
    "summary": {
        "count": 1,
        "total_incoming": 500000,
        "total_outgoing": 0,
        "net": 500000
    },
    "pagination": {
        "limit": 100,
        "offset": 0,
        "total": 1
    }
}
```

### GET /api/v1/transactions/summary

Get aggregated transaction summary.

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `from` | date | 30 days ago | Start date |
| `to` | date | today | End date |
| `group_by` | enum | `none` | Group: `none`, `month`, `category` |

**Response (group_by=none):**

```json
{
    "period": {
        "from": "2025-01-01",
        "to": "2025-12-31"
    },
    "total_incoming": 500000,
    "total_outgoing": 186289,
    "net": 313711,
    "transaction_count": 7,
    "current_balance": null
}
```

**Response (group_by=month):**

```json
{
    "period": { "from": "2025-01-01", "to": "2025-12-31" },
    "by_month": [
        { "month": "2025-04", "incoming": 500000, "outgoing": 55000, "net": 445000 },
        { "month": "2025-05", "incoming": 0, "outgoing": 263, "net": -263 },
        { "month": "2025-06", "incoming": 0, "outgoing": 180263, "net": -180263 },
        { "month": "2025-07", "incoming": 0, "outgoing": 263, "net": -263 }
    ]
}
```

---

## Use Cases Enabled

Once bank import is implemented, these features become possible:

### Use Case: True Cash Flow Visibility

**Before (FJ only):**
```
AI: "Revenue this month: €12,450 (based on FJ invoice status)"
    → But this is what FJ THINKS happened
    → Could be wrong if payments weren't manually updated
```

**After (with bank data):**
```
AI: "💰 Financial Position - November 2025

     Bank verified this month:
     ├── Income received:  €8,200 (verified)
     ├── Expenses paid:    €2,340
     └── Net cash flow:   +€5,860

     Pending (not yet in bank):
     └── Invoices awaiting payment: €6,350"
```

### Use Case: Burn Rate & Runway

```
AI: "/runway

     MONTHLY EXPENSES (from bank, 6-month average):
     ├── Hosting (AWS, Hetzner):     €340
     ├── Software subscriptions:     €180
     ├── Professional services:      €200
     └── Other business:             €380
     ────────────────────────────────────
     Total monthly burn:            €1,100

     CURRENT POSITION:
     ├── Cash in bank:      €23,400 (from transactions)
     ├── Pending invoices:  €6,350 (from FJ)

     RUNWAY: 21-27 months"
```

### Use Case: Expense Anomaly Detection

```
AI: "⚠️ Expense Alert

     Your AWS bill this month: €680
     Your usual AWS bill: €320-€360

     This is 89% higher than your 6-month average."
```

---

## Future Integration Points

### Phase 4: Reconciliation Engine

The `reconciliation` field in transactions will be used to:
- Auto-match transactions to FJ invoices
- Match by: amount, reference (invoice number), counterparty IBAN
- Confidence scoring (high/medium/low)
- Auto-mark FJ invoices as paid when matched

### Phase 6: OMS AI Tools

New AI tools that will query this data:

```python
# Tool: fj_get_transactions
# Returns bank transactions for AI analysis

# Tool: fj_get_cash_flow
# Returns cash flow summary

# Tool: fj_get_burn_rate
# Calculates monthly expenses from bank data
```

---

## Implementation Notes

### Encoding Detection

BAWAG exports use ISO-8859-1. Implement auto-detection:
1. Try UTF-8 first
2. If decode fails, try ISO-8859-1
3. Look for German umlauts (ä, ö, ü, ß) as validation

### Future Format Support

The design should allow adding new bank formats later:
- Different CSV structures
- Different date/number formats
- Potentially MT940/CAMT formats

Consider a pluggable parser architecture:
```
parsers/
├── bawag.zig      # BAWAG format
├── sparkasse.zig  # German Sparkasse
└── generic.zig    # Configurable generic parser
```

### ID Generation

Transaction IDs are based on the bank's reference code (which is unique and sequential):

```
id = lowercase(reference_code)
     e.g., "fe000000006", "mc000000083", "vd000000089"
```

This makes deduplication trivial: if the ID exists, skip the transaction.

**Fallback** (if no reference code found - should be rare):
```
id = "txn_" + date + "_" + hash(description)[:8]
     e.g., "txn_2025-06-10_a1b2c3d4"
```

---

*Document created: November 2025*
*For: FJ Bank Import Implementation (Phase 3)*
