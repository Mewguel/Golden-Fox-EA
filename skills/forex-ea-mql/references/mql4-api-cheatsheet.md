# MQL4 API Quick Reference — EA Development

## Indicator Functions
```mql4
// EMA
double ema = iMA(NULL, 0, period, 0, MODE_EMA, PRICE_CLOSE, shift);

// Parabolic SAR
double sar = iSAR(NULL, 0, step, maximum, shift);

// RVI — returns MAIN (green) or SIGNAL (red)
double rvi_main   = iRVI(NULL, 0, period, MODE_MAIN,   shift);
double rvi_signal = iRVI(NULL, 0, period, MODE_SIGNAL, shift);

// ATR
double atr = iATR(NULL, 0, period, shift);

// Multi-timeframe (e.g., H1 EMA from M15 EA)
double h1_ema = iMA(NULL, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE, 0);
```

## Order Functions
```mql4
// Open trade
int ticket = OrderSend(Symbol(), OP_BUY, lots, Ask, slippage, sl, tp, comment, magic, 0, clrBlue);

// Modify SL/TP
bool ok = OrderModify(ticket, OrderOpenPrice(), newSL, newTP, 0, clrYellow);

// Close partial
bool ok = OrderClose(ticket, closeVolume, Bid, slippage, clrRed);

// Close full
bool ok = OrderClose(ticket, OrderLots(), Bid, slippage, clrRed);

// Loop open orders
for(int i = OrdersTotal()-1; i >= 0; i--) {
   if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic) {
         // process
      }
   }
}
```

## Account Info
```mql4
double bal  = AccountBalance();
double eq   = AccountEquity();
double free = AccountFreeMargin();
```

## Market Info
```mql4
double point    = MarketInfo(Symbol(), MODE_POINT);     // 0.00001 for 5-digit
double tickval  = MarketInfo(Symbol(), MODE_TICKVALUE); // value of 1 tick
double minlot   = MarketInfo(Symbol(), MODE_MINLOT);
double lotstep  = MarketInfo(Symbol(), MODE_LOTSTEP);
double spread   = MarketInfo(Symbol(), MODE_SPREAD);    // in points
```

## XAUUSD Specifics (MQL4)
- `Digits` = 2 (price like 1923.45)
- `Point` = 0.01 (for gold)
- 1 pip for gold = 0.10 (10 points)
- `MODE_TICKVALUE` varies — always calculate dynamically

## Time
```mql4
datetime now     = TimeCurrent();
int      hour    = TimeHour(now);
int      day     = TimeDay(now);
datetime barTime = Time[0];          // current bar open time
bool newBar      = (barTime != lastBarTime);
```

## Common Patterns
```mql4
// Normalize lot size
double NormLot(double lot) {
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double min  = MarketInfo(Symbol(), MODE_MINLOT);
   double max  = MarketInfo(Symbol(), MODE_MAXLOT);
   lot = MathFloor(lot / step) * step;
   return MathMax(min, MathMin(max, lot));
}

// Pips to price distance (XAUUSD)
double PipsToPrice(double pips) {
   return pips * MarketInfo(Symbol(), MODE_POINT) * 10;
}
```
