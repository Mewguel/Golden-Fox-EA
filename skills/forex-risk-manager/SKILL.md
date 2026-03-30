---
name: forex-risk-manager
description: Calculate, validate, and generate position sizing and risk management logic for Forex EAs — especially for cent accounts trading XAUUSD. Trigger this skill whenever the user asks about lot sizing, risk percentage, stop loss distance, daily drawdown limits, max trades, breakeven logic, partial close logic, or account-level risk rules. Also use when the user wants to verify whether a trade setup is within their risk parameters, or when generating the risk module of an MQL4/MQL5 EA. This skill is tuned for the $200 cent account (20,000 cent units) XAUUSD 15m strategy with 5–15% risk tiers.
---

# Forex Risk Manager Skill

## Account Context

| Parameter | Value |
|---|---|
| Account Type | Cent |
| Balance | ~$200 USD = 20,000 cent units |
| Symbol | XAUUSD |
| Platform | MT4 or MT5 (MQL4 / MQL5) |
| Max Lot (hard cap) | 0.12 |

---

## Risk Tiers

| Mode | Risk % | Max Risk $ (cent) | Default Lot | Max Open Trades |
|---|---|---|---|---|
| Moderate-Aggressive | 5% | $10 / 1,000c | 0.05 | 3 |
| Aggressive | 10% | $20 / 2,000c | 0.10 | 2 |
| Extreme | 15% | $30 / 3,000c | 0.12 | 1 |

> **Rule**: Never open a new trade until the previous one is at breakeven.

---

## Lot Size Formula

```
SL_distance  = 1.2 × ATR(14)           // in price units (e.g., 3.50 for gold)
Risk_amount  = Balance × (RiskPct / 100)
Tick_value   = value of 1 lot moving 1 point  // fetch from broker
Lot_size     = Risk_amount / (SL_distance / Point × Tick_value)

// Then normalize and clamp:
Lot_size = floor(Lot_size / LotStep) × LotStep
Lot_size = max(MinLot, min(MaxLot_cap, Lot_size))
```

### MQL4 Implementation
```mql4
double CalcLotSize(double slPoints) {
   double riskAmt  = AccountBalance() * (RiskPercent / 100.0);
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double lotStep  = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot   = MarketInfo(Symbol(), MODE_MINLOT);
   
   double rawLot   = riskAmt / (slPoints * tickVal);
   double lot      = MathFloor(rawLot / lotStep) * lotStep;
   return MathMax(minLot, MathMin(MaxLotCap, lot));
}
```

### MQL5 Implementation
```mql5
double CalcLotSize(double slPoints) {
   double riskAmt  = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double rawLot   = riskAmt / ((slPoints / (tickSize / point)) * tickVal);
   double lot      = MathFloor(rawLot / lotStep) * lotStep;
   return MathMax(minLot, MathMin(MaxLotCap, lot));
}
```

---

## SL / TP Levels

```
// Given entry price and SL distance:
BUY:
  SL_price  = Ask - (ATR * 1.2)
  TP1_price = Ask + (ATR * 1.2)        // 1:1 partial exit
  TP2_price = Ask + (ATR * 1.2 * 2.0)  // 1:2 final exit

SELL:
  SL_price  = Bid + (ATR * 1.2)
  TP1_price = Bid - (ATR * 1.2)
  TP2_price = Bid - (ATR * 1.2 * 2.0)
```

---

## Trade Management Flow (v2)

> ⚠️ **v2 Update**: Partial close + SAR trail removed from default flow after v1 backtest showed inverted RR (avg win $52 < avg loss $58). Default is now straight TP2 exit. Partial close available via `UsePartialClose` input when future testing confirms it adds value.

```
1. Trade opens → set SL (1.2×ATR) and TP (2×SL)
2. Hold until:
   a. TP hit → close full position ✅
   b. SL hit → close full position, count daily loss ❌
   c. RVI invalidation cross → close full position early ⚠️
3. If UsePartialClose = true (experimental):
   → At 1:1 RR: close 60%, move SL to breakeven
   → Trail remainder via SAR
```

### MQL4 Breakeven + Partial Close
```mql4
void ManageTrade(int ticket, double entryPrice, double slDist) {
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   
   double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
   double profit_dist  = (OrderType() == OP_BUY)
                         ? currentPrice - entryPrice
                         : entryPrice - currentPrice;
   
   // At 1:1 — partial close + move to BE
   if(profit_dist >= slDist && !partialDone[ticket]) {
      double closeVol = NormLot(OrderLots() * PartialClosePct);
      OrderClose(ticket, closeVol, currentPrice, 3, clrGold);
      
      double be = (OrderType() == OP_BUY)
                  ? entryPrice + Spread * Point
                  : entryPrice - Spread * Point;
      OrderModify(ticket, entryPrice, be, OrderTakeProfit(), 0, clrYellow);
      partialDone[ticket] = true;
   }
}
```

---

## Daily Risk Guard

```mql4
// MQL4
bool IsTradingHalted() {
   // Reset at new day
   if(TimeDay(TimeCurrent()) != TimeDay(dayStartTime)) {
      dayStartBalance = AccountBalance();
      dayStartTime    = TimeCurrent();
      dailyLosses     = 0;
   }
   
   double ddPct = (dayStartBalance - AccountEquity()) / dayStartBalance * 100.0;
   return (ddPct >= MaxDailyDDPct || dailyLosses >= MaxDailyLosses);
}
```

---

## New Trade Gate

Only allow a new trade if:
1. `CountOpenTrades() == 0` OR all open trades are at breakeven
2. `dailyLosses < MaxDailyLosses`
3. Daily DD% < 15%
4. Session filter passes (London or NY if enabled)

```mql4
bool CanOpenNewTrade() {
   if(IsTradingHalted()) return false;
   if(CountOpenTrades() >= MaxTrades) return false;
   
   // Ensure all open trades are at or above breakeven
   for(int i = OrdersTotal()-1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == Magic) {
            double openP = OrderOpenPrice();
            double curSL = OrderStopLoss();
            bool atBE    = (OrderType() == OP_BUY)  ? curSL >= openP - Point
                         : (OrderType() == OP_SELL) ? curSL <= openP + Point
                         : false;
            if(!atBE) return false;
         }
      }
   }
   return true;
}
```

---

## Risk Validation Checklist (Pre-Trade)

When asked to validate a trade setup, check all of:
- [ ] Lot size ≤ tier maximum (0.05 / 0.10 / 0.12)
- [ ] Risk amount ≤ tier maximum (5% / 10% / 15% of current balance)
- [ ] SL is ATR-based (not arbitrary)
- [ ] TP = 2× SL distance (straight to TP2 — no partial in v2 default)
- [ ] ADX(14) on M15 ≥ 25 (trending regime confirmed) ← NEW
- [ ] H4 21 EMA agrees with H1 50 EMA direction ← NEW
- [ ] RVI |value| ≥ 0.05 (not in chop zone) ← raised threshold
- [ ] Daily DD not exceeded
- [ ] Daily loss count < 3
- [ ] Session filter: London (07–16 UTC) or New York (12–21 UTC)

---

## Quick Calc Output Format

When the user asks for a position size or risk calc, always output a table like:

```
Symbol:        XAUUSD
Balance:       $200 (20,000c)
Risk %:        5%
Risk Amount:   $10 (1,000c)
ATR(14):       2.85
SL Distance:   3.42 (1.2 × ATR)
TP Distance:   6.84 (2× SL)
Lot Size:      0.05
TP1 (1:1):     +3.42
TP2 (1:2):     +6.84
```
