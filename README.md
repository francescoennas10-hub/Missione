# Expert Advisor per MetaTrader 4 (MQL4)

Due Expert Advisor, due orizzonti operativi diversi sullo stesso strumento:

| EA | File | Strumento / timeframe | Idea |
|---|---|---|---|
| **Gold Scalper M1** | `MQL4/Experts/GoldScalperM1.mq4` | XAUUSD, **M1** (direzione da M15) | scalping su pullback, con dashboard operativa |
| **Adaptive Regime EA** | `MQL4/Experts/AdaptiveRegimeEA.mq4` | XAUUSD, M5/M15 (regime da H1) | trend following o mean reversion secondo il regime |

## Installazione (vale per entrambi)

1. In MetaTrader 4: `File -> Apri cartella dati` -> `MQL4/Experts/`.
2. Copiare il file `.mq4` nella cartella.
3. In MetaEditor premere `F7` per compilare.
4. Trascinare l'EA sul grafico, abilitare l'AutoTrading, verificare i parametri.

---

# Gold Scalper M1 v1.00

Scalper per **XAUUSD su M1**. Lo scalping sull'oro in M1 non fallisce per mancanza di segnali:
fallisce per i **costi** e per il **rumore**. L'EA e' costruito attorno a questi due problemi.

File sorgente: `MQL4/Experts/GoldScalperM1.mq4`

## Come ragiona

### 1. La direzione non si legge su M1
Su M1 la direzione e' rumore, quindi si legge su `TrendTimeframe` (default M15): EMA 21 sopra o
sotto EMA 50, prezzo dalla parte giusta, pendenza della EMA lenta misurata su `BiasSlopeBars`
barre e, se `UseADXFilter` e' attivo, ADX sopra `ADX_Min`. Senza direzione chiara non si opera.

### 2. Si entra sul ritracciamento, non sulla rottura
Sul timeframe di ingresso l'EA cerca un **pullback sulla EMA veloce** entro `PullbackBars` barre,
seguito dalla ripartenza nella direzione del bias. La barra di innesco deve:

- chiudere oltre la EMA veloce, dalla parte del bias;
- avere un corpo di almeno `MinBodyATR * ATR` (niente doji);
- rompere il massimo/minimo della barra precedente (`RequireBreakout`);
- avere l'RSI oltre la soglia di momentum ma **sotto** `RSI_MaxEntry`, per non comprare
  un movimento gia' esteso.

### 3. Il filtro che conta davvero: i costi
Su M1 il take profit e' piccolo, lo spread no. Prima di ogni ordine `BuildStopDistances()`
esegue quattro verifiche e, se una fallisce, **scarta il trade** invece di eseguirlo degradato:

1. **Vincolo broker contro volatilita'** — se `STOPLEVEL + spread` supera `MaxStopLevelATR`
   volte l'ATR, su quel broker l'M1 non e' sostenibile in quel momento.
2. **Allargamento massimo dello stop** — oltre `MaxStopWideningFactor` il trade perde la
   relazione con la volatilita' che lo ha generato.
3. **Copertura dei costi** — il TP deve valere almeno `MinTPCostRatio` volte spread + commissione.
4. **Rischio/rendimento residuo** — dopo ogni aggiustamento il R:R deve restare sopra `MinRiskReward`.

A questi si aggiungono il filtro di spread (assoluto **e** in rapporto all'ATR) e la banda di
volatilita' `MinATRPips` / `MaxATRPips`, che tiene fuori sia il mercato morto sia le candele da
notizia, insieme alla guardia anti-spike `SpikeATRFactor`.

### 4. Uscita rapida
Uno scalp M1 che dura un'ora non e' piu' uno scalp. La gestione lavora in **multipli di R**
(R = distanza dello stop iniziale):

- **parziale** del `PartialPercent` del volume a `PartialAtR` (default 50% a 1R);
- **break-even** a `BreakEvenR` con `BreakEvenLockPips` bloccati;
- **trailing** su ATR da `TrailStartR` in poi, con passo minimo `TrailStepPips`;
- **uscita a tempo** dopo `MaxTradeMinutes` (default 45).

Lo stop non arretra mai e il freeze level del broker viene sempre rispettato.
Poiche' MT4 assegna un **nuovo ticket** alla parte residua dopo una parziale, l'EA tiene un
registro interno indicizzato sull'**ora di apertura**, che la parziale non modifica: e' cosi' che
1R resta noto per tutta la vita della posizione, anche dopo il cambio di ticket.

### 5. Protezioni
`MaxTradesPerDay`, `MaxTradesPerHour`, stop giornaliero `MaxDailyLossPercent`, target giornaliero
`DailyProfitTargetPct` (raggiunto il quale si smette: fa parte del metodo), pausa di
`CooldownMinutes` dopo `MaxConsecutiveLosses` perdite consecutive, attesa di `CooldownBars` barre
dopo ogni operazione, finestra di rollover esclusa e chiusura del venerdi'.

I limiti giornalieri contano gli **ingressi**, non i record di cronologia: una chiusura parziale
lascia due operazioni con la stessa ora di apertura e senza questa distinzione un solo ingresso
consumerebbe due posti.

## Dashboard

Pannello ad oggetti, ancorabile in alto a sinistra o a destra (`PanelCorner`), aggiornato ogni
secondo anche in assenza di tick (timer). Contiene:

- **intestazione** con badge di stato (`OPERATIVO`, `IN POSIZIONE`, `IN PAUSA`, `COOLDOWN`,
  `STOP GIORNO`, `AUTOTRADING OFF`) e tre pulsanti: **II** sospende i nuovi ingressi,
  **X** chiude tutte le posizioni dell'EA, **-** riduce il pannello;
- **tre riquadri KPI**: equity, risultato di oggi, risultato totale dell'EA;
- **mercato**: direzione M15, ADX, ATR, **barra dello spread** rispetto al limite operativo
  effettivo (il piu' stringente fra soglia assoluta e soglia relativa all'ATR), countdown della
  barra M1;
- **checklist dei filtri** con semaforo: sessione, spread, volatilita', direzione, setup M1,
  copertura dei costi, limiti e attese. Si vede a colpo d'occhio **cosa manca** per entrare;
- **prossima operazione**: SL, TP, R:R e volume che verrebbero usati adesso;
- **posizione aperta**: direzione, volume, ingresso, durata, SL/TP, P/L e una barra che mostra
  l'avanzamento da SL (-1R) a TP, con lo stato della parziale;
- **giornata**: barra della perdita giornaliera consumata, barra del target, trade usati su
  limite giornaliero e orario, perdite consecutive;
- **storico EA**: operazioni chiuse, win rate, profit factor, drawdown dal picco;
- **ultimo filtro attivato**: il motivo per cui l'ultimo ingresso non e' avvenuto.

Il conteggio di "operazioni chiuse" e il win rate seguono la convenzione del report di MT4:
una chiusura parziale e' un'operazione a se'.

## Parametri di partenza (gia' impostati nel file)

| Parametro | Valore | Note |
|---|---|---|
| `EntryTimeframe` / `TrendTimeframe` | M1 / M15 | |
| `RiskPercent` | 0.5 | basso per frequenza alta |
| `SL_ATR` / `MinSLPips` | 1.20 / 8.0 | stop tecnico con pavimento |
| `RewardRatio` | 1.50 | TP = 1.5 volte lo stop |
| `MaxSpreadPips` / `MaxSpreadToATR` | 3.0 / 0.25 | il secondo e' quello che conta |
| `MinATRPips` / `MaxATRPips` | 2.0 / 30.0 | banda di volatilita' operativa |
| `MinTPCostRatio` | 2.50 | il TP deve valere 2.5 volte i costi |
| `MaxTradesPerDay` / `PerHour` | 15 / 4 | |
| `MaxDailyLossPercent` / `DailyProfitTargetPct` | 2.5 / 3.0 | |
| `MaxConsecutiveLosses` / `CooldownMinutes` | 3 / 30 | |
| Sessioni | 08:00-11:30 e 14:30-17:30 | **ora del server** |
| `MaxTradeMinutes` | 45 | uscita a tempo |
| `CommissionPerLot` | 0.0 | **da impostare** |

## Note operative

- **`CommissionPerLot` va impostato.** Su M1 la commissione incide sul risultato piu' della
  strategia: entra sia nel calcolo del lotto sia nella verifica di copertura del TP.
- **Le ore di sessione sono ora del server**, non locale. I default assumono un broker su
  GMT+2/GMT+3: verificali prima di operare.
- **Guarda la barra dello spread.** Se sta stabilmente oltre il 75% del limite, quel broker non
  e' adatto allo scalping M1 sull'oro, e nessun parametro puo' compensarlo.
- Se il volume calcolato e' inferiore al doppio del lotto minimo, la chiusura parziale non e'
  eseguibile e la posizione uscira' intera al TP: l'EA lo segnala nel journal.
- Il backtest M1 e' attendibile solo con **dati tick reali** e modello "Every tick": con i dati
  M1 interpolati di MT4 i risultati di uno scalper non significano nulla.
- I default sono punti di partenza ragionevoli, non parametri ottimizzati. Backtest, poi
  walk-forward, poi demo. Sotto un centinaio di operazioni il risultato non e' interpretabile.

---

# Adaptive Regime EA v2.00

Expert Advisor costruito attorno a tre principi: **adattamento al regime di
mercato**, **controllo rigido del rischio** e **verifica preventiva dei vincoli del broker**.
La v2.00 e' tarata per operare su **XAUUSD in M5/M15**, ma resta utilizzabile su Forex e su
timeframe superiori senza ritarature manuali.

File sorgente: `MQL4/Experts/AdaptiveRegimeEA.mq4`

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
