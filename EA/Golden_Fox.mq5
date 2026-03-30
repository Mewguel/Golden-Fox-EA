//+------------------------------------------------------------------+
//| XAUUSD Scalp-Intraday EA                                        |
//| Strategy : 6 EMA + SAR + RVI(10) zone + H1/H4 EMA + ADX filter  |
//| Platform  : MetaTrader 5 (MQL5)                                 |
//| Version   : 2.2                                                 |
//| Changes   : SL anchored to first SAR dot of new trend.          |
//|             Buy  → SL at SAR dot below entry.                   |
//|             Sell → SL at SAR dot above entry.                   |
//|             TP fixed at 1:1.5 RR (Risk × 1.5).                 |
//|             ATR_Multiplier removed — SAR is the SL source now.  |
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
input double             RiskPercent     = 5.0;
input double             RR_Ratio        = 1.5;    // Fixed 1:1.5 RR (Risk × 1.5)
input double             MaxLotCap       = 0.12;

input group              "=== Exit Logic ==="
input bool               UsePartialClose = false;
input double             PartialClosePct = 0.60;

input group              "=== Daily Guard ==="
input int                MaxDailyLosses  = 3;
input double             MaxDailyDDPct   = 15.0;

input group              "=== Session Filter ==="
input bool               UseSessionFilter = true;
input int                LondonOpen      = 7;
input int                LondonClose     = 16;
input int                NYOpen          = 12;
input int                NYClose         = 21;

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
bool        partialDone     = false;
double      tradeOpenPrice  = 0;
double      tradeSLDist     = 0;

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

   Print("Golden Fox EA v2.2 initialized. ADX_Min=", ADX_Min,
         " RR=1:", RR_Ratio, " RVI_Zone=", RVI_Zone, " SL=SAR-anchored");
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
//| BUY  : Both RVI lines trending UP  AND both BELOW -RVI_Zone     |
//| SELL : Both RVI lines trending DOWN AND both ABOVE +RVI_Zone     |
//| BLOCK: Both lines inside ±RVI_Zone → no trade (weak momentum)   |
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

   // Gate 2: RVI no-trade zone — block when BOTH lines are inside ±RVI_Zone
   bool rviChop = (rviM1[0] > -RVI_Zone && rviM1[0] < RVI_Zone) &&
                   (rviS1[0] > -RVI_Zone && rviS1[0] < RVI_Zone);
   if(rviChop) return 0;

   double h1Price = iClose(_Symbol, PERIOD_H1, 0);
   double h4Price = iClose(_Symbol, PERIOD_H4, 0);

   // BUY: both RVI lines trending UP and BELOW -RVI_Zone
   bool buyRVI_trend = rviM1[0] > rviM2[0] && rviS1[0] > rviS2[0];
   bool buyRVI_zone  = rviM1[0] < -RVI_Zone && rviS1[0] < -RVI_Zone;
   bool buyEMA       = close1[0] > ema1[0];
   bool buySAR       = sar1[0]   < low1[0];
   bool buyH1        = h1Price   > h1ema[0];
   bool buyH4        = h4Price   > h4ema[0];

   if(buyEMA && buySAR && buyRVI_trend && buyRVI_zone && buyH1 && buyH4) return 1;

   // SELL: both RVI lines trending DOWN and ABOVE +RVI_Zone
   bool sellRVI_trend = rviM1[0] < rviM2[0] && rviS1[0] < rviS2[0];
   bool sellRVI_zone  = rviM1[0] > RVI_Zone  && rviS1[0] > RVI_Zone;
   bool sellEMA       = close1[0] < ema1[0];
   bool sellSAR       = sar1[0]   > high1[0];
   bool sellH1        = h1Price   < h1ema[0];
   bool sellH4        = h4Price   < h4ema[0];

   if(sellEMA && sellSAR && sellRVI_trend && sellRVI_zone && sellH1 && sellH4) return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Trade Execution                                                  |
//| SL  : First SAR dot of the new trend (SAR value at bar[1])      |
//| TP  : Entry ± (|Entry - SL| × RR_Ratio)  — default 1:1.5       |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
   double sar1[1];
   if(CopyBuffer(hSAR_M15, 0, 1, 1, sar1) < 1) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(signal == 1)
   {
      double sl    = NormalizeDouble(sar1[0], _Digits);   // SAR dot below price
      double risk  = ask - sl;
      if(risk <= 0) return;                               // SAR above entry — invalid
      double tp    = NormalizeDouble(ask + risk * RR_Ratio, _Digits);
      double lots  = CalcLotSize(risk);
      if(lots <= 0) return;

      if(trade.Buy(lots, _Symbol, ask, sl, tp, "GoldenFox_BUY"))
      {
         tradeOpenPrice = ask;
         tradeSLDist    = risk;
         partialDone    = false;
      }
   }
   else if(signal == -1)
   {
      double sl    = NormalizeDouble(sar1[0], _Digits);   // SAR dot above price
      double risk  = sl - bid;
      if(risk <= 0) return;                               // SAR below entry — invalid
      double tp    = NormalizeDouble(bid - risk * RR_Ratio, _Digits);
      double lots  = CalcLotSize(risk);
      if(lots <= 0) return;

      if(trade.Sell(lots, _Symbol, bid, sl, tp, "GoldenFox_SELL"))
      {
         tradeOpenPrice = bid;
         tradeSLDist    = risk;
         partialDone    = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Position Management                                              |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   if(!PositionSelect(_Symbol)) return;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL     = PositionGetDouble(POSITION_SL);
   double curTP     = PositionGetDouble(POSITION_TP);
   double lots      = PositionGetDouble(POSITION_VOLUME);
   long   posType   = PositionGetInteger(POSITION_TYPE);
   ulong  ticket    = PositionGetInteger(POSITION_TICKET);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price = (posType == POSITION_TYPE_BUY) ? bid : ask;

   double rviM1[1], rviM2[1], rviS1[1], rviS2[1];
   if(CopyBuffer(hRVI_M15, 0, 1, 1, rviM1) < 1) return;
   if(CopyBuffer(hRVI_M15, 0, 2, 1, rviM2) < 1) return;
   if(CopyBuffer(hRVI_M15, 1, 1, 1, rviS1) < 1) return;
   if(CopyBuffer(hRVI_M15, 1, 2, 1, rviS2) < 1) return;

   // RVI Invalidation: cross reversal → exit immediately
   bool rviInvalidBuy  = (posType == POSITION_TYPE_BUY)  &&
                          rviM1[0] < rviS1[0] && rviM2[0] > rviS2[0];
   bool rviInvalidSell = (posType == POSITION_TYPE_SELL) &&
                          rviM1[0] > rviS1[0] && rviM2[0] < rviS2[0];

   if(rviInvalidBuy || rviInvalidSell)
   {
      trade.PositionClose(_Symbol);
      dailyLosses++;
      return;
   }

   // Optional partial close (disabled by default)
   if(UsePartialClose && !partialDone)
   {
      double profitDist = (posType == POSITION_TYPE_BUY)
                          ? price - openPrice
                          : openPrice - price;

      if(profitDist >= tradeSLDist)
      {
         double closeVol = NormalizeLot(lots * PartialClosePct);
         if(closeVol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            trade.PositionClosePartial(ticket, closeVol);

            double spread = ask - bid;
            double be = (posType == POSITION_TYPE_BUY)
                        ? openPrice + spread
                        : openPrice - spread;
            trade.PositionModify(_Symbol, NormalizeDouble(be, _Digits), curTP);
            partialDone = true;

            double sar[1];
            if(CopyBuffer(hSAR_M15, 0, 1, 1, sar) == 1)
            {
               if(posType == POSITION_TYPE_BUY && sar[0] > curSL && sar[0] < price)
                  trade.PositionModify(_Symbol, NormalizeDouble(sar[0], _Digits), curTP);
               else if(posType == POSITION_TYPE_SELL && sar[0] < curSL && sar[0] > price)
                  trade.PositionModify(_Symbol, NormalizeDouble(sar[0], _Digits), curTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Position Sizing                                                  |
//+------------------------------------------------------------------+
double CalcLotSize(double slDist)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * (RiskPercent / 100.0);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickVal <= 0 || tickSize <= 0) return 0;

   double slInTicks = slDist / tickSize;
   double rawLot    = riskAmt / (slInTicks * tickVal);

   return NormalizeLot(rawLot);
}

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
//+------------------------------------------------------------------+
