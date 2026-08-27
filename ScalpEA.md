# Scalp EA v1.10 (MQL4 / MetaTrader 4)

Scalper intraday a **posizione singola**, **senza take profit**, con livelli virtuali,
stop fisso e **Stop And Reverse**, ricostruito dalla registrazione dello Strategy Tester
allegata e dal set di parametri fornito.

L'uscita ha due sole strade: il **trailing stop**, che insegue il profitto finche' il
movimento prosegue, e lo **stop loss** iniziale, fisso a 0.90 di prezzo (una vendita a
4578.50 ha lo stop a 4579.40).

- Sorgente: `MQL4/Experts/ScalpEA.mq4`
- Preset: `MQL4/Presets/ScalpEA_XAUUSD_M5.set`

## Cosa mostra il video e cosa se ne deduce

Il filmato e' una registrazione muta (audio a silenzio digitale) dello Strategy Tester
in modalita' visuale. Analizzando i fotogrammi si ricavano cinque fatti, che sono le
basi su cui e' costruito l'EA:

| Osservazione sul video | Conseguenza nel codice |
|---|---|
| Grafico `XAUUSD+, M5`, barre da 30-40 secondi di filmato ciascuna | timeframe operativo M5, valutazione a ogni tick |
| Etichette `#25 buy 0.01`, `#26 buy 0.01`, `#32 sell 0.01`: **una sola posizione alla volta**, ticket che avanzano di circa uno ogni 5 secondi di video | scalping ad alta frequenza, circa 4 operazioni per barra M5, `Lots` fisso |
| Frecce blu e rosse **alternate sullo stesso livello**, unite da tratteggi quasi verticali | chiusura e riapertura immediata nel verso opposto: `SAR` |
| Frecce impilate a distanze regolari sulla stessa barra | ingressi successivi separati da `EntryDistance` punti, fino a `maxOrders` |
| Sul grafico compaiono solo la linea del prezzo e la linea di apertura della posizione: **nessuna linea di stop loss o take profit** | i livelli non vengono inviati al broker, l'EA li sorveglia e chiude a mercato (`UseVirtualLevels`) |

Il video non rivela le formule usate per calcolare i livelli "Automatic": quella parte e'
una ricostruzione dichiarata, ancorata all'ATR e completamente esposta negli input, non
una copia di parametri interni. E' la sola porzione della logica che va ritarata sui
propri dati prima di usarla.

## Installazione

1. In MetaTrader 4: `File -> Apri cartella dati`.
2. Copiare `ScalpEA.mq4` in `MQL4/Experts/` e `ScalpEA_XAUUSD_M5.set` in `MQL4/Presets/`.
3. In MetaEditor aprire il file e premere `F7` per compilare.
4. Trascinare l'EA sul grafico **XAUUSD M5**, aprire la scheda `Parametri di Ingresso`,
   premere `Carica` e scegliere il preset.
5. Abilitare l'AutoTrading.

Per il filtro notizie in tempo reale: `Strumenti -> Opzioni -> Expert Advisors -> Consenti
WebRequest per gli URL elencati` e aggiungere `https://nfs.faireconomy.media`.

## Come lavora

### 1. Segnale di ingresso
Rottura del canale delle ultime `SignalBars` barre chiuse, di almeno `EntryDistance` punti:

```
soglia acquisto = massimo(SignalBars barre) + EntryDistance * Point
soglia vendita  = minimo (SignalBars barre) - EntryDistance * Point
```

Con `SignalBars = 1` la soglia e' l'estremo della barra precedente: e' quel che serve a un
sistema che deve poter entrare piu' volte dentro la stessa candela M5.

### 2. Una posizione alla volta
`maxOrders = 1`: l'EA tiene aperta una sola posizione, come si vede nel video. Il
meccanismo della griglia resta nel codice ma dorme: alzando `maxOrders`, ogni ordine
aggiuntivo dello stesso verso viene accettato solo se **nessuna** posizione aperta di quel
verso si trova entro `EntryDistance` punti dal prezzo corrente.

### 3. Uscita: niente take profit
La posizione **non ha un obiettivo di prezzo**. Resta aperta finche' il movimento le da'
ragione e si chiude in due soli modi:

- **trailing stop** — segue il prezzo a distanza `TrailingStop` e si attiva quando il
  guadagno supera quella distanza piu' lo spread. Non arretra mai;
- **stop loss** — distanza fissa dall'ingresso, `StopLossPriceDistance = 0.90`. Con una
  vendita a `4578.50` lo stop sta a `4579.40`; con un acquisto alla stessa quota starebbe
  a `4577.60`.

Il take profit resta come input (`TakeProfit`) ma parte su `Disabled`. Portandolo su
`Automatic` o `Manual` torna in funzione.

Esprimere lo stop **in prezzo** e non in punti lo rende indipendente dalle cifre decimali
del broker: 0.90 vale 0.90 dollari sia su un XAUUSD a due decimali sia su uno a tre,
mentre "90 punti" varrebbe 0.90 sul primo e 0.09 sul secondo. `ManualStopLossPoints`
resta disponibile per chi preferisce ragionare in punti: basta mettere
`StopLossPriceDistance = 0`.

### 4. Livelli virtuali
Con `UseVirtualLevels = true` (impostazione del video) stop e trailing **non** vengono
inviati al broker: l'EA li conserva in variabili globali del terminale (quindi
sopravvivono a un riavvio) e chiude a mercato quando il prezzo li tocca, con la stessa
semantica del server — un acquisto esce sul Bid, una vendita sull'Ask. Il grafico resta
pulito, come nel filmato.

La rete di sicurezza e' `UseEmergencyBrokerStop`: uno stop reale, largo
`EmergencyStopFactor` volte quello logico, viene comunque registrato sul server. Serve a
una sola cosa, ma importante: se il terminale si spegne, la posizione non resta scoperta.

Impostando `UseVirtualLevels = false` l'EA torna al comportamento classico, con SL e TP sul
broker e trailing via `OrderModify`.

### 5. SAR (Stop And Reverse)
Quando una posizione viene chiusa **in perdita** sul proprio stop, l'EA apre subito la
posizione opposta. Un'uscita in profitto — trailing compreso — non innesca nulla. Vale sia per gli stop virtuali sia per le chiusure decise dal broker
(stop di emergenza, stop out, chiusura manuale): la scomparsa di un ticket viene
riconosciuta confrontando lo stato degli ordini con quello del tick precedente.

Due limiti proteggono dal loop:

- un reversal appena eseguito esaurisce il tick, quindi l'EA non apre anche il verso
  opposto nello stesso istante;
- `MaxSarChain` limita i reversal consecutivi. Il preset lo lascia a `0` (illimitati,
  come nel video): su un conto reale un valore di 2 o 3 e' molto piu' prudente.

### 6. Livelli automatici
`TakeProfit`, `StopLoss` e `TrailingStop` sono enumerazioni con tre stati:
`Automatic`, `Manual`, `Disabled`.

Il preset usa `TakeProfit = Disabled`, `StopLoss = Manual` (0.90 di prezzo) e
`TrailingStop = Automatic`. In modalita' `Automatic` le distanze si ricavano dall'ATR del
timeframe operativo, quindi seguono da sole la volatilita':

| Livello | Formula | Default | XAUUSD M5 con ATR ~200 punti |
|---|---|---|---|
| Take profit | `AutoTP_ATR * ATR` | 0.25 | ~50 punti (spento nel preset) |
| Stop loss | `AutoSL_ATR * ATR` | 0.50 | ~100 punti (sostituito dal fisso 0.90) |
| Trailing | `AutoTS_ATR * ATR` | 0.35 | ~70 punti |

Il fattore del trailing e' 0.35 e non un valore piu' stretto per una ragione precisa:
essendo l'**unica** uscita in profitto, un trailing troppo corto taglierebbe il movimento
dentro il rumore invece di lasciarlo correre. Con ~70 punti di trailing e 90 punti di
stop, il trailing entra in gioco quando il guadagno supera circa 70 punti piu' lo spread.

In modalita' `Manual` valgono `ManualTakeProfitPoints`, `ManualStopLossPoints` e
`ManualTrailingPoints`; `StopLossPriceDistance` e `TrailingPriceDistance`, se maggiori di
zero, hanno la precedenza e si esprimono in prezzo. Sul take profit, quando e' attivo,
agiscono due vincoli: non puo' valere meno di `AutoTP_MinSpreadRatio` volte lo spread
corrente e, con i livelli sul broker, non puo' violare `MODE_STOPLEVEL`.

### 7. Protezioni di paniere
- **`Total SL [points]`** — somma algebrica dei punti a mercato di tutte le posizioni
  dell'EA. Sotto la soglia negativa il paniere viene chiuso. `0` disattiva.
- **`DailyProfit`** — realizzato piu' flottante della giornata. Raggiunto l'obiettivo l'EA
  chiude tutto e resta fermo fino al giorno successivo. `0` disattiva.
- **`MaxDD`** — stessa misura, sul lato della perdita. `0` disattiva.

Entrambi i limiti giornalieri sono in valuta del conto; con `DailyLimitsInPercent = true`
vengono letti come percentuale del saldo di inizio giornata.

### 8. Filtri temporali
- `Trading24h` ignora le finestre orarie ma **non** i giorni disabilitati.
- Le finestre sono in **ora del server**, non locale, e possono scavalcare la mezzanotte
  (`22:00` - `02:00` funziona). Start uguale a End significa 24 ore.
- `TradingNonFarmFriday = false` esclude il primo venerdi' del mese (giorno NFP).
- `TradingDuringHolidays = false` esclude la finestra 12 dicembre - 12 gennaio.

### 9. Filtro notizie
Con `NewsFilter = true` l'EA scarica il calendario da `NewsCalendarUrl` (di default il feed
settimanale di Forex Factory), tiene gli eventi delle valute selezionate con
`Report for USD/EUR/GBP/JPY` e, se `NewsHighImpactOnly` e' attivo, solo quelli ad alto
impatto. Il trading si ferma da `doNotTradeBeforeInMinutes` prima a
`doNotTradeAfterInMinutes` dopo ogni evento. Con `CloseBeforeNews` le posizioni aperte
vengono chiuse all'inizio della finestra.

L'ora del server rispetto a GMT viene dedotta da sola (`TimeCurrent() - TimeGMT()`);
`NewsFeedGmtOffset` dichiara il fuso del feed. Gli eventi caricati vengono scritti nel
journal con l'orario gia' convertito: **verificare un evento noto** e' il modo piu' rapido
per accorgersi che l'offset e' sbagliato.

Due limiti da conoscere:

- `WebRequest` non funziona nello Strategy Tester. In backtest il filtro usa solo gli
  orari elencati in `ManualNewsTimes` (formato `YYYY.MM.DD HH:MM;YYYY.MM.DD HH:MM`).
- Se l'URL non e' fra quelli autorizzati in MT4, il journal riporta l'errore 4060 e il
  pannello segnala `URL non autorizzato`: l'EA continua a operare **senza** filtro.

### 10. Pannello
Con `showPanel = true` compare un riquadro con simbolo e timeframe, spread e stop level,
ATR, TP/SL/trailing correnti in punti (`off` quando un livello non esiste), direzione e stato del SAR, ordini aperti e lotto,
flottante, risultato della giornata, stato della sessione, stato del filtro notizie e
ultimo filtro che ha bloccato un ingresso. Si aggiorna una volta al secondo.

## Parametri del preset

| Parametro | Valore | Significato |
|---|---|---|
| `TradeDirection` | BuyAndSell | entrambi i versi, anche contemporaneamente |
| `SAR` | true | reversal immediato dopo uno stop in perdita |
| `Lots` | 0.01 | lotto fisso, riallineato al passo del broker |
| `Magic` | 888777 | identificativo delle operazioni dell'EA |
| `TradeComment` | Scalp EA | commento degli ordini |
| `EntryDistance` | 30 | punti di rottura e distanza minima tra ordini dello stesso verso |
| `TakeProfit` | Disabled | nessun obiettivo di prezzo |
| `StopLoss` | Manual | distanza fissa, `StopLossPriceDistance` = 0.90 |
| `TrailingStop` | Automatic | 0.35 x ATR, unica uscita in profitto |
| `maxOrders` | 1 | una posizione alla volta |
| `DailyProfit` / `MaxDD` / `Total SL` | 0 | protezioni di paniere disattivate |
| `Trading24h` | true | nessun vincolo orario |
| `Monday`...`Friday` | true | tutti i giorni feriali abilitati |
| `NewsFilter` | true | filtro notizie attivo, 60 minuti prima e dopo |
| `Report for USD` / `EUR` | true | valute sorvegliate |
| `Report for GBP` / `JPY` | false | ignorate |
| `showPanel` | true | pannello visibile |

I primi 40 input riproducono nome, ordine e valore del set allegato; il blocco `ADVANCED`
che segue espone i coefficienti del motore automatico e le sicurezze, ed e' l'unica parte
aggiunta.

## Note operative

- **`EntryDistance` e' in punti, non in pip.** Su un XAUUSD quotato a due decimali
  30 punti valgono 0.30 dollari. Su un broker a tre decimali gli stessi 30 punti valgono
  0.03: prima di usare il preset su un altro server, controllare `Digits`. Lo stop e il
  trailing, espressi in prezzo, non hanno questo problema.
- **Senza take profit il profilo del rischio cambia.** Lo stop rischia 90 punti; il
  trailing, quando si attiva, blocca all'inizio circa 70 punti meno lo spread. Le
  operazioni vincenti utili sono quelle che scappano, non quelle che si fermano appena
  oltre la soglia: il sistema vive sulla coda destra della distribuzione, non sulla
  percentuale di vincite. E' esattamente il compromesso opposto a quello di uno scalper
  con take profit stretto, e va verificato su un numero di trade sufficiente a vedere
  quella coda.
- Il preset lascia `MaxSpreadPoints = 0`, cioe' nessun filtro sullo spread, com'e' nel
  video. Su conti reali vale la pena impostarlo a circa il doppio dello spread tipico:
  un TP di 50 punti con 40 punti di spread non e' un'operazione, e' una commissione.
- `DailyProfit`, `MaxDD` e `Total SL` sono a zero nel preset. Sono le tre protezioni che
  conviene accendere per prime quando si passa dal test al conto reale.
- Con `SAR` senza limiti e senza protezioni di paniere, una fase laterale stretta produce
  una catena di reversal in perdita. E' il rischio strutturale di questo schema: va
  misurato in backtest, non stimato.
- Backtest in modalita' `Every tick` con dati tick di qualita': con TP di poche decine di
  punti, i dati M1 interpolati danno risultati privi di significato. Verificare anche che
  lo spread simulato sia realistico.

## Struttura del codice

| Sezione | Funzioni principali |
|---|---|
| Livelli | `AtrPoints`, `TakeProfitPoints`, `StopLossPoints`, `TrailingPoints`, `MinBrokerDistance` |
| Filtri | `TimeAllowed`, `IsNonFarmFriday`, `IsHolidayPeriod`, `NewsBlocked`, `LoadNewsCalendar` |
| Ordini | `TryOpenPosition`, `ClosePositionByTicket`, `CloseAllPositions`, `SpacingOk` |
| Livelli virtuali | `EnsureLevels`, `StoreLevels`, `ForgetLevels`, `ManageOpenPositions` |
| SAR | `SnapshotOpenTickets`, `DetectBrokerClosures`, `QueueSar`, `ProcessSarQueue` |
| Paniere | `CheckBasketLimits`, `DayProfit`, `RealizedToday`, `FloatingPoints` |
| Interfaccia | `BuildPanel`, `PanelRow`, `UpdatePanel` |
