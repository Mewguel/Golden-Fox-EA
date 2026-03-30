---
name: forex-backtester
description: Guide, generate, and analyze backtesting and optimization workflows for MetaTrader 4/5 Expert Advisors. Use this skill whenever the user wants to set up a backtest, interpret MT4/MT5 Strategy Tester results, choose optimization parameters, avoid overfitting, select date ranges, compare results, or understand performance metrics (profit factor, drawdown, win rate, RR, etc.). Also trigger when the user asks how to forward-test, walk-forward analyze, or validate an EA before live trading. This skill is tuned for the XAUUSD 15m scalp-intraday strategy with ATR-based SL/TP and 6 EMA/SAR/RVI signals.
---

# Forex EA Backtesting & Optimization Skill

## Strategy Tester Settings (MT4 / MT5)

### Recommended Backtest Configuration

| Setting | MT4 | MT5 |
|---|---|---|
| Symbol | XAUUSD | XAUUSD |
| Timeframe | M15 | M15 |
| Model | Every Tick | Every Tick |
| Date range | Min 2 years (more = better) | Min 2 years |
| Spread | Fixed: 20–30 pts (ask broker) | Fixed or variable |
| Initial deposit | 200 (if cent, use $20,000) | Same |
| Optimization | Genetic algorithm | Same |

> **MT4 Cent Account Note**: In MT4 Strategy Tester, set deposit to 20,000 (the cent value) and interpret all dollar figures as cents.

---

## Key Performance Metrics

### Must-Pass Thresholds (Minimum for Live Consideration)

| Metric | Minimum | Target |
|---|---|---|
| Profit Factor | ≥ 1.5 | ≥ 2.0 |
| Win Rate | ≥ 40% | ≥ 50% |
| Max Drawdown | ≤ 20% | ≤ 15% |
| RR Ratio (avg) | ≥ 1.5 | ≥ 2.0 |
| Total Trades | ≥ 100 | ≥ 200 |
| Recovery Factor | ≥ 2.0 | ≥ 3.0 |
| Sharpe Ratio | ≥ 1.0 | ≥ 1.5 |

### Metric Definitions
- **Profit Factor** = Gross Profit / Gross Loss (>1 = net profitable)
- **Recovery Factor** = Net Profit / Max Drawdown
- **Expected Payoff** = Average profit per trade (should be positive)
- **Max DD %** = Largest peak-to-trough equity drop

---

## Parameters to Optimize (and Ranges)

### High Priority (most impact)
| Parameter | Range | Step | Notes |
|---|---|---|---|
| ATR_Multiplier | 1.0 – 2.0 | 0.1 | Controls SL size |
| RR_Ratio | 1.5 – 3.0 | 0.25 | TP multiplier |
| **ADX_Min** | **20 – 35** | **5** | **NEW — regime gate threshold** |
| RiskPercent | 3 – 10 | 1 | Per-trade risk |

### Medium Priority
| Parameter | Range | Step | Notes |
|---|---|---|---|
| SAR_Step | 0.02 – 0.06 | 0.01 | SAR sensitivity |
| SAR_Max | 0.15 – 0.25 | 0.05 | SAR max step |
| RVI_Period | 8 – 14 | 1 | Momentum lookback |
| **ChopThreshold** | **0.03 – 0.08** | **0.01** | **NEW — raised from 0.02** |
| **H4_EMA_Period** | **18 – 26** | **2** | **NEW — H4 trend filter period** |

### Low Priority (rarely change)
| Parameter | Notes |
|---|---|
| H1_EMA_Period | Keep at 50 — standard trend filter |
| ATR_Period | Keep at 14 — standard volatility |
| MaxDailyLosses | Keep at 3 — discipline rule, not performance |
| UsePartialClose | Keep false until entry edge is confirmed |

### v2 Baseline Expectations
After adding ADX + H4 + raised chop threshold:
- Trade count should drop from ~1,930 to ~800–1,100 over same period
- If trade count stays above 1,500 → ADX_Min threshold too low, raise it
- Target PF ≥ 1.3 before re-enabling partial close logic

---

## Overfitting Prevention

**The #1 risk in EA optimization.** Follow these rules:

1. **Out-of-sample test**: Optimize on 70% of data, validate on remaining 30%
   - Train: Jan 2021 – Jun 2023
   - Test: Jul 2023 – Dec 2024

2. **Walk-forward analysis**: Roll the window forward in chunks
   ```
   Window 1: Train Jan–Dec 2021 → Test Jan–Mar 2022
   Window 2: Train Apr 2021–Mar 2022 → Test Apr–Jun 2022
   ... and so on
   ```

3. **Parameter stability check**: A robust EA should profit across a range of parameter values — not just one specific combination
   - If Profit Factor collapses from 2.1 to 0.8 when ATR_Multiplier moves 0.1, the system is fragile

4. **Minimum trades**: Never trust a backtest with < 100 trades — not statistically significant

5. **Avoid exotic date ranges**: Always include volatile periods (COVID 2020, Fed rate hikes 2022, etc.)

---

## Interpreting MT4 Strategy Tester Report

### Reading the HTML Report
```
Total Net Profit      → Absolute PnL (cent account: divide by 100 for USD)
Profit Factor         → Key metric — target ≥ 1.5
Expected Payoff       → Avg profit/trade — should be > 0
Max Drawdown          → Worst equity drop — target < 15%
Total Trades          → Volume of sample — need ≥ 100
Short Trades Won %    → Compare vs Long Trades Won % for directional bias
```

### Common Red Flags
| Symptom | Likely Cause |
|---|---|
| Profit Factor 3.0+ but < 50 trades | Overfit, insufficient sample |
| Win rate 80%+ with low profit factor | Large losses wiping small wins (bad RR) |
| Max DD > 50% | Lot sizing or no SL |
| Equity curve spikes then crashes | Martingale or grid hidden in logic |
| Zero trades on test period | Date/session filter too restrictive |
| **Avg loss > avg win with ~50% WR** | **Exit logic destroying RR — disable partial close, go straight to TP** |
| **Z-score < -5 (loss clustering)** | **Regime dependency — add ADX gate + HTF filter** |
| **Trade count > 4/day on 5-condition system** | **Chop threshold too low — raise RVI ChopThreshold** |

### v1 Lessons Applied to v2
- v1 result: PF=0.86, avg win $52 < avg loss $58, Z=-9.11, 1,930 trades in 15 months
- Root cause: partial close trail gave back profits; 1H filter missed H4-level counter-trends; ChopThreshold=0.02 too loose
- v2 fixes: ADX≥25 gate, H4 21 EMA filter, ChopThreshold=0.05, straight TP2 exit

---

## Forward Testing Protocol

After a successful backtest:

1. **Demo first**: Run on demo account for minimum 4–6 weeks
2. **Match conditions**: Same broker, same spread, same symbol settings
3. **Compare metrics**: Track forward PF, DD, win rate vs backtest
4. **Acceptance criteria**: Forward PF should be ≥ 70% of backtest PF
5. **Go live threshold**: Only after 30+ demo trades with acceptable metrics

---

## Backtest Result Interpretation Template

When the user pastes or describes backtest results, analyze and output:

```
📊 BACKTEST ANALYSIS — XAUUSD EA

Period:         [date range]
Total Trades:   [n] ([long] L / [short] S)
Win Rate:       [x]% (min 40% ✅/❌)
Profit Factor:  [x] (min 1.5 ✅/❌)
Max Drawdown:   [x]% (max 20% ✅/❌)
Avg RR:         [x] (min 1.5 ✅/❌)
Net Profit:     [x]

VERDICT: [PASS / MARGINAL / FAIL]

STRENGTHS:
- [list]

WEAKNESSES / RED FLAGS:
- [list]

RECOMMENDATIONS:
- [parameter adjustments or test modifications]
```

---

## MT5 Strategy Tester — Key Differences from MT4

- Uses **real tick data** with variable spread if available — more accurate
- **Optimization report** shows 3D surface map — use to find stable parameter region, not just the peak
- **Custom optimization criteria** — can optimize for custom formula (e.g., PF × RecoveryFactor)
- **Forward testing mode** built-in: set "Forward" % in Tester settings
- Results report exports to `.xml` — can be analyzed in Excel

---

## Session-Specific Backtest Tips

For the London + NY session filter:
- Expect fewer total trades (roughly 40–60% of 24h volume)
- Higher average pip move per trade
- Compare 24h backtest vs session-filtered — PF should improve with filter
- If PF drops with filter: reconsider whether session logic is correct

---

## Reference Files
- See `forex-ea-mql` skill for code implementation of EA inputs to be optimized
- See `forex-risk-manager` skill for position sizing validation during forward test review
