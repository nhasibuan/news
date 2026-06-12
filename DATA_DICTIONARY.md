# Data Dictionary — FFCal_XAUUSD

## 1. External Data Source

**Source URL:** `https://nfs.faireconomy.media/ff_calendar_thisweek.json`  
**Format:** JSON array  
**Update Frequency:** Once per hour (server-side)  
**Rate Limit:** Max ~12 requests per hour; enforced 5-min cooldown on excess  

### 1.1 JSON Event Object Fields

| Field | JSON Key | Type | Example | Description |
|---|---|---|---|---|
| Event Title | `title` | string | `"Unemployment Claims"` | Name of the economic release |
| Country Code | `country` | string | `"USD"` | ISO country/currency code |
| Release Date/Time | `date` | string (ISO-8601) | `"2026-06-12T08:30:00-04:00"` | UTC datetime with timezone offset |
| Impact Level | `impact` | string | `"High"` | `"High"`, `"Medium"`, `"Low"`, `"Holiday"` |
| Forecast Value | `forecast` | string | `"219K"` | Market consensus estimate before release |
| Previous Value | `previous` | string | `"214K"` | Value from last release |
| Actual Value | `actual` | string | `""` | Published after release; empty before |

> Note: `forecast` and `previous` are raw strings as published by Forex Factory. Numeric parsing uses `StringToDouble()` which strips trailing letters (K, M, %).

---

## 2. Internal Data Arrays (In-Memory)

All arrays are sized `MAX_EVENTS = 60`.

| Array | Type | Source Field | Description |
|---|---|---|---|
| `evTitle[]` | string | `title` | Event display name |
| `evCountry[]` | string | `country` | Country/currency code |
| `evTime[]` | datetime | `date` | Parsed broker-local event datetime |
| `evImpact[]` | string | `impact` | `"Medium"` or `"High"` only |
| `evForecast[]` | string | `forecast` | Raw forecast string |
| `evPrevious[]` | string | `previous` | Raw previous string |
| `evBias[]` | int | computed | `+1` = Bullish Gold, `-1` = Bearish Gold, `0` = Neutral |
| `evTraded[]` | bool | computed | `true` if order has been opened for this event |
| `evCount` | int | computed | Total number of stored events (0–60) |

---

## 3. Input Parameters

| Variable | MQL4 Type | Default | Unit | Valid Range | Description |
|---|---|---|---|---|---|
| `InpCalURL` | string | FF JSON URL | — | valid HTTPS URL | Calendar data endpoint |
| `InpMinsBefore` | int | `5` | minutes | 1–60 | How early to open order before event |
| `InpMinsAfter` | int | `15` | minutes | 1–120 | How long after event before force-close |
| `InpLotSize` | double | `0.01` | lots | 0.01–100.0 | Order volume per trade |
| `InpSL_Points` | int | `500` | points | 10–5000 | Stop loss distance in points |
| `InpTP_Points` | int | `1000` | points | 10–10000 | Take profit distance in points |
| `InpMagic` | int | `20260612` | — | any int | Magic number to tag indicator orders |
| `InpFetchInterval` | int | `3600` | seconds | ≥3600 | Minimum interval between API fetches |
| `InpColorHigh` | color | `clrRed` | — | any MT4 color | On-chart label color for High events |
| `InpColorMedium` | color | `clrOrange` | — | any MT4 color | On-chart label color for Medium events |
| `InpColorInfo` | color | `clrWhite` | — | any MT4 color | On-chart label color for header rows |

---

## 4. Computed Fields

### 4.1 `evTime[]` — Datetime Conversion

| Step | Logic |
|---|---|
| Input | ISO-8601 string from JSON, e.g. `"2026-06-12T08:30:00-04:00"` |
| Parse year/month/day/hour/min/sec | `StringSubstr()` positional extraction |
| Parse UTC offset | Extract sign, hours, minutes from suffix (e.g. `-04:00`) |
| Convert to UTC | `StructToTime(mdt) - sign × (offsetH×3600 + offsetM×60)` |
| Convert UTC to broker time | `utc + (TimeCurrent() - TimeGMT())` |
| Output | `datetime` in broker local time |

### 4.2 `evBias[]` — Gold Directional Bias

| Value | Meaning | Order Direction |
|---|---|---|
| `+1` | Bullish Gold — USD data weakens or unemployment rises | `OP_BUY` |
| `-1` | Bearish Gold — USD data strengthens or unemployment falls | `OP_SELL` |
| `0` | Neutral — no numeric gap, unknown event type, or non-USD/CNY | No order |

**Bias Rules Table:**

| Title Keyword(s) | Country | fc > pv | fc < pv |
|---|---|---|---|
| Employment, Claims, PMI, GDP, Retail Sales, Home Sales | USD | -1 BEAR | +1 BULL |
| CPI, PCE, Inflation | USD | -1 BEAR | +1 BULL |
| Unemployment Rate | USD | +1 BULL | -1 BEAR |
| Manufacturing PMI | CNY | -1 BEAR | +1 BULL |
| (anything else) | any | 0 NEUT | 0 NEUT |

---

## 5. Order Lifecycle

| Stage | Trigger | Action |
|---|---|---|
| **Pre-event** | `0 < secsToEvent ≤ InpMinsBefore × 60` | `OpenOrder()` with bias direction |
| **Active** | TP or SL hit | Broker closes order automatically |
| **Post-event timeout** | `secsToEvent < -(InpMinsAfter × 60)` | `CloseAllOrders()` force-close |
| **Already traded** | `evTraded[i] == true` | Skip event entirely |

---

## 6. On-Chart Display Fields

| Column | Source | Color |
|---|---|---|
| Title (max 31 chars) | `evTitle[i]` | High=Red / Medium=Orange |
| Country | `evCountry[i]` | same |
| Date | `TimeToString(evTime[i], TIME_DATE)` | same |
| Time | `TimeToString(evTime[i], TIME_MINUTES)` | same |
| Forecast | `evForecast[i]` | same |
| Previous | `evPrevious[i]` | same |
| Bias | `BULL` / `BEAR` / `NEUT` | same |
| URL | Static: FF JSON endpoint | same |

---

## 7. Error Codes

| Condition | MT4 Error | Resolution |
|---|---|---|
| WebRequest returns -1 | `GetLastError()` | Add URL to Tools → Options → Expert Advisors |
| `OrderSend` fails | Logged to Experts tab | Check broker symbol name, margin, lot constraints |
| `OrderClose` fails | Logged to Experts tab | Order may already be closed by TP/SL |
| No events shown | — | Check `evCount` in Experts tab; verify fetch succeeded |
