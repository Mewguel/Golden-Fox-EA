---
name: forex-ea-mql
description: Generate, edit, debug, and refactor Forex Expert Advisor (EA) code in MQL4 and/or MQL5 for MetaTrader 4/5. Use this skill any time the user asks to build, fix, improve, or explain EA code — including entry/exit logic, indicator integration, trade management functions, or full EA scaffolding. Also trigger when the user mentions specific indicators (EMA, SAR, RVI, ATR), trade conditions, or wants to translate a trading plan into code. This skill is specialized for the XAUUSD 15m scalp-intraday strategy using 6 EMA, Parabolic SAR, RVI(10), and 1H 50 EMA trend filter.
---

# Forex EA Code Generation Skill (MQL4 / MQL5)

## Strategy Context (Always Keep in Mind)

| Component | Detail |
|---|---|
| Execution TF | M15 |
| Trend Filter TF | H1, H4 |
| Indicators | 6 EMA (M15), Parabolic SAR (0.04/0.20), RVI(10), 50 EMA (H1), 21 EMA (H4), ADX(14) |
| SL | 1.2 × ATR(14) on M15 |
| TP | 2 × SL (1:2 RR) |
| Account | Cent account (~$200 / 20,000 cents) |
| Max Daily DD | 15% or 3 consecutive losses |

---

## MQL4 vs MQL5 — Key Differences

### MQL4
- Use `iMA()`, `iSAR()`, `iRVI()`, `iATR()` inline (returns value directly)
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
2. Separate functions: signal, risk, trade management
3. Defensive: check handle errors, spread, trade context
4. Parameterize everything in `input` — never hardcode tunable values
5. Cent account: lots default 0.01–0.12, never exceed 0.12 without override

---

## Signal Logic

### 🚫 NO TRADE ZONE — Highest Priority Gate

Block ALL entries when BOTH RVI lines are inside `-RVI_Zone` to `+RVI_Zone` (default ±0.050):

```mql5
bool rviInNoTradeZone = (rviM1[0] > -RVI_Zone && rviM1[0] < RVI_Zone) &&
                         (rviS1[0] > -RVI_Zone && rviS1[0] < RVI_Zone);
if(rviInNoTradeZone) return 0;
```

Fires even when SAR flips or price crosses 6 EMA. RVI inside ±0.050 = weak momentum = high false-signal risk.

---

### BUY — All 7 conditions required

1. M15 close[1] > 6 EMA[1]
2. SAR[1] < candle[1] low
3. **Both RVI lines trending UP** — main[1] > main[2] AND signal[1] > signal[2]
4. **Both RVI lines BELOW -0.050** — main[1] < -RVI_Zone AND signal[1] < -RVI_Zone
5. H1 close > H1 50 EMA
6. H4 close > H4 21 EMA
7. ADX(14) M15 ≥ ADX_Min (25)

### SELL — All 7 conditions required

1. M15 close[1] < 6 EMA[1]
2. SAR[1] > candle[1] high
3. **Both RVI lines trending DOWN** — main[1] < main[2] AND signal[1] < signal[2]
4. **Both RVI lines ABOVE +0.050** — main[1] > RVI_Zone AND signal[1] > RVI_Zone
5. H1 close < H1 50 EMA
6. H4 close < H4 21 EMA
7. ADX(14) M15 ≥ ADX_Min (25)

### MQL5 Code Pattern

```mql5
// BUY
bool buyRVI_trend = rviM1[0] > rviM2[0] && rviS1[0] > rviS2[0];
bool buyRVI_zone  = rviM1[0] < -RVI_Zone && rviS1[0] < -RVI_Zone;
if(buyEMA && buySAR && buyRVI_trend && buyRVI_zone && buyH1 && buyH4 && buyADX) return 1;

// SELL
bool sellRVI_trend = rviM1[0] < rviM2[0] && rviS1[0] < rviS2[0];
bool sellRVI_zone  = rviM1[0] > RVI_Zone  && rviS1[0] > RVI_Zone;
if(sellEMA && sellSAR && sellRVI_trend && sellRVI_zone && sellH1 && sellH4 && sellADX) return -1;
```

---

## SL / TP (v2.2)

### Stop Loss — SAR Anchored
SL is set exactly at the **first SAR dot of the new trend** (bar[1] value):
- **Buy** → SL = SAR dot **below** entry (SAR[1] < low)
- **Sell** → SL = SAR dot **above** entry (SAR[1] > high)

Risk (R) = |Entry Price − SL Price|

Sanity check: if `risk ≤ 0` (SAR on wrong side of entry), skip the trade.

### Take Profit — 1:1.5 RR
```
TP (Buy)  = Entry + (R × RR_Ratio)   // default RR_Ratio = 1.5
TP (Sell) = Entry - (R × RR_Ratio)
```

Example (Short):
```
Entry : 1.2000
SL    : 1.2010  (first SAR dot above — 10 pip risk)
R     : 0.0010
TP    : 1.2000 - (0.0010 × 1.5) = 1.1985  (15 pip reward)
```

> ATR_Multiplier is removed in v2.2 — SAR is the sole SL source.

---

## Position Sizing

```
Risk_Amount  = Balance × (RiskPercent / 100)
SL_in_ticks  = SL_dist / SYMBOL_TRADE_TICK_SIZE
Raw_Lot      = Risk_Amount / (SL_in_ticks × SYMBOL_TRADE_TICK_VALUE)
Lot          = clamp(floor(Raw_Lot / lotStep) × lotStep, minLot, MaxLotCap)
```

---

## Trade Management

| Trigger | Action |
|---|---|
| TP2 hit (1:2 RR) | Close full — primary exit |
| SL hit | Close full, +1 dailyLoss |
| RVI cross reversal | Close immediately (invalidation) |
| UsePartialClose=true + profit ≥ 1:1 | Close 60%, move SL to BE, trail SAR |

**RVI Invalidation**:
- BUY open → RVI main crosses below signal → close
- SELL open → RVI main crosses above signal → close

v2 default: `UsePartialClose = false` — go straight to TP2. Re-enable only after walk-forward confirms it improves PF.

---

## Session Filter

```
London: 07:00–16:00 UTC
New York: 12:00–21:00 UTC
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
2. Header block: strategy name, version, platform, date
3. Order: Inputs → Globals → OnInit → OnDeinit → OnTick → Signal → Risk → Management → Helpers
4. End with short **Compile Checklist** (spread, point value, lot step)

---

## Reference Files
- `references/mql4-api-cheatsheet.md`
- `references/mql5-api-cheatsheet.md`
