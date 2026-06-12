//+------------------------------------------------------------------+
//|  FFCal_XAUUSD.mq4                                                |
//|  Forex Factory Calendar News Trader for XAU/USD                  |
//|  Source : https://nfs.faireconomy.media/ff_calendar_thisweek.json |
//|  Repo   : https://github.com/nhasibuan/news                      |
//+------------------------------------------------------------------+
#property copyright   "Delima"
#property version     "1.00"
#property strict
#property indicator_chart_window

//--- Inputs
input string   InpCalURL        = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";
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
#define CAL_URL     "https://nfs.faireconomy.media/ff_calendar_thisweek.json"

//--- Event data store (parallel arrays — MQL4 has no struct arrays)
string   evTitle    [MAX_EVENTS];
string   evCountry  [MAX_EVENTS];
datetime evTime     [MAX_EVENTS];
string   evImpact   [MAX_EVENTS];
string   evForecast [MAX_EVENTS];
string   evPrevious [MAX_EVENTS];
int      evBias     [MAX_EVENTS]; // +1 bullish gold | -1 bearish gold | 0 neutral
bool     evTraded   [MAX_EVENTS];
int      evCount    = 0;

datetime g_lastFetch = 0;
string   g_lblPrefix = "";        // built once in OnInit, avoids repeated string concat

//+------------------------------------------------------------------+
int OnInit()
{
   g_lblPrefix = LBL_PREFIX + (string)((int)TimeCurrent()) + "_";
   Print("FFCal_XAUUSD v1.00 | Magic=", InpMagic, " | Symbol=", Symbol());
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
//| Fetch JSON calendar via WebRequest                               |
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

   g_lastFetch = TimeCurrent();
   ParseJSON(CharArrayToString(result));
   Print("FFCal | Loaded ", evCount, " Medium/High events.");
}

//+------------------------------------------------------------------+
//| Lightweight brace-bounded JSON object parser                     |
//+------------------------------------------------------------------+
void ParseJSON(const string &json)
{
   evCount = 0;
   int pos     = 0;
   int jsonLen = StringLen(json);

   while (pos < jsonLen && evCount < MAX_EVENTS)
   {
      int s = StringFind(json, "{", pos);  if (s < 0) break;
      int e = StringFind(json, "}", s);    if (e < 0) break;
      pos = e + 1;

      string obj     = StringSubstr(json, s, e - s + 1);
      string impact  = ExtractField(obj, "impact");
      string country = ExtractField(obj, "country");

      if (impact != "Medium" && impact != "High") continue;

      evImpact   [evCount] = impact;
      evCountry  [evCount] = country;
      evTitle    [evCount] = ExtractField(obj, "title");
      evForecast [evCount] = ExtractField(obj, "forecast");
      evPrevious [evCount] = ExtractField(obj, "previous");
      evTime     [evCount] = ParseFFDate(ExtractField(obj, "date"));
      evBias     [evCount] = CalcBias(country, evTitle[evCount],
                                      evForecast[evCount], evPrevious[evCount]);
      evTraded   [evCount] = false;
      evCount++;
   }
}

//+------------------------------------------------------------------+
//| Extract value for a JSON string field by key                     |
//+------------------------------------------------------------------+
string ExtractField(const string &obj, const string key)
{
   string needle = "\"" + key + "\":\"";
   int    s      = StringFind(obj, needle);
   if (s < 0) return "";
   s += StringLen(needle);
   int e = StringFind(obj, "\"", s);
   if (e < 0) return "";
   return StringSubstr(obj, s, e - s);
}

//+------------------------------------------------------------------+
//| Convert FF ISO-8601 datetime string to broker-local datetime     |
//+------------------------------------------------------------------+
datetime ParseFFDate(const string &raw)
{
   if (StringLen(raw) < 19) return 0;

   MqlDateTime mdt;
   mdt.year = (int)StringSubstr(raw,  0, 4);
   mdt.mon  = (int)StringSubstr(raw,  5, 2);
   mdt.day  = (int)StringSubstr(raw,  8, 2);
   mdt.hour = (int)StringSubstr(raw, 11, 2);
   mdt.min  = (int)StringSubstr(raw, 14, 2);
   mdt.sec  = (int)StringSubstr(raw, 17, 2);

   // Parse UTC offset  e.g. "-05:00" or "+00:00"
   int    offSign = 1;
   int    offH    = 0;
   int    offM    = 0;
   string offStr  = StringSubstr(raw, 19);

   if (StringLen(offStr) >= 3)
   {
      if (StringSubstr(offStr, 0, 1) == "-") offSign = -1;
      offH = (int)StringSubstr(offStr, 1, 2);
      int c = StringFind(offStr, ":");
      if (c > 0) offM = (int)StringSubstr(offStr, c + 1, 2);
   }

   datetime utc    = StructToTime(mdt) - offSign * (offH * 3600 + offM * 60);
   datetime broker = utc + (TimeCurrent() - TimeGMT());
   return broker;
}

//+------------------------------------------------------------------+
//| Gold directional bias from Forecast vs Previous gap              |
//| +1 = Bullish Gold (BUY)  |  -1 = Bearish Gold (SELL)  |  0 = No trade |
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

   int stronger = (fc > pv) ? -1 : (fc < pv) ?  1 : 0; // stronger USD = bear gold
   int weaker   = (fc < pv) ? -1 : (fc > pv) ?  1 : 0; // (unused directly)

   if (country == "USD")
   {
      // Growth / Labour / Activity: stronger data -> USD up -> gold down
      if (StringFind(title, "Employment")  >= 0 ||
          StringFind(title, "Claims")      >= 0 ||
          StringFind(title, "PMI")         >= 0 ||
          StringFind(title, "GDP")         >= 0 ||
          StringFind(title, "Retail")      >= 0 ||
          StringFind(title, "Home Sales")  >= 0)
         return stronger;

      // Inflation: higher CPI/PCE -> hawkish Fed -> gold down
      if (StringFind(title, "CPI")       >= 0 ||
          StringFind(title, "PCE")       >= 0 ||
          StringFind(title, "Inflation") >= 0)
         return stronger;

      // Unemployment Rate: higher = weaker labour -> gold up
      if (StringFind(title, "Unemployment Rate") >= 0)
         return -stronger; // reverse polarity
   }

   // China PMI: weaker China = risk-off = modest gold support
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
                   "Title","CCY","Date","Time","Forecast","Previous","BIAS","URL"),
      x, y, InpColorInfo, 7);
   y += lineH;

   for (int i = 0; i < evCount; i++)
   {
      color  c    = (evImpact[i] == "High") ? InpColorHigh : InpColorMedium;
      string bias = (evBias[i] ==  1) ? "BULL" :
                    (evBias[i] == -1) ? "BEAR" : "NEUT";

      string line = StringFormat("%-32s %-5s %-12s %-8s %-10s %-10s %-6s  %s",
         StringSubstr(evTitle[i], 0, 31),
         evCountry[i],
         TimeToString(evTime[i], TIME_DATE),
         TimeToString(evTime[i], TIME_MINUTES),
         evForecast[i],
         evPrevious[i],
         bias,
         CAL_URL);

      LabelSet("ev" + (string)i, line, x, y, c, 7);
      y += lineH;
      if (y > 580) break;
   }

   if (evCount == 0)
      LabelSet("empty", "No events loaded — check WebRequest permission.",
               x, y, InpColorInfo, 8);
}

//+------------------------------------------------------------------+
//| Create or update a single OBJ_LABEL                             |
//+------------------------------------------------------------------+
void LabelSet(const string id,   const string text,
              const int x,       const int y,
              const color clr,   const int sz)
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
//| Delete all dashboard labels by prefix                            |
//| FIX: ObjectsTotal(chart,window,type) — explicit 3-arg form      |
//|      avoids "ambiguous call to overloaded function" in strict    |
//+------------------------------------------------------------------+
void RemoveAllLabels()
{
   //--- Use ObjectsTotal(chart_id, sub_window, object_type)
   //    chart_id=0 (current), sub_window=-1 (all), type=OBJ_LABEL
   int total = ObjectsTotal(0, -1, OBJ_LABEL);
   for (int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, OBJ_LABEL);
      if (StringFind(nm, g_lblPrefix) == 0)
         ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//| Check upcoming/past events and manage XAU/USD orders            |
//+------------------------------------------------------------------+
void CheckAndTrade()
{
   // Guard: only run on gold symbols
   string sym = Symbol();
   if (sym != "XAUUSD"  && sym != "XAUUSDm" &&
       sym != "GOLD"    && sym != "GOLDm") return;

   datetime now = TimeCurrent();

   for (int i = 0; i < evCount; i++)
   {
      if (evTraded[i] || evBias[i] == 0) continue;

      int secs = (int)(evTime[i] - now);

      // Pre-event window: open order
      if (secs > 0 && secs <= InpMinsBefore * 60)
      {
         if (!HasOpenOrder())
         {
            OpenOrder(evBias[i], evTitle[i]);
            evTraded[i] = true;
         }
      }

      // Post-event timeout: force-close
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
