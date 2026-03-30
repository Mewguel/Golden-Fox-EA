//+------------------------------------------------------------------+
//| XAUUSD Scalp-Intraday EA                                        |
//| Strategy : 6 EMA + SAR + RVI(10) zone + H1/H4 EMA + ADX filter  |
//| Platform  : MetaTrader 5 (MQL5)                                 |
//| Version   : 2.3                                                 |
//| Changes   : Static configurable lot size (default 0.01).        |
//|             Trailing SL: move to breakeven when floating         |
//|             profit reaches BreakevenTrigger (default $2.00).     |
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
input double             BreakevenTrigger = 2.00;  // Float profit in $ to move SL to BE


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
//| - RVI cross reversal → close immediately                        |
//| - Floating profit ≥ BreakevenTrigger ($) → move SL to BE        |
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

   // --- RVI Invalidation: cross reversal → exit immediately ---
   double rviM1[1], rviM2[1], rviS1[1], rviS2[1];
   if(CopyBuffer(hRVI_M15, 0, 1, 1, rviM1) < 1) return;
   if(CopyBuffer(hRVI_M15, 0, 2, 1, rviM2) < 1) return;
   if(CopyBuffer(hRVI_M15, 1, 1, 1, rviS1) < 1) return;
   if(CopyBuffer(hRVI_M15, 1, 2, 1, rviS2) < 1) return;

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

   // --- Breakeven: move SL to entry once profit ≥ BreakevenTrigger ---
   if(!breakevenMoved)
   {
      double floatingProfit = PositionGetDouble(POSITION_PROFIT);
      if(floatingProfit >= BreakevenTrigger)
      {
         double spread = ask - bid;
         double be     = (posType == POSITION_TYPE_BUY)
                         ? NormalizeDouble(openPrice + spread, _Digits)  // cover spread
                         : NormalizeDouble(openPrice - spread, _Digits);

         // Only modify if BE improves the current SL
         bool shouldMove = (posType == POSITION_TYPE_BUY  && be > curSL) ||
                           (posType == POSITION_TYPE_SELL && be < curSL);

         if(shouldMove && trade.PositionModify(_Symbol, be, curTP))
            breakevenMoved = true;
      }
   }
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
