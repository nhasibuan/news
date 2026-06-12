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

//--- Input Parameters
input string   InpCalURL        = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";
input int      InpMinsBefore    = 5;      // Minutes before event to open order
input int      InpMinsAfter     = 15;     // Minutes after event to close if no TP/SL
input double   InpLotSize       = 0.01;
input int      InpSL_Points     = 500;    // Stop Loss in points
input int      InpTP_Points     = 1000;   // Take Profit in points
input int      InpMagic         = 20260612;
input int      InpFetchInterval = 3600;   // Seconds between fetches (min 3600)
input color    InpColorHigh     = clrRed;
input color    InpColorMedium   = clrOrange;
input color    InpColorInfo     = clrWhite;

//--- Max events
#define MAX_EVENTS 60

//--- Parallel arrays
string   evTitle    [MAX_EVENTS];
string   evCountry  [MAX_EVENTS];
datetime evTime     [MAX_EVENTS];
string   evImpact   [MAX_EVENTS];
string   evForecast [MAX_EVENTS];
string   evPrevious [MAX_EVENTS];
int      evBias     [MAX_EVENTS];  // +1 gold bullish, -1 gold bearish, 0 neutral
bool     evTraded   [MAX_EVENTS];
int      evCount    = 0;

datetime lastFetchTime = 0;
int      labelBase     = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   labelBase = (int)TimeCurrent();
   Print("FFCal_XAUUSD initialized. Magic=", InpMagic);
   FetchAndParseCalendar();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RemoveAllLabels();
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   if (TimeCurrent() - lastFetchTime >= InpFetchInterval)
      FetchAndParseCalendar();

   DrawDashboard();
   CheckAndTrade();
   return rates_total;
}

//+------------------------------------------------------------------+
//| Fetch JSON from FF and trigger parse                             |
//+------------------------------------------------------------------+
void FetchAndParseCalendar()
{
   string headers = "User-Agent: Mozilla/5.0\r\n";
   char   post[], result[];
   string resultHeaders;

   int res = WebRequest("GET", InpCalURL, headers, 5000, post, result, resultHeaders);
   if (res == -1)
   {
      Print("WebRequest error: ", GetLastError(),
            " — add URL in Tools > Options > Expert Advisors");
      return;
   }

   string json = CharArrayToString(result);
   lastFetchTime = TimeCurrent();
   ParseJSON(json);
   Print("FFCal fetched. Events loaded: ", evCount);
}

//+------------------------------------------------------------------+
//| Lightweight JSON array parser                                    |
//+------------------------------------------------------------------+
void ParseJSON(const string &json)
{
   evCount = 0;
   int pos = 0;
   int jsonLen = StringLen(json);

   while (pos < jsonLen && evCount < MAX_EVENTS)
   {
      int objStart = StringFind(json, "{", pos);
      if (objStart < 0) break;
      int objEnd = StringFind(json, "}", objStart);
      if (objEnd < 0) break;

      string obj = StringSubstr(json, objStart, objEnd - objStart + 1);
      pos = objEnd + 1;

      string impact  = ExtractField(obj, "impact");
      string country = ExtractField(obj, "country");

      if (impact != "Medium" && impact != "High") continue;

      evImpact   [evCount] = impact;
      evCountry  [evCount] = country;
      evTitle    [evCount] = ExtractField(obj, "title");
      evForecast [evCount] = ExtractField(obj, "forecast");
      evPrevious [evCount] = ExtractField(obj, "previous");
      evTraded   [evCount] = false;

      string dateStr = ExtractField(obj, "date");
      evTime[evCount] = ParseFFDate(dateStr);

      evBias[evCount] = CalcBias(country, evTitle[evCount],
                                 evForecast[evCount], evPrevious[evCount]);
      evCount++;
   }
}

//+------------------------------------------------------------------+
//| Extract a JSON string field value by key                         |
//+------------------------------------------------------------------+
string ExtractField(const string &obj, const string key)
{
   string searchKey = "\"" + key + "\":\"";
   int start = StringFind(obj, searchKey);
   if (start < 0) return "";
   start += StringLen(searchKey);
   int end = StringFind(obj, "\"", start);
   if (end < 0) return "";
   return StringSubstr(obj, start, end - start);
}

//+------------------------------------------------------------------+
//| Parse FF ISO date string to broker-local datetime                |
//+------------------------------------------------------------------+
datetime ParseFFDate(const string &dateStr)
{
   if (StringLen(dateStr) < 19) return 0;

   int yr  = (int)StringSubstr(dateStr, 0,  4);
   int mo  = (int)StringSubstr(dateStr, 5,  2);
   int dy  = (int)StringSubstr(dateStr, 8,  2);
   int hr  = (int)StringSubstr(dateStr, 11, 2);
   int mn  = (int)StringSubstr(dateStr, 14, 2);
   int sc  = (int)StringSubstr(dateStr, 17, 2);

   int    offSign = 1;
   string offStr  = StringSubstr(dateStr, 19);
   int    colonP  = StringFind(offStr, ":");
   int    offH = 0, offM = 0;

   if (StringLen(offStr) >= 3)
   {
      string signChar = StringSubstr(offStr, 0, 1);
      if (signChar == "-") offSign = -1;
      offH = (int)StringSubstr(offStr, 1, 2);
      if (colonP > 0) offM = (int)StringSubstr(offStr, colonP + 1, 2);
   }

   MqlDateTime mdt;
   mdt.year  = yr; mdt.mon = mo; mdt.day = dy;
   mdt.hour  = hr; mdt.min = mn; mdt.sec = sc;
   datetime utc = StructToTime(mdt) - offSign * (offH * 3600 + offM * 60);

   datetime brokerOffset = TimeCurrent() - TimeGMT();
   return utc + brokerOffset;
}

//+------------------------------------------------------------------+
//| Compute gold bias from event metadata                            |
//| Returns: +1 Bullish Gold, -1 Bearish Gold, 0 Neutral             |
//+------------------------------------------------------------------+
int CalcBias(const string country, const string title,
             const string forecast, const string previous)
{
   if (forecast == "" || previous == "") return 0;

   double fc = StringToDouble(forecast);
   double pv = StringToDouble(previous);
   if (fc == 0 && pv == 0) return 0;

   bool forecastStronger = (fc > pv);
   bool forecastWeaker   = (fc < pv);

   if (country == "USD")
   {
      if (StringFind(title, "Employment")   >= 0 ||
          StringFind(title, "Claims")       >= 0 ||
          StringFind(title, "PMI")          >= 0 ||
          StringFind(title, "GDP")          >= 0 ||
          StringFind(title, "Retail")       >= 0 ||
          StringFind(title, "Home Sales")   >= 0)
         return forecastStronger ? -1 : (forecastWeaker ? +1 : 0);

      if (StringFind(title, "CPI")       >= 0 ||
          StringFind(title, "PCE")       >= 0 ||
          StringFind(title, "Inflation") >= 0)
         return forecastStronger ? -1 : (forecastWeaker ? +1 : 0);

      if (StringFind(title, "Unemployment Rate") >= 0)
         return forecastStronger ? +1 : (forecastWeaker ? -1 : 0);
   }

   if (country == "CNY" && StringFind(title, "PMI") >= 0)
      return forecastWeaker ? +1 : (forecastStronger ? -1 : 0);

   return 0;
}

//+------------------------------------------------------------------+
//| Draw on-screen dashboard with all events                         |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   RemoveAllLabels();

   int y     = 20;
   int x     = 10;
   int lineH = 16;

   DrawLabel("hdr0", "== FF Calendar: Medium/High Impact ==",
             x, y, InpColorInfo, 8);
   y += lineH + 4;
   DrawLabel("hdr1",
      StringFormat("%-32s %-5s %-12s %-10s %-12s %-10s  BIAS  URL",
                   "Title", "CCY", "Date", "Time", "Forecast", "Previous"),
      x, y, InpColorInfo, 7);
   y += lineH;

   for (int i = 0; i < evCount; i++)
   {
      color  c    = (evImpact[i] == "High") ? InpColorHigh : InpColorMedium;
      string dt   = TimeToString(evTime[i], TIME_DATE);
      string tm   = TimeToString(evTime[i], TIME_MINUTES);
      string bias = (evBias[i] == +1) ? "BULL" :
                    (evBias[i] == -1) ? "BEAR" : "NEUT";
      string url  = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";

      string line = StringFormat("%-32s %-5s %-12s %-10s %-12s %-10s  %-6s  %s",
                                 StringSubstr(evTitle[i], 0, 31),
                                 evCountry[i], dt, tm,
                                 evForecast[i], evPrevious[i],
                                 bias, url);

      DrawLabel("ev" + (string)i, line, x, y, c, 7);
      y += lineH;
      if (y > 600) break;
   }

   if (evCount == 0)
      DrawLabel("noev", "No Medium/High impact events loaded.",
                x, y, InpColorInfo, 8);
}

//+------------------------------------------------------------------+
void DrawLabel(const string name, const string text,
               const int x, const int y,
               const color clr, const int fontSize)
{
   string lbl = "FFCal_" + (string)labelBase + "_" + name;
   if (ObjectFind(0, lbl) < 0)
      ObjectCreate(0, lbl, OBJ_LABEL, 0, 0, 0);
   ObjectSetString (0, lbl, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, lbl, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, lbl, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, lbl, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetString (0, lbl, OBJPROP_FONT,      "Courier New");
   ObjectSetInteger(0, lbl, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void RemoveAllLabels()
{
   string prefix = "FFCal_" + (string)labelBase + "_";
   for (int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if (StringFind(nm, prefix) == 0)
         ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//| Check events and manage orders                                   |
//+------------------------------------------------------------------+
void CheckAndTrade()
{
   if (Symbol() != "XAUUSD" && Symbol() != "XAUUSDm" &&
       Symbol() != "GOLD"   && Symbol() != "GOLDm") return;

   datetime now = TimeCurrent();

   for (int i = 0; i < evCount; i++)
   {
      if (evTraded[i])    continue;
      if (evBias[i] == 0) continue;

      int secsToEvent = (int)(evTime[i] - now);

      if (secsToEvent > 0 && secsToEvent <= InpMinsBefore * 60)
      {
         if (!HasOpenOrder())
         {
            OpenOrder(evBias[i], evTitle[i]);
            evTraded[i] = true;
         }
      }

      if (secsToEvent < -(InpMinsAfter * 60))
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
   int    cmd   = (bias == +1) ? OP_BUY : OP_SELL;
   double price = (cmd  == OP_BUY) ? Ask : Bid;
   double sl    = (cmd  == OP_BUY) ? price - InpSL_Points * Point
                                   : price + InpSL_Points * Point;
   double tp    = (cmd  == OP_BUY) ? price + InpTP_Points * Point
                                   : price - InpTP_Points * Point;

   int ticket = OrderSend(Symbol(), cmd, InpLotSize, price, 3, sl, tp,
                          "FFCal:" + StringSubstr(evName, 0, 20),
                          InpMagic, 0,
                          (cmd == OP_BUY) ? clrLime : clrRed);

   if (ticket < 0)
      Print("OrderSend failed. Error=", GetLastError(),
            " Event=", evName, " Bias=", bias);
   else
      Print("Order opened. Ticket=", ticket, " Event=", evName,
            " Dir=", (cmd == OP_BUY ? "BUY" : "SELL"));
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
      bool   ok    = OrderClose(OrderTicket(), OrderLots(), price, 3, clrYellow);
      if (!ok) Print("OrderClose failed. Error=", GetLastError());
   }
}
//+------------------------------------------------------------------+
