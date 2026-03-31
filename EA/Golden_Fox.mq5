//+------------------------------------------------------------------+
//| XAUUSD Scalp-Intraday EA                                        |
//| Strategy : 6 EMA + SAR + RVI(10) zone + H1/H4 EMA + ADX filter  |
//| Platform  : MetaTrader 5 (MQL5)                                 |
//| Version   : 2.6                                                 |
//| Changes   : Multi-signal invalidation score system.             |
//|             EMA(+1) + RVI slope(+1) + SAR flip(+2) + RVI cross(+3)|
//|             Score>=3 → close. Score==2 → breakeven. <=1 → ignore.|
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

//--- Inputs
input group              "=== Indicators ==="
input int                EMA_Period      = 6;
input double             SAR_Step        = 0.04;
input double             SAR_Max         = 0.20;
input int                RVI_Period      = 10;
input int                H1_EMA_Period   = 50;
input int                H4_EMA_Period   = 21;
input int                ADX_Period      = 14;
input double             ADX_Min         = 25.0;
input double             RVI_Zone        = 0.050;  // No-trade zone boundary (±)

input group              "=== Risk ==="
input double             LotSize         = 0.01;   // Fixed lot size per trade
input double             TP_Pips   = 100;          // Take profit in pips
input double             MaxLotCap       = 0.12;   // Hard lot ceiling

input group              "=== Breakeven ==="
input double             BreakevenTrigger    = 2.00;  // Float profit in $ to move SL to BE

input group              "=== Invalidation ==="
input int                InvalidationThreshold = 3;   // Score to trigger close (3=exit, 2=BE)
input int                EMAInvalidBars        = 1;   // Bars close must be below/above EMA
input bool               UseRVISlope           = true; // Count RVI slope weakening (+1)


input group              "=== Daily Guard ==="
input int                MaxDailyLosses  = 3;
input double             MaxDailyDDPct   = 15.0;

input group              "=== Session Filter ==="
input bool               UseSessionFilter = true;
input int                LondonOpen      = 7;
input int                LondonClose     = 16;
input int                NYOpen          = 12;
input int                NYClose         = 21;

input group              "=== News Filter ==="
input bool               UseNewsFilter    = true;   // Enable economic calendar filter
input int                PauseBeforeNews  = 60;     // Minutes to pause before event
input int                ResumeAfterNews  = 45;     // Minutes to resume after event

input group              "=== General ==="
input int                MagicNumber     = 202402;
input int                MaxSlippage     = 30;

//--- Handles
int hEMA_M15, hSAR_M15, hRVI_M15, hEMA_H1, hEMA_H4, hADX_M15;

//--- Globals
CTrade      trade;
datetime    lastBarTime     = 0;
double      dayStartBalance = 0;
datetime    dayStartTime    = 0;
int         dailyLosses     = 0;
bool        breakevenMoved  = false;

//+------------------------------------------------------------------+
int OnInit()
{
   hEMA_M15 = iMA(_Symbol, PERIOD_M15, EMA_Period,    0, MODE_EMA, PRICE_CLOSE);
   hSAR_M15 = iSAR(_Symbol, PERIOD_M15, SAR_Step, SAR_Max);
   hRVI_M15 = iRVI(_Symbol, PERIOD_M15, RVI_Period);
   hEMA_H1  = iMA(_Symbol, PERIOD_H1,  H1_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hEMA_H4  = iMA(_Symbol, PERIOD_H4,  H4_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hADX_M15 = iADX(_Symbol, PERIOD_M15, ADX_Period);

   if(hEMA_M15 == INVALID_HANDLE || hSAR_M15 == INVALID_HANDLE ||
      hRVI_M15 == INVALID_HANDLE || hEMA_H1  == INVALID_HANDLE ||
      hEMA_H4  == INVALID_HANDLE || hADX_M15 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dayStartTime    = TimeCurrent();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hEMA_M15);
   IndicatorRelease(hSAR_M15);
   IndicatorRelease(hRVI_M15);
   IndicatorRelease(hEMA_H1);
   IndicatorRelease(hEMA_H4);
   IndicatorRelease(hADX_M15);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(UseNewsFilter && IsNewsBlocked()) return;

   if(!IsNewBar()) return;

   ResetDailyIfNeeded();
   ManageOpenPosition();

   if(IsTradingHalted()) return;
   if(HasOpenPosition())  return;

   int signal = GetSignal();
   if(signal == 0) return;

   ExecuteTrade(signal);
}

//+------------------------------------------------------------------+
//| Signal Logic                                                     |
//|                                                                  |
//| BUY  : RVI fresh cross UP  (M2 below, M1 above signal)          |
//|        AND rviM1 still below -RVI_Zone (oversold territory)      |
//| SELL : RVI fresh cross DOWN (M2 above, M1 below signal)         |
//|        AND rviM1 still above +RVI_Zone (overbought territory)    |
//| BLOCK: No fresh cross detected on last closed bar                |
//+------------------------------------------------------------------+
int GetSignal()
{
   if(UseSessionFilter && !InSession()) return 0;

   double ema1[1];
   double sar1[1];
   double rviM1[1], rviM2[1], rviS1[1], rviS2[1];
   double h1ema[1], h4ema[1];
   double adx[1];
   double close1[1], high1[1], low1[1];

   if(CopyBuffer(hEMA_M15, 0, 1, 1, ema1)   < 1) return 0;
   if(CopyBuffer(hSAR_M15, 0, 1, 1, sar1)   < 1) return 0;
   if(CopyBuffer(hRVI_M15, 0, 1, 1, rviM1)  < 1) return 0;
   if(CopyBuffer(hRVI_M15, 0, 2, 1, rviM2)  < 1) return 0;
   if(CopyBuffer(hRVI_M15, 1, 1, 1, rviS1)  < 1) return 0;
   if(CopyBuffer(hRVI_M15, 1, 2, 1, rviS2)  < 1) return 0;
   if(CopyBuffer(hEMA_H1,  0, 0, 1, h1ema)  < 1) return 0;
   if(CopyBuffer(hEMA_H4,  0, 0, 1, h4ema)  < 1) return 0;
   if(CopyBuffer(hADX_M15, 0, 1, 1, adx)    < 1) return 0;
   if(CopyClose(_Symbol, PERIOD_M15, 1, 1, close1) < 1) return 0;
   if(CopyHigh (_Symbol, PERIOD_M15, 1, 1, high1)  < 1) return 0;
   if(CopyLow  (_Symbol, PERIOD_M15, 1, 1, low1)   < 1) return 0;

   // Gate 1: ADX regime filter — trending markets only
   if(adx[0] < ADX_Min) return 0;

   double h1Price = iClose(_Symbol, PERIOD_H1, 0);
   double h4Price = iClose(_Symbol, PERIOD_H4, 0);

   // BUY: fresh RVI cross UP on bar[1], main still below -RVI_Zone
   bool buyRVI_cross = rviM2[0] < rviS2[0] &&   // prev bar: main below signal
                       rviM1[0] > rviS1[0] &&   // curr bar: main crossed above signal
                       rviM1[0] < -RVI_Zone;    // cross happened in oversold territory
   bool buyEMA       = close1[0] > ema1[0];
   bool buySAR       = sar1[0]   < low1[0];
   bool buyH1        = h1Price   > h1ema[0];
   bool buyH4        = h4Price   > h4ema[0];

   if(buyRVI_cross && buyEMA && buySAR && buyH1 && buyH4) return 1;

   // SELL: fresh RVI cross DOWN on bar[1], main still above +RVI_Zone
   bool sellRVI_cross = rviM2[0] > rviS2[0] &&  // prev bar: main above signal
                        rviM1[0] < rviS1[0] &&  // curr bar: main crossed below signal
                        rviM1[0] > RVI_Zone;    // cross happened in overbought territory
   bool sellEMA       = close1[0] < ema1[0];
   bool sellSAR       = sar1[0]   > high1[0];
   bool sellH1        = h1Price   < h1ema[0];
   bool sellH4        = h4Price   < h4ema[0];

   if(sellRVI_cross && sellEMA && sellSAR && sellH1 && sellH4) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Trade Execution                                                  |
//| SL  : First SAR dot of the new trend (SAR[1])                    |
//| TP  : Entry ± (100 pips)                                         |
//| Lot : Static LotSize input (default 0.01)                        |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
   double sar1[1];
   if(CopyBuffer(hSAR_M15, 0, 1, 1, sar1) < 1) return;

   double lots = NormalizeLot(LotSize);
   if(lots <= 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(signal == 1)
   {
      double sl   = NormalizeDouble(sar1[0], _Digits);
      double risk = ask - sl;
      if(risk <= 0) return;
      double tp = NormalizeDouble(ask + PipsToPrice(TP_Pips), _Digits);
      if(trade.Buy(lots, _Symbol, ask, sl, tp, "GoldenFox_BUY"))
         breakevenMoved = false;
   }
   else if(signal == -1)
   {
      double sl   = NormalizeDouble(sar1[0], _Digits);
      double risk = sl - bid;
      if(risk <= 0) return;
      double tp = NormalizeDouble(bid - PipsToPrice(TP_Pips), _Digits);
      if(trade.Sell(lots, _Symbol, bid, sl, tp, "GoldenFox_SELL"))
         breakevenMoved = false;
   }
}

//+------------------------------------------------------------------+
//| Position Management                                              |
//| Priority order:                                                  |
//|   1. Score >= InvalidationThreshold → close trade               |
//|   2. Score == 2 (and BE not yet moved) → move SL to BE          |
//|   3. Existing BE trigger ($profit threshold)                     |
//| Daily loss count: only incremented on closes at a loss.         |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   if(!PositionSelect(_Symbol)) return;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL     = PositionGetDouble(POSITION_SL);
   double curTP     = PositionGetDouble(POSITION_TP);
   long   posType   = PositionGetInteger(POSITION_TYPE);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // --- 1. Invalidation score ---
   int score = GetInvalidationScore(posType);

   if(score >= InvalidationThreshold)
   {
      double floatProfit = PositionGetDouble(POSITION_PROFIT);
      if(!trade.PositionClose(_Symbol)) return;
      if(floatProfit < 0) dailyLosses++;
      return;
   }

   // --- 2. Score == 2: tighten risk by moving SL to BE ---
   if(score == 2 && !breakevenMoved)
   {
      double spread = ask - bid;
      double be     = (posType == POSITION_TYPE_BUY)
                      ? NormalizeDouble(openPrice + spread, _Digits)
                      : NormalizeDouble(openPrice - spread, _Digits);

      bool shouldMove = (posType == POSITION_TYPE_BUY  && be > curSL) ||
                        (posType == POSITION_TYPE_SELL && be < curSL);

      if(shouldMove && trade.PositionModify(_Symbol, be, curTP))
         breakevenMoved = true;

      return;
   }

   // --- 3. Profit-triggered BE (existing logic, fires when score <= 1) ---
   if(!breakevenMoved)
   {
      double floatingProfit = PositionGetDouble(POSITION_PROFIT);
      if(floatingProfit >= BreakevenTrigger)
      {
         double spread = ask - bid;
         double be     = (posType == POSITION_TYPE_BUY)
                         ? NormalizeDouble(openPrice + spread, _Digits)
                         : NormalizeDouble(openPrice - spread, _Digits);

         bool shouldMove = (posType == POSITION_TYPE_BUY  && be > curSL) ||
                           (posType == POSITION_TYPE_SELL && be < curSL);

         if(shouldMove && trade.PositionModify(_Symbol, be, curTP))
            breakevenMoved = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Invalidation Score                                               |
//|                                                                  |
//| Signal                  Weight  Trigger                         |
//| EMA(6) failure            +1    close[1] crosses EMA[1]         |
//| RVI slope weakening       +1    main approaching signal line     |
//| SAR flip                  +2    SAR switches side                |
//| RVI cross reversal        +3    main crosses signal (hard flip)  |
//|                                                                  |
//| Score >= 3 → close trade                                        |
//| Score == 2 → move SL to breakeven                               |
//| Score <= 1 → ignore (noise tolerance)                           |
//+------------------------------------------------------------------+
int GetInvalidationScore(long posType)
{
   int score = 0;

   // Read all needed indicator values
   double rviM1[2], rviS1[2];
   double ema1[];  ArrayResize(ema1, EMAInvalidBars + 1);
   double sar1[1];
   double close1[]; ArrayResize(close1, EMAInvalidBars + 1);
   double high1[1], low1[1];

   if(CopyBuffer(hRVI_M15, 0, 1, 2, rviM1) < 2) return 0;
   if(CopyBuffer(hRVI_M15, 1, 1, 2, rviS1) < 2) return 0;
   if(CopyBuffer(hEMA_M15, 0, 1, EMAInvalidBars + 1, ema1)   < EMAInvalidBars + 1) return 0;
   if(CopyBuffer(hSAR_M15, 0, 1, 1, sar1)                    < 1) return 0;
   if(CopyClose(_Symbol, PERIOD_M15, 1, EMAInvalidBars + 1, close1) < EMAInvalidBars + 1) return 0;
   if(CopyHigh (_Symbol, PERIOD_M15, 1, 1, high1) < 1) return 0;
   if(CopyLow  (_Symbol, PERIOD_M15, 1, 1, low1)  < 1) return 0;

   // rviM1[0] = bar[1] (most recent closed), rviM1[1] = bar[2]
   // ema1[0]  = bar[1], close1[0] = bar[1]  (index 0 = most recent in copied array)

   if(posType == POSITION_TYPE_BUY)
   {
      // RVI cross reversal (+3): main crossed BELOW signal on last bar
      if(rviM1[0] < rviS1[0] && rviM1[1] > rviS1[1])
         score += 3;

      // RVI slope weakening (+1): main converging toward signal from above
      else if(UseRVISlope && rviM1[0] > rviS1[0] &&
              (rviM1[0] - rviS1[0]) < (rviM1[1] - rviS1[1]))
         score += 1;

      // EMA(6) failure (+1): close below EMA for EMAInvalidBars consecutive bars
      bool emaFail = true;
      for(int i = 0; i < EMAInvalidBars; i++)
         if(close1[i] >= ema1[i]) { emaFail = false; break; }
      if(emaFail) score += 1;

      // SAR flip (+2): SAR now above price (flipped to bearish)
      if(sar1[0] > high1[0])
         score += 2;
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      // RVI cross reversal (+3): main crossed ABOVE signal on last bar
      if(rviM1[0] > rviS1[0] && rviM1[1] < rviS1[1])
         score += 3;

      // RVI slope weakening (+1): main converging toward signal from below
      else if(UseRVISlope && rviM1[0] < rviS1[0] &&
              (rviS1[0] - rviM1[0]) < (rviS1[1] - rviM1[1]))
         score += 1;

      // EMA(6) failure (+1): close above EMA for EMAInvalidBars consecutive bars
      bool emaFail = true;
      for(int i = 0; i < EMAInvalidBars; i++)
         if(close1[i] <= ema1[i]) { emaFail = false; break; }
      if(emaFail) score += 1;

      // SAR flip (+2): SAR now below price (flipped to bullish)
      if(sar1[0] < low1[0])
         score += 2;
   }

   return score;
}

//+------------------------------------------------------------------+
//| Lot Normalization                                                |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lot = MathFloor(lot / lotStep) * lotStep;
   return MathMax(minLot, MathMin(MaxLotCap, lot));
}

//+------------------------------------------------------------------+
//| Daily Guard                                                      |
//+------------------------------------------------------------------+
void ResetDailyIfNeeded()
{
   MqlDateTime now, start;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(dayStartTime, start);

   if(now.day != start.day || now.mon != start.mon)
   {
      dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      dayStartTime    = TimeCurrent();
      dailyLosses     = 0;
   }
}

bool IsTradingHalted()
{
   double ddPct = (dayStartBalance - AccountInfoDouble(ACCOUNT_EQUITY))
                  / dayStartBalance * 100.0;
   return (ddPct >= MaxDailyDDPct || dailyLosses >= MaxDailyLosses);
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t[1];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, t) < 1) return false;
   if(t[0] == lastBarTime) return false;
   lastBarTime = t[0];
   return true;
}

bool HasOpenPosition()
{
   return PositionSelect(_Symbol);
}

bool InSession()
{
   datetime utc = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   int h = dt.hour;
   return (h >= LondonOpen && h < LondonClose) ||
          (h >= NYOpen     && h < NYClose);
}

double PipsToPrice(double pips)
{
   double pipSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // XAUUSD typically 0.01 point = 1 pip
   if(_Digits == 3 || _Digits == 5)
      pipSize *= 10;

   return pips * pipSize;
}

//+------------------------------------------------------------------+
//| News Filter — MQL5 Economic Calendar                             |
//| Blocks new entries PauseBeforeNews min before and               |
//| ResumeAfterNews min after any high-impact USD event.            |
//| Open positions are NOT closed — only new entries are blocked.   |
//+------------------------------------------------------------------+
bool IsNewsBlocked()
{
   datetime now  = TimeCurrent();
   int lookbackMin = (int)MathMax(PauseBeforeNews, ResumeAfterNews);
   datetime from = now - (datetime)(lookbackMin * 60);      // include full post-news horizon
   datetime to   = now + (datetime)(PauseBeforeNews * 60);  // look ahead full pause window

   MqlCalendarValue values[];
   if(CalendarValueHistory(values, from, to, NULL, "USD") <= 0)
      return false;

   for(int i = 0; i < ArraySize(values); i++)
   {
      // High-impact events only — currency already filtered by CalendarValueHistory()
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)  continue;
      if(!IsRelevantEvent(ev.name))                  continue;

      datetime newsTime = values[i].time;

      bool inPreWindow  = (now >= newsTime - (datetime)(PauseBeforeNews * 60) &&
                           now <  newsTime);
      bool inPostWindow = (now >= newsTime &&
                           now <= newsTime + (datetime)(ResumeAfterNews * 60));

      if(inPreWindow || inPostWindow)
      {
         PrintFormat("NEWS BLOCK: %s at %s — trading paused", ev.name,
                     TimeToString(newsTime, TIME_DATE | TIME_MINUTES));
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Relevant event keyword matching                                  |
//| Tier 1: FOMC, CPI, NFP, PCE, Jackson Hole                      |
//| Tier 2: GDP, Retail Sales, ISM, Unemployment                    |
//+------------------------------------------------------------------+
bool IsRelevantEvent(const string eventName)
{
   string keywords[] =
   {
      "FOMC", "Federal Funds", "Jackson Hole",
      "CPI", "Core CPI", "Consumer Price",
      "Non-Farm", "NFP", "Nonfarm",
      "PCE", "Personal Consumption",
      "GDP", "Gross Domestic",
      "Retail Sales",
      "ISM Manufacturing", "ISM Services", "ISM Non-Manufacturing",
      "Unemployment Claims", "Initial Claims"
   };

   for(int k = 0; k < ArraySize(keywords); k++)
   {
      if(StringFind(eventName, keywords[k]) >= 0)
         return true;
   }

   return false;
}
//+------------------------------------------------------------------+
