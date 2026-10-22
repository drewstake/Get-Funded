# Complete six-case development results

Same snapshots, 20-minute adaptation, 60-minute measured candles, three markets per case. All listed runs have exact serialized replay and positive terminal equity. Values are development results, not independent validation.

| Frozen arm | Long-leg occupancy | Max leg (mean min) | Counter events | Strict pullbacks | Minute RV | 30m range | p95 spread (mean ticks) | Recovery | Failed development gates |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Installed baseline | 92.69% | 23.17 | 61 | 0 | 0.2568% | 0.4652% | 4.000 | $5.628m | Reference |
| control | 75.65% | 17.33 | 102 | 12 | 0.2639% | 0.3430% | 4.222 | $2.336m | MeaningfulLong8, RangeRetention, CurrentBXMovement |
| stretch | 86.94% | 22.67 | 74 | 5 | 0.2211% | 0.3290% | 4.778 | $2.120m | MeaningfulLong8, MeaningfulMaxLeg, MeaningfulCounters, OneMinuteRV, RangeRetention, CurrentBXMovement |
| portfolio | 68.52% | 18.44 | 120 | 19 | 0.4121% | 0.4699% | 5.611 | $1.646m | Numeric pass; chart review required |
| mixed | 77.50% | 20.33 | 98 | 17 | 0.3071% | 0.4058% | 5.722 | $1.453m | MeaningfulLong8, MeaningfulMaxLeg |
| mixed-wide | 70.74% | 18.67 | 118 | 18 | 0.3061% | 0.4047% | 6.056 | $0.926m | Spread |
| midquote | 91.94% | 26.17 | 57 | 2 | 0.1966% | 0.2226% | 4.667 | $0.248m | MeaningfulLong8, MeaningfulMaxLeg, MeaningfulCounters, OneMinuteRV, MeanMinuteRangePercent, FifteenSecondMidpointRV, CaseWins, RangeRetention, CurrentBX, CurrentBXMovement |
| midquote-portfolio | 88.98% | 18.22 | 83 | 4 | 0.3278% | 0.3754% | 6.222 | $0.595m | MeaningfulLong8, CaseWins, Spread, CurrentBXMovement |
| midquote-mixed | 86.48% | 22.89 | 77 | 5 | 0.2497% | 0.3109% | 6.056 | $1.127m | MeaningfulLong8, MeaningfulMaxLeg, MeaningfulCounters, Spread, RangeRetention, CurrentBXMovement |
| mid-reserve-withdraw | 83.06% | 22.56 | 82 | 5 | 0.2827% | 0.3644% | 5.944 | $0.761m | MeaningfulLong8, MeaningfulMaxLeg, RangeRetention, CurrentBXMovement |
| mid-reserve-diverse | 75.28% | 20.61 | 118 | 23 | 0.3143% | 0.3993% | 6.833 | $1.627m | MeaningfulLong8, MeaningfulMaxLeg, Spread, CurrentBX |
| last-reserve-diverse | 61.94% | 17.50 | 148 | 33 | 0.3433% | 0.4156% | 6.389 | $0.745m | Spread |
| portfolio-dense | 72.69% | 17.28 | 113 | 16 | 0.3889% | 0.4448% | 4.556 | $2.191m | Numeric pass; chart review required |
| mixed-wide-dense | 76.11% | 18.22 | 111 | 20 | 0.2636% | 0.3333% | 4.500 | $1.853m | MeaningfulLong8, RangeRetention, CurrentBXMovement |
| last-reserve-dense | 78.24% | 20.50 | 109 | 27 | 0.3179% | 0.4100% | 4.611 | $1.719m | MeaningfulLong8, MeaningfulMaxLeg, CurrentBXMovement |
| last-reserve-balanced | 69.54% | 20.33 | 134 | 29 | 0.3196% | 0.3900% | 5.444 | $1.570m | MeaningfulMaxLeg, CurrentBXMovement |
| last-reserve-tight | 64.54% | 18.56 | 141 | 34 | 0.3666% | 0.4486% | 6.222 | $0.585m | Spread, CurrentBX, CurrentBXMovement |
| last-reserve-withdraw | 72.31% | 17.72 | 117 | 22 | 0.4086% | 0.4498% | 6.278 | $1.607m | Spread |
| last-reserve-faders | 71.20% | 20.56 | 126 | 25 | 0.2968% | 0.3856% | 5.667 | $0.919m | MeaningfulMaxLeg |
| last-reserve-contiguous | 72.22% | 18.22 | 134 | 27 | 0.3405% | 0.3628% | 4.833 | $1.193m | RangeRetention, CurrentBX, CurrentBXMovement |
| last-reserve-inner | 72.22% | 18.33 | 126 | 29 | 0.3650% | 0.4413% | 5.500 | $0.706m | CurrentBXMovement |
| inner-multihorizon | 71.11% | 18.94 | 122 | 21 | 0.3180% | 0.3910% | 5.556 | $3.357m | CurrentBX |
| inner-patient-stretch | 64.26% | 18.83 | 149 | 38 | 0.3763% | 0.4224% | 5.444 | $0.995m | Numeric pass; chart review required |
| diverse-patient-stretch | 66.30% | 17.28 | 146 | 32 | 0.4010% | 0.4457% | 6.111 | $1.096m | Spread |
| rolling-portfolio-robust | 74.35% | 17.44 | 123 | 27 | 0.7918% | 0.8237% | 6.944 | $12.319m | MeaningfulLong8, Recovery, Quotes, Spread |
| rolling-patient-robust | 75.00% | 19.56 | 116 | 33 | 1.3284% | 1.2010% | 7.111 | $31.472m | MeaningfulLong8, Recovery, Quotes, Spread |
| inner-patient-quote-safe | 59.17% | 16.78 | 155 | 47 | 0.3531% | 0.4130% | 5.556 | $1.680m | Numeric pass; chart review required |
| rolling-portfolio-depth | 72.78% | 19.56 | 110 | 14 | 1.0615% | 0.9314% | 5.333 | $8.204m | Recovery, Quotes |
| rolling-patient-depth | 68.43% | 17.56 | 125 | 26 | 0.9771% | 0.9000% | 5.111 | $8.335m | Recovery, Quotes, CurrentBX |
| rolling-cost-aware | 76.11% | 18.22 | 118 | 23 | 0.6837% | 0.6803% | 4.556 | $3.239m | MeaningfulLong8, Quotes |
| rolling-touch-participation | 79.54% | 19.39 | 106 | 11 | 0.5271% | 0.5431% | 4.500 | $2.959m | MeaningfulLong8, CurrentBXMovement |

Every arm has an immutable source manifest and patch in `variants/<name>/`, paired raw data in `development-<name>/`, and exact metrics in `development-<name>-metrics.json`. Candle figures are named `development-<name>-BX.png`, `-BT.png`, and `-BG.png`.

## Current saved BX world and liquidity

Current-BX columns refer only to BX in that saved case; missing-quote and volume columns average all eighteen measured market-hours. Volume counts matched contracts once. Chart links contain all six paired cases at comparable vertical scales.

| Arm | Current BX long-leg occupancy | Max leg | Counter events | Strict pullbacks | Minute RV | Missing quotes (mean) | Matched volume (mean) | Charts |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| control | 81.67% | 22m | 4 | 0 | 0.3938% | 0.0093% | 15,807.6 | [BX](development-control-BX.png) / [BT](development-control-BT.png) / [BG](development-control-BG.png) |
| stretch | 91.67% | 24m | 3 | 0 | 0.3763% | 0.0015% | 15,616.4 | [BX](development-stretch-BX.png) / [BT](development-stretch-BT.png) / [BG](development-stretch-BG.png) |
| portfolio | 73.33% | 20m | 5 | 0 | 0.6206% | 0.0015% | 22,791.6 | [BX](development-portfolio-BX.png) / [BT](development-portfolio-BT.png) / [BG](development-portfolio-BG.png) |
| mixed | 80.00% | 17m | 7 | 1 | 0.4734% | 0.0062% | 24,096.5 | [BX](development-mixed-BX.png) / [BT](development-mixed-BT.png) / [BG](development-mixed-BG.png) |
| mixed-wide | 93.33% | 20m | 4 | 1 | 0.4792% | 0.0077% | 24,511.8 | [BX](development-mixed-wide-BX.png) / [BT](development-mixed-wide-BT.png) / [BG](development-mixed-wide-BG.png) |
| midquote | 100.00% | 21m | 3 | 0 | 0.1401% | 0.0062% | 11,415.0 | [BX](development-midquote-BX.png) / [BT](development-midquote-BT.png) / [BG](development-midquote-BG.png) |
| midquote-portfolio | 90.00% | 15m | 5 | 0 | 0.4124% | 0.0139% | 20,739.3 | [BX](development-midquote-portfolio-BX.png) / [BT](development-midquote-portfolio-BT.png) / [BG](development-midquote-portfolio-BG.png) |
| midquote-mixed | 88.33% | 14m | 5 | 0 | 0.4095% | 0.0031% | 21,424.4 | [BX](development-midquote-mixed-BX.png) / [BT](development-midquote-mixed-BT.png) / [BG](development-midquote-mixed-BG.png) |
| mid-reserve-withdraw | 90.00% | 35m | 3 | 0 | 0.4046% | 0.0170% | 21,292.8 | [BX](development-mid-reserve-withdraw-BX.png) / [BT](development-mid-reserve-withdraw-BT.png) / [BG](development-mid-reserve-withdraw-BG.png) |
| mid-reserve-diverse | 100.00% | 20m | 3 | 0 | 0.4670% | 0.0340% | 26,193.4 | [BX](development-mid-reserve-diverse-BX.png) / [BT](development-mid-reserve-diverse-BT.png) / [BG](development-mid-reserve-diverse-BG.png) |
| last-reserve-diverse | 85.00% | 26m | 4 | 2 | 0.5615% | 0.0231% | 28,444.7 | [BX](development-last-reserve-diverse-BX.png) / [BT](development-last-reserve-diverse-BT.png) / [BG](development-last-reserve-diverse-BG.png) |
| portfolio-dense | 85.00% | 17m | 6 | 0 | 0.5544% | 0.0015% | 22,802.3 | [BX](development-portfolio-dense-BX.png) / [BT](development-portfolio-dense-BT.png) / [BG](development-portfolio-dense-BG.png) |
| mixed-wide-dense | 66.67% | 19m | 6 | 0 | 0.4087% | 0.0046% | 23,996.5 | [BX](development-mixed-wide-dense-BX.png) / [BT](development-mixed-wide-dense-BT.png) / [BG](development-mixed-wide-dense-BG.png) |
| last-reserve-dense | 60.00% | 10m | 11 | 2 | 0.3790% | 0.0278% | 28,588.8 | [BX](development-last-reserve-dense-BX.png) / [BT](development-last-reserve-dense-BT.png) / [BG](development-last-reserve-dense-BG.png) |
| last-reserve-balanced | 78.33% | 27m | 6 | 1 | 0.3725% | 0.0355% | 28,327.0 | [BX](development-last-reserve-balanced-BX.png) / [BT](development-last-reserve-balanced-BT.png) / [BG](development-last-reserve-balanced-BG.png) |
| last-reserve-tight | 100.00% | 23m | 3 | 0 | 0.4138% | 0.0509% | 28,348.6 | [BX](development-last-reserve-tight-BX.png) / [BT](development-last-reserve-tight-BT.png) / [BG](development-last-reserve-tight-BG.png) |
| last-reserve-withdraw | 70.00% | 18m | 6 | 0 | 0.4877% | 0.0278% | 24,532.4 | [BX](development-last-reserve-withdraw-BX.png) / [BT](development-last-reserve-withdraw-BT.png) / [BG](development-last-reserve-withdraw-BG.png) |
| last-reserve-faders | 91.67% | 19m | 8 | 1 | 0.4378% | 0.0340% | 25,539.5 | [BX](development-last-reserve-faders-BX.png) / [BT](development-last-reserve-faders-BT.png) / [BG](development-last-reserve-faders-BG.png) |
| last-reserve-contiguous | 100.00% | 17m | 4 | 1 | 0.3729% | 0.0278% | 26,984.2 | [BX](development-last-reserve-contiguous-BX.png) / [BT](development-last-reserve-contiguous-BT.png) / [BG](development-last-reserve-contiguous-BG.png) |
| last-reserve-inner | 88.33% | 22m | 3 | 1 | 0.3567% | 0.0262% | 28,120.2 | [BX](development-last-reserve-inner-BX.png) / [BT](development-last-reserve-inner-BT.png) / [BG](development-last-reserve-inner-BG.png) |
| inner-multihorizon | 100.00% | 41m | 2 | 1 | 0.4955% | 0.0355% | 27,656.6 | [BX](development-inner-multihorizon-BX.png) / [BT](development-inner-multihorizon-BT.png) / [BG](development-inner-multihorizon-BG.png) |
| inner-patient-stretch | 48.33% | 21m | 10 | 1 | 0.5071% | 0.0201% | 27,370.1 | [BX](development-inner-patient-stretch-BX.png) / [BT](development-inner-patient-stretch-BT.png) / [BG](development-inner-patient-stretch-BG.png) |
| diverse-patient-stretch | 98.33% | 26m | 4 | 0 | 0.5563% | 0.0417% | 27,264.1 | [BX](development-diverse-patient-stretch-BX.png) / [BT](development-diverse-patient-stretch-BT.png) / [BG](development-diverse-patient-stretch-BG.png) |
| rolling-portfolio-robust | 91.67% | 14m | 6 | 2 | 0.7420% | 0.1096% | 39,383.8 | [BX](development-rolling-portfolio-robust-BX.png) / [BT](development-rolling-portfolio-robust-BT.png) / [BG](development-rolling-portfolio-robust-BG.png) |
| rolling-patient-robust | 60.00% | 15m | 9 | 2 | 0.8815% | 0.1698% | 39,399.4 | [BX](development-rolling-patient-robust-BX.png) / [BT](development-rolling-patient-robust-BT.png) / [BG](development-rolling-patient-robust-BG.png) |
| inner-patient-quote-safe | 78.33% | 24m | 4 | 0 | 0.4703% | 0.0201% | 27,708.7 | [BX](development-inner-patient-quote-safe-BX.png) / [BT](development-inner-patient-quote-safe-BT.png) / [BG](development-inner-patient-quote-safe-BG.png) |
| rolling-portfolio-depth | 65.00% | 15m | 6 | 0 | 0.4795% | 0.1111% | 39,599.8 | [BX](development-rolling-portfolio-depth-BX.png) / [BT](development-rolling-portfolio-depth-BT.png) / [BG](development-rolling-portfolio-depth-BG.png) |
| rolling-patient-depth | 100.00% | 16m | 4 | 0 | 0.6440% | 0.1343% | 38,913.2 | [BX](development-rolling-patient-depth-BX.png) / [BT](development-rolling-patient-depth-BT.png) / [BG](development-rolling-patient-depth-BG.png) |
| rolling-cost-aware | 86.67% | 26m | 7 | 3 | 0.5242% | 0.1034% | 36,425.4 | [BX](development-rolling-cost-aware-BX.png) / [BT](development-rolling-cost-aware-BT.png) / [BG](development-rolling-cost-aware-BG.png) |
| rolling-touch-participation | 98.33% | 17m | 5 | 0 | 0.2574% | 0.0787% | 31,385.7 | [BX](development-rolling-touch-participation-BX.png) / [BT](development-rolling-touch-participation-BT.png) / [BG](development-rolling-touch-participation-BG.png) |

## Numerical passes rejected on chart review

- **portfolio:** Current BX still has quiet platforms and largely uninterrupted separate waves, with no strict completed pullback. Aggregate counter counts do not demonstrate the requested within-trend chart behavior. [Candles](development-portfolio-BX.png).
- **portfolio-dense:** Restoring depth improves spreads but leaves quiet intervals and current BX smooth waves without a strict completed pullback. [Candles](development-portfolio-dense-BX.png).
- **inner-patient-stretch:** Current BX has a prolonged quiet middle and late jump. One minute contributes 49.03% of close-return variance and five contribute 80.72%; 62.71% of intervals are below the original six-tick/0.025% floor. This is not sustained useful movement. [Candles](development-inner-patient-stretch-BX.png).
- **inner-patient-quote-safe:** Current BX retains a 24-minute meaningful leg, a prolonged downward sequence with shallow interruptions and no strict completed pullback. Nearly half its minute intervals are below the movement floor. Other worlds improve, but this required world does not convincingly meet the chart objective. [Candles](development-inner-patient-quote-safe-BX.png).

## Compatibility derivatives and aborted implementations

The two compatibility derivatives are not additional economic hypotheses: `last-reserve-diverse-ready` and `inner-patient-stretch-ready` reproduce their parents across all six measured paths and accounting results. Their broader regression results are in RESULTS.md; the second retains one new geometry-test failure in its immutable source.

- **rolling-portfolio:** incomplete and rejected; [reason](variants/rolling-portfolio/rejection.json). Partial files and source manifests are retained and excluded from full-batch averages.
- **rolling-patient:** incomplete and rejected; [reason](variants/rolling-patient/rejection.json). Partial files and source manifests are retained and excluded from full-batch averages.
- **rolling-portfolio-safe:** incomplete and rejected; [reason](variants/rolling-portfolio-safe/rejection.json). Partial files and source manifests are retained and excluded from full-batch averages.
- **rolling-patient-safe:** incomplete and rejected; [reason](variants/rolling-patient-safe/rejection.json). Partial files and source manifests are retained and excluded from full-batch averages.
