# Data Flow Diagram — FFCal_XAUUSD

## Overview

This document describes the end-to-end data flow of the `FFCal_XAUUSD.mq4` indicator from calendar fetch to order execution.

---

## Level 0 — Context Diagram

```mermaid
flowchart LR
    FF[("Forex Factory\nnfs.faireconomy.media")] -->|JSON Calendar| IND(["FFCal_XAUUSD\nIndicator"])
    IND -->|OBJ_LABEL| CHT["MT4 Chart\n(On-Screen Display)"]
    IND -->|OrderSend / OrderClose| BRK["MT4 Broker\n(XAU/USD Orders)"]
```

---

## Level 1 — Main Process Flow

```mermaid
flowchart TD
    A(["OnInit / OnCalculate"]) --> B{"Time since\nlast fetch\n>= 3600s ?"}
    B -- Yes --> C["WebRequest GET\nhttps://nfs.faireconomy.media/\nff_calendar_thisweek.json"]
    B -- No  --> G
    C --> D{"HTTP 200 OK ?"}
    D -- No  --> E["Print error\n+ GetLastError()"]
    D -- Yes --> F["ParseJSON()\nExtract fields per event object"]
    F --> F1{"impact ==\nMedium OR High ?"}
    F1 -- No  --> F2["Skip event"]
    F1 -- Yes --> F3["Store in\nparallel arrays\n(evTitle, evTime, evBias…)"]
    F3 --> F4["CalcBias()\nForecast vs Previous\n→ +1 / -1 / 0"]
    F4 --> G["DrawDashboard()\nOBJ_LABEL per event row"]
    G --> H["CheckAndTrade()"]
    H --> I{"Symbol ==\nXAUUSD ?"}
    I -- No  --> Z([End tick])
    I -- Yes --> J{"For each\nnon-traded event"}
    J --> K{"secsToEvent\n∈ [0, InpMinsBefore×60] ?"}
    K -- Yes --> L{"HasOpenOrder() ?"}
    L -- No  --> M["OpenOrder()\nBUY if bias=+1\nSELL if bias=-1"]
    L -- Yes --> Z
    M --> Z
    K -- No  --> N{"secsToEvent\n< -(InpMinsAfter×60) ?"}
    N -- Yes --> O["CloseAllOrders()\nmark evTraded=true"]
    N -- No  --> Z
    O --> Z
```

---

## Level 2 — ParseJSON Detail

```mermaid
flowchart TD
    P1["Raw JSON string"] --> P2["Find next '{' '}'\nobject boundary"]
    P2 --> P3["ExtractField()\nfor each key"]
    P3 --> P4{"impact ==\nMedium or High ?"}
    P4 -- No  --> P2
    P4 -- Yes --> P5["ParseFFDate()\nISO-8601 + UTC offset\n→ broker datetime"]
    P5 --> P6["CalcBias()\ncountry + title + fc + pv\n→ int bias"]
    P6 --> P7["Write to\nevTitle[n]..evBias[n]\nevCount++"]
    P7 --> P2
```

---

## Level 2 — CalcBias Decision Tree

```mermaid
flowchart TD
    B1{"forecast or\nprevious empty?"} -- Yes --> B_NEUT(["return 0 NEUT"])
    B1 -- No  --> B2{"country == USD ?"}
    B2 -- Yes --> B3{"title contains\nEmployment/Claims/\nPMI/GDP/Retail/\nHome Sales ?"}
    B3 -- Yes --> B4{"fc > pv ?"}
    B4 -- Yes --> B_BEAR(["return -1 BEAR"])
    B4 -- No  --> B5{"fc < pv ?"}
    B5 -- Yes --> B_BULL(["return +1 BULL"])
    B5 -- No  --> B_NEUT2(["return 0 NEUT"])
    B3 -- No  --> B6{"title contains\nCPI/PCE/Inflation ?"}
    B6 -- Yes --> B4
    B6 -- No  --> B7{"title contains\nUnemployment Rate ?"}
    B7 -- Yes --> B8{"fc > pv ?"}
    B8 -- Yes --> B_BULL2(["return +1 BULL"])
    B8 -- No  --> B_BEAR2(["return -1 BEAR"])
    B7 -- No  --> B_NEUT3(["return 0 NEUT"])
    B2 -- No  --> B9{"country == CNY\nAND title has PMI ?"}
    B9 -- Yes --> B10{"fc < pv ?"}
    B10 -- Yes --> B_BULL3(["return +1 BULL"])
    B10 -- No  --> B_BEAR3(["return -1 BEAR"])
    B9 -- No  --> B_NEUT4(["return 0 NEUT"])
```

---

## Timing Diagram

```
Time axis →

T-60min   FF JSON updated by server (hourly)
T-5min    CheckAndTrade: OpenOrder() fires (InpMinsBefore=5)
T=0       News event releases
T+15min   CheckAndTrade: CloseAllOrders() fires if order still open (InpMinsAfter=15)
```

---

## Data Store

```
In-memory parallel arrays (evCount max 60)
──────────────────────────────────────────
evTitle[]     string   Event name
evCountry[]   string   Country code
evTime[]      datetime Broker-local event time
evImpact[]    string   "Medium" | "High"
evForecast[]  string   Raw forecast string
evPrevious[]  string   Raw previous string
evBias[]      int      +1 | -1 | 0
evTraded[]    bool     Order already placed?
```
