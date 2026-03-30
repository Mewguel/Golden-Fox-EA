# Golden Fox EA

XAUUSD 15m scalp-intraday Expert Advisor for MetaTrader 5.

## Strategy
6 EMA + Parabolic SAR + RVI(10) zone filter + H1 50 EMA + H4 21 EMA + ADX(14) gate.
SL: 1.2× ATR(14) · TP: 1:2 RR · Risk: 5% per trade · Max lot: 0.12

## RVI Entry Rule (v2.1)
- **Buy**: Both RVI lines trending UP and located **below -0.050**
- **Sell**: Both RVI lines trending DOWN and located **above +0.050**
- **No-trade zone**: Both lines inside ±0.050 → skip entry, wait for momentum

## Project Layout
```
EA/              → Golden_Fox.mq5 (deploy to MT5 Experts folder)
skills/          → Claude Code skill files for this strategy
CLAUDE.md        → This file
```

## Skills
| Skill | Purpose |
|---|---|
| `skills/forex-ea-mql` | Code generation & signal logic |
| `skills/forex-backtester` | Backtest setup & result interpretation |
| `skills/forex-quant-analyst` | Performance diagnosis & fixes |
| `skills/forex-risk-manager` | Lot sizing & risk rules |

## Key Parameters to Tune
| Param | Default | Backtest Range |
|---|---|---|
| `RVI_Zone` | 0.050 | 0.030 – 0.080 |
| `ADX_Min` | 25.0 | 20 – 35 |
| `ATR_Multiplier` | 1.2 | 1.0 – 2.0 |
| `RR_Ratio` | 2.0 | 1.5 – 3.0 |

## Version History
- v2.0 — Added ADX gate, H4 21 EMA, raised chop threshold, disabled partial close
- v2.1 — RVI entry requires both lines outside ±0.050 zone, trending in signal direction
