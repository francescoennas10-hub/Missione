# Adaptive Regime EA (MQL4 / MetaTrader 4)

Expert Advisor per MetaTrader 4 costruito attorno a due principi: **adattamento al regime di
mercato** e **controllo rigido del rischio**. Nessuna logica rigida o sovra-ottimizzata: l'EA
classifica prima il contesto, poi sceglie la strategia coerente con esso.

File sorgente: `MQL4/Experts/AdaptiveRegimeEA.mq4`

## Installazione

1. In MetaTrader 4: `File -> Apri cartella dati` -> `MQL4/Experts/`.
2. Copiare `AdaptiveRegimeEA.mq4` nella cartella.
3. In MetaEditor premere `F7` per compilare (0 errori, 0 warning attesi).
4. Trascinare l'EA sul grafico, abilitare l'AutoTrading e verificare i parametri.

## Architettura

### 1. Regime Filter (`DetectMarketRegime`)
Combina tre misure indipendenti calcolate sulla barra chiusa (shift 1):

| Misura | Ruolo |
|---|---|
| `ADX(ADX_Period)` | forza direzionale |
| `ATR(ATR_Period)` vs media ATR su `ATR_AvgPeriod` | espansione / compressione di volatilita' |
| Distanza del prezzo dalla MA lunga (`MA_Long_Period`), misurata in ATR | posizione strutturale |

- **REGIME_TREND**: `ADX >= ADX_Threshold`, ATR ratio `>= ATR_TrendFactor`, prezzo staccato dalla MA lunga (>= 0.5 ATR).
- **REGIME_RANGE**: `ADX <= ADX_RangeThreshold`, ATR ratio `<= ATR_RangeFactor`, prezzo entro `RangeMaxDistanceATR` dalla MA lunga.
- **REGIME_NONE**: zona grigia -> nessuna operazione.

### 2. Strategie
- **Trend following**: incrocio MA veloce/lenta sulla barra chiusa, confermato dal bias della MA
  lunga e dalla dominanza `+DI`/`-DI` (disattivabile con `UseDIConfirmation`).
- **Mean reversion**: estensione oltre la banda di Bollinger con RSI in ipercomprato/ipervenduto
  e chiusura che rientra nel canale (conferma del rifiuto, non semplice tocco).

### 3. Rischio
- SL e TP **sempre** presenti all'apertura: `SL = ATR * ATR_Multiplier_SL`, `TP = ATR * ATR_Multiplier_TP`.
- Distanze allargate automaticamente al `MODE_STOPLEVEL`/`MODE_FREEZELEVEL` del broker piu' lo spread.
- `CalculateLotSize()` dimensiona il volume su `RiskPercent` del capitale usando la distanza reale
  dello SL: `lotti = rischio / ((distanzaSL / TICKSIZE) * TICKVALUE)`, quindi normalizza su
  `MODE_LOTSTEP`, `MODE_MINLOT`, `MODE_MAXLOT`, verifica il margine libero e il tetto `MaxLotCap`.
  Se il lotto minimo del broker eccede il budget di rischio, l'operazione viene annullata.
- Modalita' `TwoStepStops` per broker ECN: apertura e impostazione stop in due passaggi; se gli stop
  non risultano impostabili la posizione viene **chiusa immediatamente** (mai un ordine "nudo").

### 4. Gestione della posizione
- **Break-Even** (`EnableBreakEven`): a `BreakEvenPips` di profitto lo SL passa all'entrata + `BreakEvenLockPips`.
- **Trailing Stop** (`EnableTrailingStop`): parte a `TrailingStartPips`, insegue a `TrailingStopPips`
  con passo minimo `TrailingStepPips`. Lo stop non arretra mai.
- **Esposizione**: massimo `MaxOpenPositions` (default 1) posizioni contemporanee per simbolo/magic.
- Cooldown di `CooldownBars` barre dopo l'ultimo trade.

### 5. Esecuzione e compatibilita'
- Pip calcolato dinamicamente: broker a 5 (e 3) cifre -> `Point * 10`; broker a 4 cifre -> `Point`.
  Slippage convertito coerentemente in points.
- `OrderSend` / `OrderModify` / `OrderClose` con retry, backoff progressivo, attesa del contesto di
  trading e log degli errori tramite `GetLastError()` con descrizione testuale.
- Fallback automatico sull'errore 130 (stop non validi): apertura senza stop seguita da `OrderModify`.
- Segnali valutati solo alla chiusura di barra (`TradeOnNewBarOnly`), filtro spread (`MaxSpreadPips`).
- Pannello informativo sul grafico con regime corrente, ATR, SL/TP dinamici, rischio ed esposizione.

## Parametri principali

| Parametro | Default | Descrizione |
|---|---|---|
| `RiskPercent` | 1.0 | rischio % per operazione |
| `MagicNumber` | 20250814 | identificativo dell'EA |
| `ATR_Period` / `ATR_Multiplier_SL` / `ATR_Multiplier_TP` | 14 / 1.5 / 3.0 | stop dinamici |
| `ADX_Threshold` / `ADX_RangeThreshold` | 25.0 / 20.0 | separazione trend/range |
| `EnableTrailingStop` / `TrailingStopPips` | true / 20.0 | trailing |
| `EnableBreakEven` / `BreakEvenPips` | true / 15.0 | break-even |
| `MaxOpenPositions` | 1 | limite di esposizione |
| `TwoStepStops` | false | attivare su broker ECN che rifiutano gli stop in apertura |

## Note operative

- Timeframe di riferimento consigliato: H1 / H4. Su M1-M5 lo spread erode il vantaggio del
  mean reversion.
- Prima dell'uso in reale: backtest su "Every tick" con dati di qualita' e forward test in demo.
- I default sono punti di partenza ragionevoli, non parametri ottimizzati: evitare di
  sovra-ottimizzarli su un singolo simbolo o periodo.
