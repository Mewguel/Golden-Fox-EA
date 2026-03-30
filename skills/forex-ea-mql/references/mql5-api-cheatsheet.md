# MQL5 API Quick Reference — EA Development

## Indicator Handles & Buffer Reading
```mql5
// Always create handles in OnInit()
int hEMA   = iMA(_Symbol, PERIOD_M15, 6,  0, MODE_EMA, PRICE_CLOSE);
int hSAR   = iSAR(_Symbol, PERIOD_M15, 0.04, 0.20);
int hRVI   = iRVI(_Symbol, PERIOD_M15, 10);
int hATR   = iATR(_Symbol, PERIOD_M15, 14);
int hEMAh1 = iMA(_Symbol, PERIOD_H1,  50, 0, MODE_EMA, PRICE_CLOSE);

// Read values (shift=1 = last closed bar)
double buf[3];
CopyBuffer(hEMA, 0, 1, 3, buf);   // buf[0]=shift1, buf[1]=shift2, buf[2]=shift3
double ema1 = buf[0];

// RVI buffers: 0=MAIN(green), 1=SIGNAL(red)
double rvi_main[2], rvi_sig[2];
CopyBuffer(hRVI, 0, 1, 2, rvi_main);
CopyBuffer(hRVI, 1, 1, 2, rvi_sig);
// rvi_main[0] = shift1 (last closed), rvi_main[1] = shift2

// SAR buffer: 0=SAR values
double sar[2];
CopyBuffer(hSAR, 0, 1, 2, sar);

// ATR
double atr[1];
CopyBuffer(hATR, 0, 1, 1, atr);
double atrVal = atr[0];

// Release handles in OnDeinit()
IndicatorRelease(hEMA);
```

## Trade Execution (CTrade)
```mql5
#include <Trade\Trade.mqh>
CTrade trade;

// Setup (in OnInit)
trade.SetExpertMagicNumber(Magic);
trade.SetDeviationInPoints(30);
trade.SetTypeFilling(ORDER_FILLING_IOC);

// Open
trade.Buy(lots, _Symbol, 0, sl, tp, "EA_BUY");
trade.Sell(lots, _Symbol, 0, sl, tp, "EA_SELL");

// Modify open position
if(PositionSelect(_Symbol))
   trade.PositionModify(_Symbol, newSL, newTP);

// Close partial
ulong ticket = PositionGetInteger(POSITION_TICKET);
trade.PositionClosePartial(ticket, closeVolume);

// Close full
trade.PositionClose(_Symbol);
```

## Position Info
```mql5
if(PositionSelect(_Symbol)) {
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL     = PositionGetDouble(POSITION_SL);
   double curTP     = PositionGetDouble(POSITION_TP);
   double lots      = PositionGetDouble(POSITION_VOLUME);
   long   type      = PositionGetInteger(POSITION_TYPE);  // POSITION_TYPE_BUY/SELL
   double profit    = PositionGetDouble(POSITION_PROFIT);
}
```

## Account Info
```mql5
double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
```

## Symbol Info
```mql5
double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
double tickval = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
double minlot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
double lotstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
double spread  = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
```

## New Bar Detection
```mql5
datetime barTimes[];
ArraySetAsSeries(barTimes, true);
CopyTime(_Symbol, PERIOD_M15, 0, 1, barTimes);
bool isNewBar = (barTimes[0] != lastBarTime);
if(isNewBar) lastBarTime = barTimes[0];
```

## XAUUSD Specifics (MQL5)
- `SYMBOL_DIGITS` = 2
- `SYMBOL_POINT` = 0.01
- 1 pip = 0.10 (10 points)
- `SYMBOL_TRADE_TICK_SIZE` = 0.01
- Lot step typically 0.01; min lot 0.01

## Candle Data
```mql5
double closes[], highs[], lows[];
ArraySetAsSeries(closes, true);
CopyClose(_Symbol, PERIOD_M15, 1, 3, closes);  // last 3 closed bars
// closes[0]=shift1, closes[1]=shift2, closes[2]=shift3
```
