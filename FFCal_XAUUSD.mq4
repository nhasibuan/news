//+------------------------------------------------------------------+
//|  FFCal_XAUUSD.mq4                                                |
//|  Forex Factory Calendar News Trader for XAU/USD                  |
//|  Source : https://nfs.faireconomy.media/ff_calendar_thisweek.csv  |
//|  Repo   : https://github.com/nhasibuan/news                      |
//+------------------------------------------------------------------+
#property copyright   "Delima"
#property version     "1.10"
#property strict
#property indicator_chart_window

//--- Inputs
input string   InpCalURL        = "https://nfs.faireconomy.media/ff_calendar_thisweek.csv";
input int      InpMinsBefore    = 5;       // Minutes before event to open order
input int      InpMinsAfter     = 15;      // Minutes after event to force-close
input double   InpLotSize       = 0.01;    // Order lot size
input int      InpSL_Points     = 500;     // Stop Loss in points
input int      InpTP_Points     = 1000;    // Take Profit in points
input int      InpMagic         = 20260612;
input int      InpFetchInterval = 3600;    // Seconds between fetches (min 3600)
input color    InpColorHigh     = clrRed;
input color    InpColorMedium   = clrOrange;
input color    InpColorInfo     = clrWhite;

//--- Constants
#define MAX_EVENTS  60
#define LBL_PREFIX  "FFCal_"

// CSV column indices (0-based)
// Title,Country,Date,Time,Impact,Forecast,Previous,URL
#define COL_TITLE    0
#define COL_COUNTRY  1
#define COL_DATE     2
#define COL_TIME     3
#define COL_IMPACT   4
#define COL_FORECAST 5
#define COL_PREVIOUS 6
#define COL_URL      7
#define COL_COUNT    8

//--- Event data store (parallel arrays)
string   evTitle    [MAX_EVENTS];
string   evCountry  [MAX_EVENTS];
datetime evTime     [MAX_EVENTS];
string   evImpact   [MAX_EVENTS];
string   evForecast [MAX_EVENTS];
string   evPrevious [MAX_EVENTS];
string   evURL      [MAX_EVENTS];
int      evBias     [MAX_EVENTS]; // +1 bullish gold | -1 bearish gold | 0 neutral
bool     evTraded   [MAX_EVENTS];
int      evCount    = 0;

datetime g_lastFetch = 0;
string   g_lblPrefix = "";

//+------------------------------------------------------------------+
int OnInit()
{
   g_lblPrefix = LBL_PREFIX + (string)((int)TimeCurrent()) + "_";
   Print("FFCal_XAUUSD v1.10 | Magic=", InpMagic, " | Symbol=", Symbol());
   FetchAndParseCalendar();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RemoveAllLabels();
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if ((int)(TimeCurrent() - g_lastFetch) >= InpFetchInterval)
      FetchAndParseCalendar();

   DrawDashboard();
   CheckAndTrade();
   return rates_total;
}

//+------------------------------------------------------------------+
//| Fetch CSV calendar via WebRequest                                |
//+------------------------------------------------------------------+
void FetchAndParseCalendar()
{
   string headers = "User-Agent: Mozilla/5.0\r\n";
   char   post[], result[];
   string respHeaders;

   ResetLastError();
   int httpCode = WebRequest("GET", InpCalURL, headers, 5000,
                             post, result, respHeaders);
   if (httpCode == -1)
   {
      Print("FFCal | WebRequest failed. Err=", GetLastError(),
            " | Add URL to: Tools > Options > Expert Advisors");
      return;
   }
   if (httpCode != 200)
   {
      Print("FFCal | HTTP ", httpCode, " — check rate limit or URL.");
      return;
   }

   string csv = CharArrayToString(result);
   g_lastFetch = TimeCurrent();
   ParseCSV(csv);
   Print("FFCal | Loaded ", evCount, " Medium/High events from CSV.");
}

//+------------------------------------------------------------------+
//| CSV line-by-line parser                                          |
//| Format: Title,Country,Date,Time,Impact,Forecast,Previous,URL     |
//| Date  : MM-DD-YYYY   Time: 12h am/pm  e.g. "12:30pm"            |
//+------------------------------------------------------------------+
void ParseCSV(string csv)
{
   evCount = 0;

   // Normalise line endings
   StringReplace(csv, "\r\n", "\n");
   StringReplace(csv, "\r",   "\n");

   int pos    = 0;
   int csvLen = StringLen(csv);
   bool firstLine = true;   // skip header row

   while (pos < csvLen && evCount < MAX_EVENTS)
   {
      // Find end of line
      int eol = StringFind(csv, "\n", pos);
      if (eol < 0) eol = csvLen;

      string line = StringSubstr(csv, pos, eol - pos);
      pos = eol + 1;

      if (StringLen(line) < 5) continue;

      // Skip header
      if (firstLine) { firstLine = false; continue; }

      // Split line into 8 fields by comma
      string fields[COL_COUNT];
      if (!SplitCSVLine(line, fields)) continue;

      string impact  = fields[COL_IMPACT];
      string country = fields[COL_COUNTRY];

      if (impact != "Medium" && impact != "High") continue;

      evImpact   [evCount] = impact;
      evCountry  [evCount] = country;
      evTitle    [evCount] = fields[COL_TITLE];
      evForecast [evCount] = fields[COL_FORECAST];
      evPrevious [evCount] = fields[COL_PREVIOUS];
      evURL      [evCount] = fields[COL_URL];

      // Parse date + time to broker datetime
      string dateStr = fields[COL_DATE];  // MM-DD-YYYY
      string timeStr = fields[COL_TIME];  // e.g. "12:30pm"
      evTime[evCount] = ParseCSVDateTime(dateStr, timeStr);

      evBias   [evCount] = CalcBias(country, evTitle[evCount],
                                    evForecast[evCount], evPrevious[evCount]);
      evTraded [evCount] = false;
      evCount++;
   }
}

//+------------------------------------------------------------------+
//| Split one CSV line into exactly COL_COUNT fields                 |
//| Returns false if field count does not match                      |
//+------------------------------------------------------------------+
bool SplitCSVLine(const string line, string &fields[])
{
   int f   = 0;
   int pos = 0;
   int len = StringLen(line);

   while (pos <= len && f < COL_COUNT)
   {
      int comma = StringFind(line, ",", pos);
      if (comma < 0) comma = len;

      fields[f] = StringSubstr(line, pos, comma - pos);
      // Trim leading/trailing spaces
      StringTrimLeft(fields[f]);
      StringTrimRight(fields[f]);

      pos = comma + 1;
      f++;
   }
   return (f == COL_COUNT);
}

//+------------------------------------------------------------------+
//| Parse FF CSV date (MM-DD-YYYY) + time (h:mmam/pm) to datetime   |
//| All FF CSV times are New York time (UTC-4 EDT / UTC-5 EST)       |
//+------------------------------------------------------------------+
datetime ParseCSVDateTime(const string dateStr, const string timeStr)
{
   // dateStr: MM-DD-YYYY
   if (StringLen(dateStr) < 10) return 0;
   int mo = (int)StringSubstr(dateStr, 0, 2);
   int dy = (int)StringSubstr(dateStr, 3, 2);
   int yr = (int)StringSubstr(dateStr, 6, 4);

   // timeStr examples: "12:30pm", "8:30am", "1:45pm"
   int colonPos = StringFind(timeStr, ":");
   if (colonPos < 0) return 0;

   int hr  = (int)StringSubstr(timeStr, 0, colonPos);
   int mn  = (int)StringSubstr(timeStr, colonPos + 1, 2);

   string suffix = StringSubstr(timeStr, colonPos + 3); // "am" or "pm"
   StringToLower(suffix);

   if (suffix == "pm" && hr != 12) hr += 12;
   if (suffix == "am" && hr == 12) hr  = 0;

   MqlDateTime mdt;
   mdt.year = yr; mdt.mon = mo; mdt.day = dy;
   mdt.hour = hr; mdt.min = mn; mdt.sec = 0;

   // FF CSV uses New York time: EDT = UTC-4, EST = UTC-5
   // Use UTC-4 (EDT) as default; adjust if needed per broker offset
   datetime utc    = StructToTime(mdt) + 4 * 3600;
   datetime broker = utc + (TimeCurrent() - TimeGMT());
   return broker;
}

//+------------------------------------------------------------------+
//| Gold directional bias from Forecast vs Previous gap              |
//| +1 = Bullish Gold (BUY) | -1 = Bearish Gold (SELL) | 0 = Skip   |
//+------------------------------------------------------------------+
int CalcBias(const string country,
             const string title,
             const string forecast,
             const string previous)
{
   if (forecast == "" || previous == "") return 0;

   double fc = StringToDouble(forecast);
   double pv = StringToDouble(previous);
   if (fc == 0.0 && pv == 0.0) return 0;

   // stronger USD data = bearish gold (-1); weaker = bullish (+1)
   int stronger = (fc > pv) ? -1 : (fc < pv) ? 1 : 0;

   if (country == "USD")
   {
      if (StringFind(title, "Employment")  >= 0 ||
          StringFind(title, "Claims")      >= 0 ||
          StringFind(title, "PMI")         >= 0 ||
          StringFind(title, "GDP")         >= 0 ||
          StringFind(title, "Retail")      >= 0 ||
          StringFind(title, "Home Sales")  >= 0)
         return stronger;

      if (StringFind(title, "CPI")       >= 0 ||
          StringFind(title, "PCE")       >= 0 ||
          StringFind(title, "Inflation") >= 0)
         return stronger;

      if (StringFind(title, "Unemployment Rate") >= 0)
         return -stronger;
   }

   if (country == "CNY" && StringFind(title, "PMI") >= 0)
      return -stronger;

   return 0;
}

//+------------------------------------------------------------------+
//| Render fixed-width dashboard as OBJ_LABEL objects                |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   RemoveAllLabels();

   int x     = 10;
   int y     = 20;
   int lineH = 16;

   LabelSet("hdr0", "== FF Calendar: Medium/High Impact for XAU/USD ==",
            x, y, InpColorInfo, 8);
   y += lineH + 4;

   LabelSet("hdr1",
      StringFormat("%-32s %-5s %-12s %-8s %-10s %-10s %-6s  %s",
                   "Title","CCY","Date","Time","Forecast","Previous","BIAS","Event URL"),
      x, y, InpColorInfo, 7);
   y += lineH;

   for (int i = 0; i < evCount; i++)
   {
      color  c    = (evImpact[i] == "High") ? InpColorHigh : InpColorMedium;
      string bias = (evBias[i] ==  1) ? "BULL" :
                    (evBias[i] == -1) ? "BEAR" : "NEUT";

      string dt = TimeToString(evTime[i], TIME_DATE);
      string tm = TimeToString(evTime[i], TIME_MINUTES);

      string line = StringFormat("%-32s %-5s %-12s %-8s %-10s %-10s %-6s  %s",
         StringSubstr(evTitle[i], 0, 31),
         evCountry[i], dt, tm,
         evForecast[i], evPrevious[i],
         bias, evURL[i]);

      LabelSet("ev" + (string)i, line, x, y, c, 7);
      y += lineH;
      if (y > 580) break;
   }

   if (evCount == 0)
      LabelSet("empty", "No events loaded — check WebRequest permission.",
               x, y, InpColorInfo, 8);
}

//+------------------------------------------------------------------+
//| Create or update a single OBJ_LABEL                              |
//+------------------------------------------------------------------+
void LabelSet(const string id,  const string text,
              const int x,      const int y,
              const color clr,  const int sz)
{
   string nm = g_lblPrefix + id;
   if (ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);

   ObjectSetString (0, nm, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   sz);
   ObjectSetString (0, nm, OBJPROP_FONT,       "Courier New");
   ObjectSetInteger(0, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_BACK,       false);
}

//+------------------------------------------------------------------+
//| Delete all dashboard labels matched by prefix                    |
//+------------------------------------------------------------------+
void RemoveAllLabels()
{
   int total = ObjectsTotal(0, -1, OBJ_LABEL);
   for (int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, OBJ_LABEL);
      if (StringFind(nm, g_lblPrefix) == 0)
         ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//| Check upcoming/past events and manage XAU/USD orders             |
//+------------------------------------------------------------------+
void CheckAndTrade()
{
   string sym = Symbol();
   if (sym != "XAUUSD"  && sym != "XAUUSDm" &&
       sym != "GOLD"    && sym != "GOLDm") return;

   datetime now = TimeCurrent();

   for (int i = 0; i < evCount; i++)
   {
      if (evTraded[i] || evBias[i] == 0) continue;

      int secs = (int)(evTime[i] - now);

      if (secs > 0 && secs <= InpMinsBefore * 60)
      {
         if (!HasOpenOrder())
         {
            OpenOrder(evBias[i], evTitle[i]);
            evTraded[i] = true;
         }
      }

      if (secs < -(InpMinsAfter * 60))
      {
         CloseAllOrders();
         evTraded[i] = true;
      }
   }
}

//+------------------------------------------------------------------+
bool HasOpenOrder()
{
   for (int i = 0; i < OrdersTotal(); i++)
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if (OrderMagicNumber() == InpMagic && OrderSymbol() == Symbol())
            return true;
   return false;
}

//+------------------------------------------------------------------+
void OpenOrder(const int bias, const string evName)
{
   int    cmd   = (bias == 1) ? OP_BUY : OP_SELL;
   double price = (cmd  == OP_BUY) ? Ask : Bid;
   double sl    = (cmd  == OP_BUY) ? price - InpSL_Points * Point
                                   : price + InpSL_Points * Point;
   double tp    = (cmd  == OP_BUY) ? price + InpTP_Points * Point
                                   : price - InpTP_Points * Point;

   ResetLastError();
   int ticket = OrderSend(Symbol(), cmd, InpLotSize, price, 3, sl, tp,
                          "FFCal:" + StringSubstr(evName, 0, 20),
                          InpMagic, 0,
                          (cmd == OP_BUY) ? clrLime : clrRed);

   if (ticket < 0)
      Print("FFCal | OrderSend failed. Err=", GetLastError(),
            " | Ev=", evName, " | Bias=", bias);
   else
      Print("FFCal | Opened #", ticket, " ", (cmd == OP_BUY ? "BUY" : "SELL"),
            " | Ev=", evName);
}

//+------------------------------------------------------------------+
void CloseAllOrders()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderMagicNumber() != InpMagic)              continue;
      if (OrderSymbol()      != Symbol())              continue;

      double price = (OrderType() == OP_BUY) ? Bid : Ask;
      ResetLastError();
      if (!OrderClose(OrderTicket(), OrderLots(), price, 3, clrYellow))
         Print("FFCal | OrderClose failed. Err=", GetLastError(),
               " | Ticket=", OrderTicket());
   }
}
//+------------------------------------------------------------------+
