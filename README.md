# FFCal_XAUUSD — Forex Factory News Trader for Gold

> **Version:** 1.0.0 · **Platform:** MetaTrader 4 · **Pair:** XAU/USD (Gold)

A single-file MQL4 indicator that fetches the Forex Factory weekly economic calendar, displays Medium and High impact events on-chart, and automatically opens/closes XAU/USD orders based on the gap between `Forecast` and `Previous` values.

---

## Table of Contents
- [Features](#features)
- [How It Works](#how-it-works)
- [Setup](#setup)
- [Input Parameters](#input-parameters)
- [Bias Logic](#bias-logic)
- [Data Flow](#data-flow)
- [Data Dictionary](#data-dictionary)
- [File Structure](#file-structure)
- [Disclaimer](#disclaimer)

---

## Features

- ✅ Fetches live JSON calendar from `https://nfs.faireconomy.media/ff_calendar_thisweek.json`
- ✅ Filters only **Medium** and **High** impact events
- ✅ Displays **Title, Country, Date, Time, Forecast, Previous, Bias, URL** on chart
- ✅ Auto-computes gold directional bias (`BULL` / `BEAR` / `NEUT`) from forecast vs previous gap
- ✅ Opens BUY or SELL order `N` minutes before event
- ✅ Closes lingering orders `N` minutes after event
- ✅ Respects 1-hour rate limit — never over-fetches the endpoint
- ✅ Clean single-file architecture — no DLL, no external library

---

## How It Works

```
FF Calendar JSON  →  Parse & Filter  →  Bias Calculation  →  On-Chart Display
                                               ↓
                                       Order Manager
                                    (Open / Close XAU/USD)
```

1. **Fetch** — On init and every hour, `WebRequest` downloads the FF JSON calendar.
2. **Parse** — A lightweight field extractor pulls `title`, `country`, `date`, `impact`, `forecast`, `previous` from each event object.
3. **Filter** — Only `Medium` or `High` impact events are stored (max 60).
4. **Bias** — `CalcBias()` compares `Forecast` vs `Previous` for each USD/CNY event and returns `+1` (bullish gold), `-1` (bearish gold), or `0` (neutral).
5. **Display** — `OBJ_LABEL` objects are drawn on the chart in Courier New fixed-width format.
6. **Trade** — `InpMinsBefore` minutes before each non-neutral event, one order is opened. It is closed after `InpMinsAfter` minutes if TP/SL has not been hit.

---

## Setup

### 1. Install
```
Copy FFCal_XAUUSD.mq4 → <MT4 Data Folder>/MQL4/Indicators/
Open MetaEditor → Compile
```

### 2. Allow WebRequest
```
MT4 → Tools → Options → Expert Advisors
☑ Allow WebRequest for listed URL
+ https://nfs.faireconomy.media/ff_calendar_thisweek.json
```

### 3. Attach to Chart
- Open a **XAUUSD** (or XAUUSDm / GOLD / GOLDm) chart
- Insert → Indicators → Custom → `FFCal_XAUUSD`
- Set inputs as required

> ⚠️ The indicator also acts as an order manager. Ensure **AutoTrading** is enabled in MT4.

---

## Input Parameters

| Parameter | Default | Description |
|---|---|---|
| `InpCalURL` | FF JSON URL | Calendar endpoint (do not change) |
| `InpMinsBefore` | `5` | Minutes before event to open order |
| `InpMinsAfter` | `15` | Minutes after event to force-close order |
| `InpLotSize` | `0.01` | Order lot size |
| `InpSL_Points` | `500` | Stop loss in points |
| `InpTP_Points` | `1000` | Take profit in points |
| `InpMagic` | `20260612` | Magic number to identify EA orders |
| `InpFetchInterval` | `3600` | Seconds between calendar fetches (min 3600) |
| `InpColorHigh` | Red | Label color for High impact events |
| `InpColorMedium` | Orange | Label color for Medium impact events |
| `InpColorInfo` | White | Label color for header/info rows |

---

## Bias Logic

| Event Type | Country | Forecast > Previous | Forecast < Previous |
|---|---|---|---|
| Employment / Claims / PMI / GDP / Retail / Home Sales | USD | BEAR (gold ↓) | BULL (gold ↑) |
| CPI / PCE / Inflation | USD | BEAR (gold ↓) | BULL (gold ↑) |
| Unemployment Rate | USD | BULL (gold ↑) | BEAR (gold ↓) |
| Manufacturing PMI | CNY | BEAR (gold ↓) | BULL (gold ↑) |
| All others / no numeric data | Any | NEUT — no trade | NEUT — no trade |

**Rationale:** Gold (XAU/USD) moves inversely to USD strength. Stronger-than-expected USD data lifts the dollar and pressures gold. Weaker-than-expected USD data softens the dollar and supports gold.

---

## Data Flow

See [DATAFLOW.md](DATAFLOW.md) for the full Data Flow Diagram.

---

## Data Dictionary

See [DATA_DICTIONARY.md](DATA_DICTIONARY.md) for all fields, types, and descriptions.

---

## File Structure

```
news/
├── FFCal_XAUUSD.mq4       # Main indicator + order manager (single file)
├── README.md               # This file
├── DATAFLOW.md             # Data Flow Diagram (Mermaid)
└── DATA_DICTIONARY.md      # Field definitions and data types
```

---

## Disclaimer

> This indicator trades based on **pre-release forecast vs previous gap**, not on confirmed actual vs forecast deviation. Pre-release bias can be wrong when the actual release surprises the market in the opposite direction. Use small lot sizes during testing. Past results do not guarantee future performance. Trade at your own risk.
