# Expert Advisor per MetaTrader 4 (MQL4)

Due Expert Advisor, due orizzonti operativi diversi sullo stesso strumento:

| EA | File | Strumento / timeframe | Idea |
|---|---|---|---|
| **Gold Scalper M1** | `MQL4/Experts/GoldScalperM1.mq4` | XAUUSD, **M1 e M5** (direzione da M15/H1) | scalping su pullback, profilo di aggressivita', dashboard operativa |
| **Adaptive Regime EA** | `MQL4/Experts/AdaptiveRegimeEA.mq4` | XAUUSD, M5/M15 (regime da H1) | trend following o mean reversion secondo il regime |

## Installazione (vale per entrambi)

1. In MetaTrader 4: `File -> Apri cartella dati` -> `MQL4/Experts/`.
2. Copiare il file `.mq4` nella cartella.
3. In MetaEditor premere `F7` per compilare.
4. Trascinare l'EA sul grafico, abilitare l'AutoTrading, verificare i parametri.

---

# Gold Scalper M1 v1.10

Scalper per **XAUUSD su M1 e M5**. Lo scalping sull'oro non fallisce per mancanza di segnali:
fallisce per i **costi** e per il **rumore**. L'EA e' costruito attorno a questi due problemi.

File sorgente: `MQL4/Experts/GoldScalperM1.mq4`

## Come ragiona

### 1. La direzione non si legge sul timeframe di ingresso
Su M1 la direzione e' rumore, quindi si legge su `TrendTimeframe`: EMA 21 sopra o sotto EMA 50,
prezzo dalla parte giusta, pendenza della EMA lenta e, se `UseADXFilter` e' attivo, ADX sopra la
soglia. Senza direzione chiara non si opera.

### 2. Si entra sul ritracciamento, non sulla rottura
L'EA cerca un **pullback sulla EMA veloce** entro `PullbackBars` barre, seguito dalla ripartenza
nella direzione del bias. La barra di innesco deve chiudere oltre la EMA veloce dalla parte
giusta, avere un corpo di almeno `MinBodyATR * ATR`, rompere il massimo/minimo precedente
(`RequireBreakout`) e avere l'RSI oltre la soglia di momentum ma **sotto** `RSI_MaxEntry`, per non
comprare un movimento gia' esteso.

### 3. Volatilita': il confronto e' con l'abitudine dello strumento, non con un numero fisso
Il filtro principale e' **relativo**: `ATR corrente / media dell'ATR su ATR_AvgPeriod barre` deve
stare fra `MinATRRatio` e `MaxATRRatio`.

Questo e' il punto piu' importante del filtro. Una soglia assoluta in pips presuppone di sapere
quanto vale l'ATR "normale" dello strumento, ma quel valore dipende dal livello del prezzo
dell'oro, dal broker e dal periodo storico: **lasciata fissa, blocca l'operativita' per giorni
interi anche in assenza di qualunque notizia.** Il rapporto rispetto alla media, invece, si
ricalibra da solo su qualunque simbolo e qualunque fase di mercato.

`MinATRPips` e `MaxATRPips` restano disponibili come rete di sicurezza assoluta ma sono a **0
(disattivi)** di default. La guardia anti-spike `SpikeATRFactor` (range della barra oltre N volte
l'ATR) e' anch'essa relativa ed e' lo strumento giusto contro le candele da notizia.

### 4. Il filtro che decide: i costi
Il take profit di uno scalp e' piccolo, lo spread no. Prima di ogni ordine `BuildStopDistances()`
esegue quattro verifiche e, se una fallisce, **scarta il trade** invece di eseguirlo degradato:

1. **Vincolo broker contro volatilita'** — se `STOPLEVEL + spread` supera `MaxStopLevelATR` volte
   l'ATR, su quel broker quel timeframe non e' sostenibile in quel momento.
2. **Allargamento massimo dello stop** — oltre `MaxStopWideningFactor` il trade perde la relazione
   con la volatilita' che lo ha generato.
3. **Copertura dei costi** — il TP deve valere almeno `MinTPCostRatio` volte spread + commissione.
4. **Rischio/rendimento residuo** — dopo ogni aggiustamento il R:R deve restare sopra `MinRiskReward`.

### 5. Uscita rapida
La gestione lavora in **multipli di R** (R = distanza dello stop iniziale): parziale del
`PartialPercent` a `PartialAtR`, break-even a `BreakEvenR`, trailing su ATR da `TrailStartR`,
uscita a tempo dopo `MaxTradeMinutes`. Lo stop non arretra mai e il freeze level e' rispettato.

Poiche' MT4 assegna un **nuovo ticket** alla parte residua dopo una parziale, l'EA tiene un
registro interno indicizzato sull'**ora di apertura**, che la parziale non modifica: e' cosi' che
1R resta noto per tutta la vita della posizione.

### 6. Protezioni
`MaxTradesPerDay`, `MaxTradesPerHour`, stop giornaliero, target giornaliero, pausa dopo N perdite
consecutive, attesa in barre dopo ogni operazione, finestra di rollover esclusa, chiusura del
venerdi'. I limiti contano gli **ingressi**, non i record di cronologia: una chiusura parziale
lascia due operazioni con la stessa ora di apertura e senza questa distinzione un solo ingresso
consumerebbe due posti.

## Profilo di aggressivita'

`AggressionProfile` agisce insieme su tre dimensioni: quanto e' facile che un setup sia
accettato, quante operazioni sono ammesse e quanto si rischia su ognuna.

| | Conservativo | Standard | Aggressivo | Molto aggressivo |
|---|---|---|---|---|
| Corpo minimo della barra | x1.40 | x1.00 | x0.50 | x0.25 |
| ADX minimo | x1.30 | x1.00 | x0.60 | x0.30 |
| Banda ATR | piu' stretta | base | +40% | +90% |
| Barre utili al pullback | base | base | +2 | +3 |
| RSI massimo di ingresso | -5 | base | +8 | +12 |
| Rottura obbligatoria | si | input | no | no |
| Pendenza EMA obbligatoria | si | si | no | no |
| Trade al giorno e all'ora | x0.60 | x1.00 | x2.00 | x3.00 |
| Attesa fra operazioni | x1.50 | x1.00 | x0.35 | nessuna |
| Sessioni | -15 min | base | +45 min | +120 min |
| **Rischio per operazione** | **x0.70** | **x1.00** | **x1.50** | **x2.00** |

Il default e' **Aggressivo**. `Personalizzato` disattiva il profilo e usa gli input come sono.

**Restano dei pavimenti che nessun profilo puo' superare**: copertura dei costi mai sotto 1.20x,
R:R mai sotto 1.00, spread/ATR mai oltre 0.60, rischio mai oltre il 10%. Sono cio' che distingue
uno scalper da un regalo di spread al broker: allargare quei limiti non rende l'EA piu'
aggressivo, lo rende perdente in modo matematico.

Aggressivita' e drawdown crescono insieme. Il profilo `Molto aggressivo` **raddoppia il rischio
per operazione** rispetto a `RiskPercent`: verificalo in backtest e in demo prima del reale.

## Adattamento al timeframe

Con `AutoAdaptToTimeframe` attivo (default) i parametri seguono il timeframe scelto:

| Grandezza | Legge di scala | Da M1 a M5 |
|---|---|---|
| Soglie in pips (stop minimo, break-even, passo del trailing) | radice del tempo | x2.24 |
| Uscita a tempo | lineare nella durata della barra | x5 |
| Parametri misurati in barre (EMA, RSI, pullback, attese) | invariati | invariati |
| Timeframe direzionale | alzato se sotto 5 volte quello di ingresso | M15 diventa H1 |

Le escursioni di prezzo non crescono di 5 volte passando da M1 a M5, ma di circa la radice di 5:
e' la legge di scala corretta per una grandezza di volatilita'. Il filtro relativo dell'ATR non
ha bisogno di alcun adattamento, perche' e' gia' un rapporto.

## Dashboard

Pannello ad oggetti, ancorabile a sinistra o a destra, aggiornato ogni secondo anche in assenza
di tick. Contiene intestazione con badge di stato e tre pulsanti (**II** sospendi ingressi,
**X** chiudi tutto, **-** riduci), tre riquadri KPI, **assetto operativo** (profilo attivo,
adattamento applicato, rischio e limiti effettivi), mercato con **ATR e rapporto ATR/media** e
barra dello spread, **checklist dei filtri con semaforo**, piano della prossima operazione,
posizione aperta con barra da SL a TP, riepilogo della giornata, storico e **ultimo filtro
attivato**.

La dashboard mostra sempre i valori **effettivi** dopo profilo e adattamento, non gli input.

## Note operative

- **`CommissionPerLot` va impostato** con il valore reale round-turn del tuo conto: entra sia nel
  calcolo del lotto sia nella verifica di copertura del TP.
- **Dopo un aggiornamento del file, riporta i parametri ai valori di default.** MT4 conserva per
  ogni grafico gli input usati in precedenza: se resta un `MaxATRPips` vecchio, il filtro
  assoluto continua a bloccare tutto. In caso di dubbio usa `Ripristina` nella finestra
  dell'EA. All'avvio l'EA scrive nel journal una **diagnostica della volatilita'** e avvisa
  esplicitamente se una soglia impostata sta impedendo ogni ingresso.
- **Le ore di sessione sono ora del server**, non locale.
- **Guarda la barra dello spread.** Se sta stabilmente oltre il 75% del limite, quel broker non e'
  adatto allo scalping su questo simbolo, e nessun parametro puo' compensarlo.
- Il backtest su timeframe rapidi e' attendibile solo con **dati tick reali** e modello
  "Every tick".
- I default sono punti di partenza ragionevoli, non parametri ottimizzati.

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
