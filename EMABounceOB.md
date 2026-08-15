# EMA Bounce & Order Block EA v1.00 (MQL4 / MetaTrader 4)

Expert Advisor di **trend continuation** per XAUUSD su M5, con **dashboard esterna** separata
dall'EA.

| File | Cartella MT4 | Ruolo |
|---|---|---|
| `MQL4/Experts/EMABounceOrderBlockEA.mq4` | `MQL4/Experts/` | Motore operativo |
| `MQL4/Indicators/EMABounceOB_Dashboard.mq4` | `MQL4/Indicators/` | Pannello di monitoraggio |

## Installazione

1. In MetaTrader 4: `File -> Apri cartella dati`.
2. Copiare `EMABounceOrderBlockEA.mq4` in `MQL4/Experts/` e `EMABounceOB_Dashboard.mq4` in
   `MQL4/Indicators/`.
3. In MetaEditor premere `F7` su entrambi i file.
4. Trascinare l'EA sul grafico **XAUUSD M5**, abilitare l'AutoTrading.
5. Trascinare la dashboard su un grafico qualsiasi — anche di un altro simbolo, anche su un
   secondo monitor. Non serve configurarla: rileva le istanze da sola.

## La logica in tre piani

L'EA non cerca inversioni. Cerca il punto in cui un trend gia' in corso riprende dopo un
ritracciamento. Tre piani devono essere d'accordo.

### 1. Bias — dove si puo' operare (default M15)

EMA 21 / EMA 55 sul timeframe superiore, con **pendenza e separazione misurate in ATR**, non in
punti: su oro due dollari sono molto o poco a seconda della volatilita' del momento. Il bias
definisce l'unica direzione ammessa; senza bias non si opera in nessuna delle due.

Su M5 il trend letto localmente e' rumore. Il contesto si legge sopra, l'esecuzione avviene sotto.

### 2. EMA Dynamic Bounce — quando il ritracciamento e' finito (M5)

La coppia EMA 21 / EMA 50 non e' una linea, e' una **banda**, allargata di `ZoneBufferATR` volte
l'ATR. Su M5 il prezzo non tocca la media al centesimo: senza tolleranza dinamica il rimbalzo non
si vede proprio.

Il rimbalzo e' valido quando, entro `BounceLookback` barre:

- il minimo (o massimo) e' entrato nella banda;
- **nessuna chiusura** e' avvenuta oltre la banda — una chiusura oltre non e' un ritracciamento,
  e' un cambio di struttura;
- l'ultima barra chiusa respinge con un rifiuto misurabile: ombra oltre `MinWickRatio` del range
  **oppure** corpo oltre `MinBodyRatio`, con chiusura nella meta' giusta della banda.

### 3. Order Block — dove sta lo stop

L'order block e' l'**ultima candela opposta prima dell'impulso** che rompe la struttura:

- impulso di almeno `OB_MinImpulseATR` volte l'ATR entro `OB_ImpulseBars` barre;
- rottura dello swing precedente (BOS) se `OB_RequireBOS = true` — senza BOS non c'e'
  continuazione, c'e' solo una candela grande;
- la zona resta valida finche' il prezzo non la richiude oltre (`OB_MitigateOnClose`), non oltre
  `OB_MaxAgeBars` barre e non oltre `OB_MaxTouches` tocchi: una zona toccata tre volte ha gia'
  distribuito i suoi ordini.

Lo stop nasce **sotto l'order block**, non a un multiplo fisso dell'ATR. E' questo il motivo per
cui vale la pena cercarlo.

## Confluenza: il punteggio

I tre piani producono un punteggio 0-100:

| Componente | Punti |
|---|---|
| Rimbalzo dinamico confermato sulla banda EMA | 30 |
| Order block valido toccato dal ritracciamento | 30 |
| Order block sovrapposto alla banda EMA (doppia confluenza) | 10 |
| Rottura di struttura recente nella direzione del bias | 10 |
| Bias forte (forza >= 60) | 10 |
| Momentum RSI dal lato giusto | 10 |

- `EntryMode = ENTRY_CONFLUENCE` (default): servono rimbalzo **e** order block, piu' il punteggio
  minimo. E' la modalita' fedele al nome della strategia.
- `EntryMode = ENTRY_SCORE`: decide solo il punteggio. Serve a testare quanto pesa davvero ogni
  componente prima di irrigidire i requisiti.

Il punteggio non e' un abbellimento: e' cio' che permette di allentare un requisito **sapendo
di quanto** lo si sta allentando.

## Gestione del rischio

- **Sizing**: `lotti = rischio / ((distanzaSL / TICKSIZE) * TICKVALUE + CommissionPerLot)`,
  normalizzato su `MODE_LOTSTEP`, `MODE_MINLOT`, `MODE_MAXLOT`, con verifica del margine libero e
  tetto `MaxLotCap`. Se il lotto minimo del broker eccede il budget di rischio di oltre il 50%,
  l'operazione viene annullata invece di essere aperta sovradimensionata.
- **Quattro controlli prima di ogni ordine**, ognuno dei quali scarta il trade:
  1. lo `STOPLEVEL` del broker supera `MaxStopLevelATR` volte l'ATR — il timeframe e' incompatibile
     con quel broker in quel momento;
  2. lo stop tecnico supera `MaxSL_ATR` volte l'ATR, anche dopo l'allargamento imposto dai vincoli;
  3. il take profit non copre `MinTPCostRatio` volte spread + commissioni;
  4. il rapporto R:R residuo scende sotto `MinRiskReward`.
- **Gestione in R**, non in pips: parziale a `PartialAtR`, break-even a `BE_TriggerR`, trailing da
  `TrailStartR`. Le soglie restano valide al variare di volatilita', simbolo e conto.
- **Limiti**: trade giornalieri, stop giornaliero in %, target giornaliero opzionale, pausa dopo
  `MaxConsecutiveLosses` perdite consecutive, cooldown in barre.
- **Uscite programmate**: tempo massimo in posizione, fine sessione, venerdi', inversione del bias.

Il trailing ha quattro modalita': `TRAIL_ATR` (default), `TRAIL_EMA` (segue la EMA veloce),
`TRAIL_STRUCT` (segue gli swing), `TRAIL_OFF`.

## Esecuzione

- `EXEC_MARKET` (default): ingresso a mercato alla chiusura della barra di conferma.
- `EXEC_LIMIT`: ordine limite dentro l'order block, a profondita' `LimitEntryDepth`, con scadenza
  in barre. Riempimento incerto, ingresso migliore. L'ordine viene rimosso se scade o se il bias
  non e' piu' coerente.

Gestiti: retry con backoff, errore 130 (apertura senza stop e modifica immediata), errore 147
(scadenza rifiutata dal broker, ritentata senza), broker ECN con `TwoStepStops`, freeze level.
In MT4 una chiusura parziale genera un **nuovo ticket**: l'EA traccia le posizioni per
(tipo, ora, prezzo di apertura), cosi' il rischio iniziale — e con esso il significato di "1R" —
non va perso.

## La dashboard esterna

L'EA **non disegna pannelli**. Pubblica il proprio stato su GlobalVariables del terminale:

```
EBOB_<SIMBOLO>_<MAGIC>_<chiave>
```

La dashboard e' un indicatore autonomo che legge quelle chiavi. Tre conseguenze pratiche:

1. il pannello sta su un grafico dedicato e non copre quello operativo;
2. **un solo pannello vede tutte le istanze dell'EA** sul terminale — se ne hai piu' di una, in
   fondo compaiono i pulsanti per passare dall'una all'altra con un clic;
3. il disegno non pesa sul thread dell'EA: rimuovere la dashboard non cambia una virgola
   dell'operativita'.

Se l'EA viene fermato, il pannello **resta con l'ultimo stato noto e lo marca OFFLINE** con l'eta'
del dato. Distinguere "fermo" da "non ci sono dati" e' meta' del valore di un pannello di
monitoraggio.

### Cosa mostra

| Sezione | Contenuto |
|---|---|
| Trend bias | direzione ammessa, forza 0-100 con barra, timeframe |
| Banda EMA dinamica | estremi, prezzo dentro/fuori, rimbalzo, BOS, momentum |
| Order block | zone valide in memoria, zona attiva, estremi, eta', tocchi, impulso in ATR |
| Segnale | stato operativo, confluenza con barra, ultimo segnale, **ultimo blocco**, cooldown |
| Posizione | direzione, volume, ingresso, SL, TP, P/L, **multiplo di R**, barre |
| Prossimo trade | volume stimato, rischio, SL/TP calcolati, R:R, trade oggi |
| Mercato | ATR, spread, **spread/ATR con barra**, stop level, sessione, prossima barra |
| Conto | equity, saldo, P/L giornata con barra del limite, netto, win rate, profit factor, serie |

Il campo piu' utile e' **Ultimo blocco**: dice in chiaro perche' l'EA non sta operando —
spread, sessione, confluenza sotto soglia, order block assente, stop level del broker, limiti
giornalieri.

### Parametri della dashboard

`FilterSymbol` (`""` = tutti, `"CURRENT"` = simbolo del grafico), `FilterMagic`, `StaleSeconds`
(soglia OFFLINE), `RefreshSecs`, piu' posizione, larghezza colonna, font e colori.

## Configurazione di partenza per XAUUSD M5

I default del file sono gia' questi.

| Parametro | Valore | Nota |
|---|---|---|
| `EntryTimeframe` / `BiasTimeframe` | M5 / M15 | H1 come bias rende l'EA piu' selettivo |
| `EMA_Fast_Period` / `EMA_Slow_Period` | 21 / 50 | banda dinamica |
| `ZoneBufferATR` | 0.20 | tolleranza del tocco |
| `OB_MinImpulseATR` | 1.20 | soglia dell'impulso |
| `OB_RequireBOS` | true | niente BOS, niente order block |
| `MinConfluenceScore` | 60 | con ENTRY_CONFLUENCE equivale a rimbalzo + OB |
| `SL_BufferATR` / `MinSL_ATR` / `MaxSL_ATR` | 0.35 / 0.50 / 2.50 | stop tecnico e suoi limiti |
| `TP_RMultiple` / `MinRiskReward` | 2.00 / 1.50 | |
| `RiskPercent` | 1.0 | |
| `MaxSpreadPips` / `MaxSpreadToATR` | 3.5 / 0.15 | 1 pip oro = 0.10 USD |
| `MaxTradesPerDay` / `MaxDailyLossPercent` | 6 / 3.0 | |
| `UseSessionFilter` | 8-21 server time | London + NY |
| `MaxBarsInTrade` | 96 | 8 ore su M5 |
| `CommissionPerLot` | 0.0 | **da impostare** con la commissione reale round-turn |

## Note operative

- **Imposta `CommissionPerLot`** con il valore reale del tuo conto: entra sia nel sizing sia nel
  controllo di copertura del take profit. Su oro con lotti piccoli la commissione pesa piu' dello
  spread.
- Le ore di sessione sono in **ora del server**, non locale: verificale sul tuo broker.
- Su M5 la variabile critica e' il **rapporto spread/ATR**. La dashboard lo mostra in percentuale
  con una barra: se sta stabilmente sopra il 10-12%, quel timeframe non e' sostenibile su quel
  broker, e nessuna taratura dei parametri lo rende sostenibile.
- Se l'EA non entra mai, guarda **Ultimo blocco** sulla dashboard prima di toccare i parametri:
  quasi sempre il motivo e' uno solo e specifico.
- Nel tester la dashboard funziona solo in **modalita' visiva**, applicandola al grafico del
  tester. I default sono punti di partenza ragionevoli, non parametri ottimizzati: backtest su
  "Every tick" con dati tick di qualita', poi walk-forward, poi demo. Sotto un centinaio di trade
  il risultato non e' interpretabile.
- Il commento degli ordini riporta la direzione e il punteggio di confluenza (`EBOB-B75`): nel
  backtest permette di verificare se i trade a punteggio alto rendono davvero piu' degli altri.
  Se non lo fanno, il punteggio va ritarato — o la logica non sta misurando cio' che crede.
