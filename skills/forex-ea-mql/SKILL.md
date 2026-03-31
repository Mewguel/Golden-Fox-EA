---
name: forex-ea-mql
description: Generate, edit, debug, and refactor Forex Expert Advisor (EA) code in MQL4 and/or MQL5 for MetaTrader 4/5. Use this skill any time the user asks to build, fix, improve, or explain EA code — including entry/exit logic, indicator integration, trade management functions, or full EA scaffolding. Also trigger when the user mentions specific indicators (EMA, SAR, RVI, ATR), trade conditions, or wants to translate a trading plan into code. This skill is specialized for the XAUUSD 15m scalp-intraday strategy using 6 EMA, Parabolic SAR, RVI(10), H1/H4 EMA, ADX, and economic calendar news filter.
---

# Forex EA Code Generation Skill (MQL4 / MQL5)

## Strategy Context — Current Version: 2.5

| Component | Detail |
|---|---|
| Execution TF | M15 |
| Trend Filter TF | H1 (50 EMA), H4 (21 EMA) |
| Indicators | 6 EMA (M15), Parabolic SAR (0.04/0.20), RVI(10), ADX(14) |
| Entry | RVI fresh cross outside ±RVI_Zone (0.050) |
| SL | First SAR dot of new trend (SAR-anchored) |
| TP | Fixed pips (`TP_Pips = 100`) |
| Lot | Static `LotSize = 0.01`, capped at `MaxLotCap = 0.12` |
| Breakeven | Move SL to entry when floating profit ≥ `$2.00` |
| News Filter | MQL5 Calendar — block 60 min before / 45 min after high-impact USD events |
| Max Daily DD | 15% or 3 consecutive losses |

---

## MQL4 vs MQL5 — Key Differences

### MQL4
- `iMA()`, `iSAR()`, `iRVI()`, `iATR()` return values directly
- `OrderSend()` / `OrderModify()` for execution
- `AccountBalance()`, `AccountEquity()`

### MQL5
- `CopyBuffer()` with handles — `iMA()` returns a handle, not a value
- `CTrade` class: `trade.Buy()`, `trade.Sell()`, `trade.PositionModify()`
- `PositionSelect()`, `PositionGetDouble()`, `PositionGetInteger()`
- Initialize handles in `OnInit()`, release in `OnDeinit()`

---

## Code Generation Principles

1. Lean code — no redundant comments, no unused variables
2. Separate functions: signal, risk, trade management, helpers
3. Defensive: check handle errors, spread, trade context
4. Parameterize everything in `input` — never hardcode tunable values
5. Static lots by default — dynamic sizing only if explicitly requested

---

## Signal Logic (v2.4+)

### Entry — RVI Fresh Cross

The EA fires **only on the bar the RVI cross occurs**, in oversold/overbought territory. This avoids late entries from trend-continuation logic.

#### BUY — all conditions required
1. **RVI fresh cross UP** — `rviM2 < rviS2` (prev bar below) AND `rviM1 > rviS1` (curr bar crossed above)
2. **Cross in oversold zone** — `rviM1 < -RVI_Zone` (default -0.050)
3. M15 close[1] > 6 EMA[1]
4. SAR[1] < candle[1] low
5. H1 close > H1 50 EMA
6. H4 close > H4 21 EMA
7. ADX(14) M15 ≥ ADX_Min (25)

#### SELL — all conditions required
1. **RVI fresh cross DOWN** — `rviM2 > rviS2` (prev bar above) AND `rviM1 < rviS1` (curr bar crossed below)
2. **Cross in overbought zone** — `rviM1 > +RVI_Zone` (default +0.050)
3. M15 close[1] < 6 EMA[1]
4. SAR[1] > candle[1] high
5. H1 close < H1 50 EMA
6. H4 close < H4 21 EMA
7. ADX(14) M15 ≥ ADX_Min (25)

#### MQL5 Code Pattern
```mql5
// BUY
bool buyRVI_cross = rviM2[0] < rviS2[0] &&   // prev: below signal
                   rviM1[0] > rviS1[0] &&   // curr: crossed above
                   rviM1[0] < -RVI_Zone;    // in oversold territory
if(buyRVI_cross && buyEMA && buySAR && buyH1 && buyH4) return 1;

// SELL
bool sellRVI_cross = rviM2[0] > rviS2[0] &&  // prev: above signal
                    rviM1[0] < rviS1[0] &&  // curr: crossed below
                    rviM1[0] > RVI_Zone;    // in overbought territory
if(sellRVI_cross && sellEMA && sellSAR && sellH1 && sellH4) return -1;
```

> The separate chop-zone gate is **implicit** — a cross below -RVI_Zone or above +RVI_Zone is by definition outside the no-trade zone.

---

## SL / TP (v2.2+)

### Stop Loss — SAR Anchored
SL placed at the **first SAR dot of the new trend** (bar[1] value):
- **Buy** → SL = SAR dot below entry (`SAR[1] < low[1]`)
- **Sell** → SL = SAR dot above entry (`SAR[1] > high[1]`)

Sanity check: if `risk <= 0` (SAR on wrong side), skip the trade.

### Take Profit — Fixed Pips
```mql5
// TP_Pips = 100 (default)
double tp = NormalizeDouble(ask + PipsToPrice(TP_Pips), _Digits);  // BUY
double tp = NormalizeDouble(bid - PipsToPrice(TP_Pips), _Digits);  // SELL

double PipsToPrice(double pips) {
   double pipSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(_Digits == 3 || _Digits == 5) pipSize *= 10;  // XAUUSD: 0.01 = 1 pip
   return pips * pipSize;
}
```

---

## Position Sizing (v2.3+)

Static lot size — simple and predictable:
```
LotSize   = 0.01   (input, default)
MaxLotCap = 0.12   (hard ceiling)
Lot       = clamp(floor(LotSize / lotStep) x lotStep, minLot, MaxLotCap)
```

Dynamic risk-% sizing (`CalcLotSize`) was removed in v2.3.

---

## Trade Management

| Trigger | Action |
|---|---|
| TP hit | Close full — primary exit |
| SL hit | Close full, +1 dailyLoss |
| RVI cross reversal | Close immediately (invalidation) |
| Float profit >= `BreakevenTrigger` ($2.00) | Move SL to entry + spread, once per trade |

### Breakeven Logic (v2.3+)
```mql5
if(!breakevenMoved && PositionGetDouble(POSITION_PROFIT) >= BreakevenTrigger)
{
   double be = (posType == POSITION_TYPE_BUY)
               ? NormalizeDouble(openPrice + spread, _Digits)
               : NormalizeDouble(openPrice - spread, _Digits);
   bool shouldMove = (posType == POSITION_TYPE_BUY  && be > curSL) ||
                     (posType == POSITION_TYPE_SELL && be < curSL);
   if(shouldMove && trade.PositionModify(_Symbol, be, curTP))
      breakevenMoved = true;
}
```

### RVI Invalidation
- BUY open → RVI main crosses **below** signal → close immediately
- SELL open → RVI main crosses **above** signal → close immediately

---

## News Filter (v2.5+)

Blocks **new entries only** (open positions run to TP/SL) around high-impact USD events.

```
UseNewsFilter    = true   // toggle
PauseBeforeNews  = 60     // minutes before event
ResumeAfterNews  = 45     // minutes after event
```

### Implementation
```mql5
bool IsNewsBlocked()
{
   datetime now  = TimeCurrent();
   datetime from = now - (datetime)(PauseBeforeNews * 60);
   datetime to   = now + (datetime)(PauseBeforeNews * 60);

   MqlCalendarValue values[];
   if(CalendarValueHistory(values, from, to, NULL, "USD") <= 0)
      return false;

   for(int i = 0; i < ArraySize(values); i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)  continue;
      if(!IsRelevantEvent(ev.name))                  continue;

      datetime newsTime = values[i].time;
      bool blocked = (now >= newsTime - (datetime)(PauseBeforeNews * 60) &&
                      now <= newsTime + (datetime)(ResumeAfterNews * 60));
      if(blocked) return true;
   }
   return false;
}
```

**CRITICAL:** `MqlCalendarEvent` has **no `currency` field** — currency is filtered upstream via `CalendarValueHistory(..., "USD")`. Never check `ev.currency` — it will not compile.

### Event Keywords (Tier 1 + Tier 2)
```mql5
string keywords[] = {
   "FOMC", "Federal Funds", "Jackson Hole",
   "CPI", "Core CPI", "Consumer Price",
   "Non-Farm", "NFP", "Nonfarm",
   "PCE", "Personal Consumption",
   "GDP", "Gross Domestic",
   "Retail Sales",
   "ISM Manufacturing", "ISM Services", "ISM Non-Manufacturing",
   "Unemployment Claims", "Initial Claims"
};
```

### OnTick Integration
```mql5
void OnTick()
{
   if(UseNewsFilter && IsNewsBlocked()) return;  // BEFORE IsNewBar()
   if(!IsNewBar()) return;
   // ... rest of logic
}
```

---

## Session Filter

```
London:   07:00-16:00 UTC
New York: 12:00-21:00 UTC
```

---

## Daily Guard

```mql5
double ddPct = (dayStartBalance - AccountInfoDouble(ACCOUNT_EQUITY)) / dayStartBalance * 100;
if(ddPct >= MaxDailyDDPct || dailyLosses >= MaxDailyLosses) return; // halt
```

---

## Output Format

1. Single compilable `.mq5` file
2. Header: strategy name, version, platform, changes
3. Section order: Inputs -> Globals -> OnInit -> OnDeinit -> OnTick -> Signal -> Execution -> Management -> Helpers -> News Filter
4. End with short **Compile Checklist** (spread, point, lot step, calendar data enabled in terminal)

---

## Version History

| Version | Key Change |
|---|---|
| v2.0 | ADX gate, H4 21 EMA, raised chop threshold, disabled partial close |
| v2.1 | RVI entry: both lines outside +/-0.050 zone, trending in direction |
| v2.2 | SL anchored to SAR dot; TP = SAR-risk x 1.5 RR |
| v2.3 | Static lot size (LotSize = 0.01); breakeven trigger ($2.00) |
| v2.4 | RVI fresh cross detection — fires once on cross bar, not continuation |
| v2.5 | XAUUSD news filter — MQL5 Calendar, 60 min pre / 45 min post USD events |

---

## Reference Files
- `references/mql4-api-cheatsheet.md`
- `references/mql5-api-cheatsheet.md`
