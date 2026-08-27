# Scalp EA v1.40 (MQL4 / MetaTrader 4)

Scalper intraday su XAUUSD M5: entra sui **movimenti minimi**, tiene **una posizione alla
volta**, non manda **nessuno stop al broker** e chiude **solo con il trailing**, che nasce
gia' al prezzo di ingresso. Le perdite vengono ribaltate con **Stop And Reverse**.

- Sorgente: `MQL4/Experts/ScalpEA.mq4`
- Preset: `MQL4/Presets/ScalpEA_XAUUSD_M5.set`

## Cosa mostrano le registrazioni

Due registrazioni mute dello Strategy Tester in modalita' visuale, stesso strumento e
stesso timeframe. Dai fotogrammi si ricavano i vincoli della logica: non le formule
interne, ma i fatti che qualunque implementazione fedele deve rispettare.

| Osservazione | Come e' stata misurata | Conseguenza nel codice |
|---|---|---|
| Grafico `XAUUSD+, M5` | intestazione del grafico | timeframe operativo, valutazione a ogni tick |
| **~7-8 operazioni per barra M5** | 2a registrazione: 13 barre scorse in 17 s (correlazione dei profili delle barre), ticket da `#41` a `#125` | il segnale deve poter scattare piu' volte dentro la stessa candela: riferimento di swing, non di barra |
| **Una sola posizione alla volta** | etichette `#41 sell 0.01`, `#125 buy 0.01`, mai due insieme | `maxOrders = 1`, `Lots` fisso |
| Frecce blu e rosse alternate sullo stesso livello | ingrandimento dei cluster | chiusura e riapertura immediata nel verso opposto: `SAR` |
| **Nessuna linea di stop o di target** accanto alla linea di apertura | scansione riga per riga dei pixel: nel grafico esistono solo la linea del prezzo e quella della posizione | i livelli non arrivano mai al broker: `UseVirtualLevels`, `UseEmergencyBrokerStop = false` |

Le distanze esatte usate dall'EA di riferimento non sono ricavabili da un filmato muto: i
valori del motore automatico sono una ricostruzione dichiarata, tutta esposta negli input.

## Installazione

1. In MetaTrader 4: `File -> Apri cartella dati`.
2. Copiare `ScalpEA.mq4` in `MQL4/Experts/` e `ScalpEA_XAUUSD_M5.set` in `MQL4/Presets/`.
3. In MetaEditor aprire il file e premere `F7` per compilare.
4. Trascinare l'EA sul grafico **XAUUSD M5**, aprire `Parametri di Ingresso`, premere
   `Carica` e scegliere il preset.
5. Abilitare l'AutoTrading.

Per il filtro notizie in tempo reale: `Strumenti -> Opzioni -> Expert Advisors -> Consenti
WebRequest per gli URL elencati`, e aggiungere `https://nfs.faireconomy.media`.

## Come lavora

### 1. Ingresso sui movimenti minimi (`SIGNAL_SWING`)
Il riferimento e' **l'ultimo estremo toccato dal prezzo**, non l'estremo di una barra.
L'EA tiene il massimo e il minimo raggiunti da quando la situazione e' cambiata l'ultima
volta e entra appena il prezzo se ne allontana di `EntryDistance` punti:

```
acquisto : Bid - minimo_locale  >= EntryDistance * Point
vendita  : massimo_locale - Bid >= EntryDistance * Point
```

Il riferimento si azzera **a ogni apertura e a ogni chiusura**: il movimento da misurare e'
quello che nasce da li' in avanti, non quello gia' sfruttato. E' questo che permette al
segnale di ripetersi piu' volte dentro la stessa candela e di avvicinarsi alle 7-8
operazioni per barra misurate nella registrazione. Con `EntryDistance = 30` su un XAUUSD a
due decimali bastano 30 centesimi di movimento; abbassandolo l'EA diventa ancora piu'
reattivo.

`SignalMode = SIGNAL_BAR` riporta al comportamento precedente, la rottura del canale delle
ultime `SignalBars` barre chiuse: molto meno frequente.

### 2. Una posizione alla volta
`maxOrders = 1`, come nelle registrazioni. Il meccanismo della griglia resta nel codice ma
dorme: alzando `maxOrders`, ogni ordine aggiuntivo dello stesso verso viene accettato solo
se nessuna posizione di quel verso si trova entro `EntryDistance` punti dal prezzo.

### 3. Uscita: solo trailing, niente stop sul grafico
Non esistono ne' take profit ne' stop loss separati. **Il trailing e' insieme la
protezione e l'unica uscita**:

- all'apertura il livello nasce a `TrailingStop` di distanza dal prezzo di ingresso;
- comincia a muoversi quando il profitto raggiunge la **soglia di partenza** (sotto);
- da quel momento si muove **solo a favore**, seguendo il massimo (acquisto) o il minimo
  (vendita) raggiunto, con passo minimo `TrailingStepPoints`;
- la posizione si chiude quando il prezzo lo tocca, e mai per altri motivi.

Il livello vive nelle variabili globali del terminale — quindi sopravvive a un riavvio — e
**non viene mai inviato al broker**: sul grafico non compare nulla, come nelle
registrazioni. La chiusura avviene a mercato con la stessa semantica del server: un
acquisto esce sul Bid, una vendita sull'Ask.

Ne discende la lettura che conta:

> **La distanza del trailing e' anche la perdita massima dell'operazione.**

Allargarla lascia respirare il movimento e riduce le chiusure premature, ma alza il rischio
per operazione; stringerla fa l'opposto. `MinTrailingPoints` (40 di default) impedisce che
scenda sotto il rumore del timeframe e chiuda al primo respiro del prezzo.

#### Quando parte il trailing

Due parametri distinti governano due cose diverse:

| Parametro | Risponde a |
|---|---|
| `TrailingStop` / `TrailingPriceDistance` | **quanto** sta indietro il livello |
| `TrailingStartPoints` / `TrailingStartPriceDistance` | **da quale profitto** comincia a muoversi |

Il preset usa `TrailingPriceDistance = 0.30` e `TrailingStartPriceDistance = 0.50`: fino a
+0.50 lo stop resta fermo dove e' nato (ingresso meno 0.30, quindi la posizione **e'
comunque protetta**), superata la soglia comincia a inseguire il massimo a 0.30 di distanza,
bloccando subito +0.20. `TrailingStartPoints` e `ManualTrailingPoints` fanno lo stesso in
punti, e valgono solo se le rispettive versioni in prezzo sono a zero.

Con `TrailingStop = Manual` (impostazione del preset) **l'ATR non entra in gioco**: il
valore dichiarato vale esattamente quello, senza pavimenti ne' correzioni sulla volatilita'.
`MinTrailingPoints` agisce solo in modo `Automatic`.

Lasciando entrambe a zero il comportamento e' quello predefinito: con
`TrailingFromEntry = true` il livello segue fin dal primo tick; con `TrailingFromEntry =
false` non esiste alcuno stop finche' il guadagno non supera la distanza del trailing piu'
lo spread — e in quel caso, senza stop loss, **la posizione resta scoperta fino a quel
momento**.

### 4. SAR (Stop And Reverse)
Quando una posizione si chiude **in perdita**, l'EA apre subito la posizione opposta. Vale
sia per le chiusure decise dall'EA sia per quelle decise dal broker: la scomparsa di un
ticket viene riconosciuta confrontando lo stato degli ordini con quello del tick
precedente. Un'uscita in profitto non innesca nulla.

Due limiti proteggono dal loop: un reversal appena eseguito esaurisce il tick, quindi l'EA
non apre anche il verso opposto nello stesso istante; e `MaxSarChain` limita i reversal
consecutivi (`0` = illimitati, come nelle registrazioni).

### 5. Livelli automatici
`TakeProfit`, `StopLoss` e `TrailingStop` sono enumerazioni con tre stati: `Automatic`,
`Manual`, `Disabled`. Il preset usa `Disabled`, `Disabled` e `Automatic`.

In `Automatic` la distanza si ricava dall'ATR del timeframe operativo, quindi segue da sola
la volatilita':

| Livello | Formula | Default | XAUUSD M5 con ATR ~200 punti |
|---|---|---|---|
| Take profit | `AutoTP_ATR * ATR` | 0.25 | spento nel preset |
| Stop loss | `AutoSL_ATR * ATR` | 0.50 | spento nel preset |
| Trailing | `AutoTS_ATR * ATR`, con pavimento `MinTrailingPoints` | 0.35 / 40 | ~70 punti (**non usato dal preset**) |
| Partenza del trailing | `TrailingStartPriceDistance` o `TrailingStartPoints` | 0.50 | +50 punti |

> **La distanza del trailing viene congelata all'apertura** di ogni posizione, insieme a TP
> e SL, e conservata per quel ticket. Ricalcolarla a ogni tick era un errore: lo stop viene
> ancorato con la distanza del momento in cui nasce, e se quella corrente si allarga il
> livello inseguito arretra rispetto all'ancora, lo stop resta fermo e il trailing sembra
> morto pur essendo attivo. Con `TrailingStop = Automatic` e un ATR in salita l'effetto era
> concreto: bastava un ATR che passasse da 1.50 a 3.00 dollari perche' servissero 57 punti
> di profitto invece dei 50 dichiarati. Nel tester, su periodi a volatilita' stabile, non si
> vedeva.

In `Manual` valgono `ManualTakeProfitPoints`, `ManualStopLossPoints` e
`ManualTrailingPoints`; `StopLossPriceDistance` e `TrailingPriceDistance`, se maggiori di
zero, hanno la precedenza e si esprimono **in prezzo** anziche' in punti. La differenza
conta: 0.90 vale 0.90 dollari sia su un XAUUSD a due decimali sia su uno a tre, mentre
"90 punti" varrebbe 0.90 sul primo e 0.09 sul secondo.

### 6. Protezioni di paniere
- **`Total SL [points]`** — somma algebrica dei punti a mercato delle posizioni dell'EA.
  Sotto la soglia negativa il paniere viene chiuso. `0` disattiva.
- **`DailyProfit`** — realizzato piu' flottante della giornata. Raggiunto l'obiettivo l'EA
  chiude tutto e resta fermo fino al giorno successivo. `0` disattiva.
- **`MaxDD`** — stessa misura, sul lato della perdita. `0` disattiva.

In valuta del conto; con `DailyLimitsInPercent = true` sono percentuali del saldo di inizio
giornata.

### 7. Filtri temporali
- `Trading24h` ignora le finestre orarie ma **non** i giorni disabilitati.
- Le finestre sono in **ora del server**, non locale, e possono scavalcare la mezzanotte
  (`22:00` - `02:00` funziona). Start uguale a End significa 24 ore.
- `TradingNonFarmFriday = false` esclude il primo venerdi' del mese.
- `TradingDuringHolidays = false` esclude la finestra 12 dicembre - 12 gennaio.

### 8. Filtro notizie
Con `NewsFilter = true` l'EA scarica il calendario da `NewsCalendarUrl`, tiene gli eventi
delle valute selezionate con `Report for USD/EUR/GBP/JPY` e, se `NewsHighImpactOnly` e'
attivo, solo quelli ad alto impatto. Il trading si ferma da `doNotTradeBeforeInMinutes`
prima a `doNotTradeAfterInMinutes` dopo ogni evento; con `CloseBeforeNews` le posizioni
aperte vengono chiuse all'inizio della finestra.

L'ora del server rispetto a GMT viene dedotta da sola (`TimeCurrent() - TimeGMT()`);
`NewsFeedGmtOffset` dichiara il fuso del feed. Gli eventi caricati finiscono nel journal
con l'orario gia' convertito: **verificare un evento noto** e' il modo piu' rapido per
accorgersi che l'offset e' sbagliato.

Due limiti da conoscere: `WebRequest` non funziona nello Strategy Tester, quindi in
backtest contano solo gli orari di `ManualNewsTimes` (formato
`YYYY.MM.DD HH:MM;YYYY.MM.DD HH:MM`); e se l'URL non e' fra quelli autorizzati in MT4 il
journal riporta l'errore 4060 e l'EA continua a operare **senza** filtro.

### 9. Vedere cosa sta facendo

I livelli sono virtuali: al broker non arrivano, quindi per costruzione non compaiono nella
finestra Terminale ne' fra le righe di trade di MT4. Senza strumenti dedicati non c'e' modo
di sapere se il trailing si e' mosso. Due cose lo rendono osservabile:

- **`ShowVirtualLevels = true`** disegna lo stop virtuale sul grafico come linea
  tratteggiata (`VirtualStopColor`). E' un **oggetto grafico locale**, non un ordine: il
  broker continua a non vedere nulla, ma tu vedi dove sta il livello e se avanza.
- **Il journal** riceve una riga al primo scatto del trailing su ogni posizione, con prezzo,
  P/L raggiunto, soglia e distanza applicata:
  `ScalpEA: trailing attivato su #12345 a 4579.00 (P/L 50 pt, soglia 50 pt, distanza 30 pt)`.

Se quella riga non compare mentre il P/L supera la soglia, il problema e' nei parametri
caricati, non nella logica: confrontare la riga `Trailing` del pannello con quanto ci si
aspetta.

### 10. Pannello

Con `showPanel = true` compare un riquadro con simbolo e timeframe, spread e stop level,
ATR, TP/SL/trailing correnti (`off` quando un livello non esiste, `= trailing` quando a
proteggere e' il trailing stesso) con la **soglia di partenza** accanto, **stop virtuale
della posizione aperta** con il P/L corrente confrontato alla soglia (la riga diventa verde
quando la soglia e' superata), **distanza attuale dal riferimento di swing** confrontata
con `EntryDistance`, direzione e stato del SAR, ordini aperti e lotto, flottante, risultato
della giornata, stato della sessione, stato del filtro notizie e ultimo filtro che ha
bloccato un ingresso. Si aggiorna una volta al secondo.

## Parametri del preset

| Parametro | Valore | Significato |
|---|---|---|
| `TradeDirection` | BuyAndSell | entrambi i versi |
| `SAR` | true | reversal immediato dopo una chiusura in perdita |
| `Lots` | 0.01 | lotto fisso, riallineato al passo del broker |
| `Magic` | 888777 | identificativo delle operazioni dell'EA |
| `TradeComment` | Scalp EA | commento degli ordini |
| `EntryDistance` | 30 | movimento minimo che fa scattare l'ingresso |
| `TakeProfit` | Disabled | nessun obiettivo di prezzo |
| `StopLoss` | Disabled | nessuno stop separato: protegge il trailing |
| `TrailingStop` | Manual | 0.30 di prezzo, valore dichiarato, senza ATR |
| `maxOrders` | 1 | una posizione alla volta |
| `DailyProfit` / `MaxDD` / `Total SL` | 0 | protezioni di paniere disattivate |
| `Trading24h` | true | nessun vincolo orario |
| `Monday`...`Friday` | true | tutti i giorni feriali abilitati |
| `NewsFilter` | true | filtro notizie attivo, 60 minuti prima e dopo |
| `Report for USD` / `EUR` | true | valute sorvegliate |
| `Report for GBP` / `JPY` | false | ignorate |
| `showPanel` | true | pannello visibile |
| `SignalMode` | SIGNAL_SWING | ingresso sui movimenti minimi |
| `TrailingFromEntry` | true | lo stop esiste gia' al prezzo di ingresso |
| `TrailingStartPriceDistance` | 0.50 | il trailing parte a +0.50 di profitto |
| `ShowVirtualLevels` | true | lo stop virtuale viene disegnato sul grafico |
| `UseEmergencyBrokerStop` | false | nessuno stop inviato al broker |

I primi 40 input riproducono nome, ordine ed etichetta del set allegato; il blocco
`ADVANCED` che segue e' l'unica parte aggiunta.

## Note operative

- **Nessuno stop arriva al broker.** Finche' MT4 e' acceso e connesso la posizione e'
  protetta dal trailing; se il terminale si chiude, va offline o perde la connessione, la
  posizione resta **scoperta** sul server. E' il prezzo di avere il grafico pulito, ed e'
  una scelta consapevole: `UseEmergencyBrokerStop = true` rimette una rete di sicurezza
  larga (`EmergencyStopFactor` volte il trailing), al costo di una linea visibile.
- **Il trailing e' il parametro che conta di piu'.** La sua distanza regola insieme quanto
  si rischia e quanto presto si esce: se le operazioni si chiudono troppo presto la leva e'
  `AutoTS_ATR`, o `TrailingPriceDistance` per fissarla in prezzo. La soglia di partenza e'
  un'altra leva ancora: alzarla lascia correre l'inizio del movimento senza toccare il
  rischio massimo, che resta la distanza del trailing.
- **Frequenza e costi.** A 7-8 operazioni per barra M5 lo spread e' il primo avversario:
  con 25 punti di spread e un trailing di 70, ogni giro parte con oltre un terzo del
  risultato gia' speso. `MaxSpreadPoints` e' a zero nel preset, com'e' nelle registrazioni:
  impostarlo a circa il doppio dello spread tipico e' la prima modifica da fare su conto
  reale.
- **`EntryDistance` e' in punti, non in pip.** Su un XAUUSD a due decimali 30 punti valgono
  0.30 dollari; su un broker a tre decimali valgono 0.03. Trailing e stop, espressi in
  prezzo, non hanno questo problema.
- **`DailyProfit`, `MaxDD` e `Total SL` sono a zero.** Sono le tre protezioni da accendere
  per prime passando dal test al conto reale.
- **Backtest in `Every tick` con dati tick di qualita'.** Con uscite di poche decine di
  punti e diverse operazioni per candela, i dati M1 interpolati non dicono nulla.
  Verificare anche che lo spread simulato sia realistico.

## Struttura del codice

| Sezione | Funzioni principali |
|---|---|
| Segnale | `EntrySignal`, `SwingSignal`, `BarSignal`, `ResetSwingRefs`, `UpdateSwingRefs` |
| Livelli | `AtrPoints`, `TakeProfitPoints`, `StopLossPoints`, `TrailingPoints`, `TrailingStartThreshold`, `MinBrokerDistance` |
| Filtri | `TimeAllowed`, `IsNonFarmFriday`, `IsHolidayPeriod`, `NewsBlocked`, `LoadNewsCalendar` |
| Ordini | `TryOpenPosition`, `ClosePositionByTicket`, `CloseAllPositions`, `SpacingOk` |
| Livelli virtuali | `EnsureLevels`, `StoreLevels`, `ForgetLevels`, `ManageOpenPositions` |
| SAR | `SnapshotOpenTickets`, `DetectBrokerClosures`, `QueueSar`, `ProcessSarQueue` |
| Paniere | `CheckBasketLimits`, `DayProfit`, `RealizedToday`, `FloatingPoints` |
| Interfaccia | `BuildPanel`, `PanelRow`, `UpdatePanel`, `DrawVirtualStop`, `CurrentVirtualStop` |
