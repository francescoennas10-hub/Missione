# EA per MetaTrader 4

Questo repository contiene due Expert Advisor indipendenti.

| EA | Sorgente | Documentazione | In una riga |
|---|---|---|---|
| **Scalp EA** | `MQL4/Experts/ScalpEA.mq4` | [ScalpEA.md](ScalpEA.md) | scalper M5 con griglia a distanza fissa, livelli virtuali e Stop&Reverse; preset in `MQL4/Presets/` |
| **Adaptive Regime EA** | `MQL4/Experts/AdaptiveRegimeEA.mq4` | vedi sotto | classifica il regime di mercato e sceglie la strategia coerente |

---

# Adaptive Regime EA v2.00 (MQL4 / MetaTrader 4)

Expert Advisor per MetaTrader 4 costruito attorno a tre principi: **adattamento al regime di
mercato**, **controllo rigido del rischio** e **verifica preventiva dei vincoli del broker**.
La v2.00 e' tarata per operare su **XAUUSD in M5/M15**, ma resta utilizzabile su Forex e su
timeframe superiori senza ritarature manuali.

File sorgente: `MQL4/Experts/AdaptiveRegimeEA.mq4`

## Installazione

1. In MetaTrader 4: `File -> Apri cartella dati` -> `MQL4/Experts/`.
2. Copiare `AdaptiveRegimeEA.mq4` nella cartella.
3. In MetaEditor premere `F7` per compilare.
4. Trascinare l'EA sul grafico, abilitare l'AutoTrading, verificare i parametri.

## Cosa cambia rispetto alla v1

| Area | v1.00 | v2.00 |
|---|---|---|
| Pip | 4/5 cifre Forex | profilo automatico per Forex, oro, argento, indici |
| Regime | stesso timeframe dell'ingresso | timeframe separato (`RegimeTimeframe`, default H1) |
| Distanze minime | solo allargamento silenzioso | **motore di controllo con 4 verifiche e scarto del trade** |
| BE / trailing | solo pips | multipli di ATR (default) o pips |
| Filtri | spread assoluto | spread assoluto + spread/ATR, sessione, limiti giornalieri |
| Strategie | sempre entrambe | attivabili singolarmente |
| Costi | ignorati | commissione inclusa nel sizing e nel controllo del TP |

## Architettura

### 1. Profilo automatico del simbolo
`DetectSymbolProfile()` classifica lo strumento (Forex / oro / argento / indice) e ne deduce il pip:
oro `0.10`, argento `0.01`, Forex `Point*10` sui broker a 3/5 cifre. Su XAUUSD un ATR di 4 dollari
viene quindi letto come 40 pips e uno spread di 25 centesimi come 2.5 pips, cosi' i parametri
mantengono lo stesso ordine di grandezza usato sul Forex. Sovrascrivibile con `PipMode` e
`CustomPipSize`.

### 2. Regime su timeframe superiore
Il regime si legge su `RegimeTimeframe` (default H1) con ADX, rapporto ATR/ATR medio e distanza del
prezzo dalla MA lunga misurata in ATR; l'ingresso avviene su `SignalTimeframe` (default M15).
Su M5 l'ADX calcolato localmente e' rumore: separare i due piani e' cio' che rende utilizzabile
l'intraday veloce.

- **REGIME_TREND**: `ADX >= ADX_Threshold`, ATR ratio `>= ATR_TrendFactor`, prezzo a piu' di 0.5 ATR dalla MA lunga.
- **REGIME_RANGE**: `ADX <= ADX_RangeThreshold`, ATR ratio `<= ATR_RangeFactor`, prezzo entro `RangeMaxDistanceATR`.
- **REGIME_NONE**: nessuna operazione.

### 3. Motore delle distanze minime (`BuildStopDistances`)
Prima di ogni ordine, lo stop teorico `ATR * ATR_Multiplier_SL` viene confrontato con
`MODE_STOPLEVEL`, `MODE_FREEZELEVEL`, spread e margine di sicurezza. Quattro verifiche in sequenza;
se una fallisce **il trade viene scartato**, non eseguito in versione degradata:

1. **Vincolo contro volatilita'** — se la distanza minima del broker supera `MaxStopLevelATR` volte
   l'ATR, il timeframe e' troppo stretto per quel broker in quel momento.
2. **Allargamento massimo** — se il vincolo costringe ad allargare lo stop oltre
   `MaxStopWideningFactor` volte quello teorico, il trade perde la relazione con la volatilita'
   che lo ha generato.
3. **Copertura dei costi** — il TP deve valere almeno `MinTPCostRatio` volte spread + commissione.
4. **Rischio/rendimento residuo** — dopo ogni aggiustamento il R:R deve restare sopra
   `MinRiskReward`.

Con `PreserveRiskReward = true` un allargamento dello stop allarga proporzionalmente anche il target.
Ogni scarto viene registrato nel journal (`LogRejections`) e mostrato in fondo alla dashboard.

### 4. Strategie
- **Trend following** (`EnableTrendStrategy`): incrocio MA veloce/lenta sul timeframe di ingresso,
  confermato dal bias della MA lunga e dalla dominanza +DI/-DI letti sul timeframe del regime.
- **Mean reversion** (`EnableRangeStrategy`): estensione oltre la banda di Bollinger con RSI in
  ipercomprato/ipervenduto e chiusura che rientra nel canale.

Le due gambe sono attivabili separatamente: su oro puo' avere senso tenere solo il trend following.

### 5. Rischio
- SL e TP sempre presenti all'apertura; in modalita' `TwoStepStops` (ECN) vengono impostati subito
  dopo e, se non impostabili, la posizione viene chiusa immediatamente.
- `CalculateLotSize()` dimensiona sul rischio percentuale usando la distanza SL effettiva:
  `lotti = rischio / ((distanzaSL / TICKSIZE) * TICKVALUE + CommissionPerLot)`, quindi normalizza su
  `MODE_LOTSTEP`, `MODE_MINLOT`, `MODE_MAXLOT`, verifica il margine libero e `MaxLotCap`.
- **Limiti giornalieri**: `MaxTradesPerDay` e `MaxDailyLossPercent` (stop giornaliero in % del saldo
  di inizio giornata, con o senza flottante).
- **Filtro di sessione** e chiusura opzionale del venerdi'.

### 6. Gestione della posizione
`ManagementMode = MANAGE_ATR` (default) esprime break-even e trailing in multipli di ATR, quindi le
soglie seguono la volatilita' e non vanno ritarate cambiando simbolo o timeframe. `MANAGE_PIPS`
mantiene il comportamento classico. Lo stop non arretra mai; freeze level rispettato.

### 7. Dashboard grafica
Pannello ad oggetti ancorato in alto a sinistra, sfondo nero, aggiornato una volta al secondo:
conto, performance dell'EA (flottante, giornaliero, realizzato, **profitto totale**, win rate,
profit factor), mercato (regime, ADX, ATR, spread anche in % di ATR), **distanze** (stop level del
broker, distanza minima, SL/TP proposti, R:R effettivo, lotto stimato), stato operativo e
**ultimo filtro che ha bloccato un ingresso**.

## Configurazione di partenza per XAUUSD M5/M15

I default del file sono gia' questi:

| Parametro | Valore | Note |
|---|---|---|
| `SignalTimeframe` | `PERIOD_M15` | M5 possibile, costi piu' pesanti |
| `RegimeTimeframe` | `PERIOD_H1` | contesto |
| `ATR_Multiplier_SL` / `_TP` | 1.8 / 3.2 | R:R nominale 1:1.78 |
| `MaxSpreadPips` / `MaxSpreadToATR` | 4.0 / 0.12 | il secondo e' il filtro che conta |
| `MaxStopLevelATR` | 0.80 | scarta se lo stop level e' oltre l'80% dell'ATR |
| `MaxStopWideningFactor` | 1.50 | allargamento massimo dello stop |
| `MinTPCostRatio` | 4.0 | il TP deve valere 4 volte i costi |
| `MinRiskReward` | 1.40 | R:R minimo dopo gli aggiustamenti |
| `MaxTradesPerDay` | 6 | |
| `MaxDailyLossPercent` | 3.0 | stop giornaliero |
| `UseSessionFilter` | 8-21 server time | London + NY |
| `CommissionPerLot` | 0.0 | **da impostare** con la commissione reale round-turn |

## Note operative

- Imposta `CommissionPerLot` con il valore reale del tuo conto: entra sia nel sizing sia nel
  controllo di copertura del TP.
- Le ore di sessione sono in **ora del server**, non locale: verificale sul tuo broker.
- Su M5 il rapporto spread/ATR e' la variabile critica. La dashboard lo mostra in percentuale:
  se sta stabilmente sopra il 10-12%, quel timeframe non e' sostenibile su quel broker.
- I default sono punti di partenza ragionevoli, non parametri ottimizzati. Backtest su "Every tick"
  con dati tick di qualita', poi walk-forward, poi demo. Sotto un centinaio di trade il risultato
  non e' interpretabile.
- Nel backtest analizza separatamente i trade `-TRD` e `-RNG`: il commento dell'ordine li distingue.
