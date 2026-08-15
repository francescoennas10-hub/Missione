# Expert Advisor per MetaTrader 4 (MQL4)

Il repository contiene due EA distinti, con obiettivi diversi:

| File | Mercato di riferimento | Idea centrale |
|---|---|---|
| `MQL4/Experts/AdaptiveEurUsdEA.mq4` | **EURUSD**, regime H1 + ingresso M15 | Riconoscimento del regime a 4 stati e selezione automatica fra tre strategie, con scoring normalizzato |
| `MQL4/Experts/AdaptiveRegimeEA.mq4` | XAUUSD, M5/M15 | Trend/range a 2 stati con motore di controllo dei vincoli del broker |

Sono indipendenti: magic number diversi, nessun file condiviso.

---

# 1. Adaptive EURUSD EA v1.00

Expert Advisor adattivo per EURUSD. Non applica una strategia fissa: **classifica prima il regime di
mercato su H1**, poi attiva su M15 solo il motore di segnale coerente con quel regime.

```
EURUSD
  |
  v
H1 MARKET REGIME  ->  TREND UP / TREND DOWN / RANGE / BREAKOUT / NO TRADE
  |
  v
M15 SIGNAL ENGINE ->  Trend following | Breakout | Mean reversion
  |
  v
SIGNAL SCORING (0..10, scala unica per tutte le strategie)
  |
  v
RISK FILTERS (gate binari)  ->  TRADE EXECUTION  ->  POSITION MANAGEMENT
```

La priorita' del progetto e': **robustezza > semplicita' > adattivita' > profitto del backtest**.

## Installazione

1. In MetaTrader 4: `File -> Apri cartella dati` -> `MQL4/Experts/`.
2. Copiare `AdaptiveEurUsdEA.mq4` nella cartella.
3. In MetaEditor premere `F7` per compilare.
4. Applicare l'EA a un grafico **EURUSD** (qualunque timeframe: l'EA legge H1 e M15 esplicitamente),
   abilitare l'AutoTrading.

## Market Regime Engine (H1)

Tutte le letture usano `shift >= 1`: la barra H1 in formazione non viene mai usata come se fosse
chiusa. La classificazione ha una **priorita' esplicita**, e non e' arbitraria — un trend gia' in
corso rompe di continuo i propri estremi, quindi senza questo ordine ogni trend verrebbe
riclassificato come breakout a ogni nuovo massimo:

1. **TREND** — punteggio 0..6 su quattro componenti:

   | Componente | Punti |
   |---|---|
   | EMA20 > EMA50 > EMA200 (allineamento pieno) | +2 |
   | EMA20 > EMA50 e prezzo oltre EMA200 (parziale) | +1 |
   | ADX >= soglia | +2 |
   | ADX entro 5 punti sotto la soglia | +1 |
   | Higher High | +1 |
   | Higher Low | +1 |

   Attivo se punteggio >= `InpMinTrendScore` **e** EMA20/EMA50 concordi **e** ATR/ATRmedio >= 0.80.
   Logica speculare per il ribasso.

2. **BREAKOUT / TRANSITION** — ATR/ATRmedio >= 1.10, ADX in salita di almeno 2 punti su 3 barre,
   chiusura oltre l'estremo delle N barre precedenti. E' l'uscita da una compressione, non un trend
   maturo.

3. **RANGE** — tutte insieme: ADX sotto soglia, pendenza EMA20 (misurata in ATR) < 0.30, EMA20 ed
   EMA50 intrecciate entro 0.5 ATR, ATR/ATRmedio <= 1.30, ampiezza del canale fra 1.5 e 6 ATR.

4. **NO TRADE** — tutto il resto.

La **struttura** (HH/HL/LH/LL) usa swing confermati con 2 barre a destra gia' chiuse. E' proprio
questo ritardo a rendere la struttura non-repainting.

## Signal Engine (M15)

Ogni motore restituisce un punteggio **normalizzato 0..10**, cosi' una sola soglia
(`InpMinSignalScore`) e' confrontabile fra strategie diverse invece di richiederne tre da ottimizzare
separatamente.

| Motore | Regime | Gate obbligatori | Punteggio |
|---|---|---|---|
| **Trend following** | TREND | pullback verso EMA20/50 nelle ultime N barre + rottura del massimo/minimo locale + candela concorde | qualita' regime (0-3), pullback (2), rottura (2), candela (1), momentum (1), volume (1) |
| **Breakout** | BREAKOUT, o TREND come continuazione | rottura del livello oltre buffer ATR, corpo >= soglia ATR, estensione <= 1.5 ATR (anti-spike), ATR non depresso, contesto H1 non contrario | contesto (2), rottura (2), corpo (1), non iper-esteso (1), volume (1), ATR (1), chiusura decisa (2) |
| **Mean reversion** | RANGE | prezzo nel 20% esterno del range, estensione oltre BB o >1.2 ATR dalla EMA20, candela di rifiuto, target ancora davanti | range definito (2), zona (2), estensione (2), rifiuto (2), RSI (1), ATR (1) |

Il **breakout** non e' mai `breakout = BUY`. Il filtro anti-spike e' la parte che conta: se il prezzo
ha gia' percorso oltre 1.5 ATR dal livello, l'ingresso arriverebbe a movimento fatto e con uno stop
innaturalmente lontano.

Con `InpUseRetest = true` il breakout non entra sulla rottura ma **arma** il livello ed entra a
mercato solo se il prezzo torna a testarlo e lo rifiuta entro `InpRetestMaxBars`. E' implementato
come macchina a stati, non con ordini pendenti: i pendenti sono gestiti in modo eterogeneo dai broker
ECN e modellati in modo ottimistico dal tester.

## Gate e scoring: due livelli separati

I filtri di sicurezza sono **binari e non negoziabili**, tenuti fuori dal punteggio di proposito:
un setup da 10/10 non deve poter "comprare" il permesso di operare con lo spread anomalo o con la
perdita giornaliera gia' raggiunta.

Gate applicati in sequenza: terminale operativo, news (stub), sessione, pausa da drawdown, perdita
giornaliera, perdita settimanale, trade giornalieri, distanza minima fra ingressi, posizione gia'
aperta nella stessa direzione, hedging, numero massimo di posizioni, spread (assoluto **e** in
frazione di ATR), ATR fuori range, coerenza segnale/regime.

## Rischio e dimensionamento

```
lotti = (equity * Risk% * fattoreStreak) / ((distanzaSL / TICKSIZE) * TICKVALUE + commissione)
```

`TICKVALUE`, `TICKSIZE`, `MINLOT`, `MAXLOT`, `LOTSTEP`, `STOPLEVEL`, `FREEZELEVEL` sono letti dal
broker: nessuna ipotesi su contract size, valuta del conto o numero di cifre. Se il **lotto minimo
del broker eccede di oltre il 50% il budget di rischio, l'EA non opera** invece di rischiare piu' del
previsto.

**Stop loss** — combinazione di struttura e volatilita': si parte dal minimo/massimo strutturale
delle ultime 8 barre M15 con buffer 0.25 ATR, poi il valore viene **ancorato** fra 0.70 e 1.80 volte
lo stop ATR di riferimento. Senza questo vincolo un minimo strutturale lontano produrrebbe stop
enormi e lotti irrisori, uno vicinissimo produrrebbe stop dentro il rumore.

**Take profit** — trend: multiplo di R come rete di sicurezza, l'uscita reale e' il trailing; range:
il centro del canale H1 (ipotesi verificabile, non estetica), scartato se non offre almeno 1R;
breakout: multiplo di R con parziale opzionale.

**Motore delle distanze** — prima di ogni ordine lo stop viene confrontato con i vincoli del broker.
Se una verifica fallisce il trade viene **scartato**, non eseguito in versione degradata: distanza
minima sproporzionata all'ATR, allargamento oltre `InpMaxStopWiden`, TP che non copre 3 volte i
costi, R:R sotto `InpMinRiskReward`.

## Gestione della posizione

Gira a ogni tick (uno stop deve poter essere spostato senza aspettare la chiusura di barra), mentre
le **decisioni di ingresso avvengono solo alla chiusura di una barra M15**: il sistema non reagisce
al rumore intrabar e i risultati del tester non dipendono dalla qualita' dei tick.

Ordine delle operazioni: uscita per ribaltamento del regime, chiusura parziale, break-even, trailing.
**Lo stop non arretra mai.**

Il rischio iniziale (1R) di ogni posizione e' conservato su tre livelli di ridondanza — array in
memoria, codifica nel commento dell'ordine, stima da ATR — perche' senza di essi un riavvio del
terminale trasformerebbe la gestione delle posizioni aperte in un comportamento casuale. Dopo una
chiusura parziale MT4 assegna un **nuovo ticket** al residuo: viene ritrovato per data e prezzo di
apertura e ritracciato subito.

## News filter

`IsNewsBlackout()` restituisce **sempre `false`** in v1. Nessun dato macro viene letto e **nessuna
finestra viene simulata**: fingere di avere le news darebbe un backtest piu' bello e una falsa
sicurezza. Per implementarlo in futuro basta caricare un CSV in `MQL4/Files`, leggerlo in `OnInit` e
confrontare `TimeCurrent()` con le finestre: l'unico contratto richiesto e' quella firma booleana.

## Parametri: cosa ottimizzare

Gli input sono marcati nel codice `[OPT]` o `[FIX]`. **Solo dieci sono destinati
all'ottimizzazione**; il resto ha significato strutturale.

| Parametro | Default | Range di test suggerito |
|---|---|---|
| `InpAdxTrend` | 23.0 | 20 / 23 / 26 |
| `InpAdxRange` | 18.0 | 15 / 18 / 21 |
| `InpEmaMid` | 50 | 45 / 50 / 55 |
| `InpRegimeLookback` | 20 | 15 / 20 / 25 |
| `InpMinTrendScore` | 4 | 3 / 4 / 5 |
| `InpMinSignalScore` | 6.0 | 5 / 6 / 7 |
| `InpSL_ATR_Trend` | 1.5 | 1.3 / 1.5 / 1.7 |
| `InpTrailATR` | 1.5 | 1.2 / 1.5 / 1.8 |
| `InpBreakLookback` | 20 | 15 / 20 / 25 |
| `InpRiskPercent` | 0.50 | non ottimizzare: e' una scelta, non un risultato |

Diverse soglie (pendenza EMA, larghezza del range, anti-spike, ombre, corpi) sono **costanti interne
e non input**: e' una scelta deliberata per ridurre la superficie di overfitting. Chi vuole testarne
la sensibilita' le modifica nel blocco `COSTANTI INTERNE` e ricompila.

## Protocollo di test

1. **In-sample** — es. 2015-2020. Serve a verificare che il sistema faccia quello che dice, non a
   massimizzare il profitto.
2. **Out-of-sample** — es. 2021-2024, **una sola volta**, senza ritoccare nulla dopo aver visto il
   risultato. Ogni ritocco successivo lo trasforma in in-sample.
3. **Walk-forward** — finestre mobili (es. 12 mesi di ottimizzazione, 6 di verifica).
4. **Monte Carlo** — permutazione dell'ordine dei trade, slippage aggiunto, spread peggiorato,
   rimozione casuale del 10% dei trade.
5. **Test di robustezza** — variare ogni parametro `[OPT]` di +/-15%. **Se una piccola variazione
   distrugge il risultato, il sistema e' overfittato**: l'obiettivo non e' il picco, e' l'altopiano.

Metriche da leggere insieme, mai il solo Net Profit: Profit Factor, Expected Payoff, Max Drawdown,
Recovery Factor, Sharpe, Win Rate, Average Win/Loss, numero di trade, vincite e perdite consecutive,
rendimento annualizzato, stabilita' mensile, **risultati separati per regime, per sessione e per
direzione long/short**. Il commento dell'ordine (`AdaptEU|T|R…`, `|B|`, `|M|`) permette di separare i
trade per strategia. Sotto ~100 trade il risultato non e' interpretabile.

## Note operative

- Le ore di sessione sono in **ora del server**, non locale.
- `InpCommissionPerLot` va impostato con il valore reale del conto: entra sia nel sizing sia nel
  controllo di copertura del TP.
- Con `InpAllowOpposite = false` (default) il numero reale di posizioni contemporanee e' **1**, anche
  se `InpMaxOpenTrades` vale 2: la direzione uguale e' vietata e quella opposta pure. E' voluto —
  aprire long e short insieme sullo stesso simbolo raddoppia i costi per un'esposizione netta nulla.
- `InpLossStreakLimit` (riduzione del rischio dopo N perdite) non ha una giustificazione statistica
  forte se i trade sono indipendenti. E' anti-martingala, quindi non puo' amplificare le perdite, ma
  **il test di riferimento va fatto con `InpLossStreakLimit = 0`**.
- `DebugMode = true` stampa regime, punteggi, filtri e decisione a ogni barra M15. Tenerlo spento nei
  backtest lunghi.

---

# 2. Adaptive Regime EA v2.00 (XAUUSD)

Expert Advisor costruito attorno a tre principi: **adattamento al regime di mercato**, **controllo
rigido del rischio** e **verifica preventiva dei vincoli del broker**. Tarato per **XAUUSD in
M5/M15**, resta utilizzabile su Forex e su timeframe superiori senza ritarature manuali.

File sorgente: `MQL4/Experts/AdaptiveRegimeEA.mq4`

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

### 5. Rischio
- SL e TP sempre presenti all'apertura; in modalita' `TwoStepStops` (ECN) vengono impostati subito
  dopo e, se non impostabili, la posizione viene chiusa immediatamente.
- `CalculateLotSize()` dimensiona sul rischio percentuale usando la distanza SL effettiva, quindi
  normalizza su `MODE_LOTSTEP`, `MODE_MINLOT`, `MODE_MAXLOT`, verifica il margine libero e `MaxLotCap`.
- **Limiti giornalieri**: `MaxTradesPerDay` e `MaxDailyLossPercent`.
- **Filtro di sessione** e chiusura opzionale del venerdi'.

### 6. Gestione della posizione
`ManagementMode = MANAGE_ATR` (default) esprime break-even e trailing in multipli di ATR, quindi le
soglie seguono la volatilita' e non vanno ritarate cambiando simbolo o timeframe. `MANAGE_PIPS`
mantiene il comportamento classico. Lo stop non arretra mai; freeze level rispettato.

### 7. Dashboard grafica
Pannello ad oggetti ancorato in alto a sinistra, aggiornato una volta al secondo: conto, performance
dell'EA, mercato (regime, ADX, ATR, spread anche in % di ATR), distanze (stop level del broker,
SL/TP proposti, R:R effettivo, lotto stimato), stato operativo e ultimo filtro che ha bloccato un
ingresso.

## Note operative

- Imposta `CommissionPerLot` con il valore reale del tuo conto.
- Le ore di sessione sono in ora del server, non locale.
- Su M5 il rapporto spread/ATR e' la variabile critica: se sta stabilmente sopra il 10-12%, quel
  timeframe non e' sostenibile su quel broker.
- I default sono punti di partenza ragionevoli, non parametri ottimizzati.

---

## Avvertenza

Nessuno dei due EA promette profitti. Sono sistemi meccanici il cui unico scopo dichiarato e'
comportarsi in modo prevedibile su dati che non hanno mai visto. Un backtest positivo non e' una
previsione: e' la condizione minima per proseguire con walk-forward e demo.
