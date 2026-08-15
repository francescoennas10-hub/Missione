//+------------------------------------------------------------------+
//|                                    EMABounceOrderBlockEA.mq4      |
//|        Trend Continuation - EMA Dynamic Bounce & Order Block      |
//|                      v1.00 - XAUUSD / M5                          |
//|                                                                   |
//|  LOGICA                                                           |
//|   L'EA non cerca inversioni: cerca la CONTINUAZIONE del trend.    |
//|   Tre piani sovrapposti, tutti e tre devono essere d'accordo.     |
//|                                                                   |
//|   1. BIAS (timeframe superiore, default M15)                      |
//|      EMA veloce sopra/sotto EMA lenta, pendenza misurata in ATR   |
//|      e prezzo dal lato giusto. Definisce la sola direzione        |
//|      ammessa. Su M5 il trend letto localmente e' rumore: il bias  |
//|      si legge sopra e si opera sotto.                             |
//|                                                                   |
//|   2. EMA DYNAMIC BOUNCE (timeframe di ingresso, default M5)       |
//|      La coppia EMA veloce/lenta forma una BANDA dinamica, non     |
//|      una linea. Il ritracciamento e' valido quando il minimo      |
//|      entra nella banda (allargata di una frazione di ATR) e una   |
//|      barra successiva la respinge con corpo e/o ombra             |
//|      significativi, senza mai chiudere oltre la banda.            |
//|                                                                   |
//|   3. ORDER BLOCK                                                  |
//|      L'ultima candela opposta prima dell'impulso che rompe la     |
//|      struttura (BOS). La zona resta valida finche' il prezzo non  |
//|      la richiude oltre. L'ingresso avviene quando il              |
//|      ritracciamento TOCCA l'order block: e' li' che si trova lo   |
//|      stop tecnico, non a una distanza arbitraria.                 |
//|                                                                   |
//|   CONFLUENZA                                                      |
//|      I tre piani producono un punteggio 0-100. In modalita'       |
//|      ENTRY_CONFLUENCE servono rimbalzo EMA + order block toccato  |
//|      + punteggio minimo; in ENTRY_SCORE basta il punteggio.       |
//|      Cio' che non raggiunge la soglia non viene eseguito in       |
//|      versione degradata: viene scartato e registrato.             |
//|                                                                   |
//|  ADATTAMENTO A XAUUSD M5                                          |
//|   - pip dell'oro = 0.10 USD, riconosciuto automaticamente;        |
//|   - filtro spread assoluto E in rapporto all'ATR (su M5 e' il     |
//|     secondo che decide la sostenibilita' del timeframe);          |
//|   - stop tecnico sotto l'order block, con controllo dello         |
//|     STOPLEVEL del broker: se il vincolo e' incompatibile con la   |
//|     volatilita', il trade viene scartato;                         |
//|   - sessione operativa, limiti giornalieri, serie di perdite.     |
//|                                                                   |
//|  DASHBOARD ESTERNA                                                |
//|   L'EA non disegna pannelli: PUBBLICA il proprio stato su         |
//|   GlobalVariables del terminale con prefisso                      |
//|        EBOB_<SIMBOLO>_<MAGIC>_<chiave>                            |
//|   L'indicatore EMABounceOB_Dashboard.mq4 puo' essere applicato a  |
//|   QUALSIASI grafico (anche di un altro simbolo) e legge da li'.   |
//|   Piu' istanze dell'EA su simboli diversi vengono rilevate e      |
//|   mostrate insieme. Elenco completo delle chiavi in fondo al      |
//|   file, sezione TELEMETRIA.                                       |
//+------------------------------------------------------------------+
#property copyright "EMA Bounce & Order Block EA"
#property link      ""
#property version   "1.00"
#property strict
#property description "Trend continuation su XAUUSD M5: rimbalzo dinamico sulla banda EMA in confluenza con Order Block."
#property description "Stato pubblicato su GlobalVariables e letto dalla dashboard esterna EMABounceOB_Dashboard."

//+------------------------------------------------------------------+
//| Costanti interne                                                 |
//+------------------------------------------------------------------+
#define MAX_OB       16   // Order block memorizzati per lato
#define MAX_TRACK    16   // Posizioni tracciate contemporaneamente
#define GV_PREFIX    "EBOB_"

//+------------------------------------------------------------------+
//| Enumerazioni                                                     |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_MODE
  {
   ENTRY_CONFLUENCE = 0,  // Rimbalzo EMA + Order Block + punteggio
   ENTRY_SCORE      = 1   // Solo punteggio di confluenza
  };

enum ENUM_EXEC_MODE
  {
   EXEC_MARKET = 0,       // Ingresso a mercato alla conferma
   EXEC_LIMIT  = 1        // Ordine limite sul bordo dell'order block
  };

enum ENUM_TP_MODE
  {
   TP_RMULTIPLE = 0,      // Take profit come multiplo del rischio
   TP_STRUCTURE = 1       // Take profit sulla struttura (con fallback a R)
  };

enum ENUM_TRAIL_MODE
  {
   TRAIL_OFF    = 0,      // Nessun trailing
   TRAIL_ATR    = 1,      // Trailing a distanza ATR
   TRAIL_EMA    = 2,      // Trailing sulla EMA veloce
   TRAIL_STRUCT = 3       // Trailing sull'ultimo swing
  };

enum ENUM_OB_ZONE
  {
   OB_FULL = 0,           // Zona = intero range della candela (high-low)
   OB_BODY = 1            // Zona = solo corpo della candela
  };

enum ENUM_PIP_MODE
  {
   PIP_AUTO   = 0,        // Automatico in base alla classe del simbolo
   PIP_FOREX  = 1,        // Forex classico (5/3 cifre = Point*10)
   PIP_POINT  = 2,        // 1 pip = 1 Point
   PIP_CUSTOM = 3         // Valore definito in CustomPipSize
  };

enum ENUM_RISK_BASE
  {
   RISK_ON_BALANCE = 0,   // Rischio calcolato sul Balance
   RISK_ON_EQUITY  = 1    // Rischio calcolato sull'Equity
  };

enum ENUM_SYMBOL_CLASS
  {
   SYMBOL_FOREX  = 0,     // Coppia valutaria
   SYMBOL_GOLD   = 1,     // Oro
   SYMBOL_SILVER = 2,     // Argento
   SYMBOL_OTHER  = 3      // Indice / CFD / altro
  };

//--- Codici di stato pubblicati alla dashboard
#define ST_INIT      0
#define ST_NOBIAS    1
#define ST_WAITPB    2
#define ST_INZONE    3
#define ST_ARMED     4
#define ST_INPOS     5
#define ST_BLOCKED   6
#define ST_FILTER    7

//--- Codici di scarto pubblicati alla dashboard
#define REJ_NONE         0
#define REJ_SPREAD       1
#define REJ_SPREAD_ATR   2
#define REJ_SESSION      3
#define REJ_DAILY_TRADES 4
#define REJ_DAILY_LOSS   5
#define REJ_DAILY_TARGET 6
#define REJ_COOLDOWN     7
#define REJ_MAXPOS       8
#define REJ_STOPLEVEL    9
#define REJ_SL_WIDE     10
#define REJ_SL_TIGHT    11
#define REJ_RR          12
#define REJ_LOTS        13
#define REJ_SEND        14
#define REJ_BARS        15
#define REJ_NOOB        16
#define REJ_NOBOUNCE    17
#define REJ_SCORE       18
#define REJ_LOSSSTREAK  19
#define REJ_NOBIAS      20

//+------------------------------------------------------------------+
//| INPUT: Timeframe                                                 |
//+------------------------------------------------------------------+
input string           s_tf              = "===== TIMEFRAME =====";
input ENUM_TIMEFRAMES  EntryTimeframe    = PERIOD_M5;   // Timeframe operativo (ingresso)
input ENUM_TIMEFRAMES  BiasTimeframe     = PERIOD_M15;  // Timeframe del bias di trend
input bool             NewBarOnly        = true;        // Valuta i segnali solo a barra chiusa

//+------------------------------------------------------------------+
//| INPUT: Bias di trend (timeframe superiore)                       |
//+------------------------------------------------------------------+
input string           s_bias            = "===== TREND BIAS =====";
input int              Bias_EMA_Fast     = 21;     // EMA veloce del bias
input int              Bias_EMA_Slow     = 55;     // EMA lenta del bias
input int              Bias_SlopeBars    = 5;      // Barre per misurare la pendenza
input double           Bias_MinSlopeATR  = 0.05;   // Pendenza minima della EMA lenta (in ATR)
input double           Bias_MinSepATR    = 0.10;   // Separazione minima tra le EMA (in ATR)
input bool             Bias_RequirePrice = true;   // Il prezzo deve stare dal lato giusto della EMA lenta

//+------------------------------------------------------------------+
//| INPUT: Banda EMA dinamica e rimbalzo (timeframe di ingresso)     |
//+------------------------------------------------------------------+
input string           s_zone            = "===== EMA DYNAMIC BOUNCE =====";
input int              EMA_Fast_Period   = 21;     // EMA veloce della banda
input int              EMA_Slow_Period   = 50;     // EMA lenta della banda
input double           ZoneBufferATR     = 0.20;   // Allargamento della banda (frazione di ATR)
input int              BounceLookback    = 4;      // Entro quante barre deve essere avvenuto il tocco
input double           MinWickRatio      = 0.30;   // Ombra di rifiuto minima (frazione del range)
input double           MinBodyRatio      = 0.45;   // In alternativa: corpo minimo (frazione del range)
input bool             RequireCloseBeyondFast = false; // La conferma deve chiudere oltre la EMA veloce
input bool             RequireBounce     = true;   // Il rimbalzo EMA e' obbligatorio

//+------------------------------------------------------------------+
//| INPUT: Order Block                                               |
//+------------------------------------------------------------------+
input string           s_ob              = "===== ORDER BLOCK =====";
input bool             UseOrderBlocks    = true;   // Attiva il motore degli order block
input ENUM_OB_ZONE     OB_ZoneMode       = OB_FULL;// Zona: intero range o solo corpo
input int              OB_ImpulseBars    = 3;      // Barre di impulso dopo la candela di origine
input double           OB_MinImpulseATR  = 1.20;   // Ampiezza minima dell'impulso (in ATR)
input bool             OB_RequireBOS     = true;   // L'impulso deve rompere la struttura (BOS)
input int              OB_SwingStrength  = 2;      // Barre per lato che definiscono uno swing
input int              OB_StructureBars  = 30;     // Barre in cui cercare lo swing di riferimento
input int              OB_ScanBars       = 300;    // Barre analizzate alla partenza
input int              OB_MaxAgeBars     = 150;    // Eta' massima di un order block (barre)
input int              OB_MaxTouches     = 2;      // Tocchi oltre i quali la zona e' consumata
input double           OB_ProximityATR   = 0.30;   // Tolleranza di contatto con la zona (in ATR)
input bool             OB_MitigateOnClose= true;   // Invalidazione alla chiusura oltre la zona
input bool             RequireOrderBlock = true;   // L'order block e' obbligatorio

//+------------------------------------------------------------------+
//| INPUT: Confluenza e modalita' di ingresso                        |
//+------------------------------------------------------------------+
input string           s_entry           = "===== ENTRY =====";
input ENUM_ENTRY_MODE  EntryMode         = ENTRY_CONFLUENCE; // Criterio di ingresso
input int              MinConfluenceScore= 60;     // Punteggio minimo di confluenza (0-100)
input ENUM_EXEC_MODE   ExecutionMode     = EXEC_MARKET; // Esecuzione a mercato o con limite
input double           LimitEntryDepth   = 0.50;   // Limite: profondita' nella zona (0=bordo, 1=fondo)
input int              PendingExpiryBars = 6;      // Barre di validita' dell'ordine limite
input bool             UseMomentumFilter = true;   // Filtro di momentum (RSI)
input int              RSI_Period        = 14;     // Periodo RSI
input double           RSI_BullMin       = 45.0;   // RSI minimo per i long
input double           RSI_BearMax       = 55.0;   // RSI massimo per gli short

//+------------------------------------------------------------------+
//| INPUT: Stop, target e volatilita'                                |
//+------------------------------------------------------------------+
input string           s_stops           = "===== STOP & TARGET =====";
input int              ATR_Period        = 14;     // Periodo ATR
input double           SL_BufferATR      = 0.35;   // Margine dello stop oltre la zona (in ATR)
input double           MinSL_ATR         = 0.50;   // Stop minimo consentito (in ATR)
input double           MaxSL_ATR         = 2.50;   // Stop massimo consentito (in ATR)
input ENUM_TP_MODE     TakeProfitMode    = TP_RMULTIPLE; // Criterio del take profit
input double           TP_RMultiple      = 2.00;   // Take profit in multipli del rischio
input int              TP_StructureBars  = 60;     // Barre in cui cercare il target strutturale
input double           MinRiskReward     = 1.50;   // R:R minimo accettato
input double           StopBufferPips    = 2.0;    // Margine oltre lo STOPLEVEL del broker (pips)
input double           MaxStopLevelATR   = 0.80;   // STOPLEVEL massimo ammesso (frazione di ATR)
input double           MinTPCostRatio    = 4.0;    // Il TP deve valere N volte spread+commissioni

//+------------------------------------------------------------------+
//| INPUT: Gestione del rischio                                      |
//+------------------------------------------------------------------+
input string           s_risk            = "===== RISK MANAGEMENT =====";
input double           RiskPercent       = 1.0;    // Rischio % del capitale per operazione
input ENUM_RISK_BASE   RiskBase          = RISK_ON_BALANCE; // Base di calcolo del rischio
input double           FixedLots         = 0.0;    // Lotto fisso (0 = calcolo automatico)
input double           MaxLotCap         = 10.0;   // Tetto massimo di lotti per operazione
input double           CommissionPerLot  = 0.0;    // Commissione round-turn per lotto (valuta conto)
input int              MaxOpenPositions  = 1;      // Posizioni contemporanee massime
input int              CooldownBars      = 3;      // Barre di attesa dopo l'ultimo trade
input int              MagicNumber       = 20250816; // Magic Number
input string           TradeComment      = "EBOB"; // Commento ordini

//+------------------------------------------------------------------+
//| INPUT: Limiti giornalieri                                        |
//+------------------------------------------------------------------+
input string           s_daily           = "===== DAILY LIMITS =====";
input int              MaxTradesPerDay   = 6;      // Trade massimi al giorno (0 = illimitato)
input double           MaxDailyLossPercent= 3.0;   // Stop giornaliero in % (0 = disattivo)
input double           DailyProfitTarget = 0.0;    // Target giornaliero in % (0 = disattivo)
input bool             IncludeFloatingInDD= false; // Includi il flottante nei limiti giornalieri
input int              MaxConsecutiveLosses= 3;    // Perdite consecutive prima della pausa (0 = off)
input int              PauseBarsAfterLosses= 24;   // Barre di pausa dopo la serie di perdite

//+------------------------------------------------------------------+
//| INPUT: Gestione della posizione                                  |
//+------------------------------------------------------------------+
input string           s_manage          = "===== POSITION MANAGEMENT =====";
input bool             UsePartialClose   = true;   // Chiusura parziale al primo obiettivo
input double           PartialAtR        = 1.00;   // Parziale a N volte il rischio
input double           PartialPercent    = 50.0;   // Percentuale di volume chiusa al parziale
input bool             UseBreakEven      = true;   // Attiva il break-even
input double           BE_TriggerR       = 1.00;   // Break-even dopo N volte il rischio
input double           BE_LockR          = 0.10;   // Profitto bloccato al break-even (in R)
input ENUM_TRAIL_MODE  TrailMode         = TRAIL_ATR; // Modalita' di trailing stop
input double           TrailStartR       = 1.20;   // Avvio del trailing (in R)
input double           TrailATR          = 1.20;   // Distanza del trailing (in ATR)
input double           TrailStepATR      = 0.15;   // Passo minimo del trailing (in ATR)
input double           TrailBufferATR    = 0.25;   // Margine del trailing su EMA/struttura (in ATR)
input int              MaxBarsInTrade    = 96;     // Chiusura dopo N barre (0 = disattivo)
input bool             CloseOnBiasFlip   = true;   // Chiudi se il bias superiore si inverte

//+------------------------------------------------------------------+
//| INPUT: Sessione (ora del server)                                 |
//+------------------------------------------------------------------+
input string           s_session         = "===== SESSION FILTER =====";
input bool             UseSessionFilter  = true;   // Opera solo nella finestra indicata
input int              SessionStartHour  = 8;      // Ora di inizio (server time)
input int              SessionEndHour    = 21;     // Ora di fine (server time, esclusa)
input bool             CloseAtSessionEnd = true;   // Chiudi le posizioni a fine sessione
input int              FridayCloseHour   = 20;     // Venerdi': stop ingressi da quest'ora (0 = off)
input bool             CloseAllOnFriday  = true;   // Chiudi tutto al FridayCloseHour

//+------------------------------------------------------------------+
//| INPUT: Esecuzione                                                |
//+------------------------------------------------------------------+
input string           s_exec            = "===== EXECUTION =====";
input ENUM_PIP_MODE    PipMode           = PIP_AUTO; // Definizione del pip
input double           CustomPipSize     = 0.10;   // Pip personalizzato (se PIP_CUSTOM)
input double           MaxSpreadPips      = 3.5;   // Spread massimo assoluto (0 = nessun filtro)
input double           MaxSpreadToATR    = 0.15;   // Spread massimo in frazione di ATR (0 = off)
input double           SlippagePips      = 3.0;    // Slippage tollerato (pips)
input int              MaxRetries        = 3;      // Tentativi di invio ordine
input int              RetryDelayMs      = 500;    // Attesa (ms) tra i tentativi
input bool             TwoStepStops      = false;  // Broker ECN: apri e poi imposta SL/TP
input bool             VerboseLog        = true;   // Log dettagliato nel journal

//+------------------------------------------------------------------+
//| INPUT: Visualizzazione e telemetria                              |
//+------------------------------------------------------------------+
input string           s_view            = "===== VISUAL & TELEMETRY =====";
input bool             ShowOrderBlocks   = true;   // Disegna gli order block sul grafico
input bool             ShowZone          = true;   // Disegna la banda EMA dinamica
input bool             ShowSignals       = true;   // Disegna le frecce di ingresso
input int              OB_ExtendBars     = 12;     // Prolungamento a destra delle zone (barre)
input color            BullOBColor       = C'0,90,60';    // Colore order block rialzista
input color            BearOBColor       = C'110,35,35';  // Colore order block ribassista
input color            ZoneColor         = C'40,40,70';   // Colore della banda EMA
input bool             PublishTelemetry  = true;   // Pubblica lo stato per la dashboard esterna
input int              PublishSeconds    = 1;      // Intervallo di pubblicazione (secondi)

//+------------------------------------------------------------------+
//| Strutture dati                                                   |
//+------------------------------------------------------------------+
//--- Order block memorizzato
struct OrderBlockInfo
  {
   bool     used;        // Slot occupato
   int      dir;         // +1 rialzista, -1 ribassista
   double   hi;          // Bordo superiore della zona
   double   lo;          // Bordo inferiore della zona
   datetime born;        // Ora della candela di origine
   double   impulse;     // Ampiezza dell'impulso in ATR
   bool     bos;         // L'impulso ha rotto la struttura
   int      touches;     // Tocchi ricevuti
   bool     dead;        // Zona mitigata o scaduta
  };

//--- Posizione tracciata: serve a conoscere il rischio INIZIALE anche
//    dopo un parziale, che in MT4 genera un nuovo ticket.
struct PosTrack
  {
   bool     used;
   int      ticket;
   int      type;
   datetime openTime;
   double   openPrice;
   double   initLots;
   double   initRisk;    // Distanza SL iniziale, in prezzo
   bool     partialDone;
   bool     beDone;
   bool     seen;
  };

//+------------------------------------------------------------------+
//| Variabili globali                                                |
//+------------------------------------------------------------------+
//--- Profilo del simbolo
double   g_pip            = 0.0;
double   g_pointsPerPip   = 1.0;
int      g_slippagePoints = 0;
ENUM_SYMBOL_CLASS g_symClass = SYMBOL_FOREX;
string   g_symClassName   = "Forex";

//--- Parametri di volume
int      g_lotDigits      = 2;
double   g_lotStep        = 0.01;
double   g_minLot         = 0.01;
double   g_maxLot         = 100.0;

//--- Timeframe risolti
int      g_tf             = 0;   // Timeframe di ingresso
int      g_biasTF         = 0;   // Timeframe del bias

//--- Stato operativo
bool     g_initOk         = false;
datetime g_lastBarTime    = 0;
datetime g_lastTradeTime  = 0;
datetime g_lastTradeBar   = 0;
int      g_state          = ST_INIT;
int      g_reject         = REJ_NONE;
string   g_rejectText     = "-";

//--- Order block
OrderBlockInfo g_ob[MAX_OB * 2];

//--- Tracciamento posizioni
PosTrack g_track[MAX_TRACK];

//--- Ultima valutazione (per telemetria)
int      g_lastScore      = 0;
int      g_lastSignal     = 0;
int      g_bias           = 0;
double   g_biasStrength   = 0.0;
double   g_zoneHi         = 0.0;
double   g_zoneLo         = 0.0;
bool     g_bounceOk       = false;
bool     g_bosOk          = false;
bool     g_momOk          = false;
int      g_activeOB       = -1;
double   g_propSL         = 0.0;   // Distanza SL proposta
double   g_propTP         = 0.0;   // Distanza TP proposta
double   g_propLots       = 0.0;

//--- Stato giornaliero
datetime g_dayStamp       = 0;
double   g_dayStartBalance= 0.0;
int      g_tradesToday    = 0;
bool     g_dailyBlocked   = false;
int      g_lossStreak     = 0;
datetime g_pauseUntil     = 0;

//--- Statistiche storiche dell'EA
double   g_statNet        = 0.0;
double   g_statGross      = 0.0;
double   g_statLoss       = 0.0;
int      g_statWins       = 0;
int      g_statLosses     = 0;

//--- Telemetria
string   g_gvPrefix       = "";
datetime g_lastPublish    = 0;

//--- Visualizzazione
string   g_objPrefix      = "";

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_initOk = false;

   g_tf     = (EntryTimeframe == PERIOD_CURRENT) ? Period() : (int)EntryTimeframe;
   g_biasTF = (BiasTimeframe  == PERIOD_CURRENT) ? Period() : (int)BiasTimeframe;

   DetectSymbolProfile();

   g_lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   g_minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   g_maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   if(g_lotStep <= 0.0) g_lotStep = 0.01;
   if(g_minLot  <= 0.0) g_minLot  = g_lotStep;
   if(g_maxLot  <= 0.0) g_maxLot  = 100.0;
   g_lotDigits = VolumeDigits(g_lotStep);

   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   g_gvPrefix   = GV_PREFIX + Symbol() + "_" + IntegerToString(MagicNumber) + "_";
   g_objPrefix  = "EBOB" + IntegerToString(MagicNumber) + "_";
   g_lastBarTime= iTime(Symbol(), g_tf, 0);

   ClearTracking();
   ResetDailyState(true);

   //--- Popolamento iniziale degli order block sullo storico disponibile
   if(UseOrderBlocks)
      ScanHistoricalOrderBlocks();

   UpdateContextState();
   DrawVisuals();

   Comment("");
   g_state  = ST_INIT;
   g_initOk = true;

   PublishTelemetryData(true);

   Print("[", TradeComment, "] Init OK | ", Symbol(), " (", g_symClassName, ")",
         " Digits=", Digits,
         " Pip=", DoubleToString(g_pip, Digits),
         " | Ingresso=", TimeframeToString(g_tf),
         " Bias=", TimeframeToString(g_biasTF),
         " | StopLevel=", DoubleToString(MarketInfo(Symbol(), MODE_STOPLEVEL), 0), " points",
         " (", DoubleToString(MarketInfo(Symbol(), MODE_STOPLEVEL) * Point / g_pip, 1), " pips)",
         " | Order block trovati=", IntegerToString(CountLiveOB()),
         " | Telemetria=", (PublishTelemetry ? g_gvPrefix + "*" : "disattivata"),
         " | Magic=", MagicNumber);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("[", TradeComment, "] Deinit, motivo=", reason, " (", DeinitReasonText(reason), ")");

   DeleteVisuals();

   //--- La telemetria sopravvive a ricompilazioni e cambi di parametro:
   //    va cancellata solo quando l'EA lascia davvero il grafico,
   //    altrimenti la dashboard perderebbe l'istanza ad ogni ricompilazione.
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE)
      GlobalVariablesDeleteAll(g_gvPrefix);

   Comment("");
  }

//+------------------------------------------------------------------+
//| OnTick - Ciclo principale                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_initOk)
      return;

   //--- 1) Gestione delle posizioni aperte: su ogni tick
   ManageOpenPositions();

   //--- 2) Stato giornaliero e statistiche
   ResetDailyState(false);

   //--- 3) Nuova barra: manutenzione delle zone e dei disegni
   datetime barTime = iTime(Symbol(), g_tf, 0);
   bool newBar = (barTime != g_lastBarTime);

   if(newBar && UseOrderBlocks)
     {
      UpdateOrderBlocks();
      DetectNewOrderBlock();
     }

   //--- 4) Chiusure programmate
   HandleScheduledExits();

   //--- 5) Contesto e telemetria
   UpdateContextState();
   PublishTelemetryData(false);

   if(newBar)
     {
      DrawVisuals();
      g_lastBarTime = barTime;
     }
   else
      if(!NewBarOnly)
         DrawVisuals();

   //--- 6) Condizioni generali di operativita'
   if(!IsTradeAllowed() || IsTradeContextBusy())
      return;

   if(!HasEnoughBars())
     { SetReject(REJ_BARS, "storico insufficiente"); return; }

   //--- 7) I segnali si valutano a barra chiusa: su M5 una conferma
   //       intrabar cambia tre volte prima della chiusura.
   if(NewBarOnly && !newBar)
      return;

   //--- 8) Pulizia degli ordini pendenti scaduti
   if(ExecutionMode == EXEC_LIMIT)
      CleanupPendingOrders();

   //--- 9) Filtri, dal piu' economico al piu' costoso
   if(!PassContextFilters())
      return;

   //--- 10) Valutazione del segnale
   int signal = EvaluateSignal();
   if(signal == 0)
      return;

   //--- 11) Esecuzione
   if(ExecutionMode == EXEC_LIMIT)
      PlaceLimitOrder(signal);
   else
      OpenMarketPosition(signal);
  }

//+------------------------------------------------------------------+
//| Filtri di contesto: restituisce false e registra il motivo       |
//+------------------------------------------------------------------+
bool PassContextFilters()
  {
   //--- Un pendente armato e' un impegno gia' preso: conta come posizione,
   //    altrimenti l'EA ne accumulerebbe uno per barra.
   if(CountOwnPositions() + CountOwnPendings() >= MaxOpenPositions)
     { SetReject(REJ_MAXPOS, "posizioni e ordini armati gia' al limite"); return(false); }

   if(g_dailyBlocked)
     { return(false); }

   if(MaxTradesPerDay > 0 && g_tradesToday >= MaxTradesPerDay)
     { SetReject(REJ_DAILY_TRADES, "limite di " + IntegerToString(MaxTradesPerDay) + " trade giornalieri"); return(false); }

   if(g_pauseUntil > 0 && TimeCurrent() < g_pauseUntil)
     { SetReject(REJ_LOSSSTREAK, "pausa dopo " + IntegerToString(g_lossStreak) + " perdite consecutive"); return(false); }

   if(!IsSessionAllowed())
     { SetReject(REJ_SESSION, "fuori sessione operativa"); return(false); }

   if(IsInCooldown())
     { SetReject(REJ_COOLDOWN, "cooldown dopo l'ultimo trade"); return(false); }

   if(!IsSpreadAcceptable())
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| PROFILO DEL SIMBOLO                                              |
//| Deduce la classe dello strumento e il valore di 1 pip: su XAUUSD |
//| 1 pip = 0.10 USD, cosi' gli stessi parametri restano leggibili   |
//| passando dal Forex ai metalli.                                   |
//+------------------------------------------------------------------+
void DetectSymbolProfile()
  {
   string sym = Symbol();
   StringToUpper(sym);

   if(StringFind(sym, "XAU", 0) >= 0 || StringFind(sym, "GOLD", 0) >= 0)
     {
      g_symClass     = SYMBOL_GOLD;
      g_symClassName = "Oro";
     }
   else
      if(StringFind(sym, "XAG", 0) >= 0 || StringFind(sym, "SILVER", 0) >= 0)
        {
         g_symClass     = SYMBOL_SILVER;
         g_symClassName = "Argento";
        }
      else
         if(Digits >= 3 && StringLen(sym) <= 9 && IsForexLike(sym))
           {
            g_symClass     = SYMBOL_FOREX;
            g_symClassName = "Forex";
           }
         else
           {
            g_symClass     = SYMBOL_OTHER;
            g_symClassName = "Indice/CFD";
           }

   switch(PipMode)
     {
      case PIP_FOREX:
         g_pip = ((Digits == 3 || Digits == 5) ? Point * 10.0 : Point);
         break;
      case PIP_POINT:
         g_pip = Point;
         break;
      case PIP_CUSTOM:
         g_pip = (CustomPipSize > 0.0 ? CustomPipSize : Point);
         break;
      default: // PIP_AUTO
         if(g_symClass == SYMBOL_GOLD)
            g_pip = 0.10;
         else
            if(g_symClass == SYMBOL_SILVER)
               g_pip = 0.01;
            else
               g_pip = ((Digits == 3 || Digits == 5) ? Point * 10.0 : Point);
         break;
     }

   if(g_pip < Point)
      g_pip = Point;

   g_pointsPerPip   = g_pip / Point;
   g_slippagePoints = (int)MathRound(SlippagePips * g_pointsPerPip);
   if(g_slippagePoints < 0)
      g_slippagePoints = 0;
  }

//+------------------------------------------------------------------+
//| Riconoscimento euristico di una coppia valutaria                 |
//+------------------------------------------------------------------+
bool IsForexLike(string sym)
  {
   string majors[8] = {"USD", "EUR", "GBP", "JPY", "CHF", "AUD", "NZD", "CAD"};
   int found = 0;
   for(int i = 0; i < 8; i++)
      if(StringFind(sym, majors[i], 0) >= 0)
         found++;
   return(found >= 2);
  }

//+------------------------------------------------------------------+
//| Validazione degli input                                          |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   bool ok = true;

   if(RiskPercent <= 0.0 && FixedLots <= 0.0)
     { Print("ERRORE INPUT: impostare RiskPercent > 0 oppure FixedLots > 0."); ok = false; }

   if(RiskPercent > 5.0)
      Print("ATTENZIONE: RiskPercent = ", DoubleToString(RiskPercent, 2), "% e' molto alto per un intraday su oro.");

   if(EMA_Fast_Period >= EMA_Slow_Period)
     { Print("ERRORE INPUT: EMA_Fast_Period deve essere minore di EMA_Slow_Period."); ok = false; }

   if(Bias_EMA_Fast >= Bias_EMA_Slow)
     { Print("ERRORE INPUT: Bias_EMA_Fast deve essere minore di Bias_EMA_Slow."); ok = false; }

   if(ATR_Period < 2)
     { Print("ERRORE INPUT: ATR_Period deve essere >= 2."); ok = false; }

   if(MinSL_ATR >= MaxSL_ATR)
     { Print("ERRORE INPUT: MinSL_ATR deve essere minore di MaxSL_ATR."); ok = false; }

   if(TP_RMultiple < MinRiskReward)
      Print("ATTENZIONE: TP_RMultiple (", DoubleToString(TP_RMultiple, 2),
            ") e' sotto MinRiskReward (", DoubleToString(MinRiskReward, 2),
            "): ogni trade verrebbe scartato in modalita' TP_RMULTIPLE.");

   if(BounceLookback < 1)
     { Print("ERRORE INPUT: BounceLookback deve essere >= 1."); ok = false; }

   if(OB_ImpulseBars < 1)
     { Print("ERRORE INPUT: OB_ImpulseBars deve essere >= 1."); ok = false; }

   if(OB_SwingStrength < 1)
     { Print("ERRORE INPUT: OB_SwingStrength deve essere >= 1."); ok = false; }

   if(MaxOpenPositions < 1)
     { Print("ERRORE INPUT: MaxOpenPositions deve essere >= 1."); ok = false; }

   if(UsePartialClose && (PartialPercent <= 0.0 || PartialPercent >= 100.0))
     { Print("ERRORE INPUT: PartialPercent deve stare tra 0 e 100 (esclusi)."); ok = false; }

   if(MinConfluenceScore < 0 || MinConfluenceScore > 100)
     { Print("ERRORE INPUT: MinConfluenceScore deve stare tra 0 e 100."); ok = false; }

   if(EntryMode == ENTRY_CONFLUENCE && !RequireBounce && !RequireOrderBlock)
      Print("ATTENZIONE: ENTRY_CONFLUENCE senza rimbalzo ne' order block obbligatori: decide solo il punteggio.");

   if(RequireOrderBlock && !UseOrderBlocks)
     { Print("ERRORE INPUT: RequireOrderBlock = true richiede UseOrderBlocks = true."); ok = false; }

   if(UseSessionFilter && SessionStartHour == SessionEndHour)
     { Print("ERRORE INPUT: SessionStartHour e SessionEndHour non possono coincidere."); ok = false; }

   if(g_tf > PERIOD_H1)
      Print("ATTENZIONE: l'EA e' tarato su M5/M15; su ", TimeframeToString(g_tf),
            " i parametri di default non sono significativi.");

   if(g_biasTF < g_tf)
      Print("ATTENZIONE: BiasTimeframe (", TimeframeToString(g_biasTF),
            ") e' piu' basso del timeframe di ingresso (", TimeframeToString(g_tf),
            "): il bias perde la sua funzione di contesto.");

   return(ok);
  }

//+------------------------------------------------------------------+
//| Storico sufficiente per tutti i calcoli                          |
//+------------------------------------------------------------------+
bool HasEnoughBars()
  {
   int needEntry = (int)MathMax(EMA_Slow_Period, MathMax(ATR_Period, RSI_Period)) + BounceLookback + OB_ImpulseBars + 10;
   int needBias  = (int)MathMax(Bias_EMA_Slow, ATR_Period) + Bias_SlopeBars + 5;

   if(iBars(Symbol(), g_tf) < needEntry)
      return(false);
   if(iBars(Symbol(), g_biasTF) < needBias)
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| Scorciatoie sul timeframe di ingresso                            |
//+------------------------------------------------------------------+
double HiE(int i) { return(iHigh (Symbol(), g_tf, i)); }
double LoE(int i) { return(iLow  (Symbol(), g_tf, i)); }
double OpE(int i) { return(iOpen (Symbol(), g_tf, i)); }
double ClE(int i) { return(iClose(Symbol(), g_tf, i)); }
datetime TmE(int i){ return(iTime(Symbol(), g_tf, i)); }

double EmaFast(int i) { return(iMA(Symbol(), g_tf, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE, i)); }
double EmaSlow(int i) { return(iMA(Symbol(), g_tf, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE, i)); }
double AtrE(int i)    { return(iATR(Symbol(), g_tf, ATR_Period, i)); }

//+------------------------------------------------------------------+
//| STRUTTURA DI MERCATO                                             |
//| Swing con OB_SwingStrength barre per lato. Non e' un massimo     |
//| qualsiasi: e' un punto che il mercato ha rifiutato da entrambi   |
//| i lati, l'unico riferimento utile per parlare di rottura.        |
//+------------------------------------------------------------------+
bool IsSwingHigh(int shift, int strength)
  {
   if(shift - strength < 0 || shift + strength >= iBars(Symbol(), g_tf))
      return(false);

   double h = HiE(shift);
   for(int i = 1; i <= strength; i++)
     {
      if(HiE(shift + i) > h)  return(false);
      if(HiE(shift - i) >= h) return(false);
     }
   return(true);
  }

bool IsSwingLow(int shift, int strength)
  {
   if(shift - strength < 0 || shift + strength >= iBars(Symbol(), g_tf))
      return(false);

   double l = LoE(shift);
   for(int i = 1; i <= strength; i++)
     {
      if(LoE(shift + i) < l)  return(false);
      if(LoE(shift - i) <= l) return(false);
     }
   return(true);
  }

//--- Ultimo swing high a partire da fromShift andando indietro
double LastSwingHigh(int fromShift, int lookback, int &foundShift)
  {
   foundShift = -1;
   int maxBar = iBars(Symbol(), g_tf) - OB_SwingStrength - 1;
   for(int i = fromShift; i <= fromShift + lookback && i <= maxBar; i++)
      if(IsSwingHigh(i, OB_SwingStrength))
        {
         foundShift = i;
         return(HiE(i));
        }
   return(0.0);
  }

double LastSwingLow(int fromShift, int lookback, int &foundShift)
  {
   foundShift = -1;
   int maxBar = iBars(Symbol(), g_tf) - OB_SwingStrength - 1;
   for(int i = fromShift; i <= fromShift + lookback && i <= maxBar; i++)
      if(IsSwingLow(i, OB_SwingStrength))
        {
         foundShift = i;
         return(LoE(i));
        }
   return(0.0);
  }

//+------------------------------------------------------------------+
//| MOTORE ORDER BLOCK                                               |
//| Candela di origine = ultima candela opposta prima dell'impulso.  |
//| L'impulso deve valere almeno OB_MinImpulseATR volte l'ATR e,     |
//| se richiesto, rompere l'ultimo swing (BOS). Senza BOS non c'e'   |
//| continuazione: c'e' solo una candela grande.                     |
//+------------------------------------------------------------------+
bool TestOrderBlockAt(int k, int dir, double atr, double &obHi, double &obLo,
                      double &impulseATR, bool &bos)
  {
   obHi = 0.0; obLo = 0.0; impulseATR = 0.0; bos = false;

   if(atr <= 0.0 || k < 1)
      return(false);

   int lastBar = k - OB_ImpulseBars;
   if(lastBar < 1)
      lastBar = 1;
   if(lastBar > k - 1)
      return(false);

   double o = OpE(k), c = ClE(k), h = HiE(k), l = LoE(k);

   int    count = k - lastBar;
   double move  = 0.0;

   if(dir > 0)
     {
      //--- Origine ribassista prima di una spinta rialzista
      if(c >= o)
         return(false);

      int    hiIdx = iHighest(Symbol(), g_tf, MODE_HIGH, count, lastBar);
      if(hiIdx < 0) return(false);
      double maxHigh = HiE(hiIdx);

      if(maxHigh <= h)
         return(false);              // l'impulso non ha nemmeno superato l'origine

      move = maxHigh - l;
      if(move < atr * OB_MinImpulseATR)
         return(false);

      int    swShift = -1;
      double swing   = LastSwingHigh(k + 1, OB_StructureBars, swShift);
      bos = (swing > 0.0 && maxHigh > swing);

      obHi = (OB_ZoneMode == OB_BODY) ? o : h;
      obLo = l;
     }
   else
     {
      //--- Origine rialzista prima di una spinta ribassista
      if(c <= o)
         return(false);

      int    loIdx = iLowest(Symbol(), g_tf, MODE_LOW, count, lastBar);
      if(loIdx < 0) return(false);
      double minLow = LoE(loIdx);

      if(minLow >= l)
         return(false);

      move = h - minLow;
      if(move < atr * OB_MinImpulseATR)
         return(false);

      int    swShift = -1;
      double swing   = LastSwingLow(k + 1, OB_StructureBars, swShift);
      bos = (swing > 0.0 && minLow < swing);

      obHi = h;
      obLo = (OB_ZoneMode == OB_BODY) ? o : l;
     }

   if(OB_RequireBOS && !bos)
      return(false);

   if(obHi <= obLo)
      return(false);

   impulseATR = move / atr;
   return(true);
  }

//+------------------------------------------------------------------+
//| Inserimento di un order block (piu' recente in testa)            |
//+------------------------------------------------------------------+
void AddOrderBlock(int dir, double hi, double lo, datetime born, double impulseATR, bool bos)
  {
   //--- Evita i duplicati sulla stessa candela di origine
   for(int i = 0; i < MAX_OB * 2; i++)
      if(g_ob[i].used && g_ob[i].born == born && g_ob[i].dir == dir)
         return;

   //--- Slot libero, altrimenti sostituisci il piu' vecchio o uno morto
   int slot = -1;
   for(int i = 0; i < MAX_OB * 2; i++)
      if(!g_ob[i].used || g_ob[i].dead)
        { slot = i; break; }

   if(slot < 0)
     {
      datetime oldest = TimeCurrent();
      for(int i = 0; i < MAX_OB * 2; i++)
         if(g_ob[i].born <= oldest)
           { oldest = g_ob[i].born; slot = i; }
     }
   if(slot < 0)
      return;

   g_ob[slot].used    = true;
   g_ob[slot].dir     = dir;
   g_ob[slot].hi      = hi;
   g_ob[slot].lo      = lo;
   g_ob[slot].born    = born;
   g_ob[slot].impulse = impulseATR;
   g_ob[slot].bos     = bos;
   g_ob[slot].touches = 0;
   g_ob[slot].dead    = false;

   if(VerboseLog)
      Print("[", TradeComment, "] Order block ", (dir > 0 ? "RIALZISTA" : "RIBASSISTA"),
            " ", DoubleToString(lo, Digits), " - ", DoubleToString(hi, Digits),
            " | impulso ", DoubleToString(impulseATR, 2), " ATR",
            " | BOS=", (bos ? "si" : "no"),
            " | ", TimeToString(born, TIME_DATE|TIME_MINUTES));
  }

//+------------------------------------------------------------------+
//| Scansione storica iniziale                                       |
//+------------------------------------------------------------------+
void ScanHistoricalOrderBlocks()
  {
   int bars = iBars(Symbol(), g_tf);
   int maxK = (int)MathMin(OB_ScanBars, bars - OB_StructureBars - OB_SwingStrength - 5);
   if(maxK < 3)
      return;

   for(int k = maxK; k >= 2; k--)
     {
      double atr = AtrE(k);
      if(atr <= 0.0)
         continue;

      double hi, lo, imp;
      bool   bos;

      if(TestOrderBlockAt(k, 1, atr, hi, lo, imp, bos))
         AddOrderBlock(1, hi, lo, TmE(k), imp, bos);

      if(TestOrderBlockAt(k, -1, atr, hi, lo, imp, bos))
         AddOrderBlock(-1, hi, lo, TmE(k), imp, bos);
     }

   UpdateOrderBlocks();
  }

//+------------------------------------------------------------------+
//| Rilevamento su nuova barra: solo la finestra recente             |
//+------------------------------------------------------------------+
void DetectNewOrderBlock()
  {
   double atr = AtrE(1);
   if(atr <= 0.0)
      return;

   int kMax = OB_ImpulseBars + 2;
   if(kMax >= iBars(Symbol(), g_tf) - OB_StructureBars - OB_SwingStrength - 2)
      return;

   for(int k = 2; k <= kMax; k++)
     {
      double hi, lo, imp;
      bool   bos;

      if(TestOrderBlockAt(k, 1, atr, hi, lo, imp, bos))
         AddOrderBlock(1, hi, lo, TmE(k), imp, bos);

      if(TestOrderBlockAt(k, -1, atr, hi, lo, imp, bos))
         AddOrderBlock(-1, hi, lo, TmE(k), imp, bos);
     }
  }

//+------------------------------------------------------------------+
//| Manutenzione: eta', mitigazione, conteggio dei tocchi            |
//+------------------------------------------------------------------+
void UpdateOrderBlocks()
  {
   for(int i = 0; i < MAX_OB * 2; i++)
     {
      if(!g_ob[i].used || g_ob[i].dead)
         continue;

      int birth = iBarShift(Symbol(), g_tf, g_ob[i].born, false);
      if(birth < 0)
        { g_ob[i].dead = true; continue; }

      //--- Eta' massima
      if(OB_MaxAgeBars > 0 && birth > OB_MaxAgeBars)
        { g_ob[i].dead = true; continue; }

      //--- Mitigazione e tocchi, dalla formazione a oggi
      int touches = 0;
      for(int b = birth - 1; b >= 1; b--)
        {
         if(g_ob[i].dir > 0)
           {
            double refClose = (OB_MitigateOnClose ? ClE(b) : LoE(b));
            if(refClose < g_ob[i].lo)
              { g_ob[i].dead = true; break; }
            if(LoE(b) <= g_ob[i].hi)
               touches++;
           }
         else
           {
            double refClose = (OB_MitigateOnClose ? ClE(b) : HiE(b));
            if(refClose > g_ob[i].hi)
              { g_ob[i].dead = true; break; }
            if(HiE(b) >= g_ob[i].lo)
               touches++;
           }
        }

      if(g_ob[i].dead)
         continue;

      g_ob[i].touches = touches;

      //--- Una zona toccata troppe volte ha gia' distribuito i suoi ordini
      if(OB_MaxTouches > 0 && touches > OB_MaxTouches)
         g_ob[i].dead = true;
     }
  }

//+------------------------------------------------------------------+
//| Order block valido piu' vicino al prezzo, nella direzione data   |
//+------------------------------------------------------------------+
int FindActiveOrderBlock(int dir, double price, double atr)
  {
   double tol  = atr * OB_ProximityATR;
   int    best = -1;
   double bestDist = 0.0;

   for(int i = 0; i < MAX_OB * 2; i++)
     {
      if(!g_ob[i].used || g_ob[i].dead || g_ob[i].dir != dir)
         continue;

      //--- La zona deve trovarsi dal lato giusto del prezzo
      if(dir > 0 && g_ob[i].lo > price + tol)
         continue;
      if(dir < 0 && g_ob[i].hi < price - tol)
         continue;

      double dist = (dir > 0) ? MathAbs(price - g_ob[i].hi) : MathAbs(g_ob[i].lo - price);
      if(best < 0 || dist < bestDist)
        { best = i; bestDist = dist; }
     }

   return(best);
  }

//--- Il prezzo indicato ha toccato la zona?
bool PriceTagsOB(int idx, double price, double atr)
  {
   if(idx < 0 || !g_ob[idx].used || g_ob[idx].dead)
      return(false);

   double tol = atr * OB_ProximityATR;
   return(price <= g_ob[idx].hi + tol && price >= g_ob[idx].lo - tol);
  }

int CountLiveOB()
  {
   int n = 0;
   for(int i = 0; i < MAX_OB * 2; i++)
      if(g_ob[i].used && !g_ob[i].dead)
         n++;
   return(n);
  }

//+------------------------------------------------------------------+
//| BIAS DI TREND (timeframe superiore)                              |
//| Restituisce +1 / -1 / 0 e una forza 0-100. La pendenza e' letta  |
//| in ATR e non in punti: su oro un movimento di 2 dollari e' molto |
//| o poco a seconda della volatilita' del momento.                  |
//+------------------------------------------------------------------+
int ComputeBias(double &strength)
  {
   strength = 0.0;

   double fast = iMA(Symbol(), g_biasTF, Bias_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slow = iMA(Symbol(), g_biasTF, Bias_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double prev = iMA(Symbol(), g_biasTF, Bias_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 1 + Bias_SlopeBars);
   double atrB = iATR(Symbol(), g_biasTF, ATR_Period, 1);
   double cls  = iClose(Symbol(), g_biasTF, 1);

   if(atrB <= 0.0 || fast <= 0.0 || slow <= 0.0)
      return(0);

   double sep   = (fast - slow) / atrB;                     // separazione in ATR
   double slope = (slow - prev) / (atrB * Bias_SlopeBars);  // pendenza per barra, in ATR

   bool bull = (fast > slow) && (sep >= Bias_MinSepATR) && (slope >= Bias_MinSlopeATR);
   bool bear = (fast < slow) && (-sep >= Bias_MinSepATR) && (-slope >= Bias_MinSlopeATR);

   if(Bias_RequirePrice)
     {
      if(bull && cls < slow) bull = false;
      if(bear && cls > slow) bear = false;
     }

   if(!bull && !bear)
      return(0);

   //--- Forza: meta' dalla separazione, meta' dalla pendenza, saturate
   double sepScore   = MathMin(MathAbs(sep)   / 1.00, 1.0) * 50.0;
   double slopeScore = MathMin(MathAbs(slope) / 0.30, 1.0) * 50.0;
   strength = sepScore + slopeScore;

   return(bull ? 1 : -1);
  }

//+------------------------------------------------------------------+
//| BANDA EMA DINAMICA                                               |
//| La banda non e' una linea: e' l'area tra EMA veloce e lenta,     |
//| allargata di ZoneBufferATR. Su M5 il prezzo raramente tocca la   |
//| media al centesimo: senza tolleranza il rimbalzo non si vede.    |
//+------------------------------------------------------------------+
void ComputeZone(int shift, double atr, double &zLo, double &zHi)
  {
   double f = EmaFast(shift);
   double s = EmaSlow(shift);
   double buf = atr * ZoneBufferATR;

   zHi = MathMax(f, s) + buf;
   zLo = MathMin(f, s) - buf;
  }

//+------------------------------------------------------------------+
//| RIMBALZO DINAMICO                                                |
//| Tocco della banda entro BounceLookback barre, nessuna chiusura   |
//| oltre la banda dal tocco in poi, barra di conferma (shift 1) con |
//| rifiuto misurabile: ombra oltre MinWickRatio del range oppure    |
//| corpo oltre MinBodyRatio, nella direzione del bias.              |
//+------------------------------------------------------------------+
bool DetectEmaBounce(int dir, double atr, int &touchShift, double &extreme)
  {
   touchShift = -1;
   extreme    = 0.0;

   if(atr <= 0.0)
      return(false);

   //--- 1) Ricerca del tocco piu' recente
   for(int i = 1; i <= BounceLookback; i++)
     {
      double zLo, zHi;
      ComputeZone(i, AtrE(i), zLo, zHi);

      if(dir > 0 && LoE(i) <= zHi)
        { touchShift = i; break; }
      if(dir < 0 && HiE(i) >= zLo)
        { touchShift = i; break; }
     }

   if(touchShift < 0)
      return(false);

   //--- 2) Nessuna chiusura oltre la banda dal tocco in poi:
   //       se il prezzo ha chiuso sotto la banda in un uptrend, quello
   //       non e' un ritracciamento, e' un cambio di struttura.
   extreme = (dir > 0) ? LoE(touchShift) : HiE(touchShift);

   for(int i = touchShift; i >= 1; i--)
     {
      double zLo, zHi;
      ComputeZone(i, AtrE(i), zLo, zHi);

      if(dir > 0)
        {
         if(ClE(i) < zLo) return(false);
         if(LoE(i) < extreme) extreme = LoE(i);
        }
      else
        {
         if(ClE(i) > zHi) return(false);
         if(HiE(i) > extreme) extreme = HiE(i);
        }
     }

   //--- 3) Barra di conferma: l'ultima chiusa
   double o = OpE(1), c = ClE(1), h = HiE(1), l = LoE(1);
   double range = h - l;
   if(range <= 0.0)
      return(false);

   double zLo1, zHi1;
   ComputeZone(1, AtrE(1), zLo1, zHi1);
   double zMid = (zLo1 + zHi1) * 0.5;

   if(dir > 0)
     {
      if(c <= o)                                   return(false);  // corpo rialzista
      if(c < zMid)                                 return(false);  // chiusura nella meta' alta della banda
      if(RequireCloseBeyondFast && c < EmaFast(1)) return(false);

      double wick = MathMin(o, c) - l;
      double body = c - o;
      if(wick < range * MinWickRatio && body < range * MinBodyRatio)
         return(false);
     }
   else
     {
      if(c >= o)                                   return(false);
      if(c > zMid)                                 return(false);
      if(RequireCloseBeyondFast && c > EmaFast(1)) return(false);

      double wick = h - MathMax(o, c);
      double body = o - c;
      if(wick < range * MinWickRatio && body < range * MinBodyRatio)
         return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Momentum: RSI in svolta dal lato del trend                       |
//+------------------------------------------------------------------+
bool CheckMomentum(int dir)
  {
   if(!UseMomentumFilter)
      return(true);

   double r1 = iRSI(Symbol(), g_tf, RSI_Period, PRICE_CLOSE, 1);
   double r2 = iRSI(Symbol(), g_tf, RSI_Period, PRICE_CLOSE, 2);

   if(dir > 0)
      return(r1 >= RSI_BullMin && r1 > r2);

   return(r1 <= RSI_BearMax && r1 < r2);
  }

//+------------------------------------------------------------------+
//| BOS recente nella direzione del bias                             |
//+------------------------------------------------------------------+
bool RecentBOS(int dir)
  {
   int    swShift = -1;
   double swing;

   if(dir > 0)
     {
      swing = LastSwingHigh(2, OB_StructureBars, swShift);
      if(swing <= 0.0 || swShift < 0)
         return(false);
      //--- Il massimo dopo lo swing lo ha superato?
      int idx = iHighest(Symbol(), g_tf, MODE_HIGH, swShift, 1);
      if(idx < 0) return(false);
      return(HiE(idx) > swing);
     }

   swing = LastSwingLow(2, OB_StructureBars, swShift);
   if(swing <= 0.0 || swShift < 0)
      return(false);
   int idx2 = iLowest(Symbol(), g_tf, MODE_LOW, swShift, 1);
   if(idx2 < 0) return(false);
   return(LoE(idx2) < swing);
  }

//+------------------------------------------------------------------+
//| VALUTAZIONE DEL SEGNALE                                          |
//| Costruisce il punteggio di confluenza e restituisce +1 / -1 / 0. |
//| Il punteggio non e' un abbellimento: e' cio' che permette di     |
//| allentare un requisito senza perdere il controllo di quanto si   |
//| sta allentando.                                                  |
//|                                                                  |
//|   30  rimbalzo dinamico confermato sulla banda EMA               |
//|   30  order block valido toccato dal ritracciamento              |
//|   10  order block sovrapposto alla banda EMA (doppia confluenza) |
//|   10  rottura di struttura recente nella direzione del bias      |
//|   10  bias forte (>= 60 di forza)                                |
//|   10  momentum dal lato giusto                                   |
//+------------------------------------------------------------------+
int EvaluateSignal()
  {
   g_lastScore  = 0;
   g_lastSignal = 0;
   g_activeOB   = -1;
   g_bounceOk   = false;
   g_bosOk      = false;
   g_momOk      = false;

   double atr = AtrE(1);
   if(atr <= 0.0)
     { SetReject(REJ_BARS, "ATR non disponibile"); return(0); }

   //--- 1) Direzione ammessa
   int dir = g_bias;
   if(dir == 0)
     { SetReject(REJ_NOBIAS, "nessun bias di trend su " + TimeframeToString(g_biasTF)); return(0); }

   //--- 2) Rimbalzo sulla banda EMA
   int    touchShift = -1;
   double extreme    = 0.0;
   g_bounceOk = DetectEmaBounce(dir, atr, touchShift, extreme);

   if(RequireBounce && !g_bounceOk)
     { SetReject(REJ_NOBOUNCE, "nessun rimbalzo confermato sulla banda EMA"); return(0); }

   //--- Riferimento del ritracciamento: l'estremo raggiunto dal pullback
   double pullExtreme = (extreme != 0.0) ? extreme : ((dir > 0) ? LoE(1) : HiE(1));

   //--- 3) Order block toccato dal ritracciamento
   bool obTagged  = false;
   bool obOverlap = false;

   if(UseOrderBlocks)
     {
      g_activeOB = FindActiveOrderBlock(dir, pullExtreme, atr);
      if(g_activeOB >= 0)
        {
         obTagged = PriceTagsOB(g_activeOB, pullExtreme, atr);

         double zLo, zHi;
         ComputeZone(1, atr, zLo, zHi);
         obOverlap = (g_ob[g_activeOB].hi >= zLo && g_ob[g_activeOB].lo <= zHi);
        }
     }

   if(RequireOrderBlock && !obTagged)
     { SetReject(REJ_NOOB, "nessun order block valido toccato dal ritracciamento"); return(0); }

   //--- 4) Contesto
   g_bosOk = RecentBOS(dir);
   g_momOk = CheckMomentum(dir);

   //--- 5) Punteggio
   int score = 0;
   if(g_bounceOk)              score += 30;
   if(obTagged)                score += 30;
   if(obTagged && obOverlap)   score += 10;
   if(g_bosOk)                 score += 10;
   if(g_biasStrength >= 60.0)  score += 10;
   if(g_momOk)                 score += 10;

   g_lastScore = score;

   //--- 6) Criterio d'ingresso
   if(EntryMode == ENTRY_CONFLUENCE)
     {
      if(RequireBounce && !g_bounceOk)
        { SetReject(REJ_NOBOUNCE, "rimbalzo assente"); return(0); }
      if(RequireOrderBlock && !obTagged)
        { SetReject(REJ_NOOB, "order block assente"); return(0); }
     }

   if(score < MinConfluenceScore)
     {
      SetReject(REJ_SCORE, StringFormat("confluenza %d/100 sotto la soglia %d", score, MinConfluenceScore));
      return(0);
     }

   if(UseMomentumFilter && !g_momOk)
     {
      SetReject(REJ_SCORE, "momentum contrario alla direzione del bias");
      return(0);
     }

   g_lastSignal = dir;

   if(VerboseLog)
      Print("[", TradeComment, "] Segnale ", (dir > 0 ? "BUY" : "SELL"),
            " | confluenza ", score, "/100",
            " | rimbalzo=", (g_bounceOk ? "si" : "no"),
            " OB=", (obTagged ? "si" : "no"),
            " sovrapposto=", (obOverlap ? "si" : "no"),
            " BOS=", (g_bosOk ? "si" : "no"),
            " momentum=", (g_momOk ? "si" : "no"),
            " | bias ", DoubleToString(g_biasStrength, 0), "/100",
            " | ATR ", DoubleToString(atr / g_pip, 1), " pips");

   return(dir);
  }

//+------------------------------------------------------------------+
//| Riferimento dello stop tecnico: il punto oltre il quale l'idea   |
//| e' semplicemente sbagliata (fondo dell'order block o del         |
//| ritracciamento, il piu' protettivo dei due).                     |
//+------------------------------------------------------------------+
double StopReference(int dir, double atr)
  {
   double extreme = (dir > 0) ? LoE(1) : HiE(1);

   //--- Estremo del ritracciamento nelle ultime barre
   for(int i = 1; i <= BounceLookback + 1; i++)
     {
      if(dir > 0 && LoE(i) < extreme) extreme = LoE(i);
      if(dir < 0 && HiE(i) > extreme) extreme = HiE(i);
     }

   //--- Fondo dell'order block attivo
   if(g_activeOB >= 0 && g_ob[g_activeOB].used && !g_ob[g_activeOB].dead)
     {
      if(dir > 0)
         extreme = MathMin(extreme, g_ob[g_activeOB].lo);
      else
         extreme = MathMax(extreme, g_ob[g_activeOB].hi);
     }

   return(extreme);
  }

//+------------------------------------------------------------------+
//| Distanza minima imposta dal broker                               |
//+------------------------------------------------------------------+
double BrokerMinStopDistance()
  {
   double stopLevel   = MarketInfo(Symbol(), MODE_STOPLEVEL)   * Point;
   double freezeLevel = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
   double spread      = MathMax(Ask - Bid, 0.0);

   double minDist = MathMax(stopLevel, freezeLevel) + spread + StopBufferPips * g_pip;
   if(minDist < g_pip)
      minDist = g_pip;

   return(NormalizeDouble(minDist, Digits));
  }

//+------------------------------------------------------------------+
//| Distanza di prezzo equivalente alla commissione per lotto        |
//+------------------------------------------------------------------+
double CommissionPriceEquivalent()
  {
   if(CommissionPerLot <= 0.0)
      return(0.0);

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return(0.0);

   return(CommissionPerLot * tickSize / tickValue);
  }

//+------------------------------------------------------------------+
//| COSTRUZIONE DI STOP E TARGET                                     |
//| Lo stop nasce dalla struttura (order block / ritracciamento),    |
//| non da un multiplo fisso. Poi viene confrontato con i vincoli    |
//| del broker e con la volatilita': se il trade non regge il        |
//| confronto viene SCARTATO, non eseguito in versione degradata.    |
//+------------------------------------------------------------------+
bool BuildStops(int dir, double entryPrice, double atr,
                double &slPrice, double &tpPrice, string &note)
  {
   slPrice = 0.0;
   tpPrice = 0.0;
   note    = "";

   if(atr <= 0.0)
     { SetReject(REJ_BARS, "ATR non disponibile"); return(false); }

   double minDist = BrokerMinStopDistance();

   //--- CONTROLLO 1: il vincolo del broker e' compatibile con la volatilita'?
   //    Uno STOPLEVEL che vale quasi quanto l'ATR rende impossibile
   //    qualunque stop tecnico su M5.
   if(MaxStopLevelATR > 0.0 && minDist > atr * MaxStopLevelATR)
     {
      note = StringFormat("distanza minima broker %.1f pips oltre il %.0f%% dell'ATR (%.1f pips)",
                          minDist / g_pip, MaxStopLevelATR * 100.0, atr / g_pip);
      SetReject(REJ_STOPLEVEL, note);
      return(false);
     }

   //--- Stop tecnico: oltre la zona, con margine in ATR
   double ref    = StopReference(dir, atr);
   double buffer = atr * SL_BufferATR;
   double slDist = (dir > 0) ? (entryPrice - (ref - buffer))
                             : ((ref + buffer) - entryPrice);

   //--- CONTROLLO 2: lo stop tecnico e' dentro i limiti di volatilita'?
   if(MaxSL_ATR > 0.0 && slDist > atr * MaxSL_ATR)
     {
      note = StringFormat("stop tecnico %.1f pips oltre il massimo %.1f ATR (%.1f pips)",
                          slDist / g_pip, MaxSL_ATR, atr * MaxSL_ATR / g_pip);
      SetReject(REJ_SL_WIDE, note);
      return(false);
     }

   //--- Pavimenti: minimo tecnico e minimo del broker
   double floorATR = atr * MinSL_ATR;
   if(slDist < floorATR)
      slDist = floorATR;
   if(slDist < minDist)
      slDist = minDist;

   //--- Ricontrollo dopo i pavimenti: se allargare lo stop lo porta
   //    oltre il tetto, il setup non e' compatibile con questo broker.
   if(MaxSL_ATR > 0.0 && slDist > atr * MaxSL_ATR)
     {
      note = StringFormat("stop allargato a %.1f pips dai vincoli, oltre il massimo %.1f ATR",
                          slDist / g_pip, MaxSL_ATR);
      SetReject(REJ_SL_WIDE, note);
      return(false);
     }

   //--- Target
   double tpDist = slDist * TP_RMultiple;

   if(TakeProfitMode == TP_STRUCTURE)
     {
      int    swShift = -1;
      double target  = (dir > 0) ? LastSwingHigh(1, TP_StructureBars, swShift)
                                 : LastSwingLow(1, TP_StructureBars, swShift);

      if(target > 0.0)
        {
         double structDist = (dir > 0) ? (target - entryPrice) : (entryPrice - target);
         //--- La struttura vale solo se e' avanti al prezzo e paga almeno il minimo
         if(structDist > slDist * MinRiskReward)
            tpDist = structDist;
        }
     }

   if(tpDist < minDist)
      tpDist = minDist;

   //--- CONTROLLO 3: il target copre i costi di transazione?
   double spread = MathMax(Ask - Bid, 0.0);
   double cost   = spread + CommissionPriceEquivalent();

   if(MinTPCostRatio > 0.0 && cost > 0.0 && tpDist < cost * MinTPCostRatio)
     {
      note = StringFormat("TP %.1f pips contro costi %.1f pips (x%.1f, richiesto x%.1f)",
                          tpDist / g_pip, cost / g_pip, tpDist / cost, MinTPCostRatio);
      SetReject(REJ_RR, note);
      return(false);
     }

   //--- CONTROLLO 4: rapporto rischio/rendimento residuo
   double rr = tpDist / slDist;
   if(MinRiskReward > 0.0 && rr < MinRiskReward)
     {
      note = StringFormat("R:R effettivo 1:%.2f sotto il minimo 1:%.2f", rr, MinRiskReward);
      SetReject(REJ_RR, note);
      return(false);
     }

   if(dir > 0)
     {
      slPrice = NormalizeDouble(entryPrice - slDist, Digits);
      tpPrice = NormalizeDouble(entryPrice + tpDist, Digits);
     }
   else
     {
      slPrice = NormalizeDouble(entryPrice + slDist, Digits);
      tpPrice = NormalizeDouble(entryPrice - tpDist, Digits);
     }

   g_propSL = slDist;
   g_propTP = tpDist;

   note = StringFormat("SL %.1f pips, TP %.1f pips, R:R 1:%.2f", slDist / g_pip, tpDist / g_pip, rr);
   return(true);
  }

//+------------------------------------------------------------------+
//| Apertura a mercato                                               |
//+------------------------------------------------------------------+
bool OpenMarketPosition(int dir)
  {
   RefreshRates();

   double atr   = AtrE(1);
   double price = NormalizeDouble((dir > 0 ? Ask : Bid), Digits);
   double sl, tp;
   string note;

   if(!BuildStops(dir, price, atr, sl, tp, note))
      return(false);

   double slDist = MathAbs(price - sl);
   if(slDist <= 0.0)
     { SetReject(REJ_SL_TIGHT, "distanza SL nulla dopo la normalizzazione"); return(false); }

   double lots = CalculateLotSize(slDist);
   if(lots <= 0.0)
     { SetReject(REJ_LOTS, "volume non calcolabile per il rischio richiesto"); return(false); }

   string comment = TradeComment + (dir > 0 ? "-B" : "-S") + IntegerToString(g_lastScore);

   if(VerboseLog)
      Print("[", TradeComment, "] Invio ", (dir > 0 ? "BUY" : "SELL"),
            " | Lots=", DoubleToString(lots, g_lotDigits),
            " Price=", DoubleToString(price, Digits),
            " SL=", DoubleToString(sl, Digits),
            " TP=", DoubleToString(tp, Digits),
            " | ", note,
            " | ATR=", DoubleToString(atr / g_pip, 1), " pips",
            " | Rischio=", DoubleToString(RiskAmount(), 2), " ", AccountCurrency());

   int ticket = SendOrderWithRetries((dir > 0 ? OP_BUY : OP_SELL), lots, price, sl, tp, comment);

   if(ticket > 0)
     {
      RegisterPosition(ticket, (dir > 0 ? OP_BUY : OP_SELL), lots, slDist);
      g_lastTradeTime = TimeCurrent();
      g_lastTradeBar  = iTime(Symbol(), g_tf, 0);
      g_tradesToday++;
      SetReject(REJ_NONE, "-");
      if(ShowSignals)
         DrawSignalArrow(dir, price);
      return(true);
     }

   SetReject(REJ_SEND, "invio ordine fallito");
   return(false);
  }

//+------------------------------------------------------------------+
//| Ordine limite sul bordo dell'order block                         |
//| Modalita' alternativa: invece di inseguire la conferma si lascia |
//| il lavoro al prezzo. Riempimento incerto, ingresso migliore.     |
//+------------------------------------------------------------------+
bool PlaceLimitOrder(int dir)
  {
   if(g_activeOB < 0 || !g_ob[g_activeOB].used || g_ob[g_activeOB].dead)
     { SetReject(REJ_NOOB, "modalita' limite senza order block valido"); return(false); }

   RefreshRates();

   double atr = AtrE(1);
   double obHi = g_ob[g_activeOB].hi;
   double obLo = g_ob[g_activeOB].lo;
   double depth = MathMax(0.0, MathMin(1.0, LimitEntryDepth));

   //--- Bordo esterno della zona + profondita' richiesta
   double entry = (dir > 0) ? (obHi - (obHi - obLo) * depth)
                            : (obLo + (obHi - obLo) * depth);
   entry = NormalizeDouble(entry, Digits);

   //--- Il limite deve trovarsi dalla parte giusta del mercato
   double minDist = BrokerMinStopDistance();
   if(dir > 0 && entry >= Ask - minDist)
     { SetReject(REJ_STOPLEVEL, "limite troppo vicino al prezzo corrente"); return(false); }
   if(dir < 0 && entry <= Bid + minDist)
     { SetReject(REJ_STOPLEVEL, "limite troppo vicino al prezzo corrente"); return(false); }

   double sl, tp;
   string note;
   if(!BuildStops(dir, entry, atr, sl, tp, note))
      return(false);

   double slDist = MathAbs(entry - sl);
   double lots   = CalculateLotSize(slDist);
   if(lots <= 0.0)
     { SetReject(REJ_LOTS, "volume non calcolabile"); return(false); }

   datetime expiry = 0;
   if(PendingExpiryBars > 0)
      expiry = TimeCurrent() + PendingExpiryBars * g_tf * 60;

   string comment = TradeComment + (dir > 0 ? "-BL" : "-SL") + IntegerToString(g_lastScore);
   int    type    = (dir > 0) ? OP_BUYLIMIT : OP_SELLLIMIT;

   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, entry, g_slippagePoints, sl, tp,
                          comment, MagicNumber, expiry, clrGold);

   //--- Alcuni broker rifiutano la scadenza: si ritenta senza, la
   //    validita' viene poi gestita da CleanupPendingOrders().
   if(ticket < 0 && GetLastError() == 147 && expiry > 0)
     {
      ResetLastError();
      ticket = OrderSend(Symbol(), type, lots, entry, g_slippagePoints, sl, tp,
                         comment, MagicNumber, 0, clrGold);
     }

   if(ticket > 0)
     {
      g_lastTradeBar = iTime(Symbol(), g_tf, 0);
      SetReject(REJ_NONE, "-");
      if(VerboseLog)
         Print("[", TradeComment, "] Limite ", (dir > 0 ? "BUY" : "SELL"),
               " a ", DoubleToString(entry, Digits),
               " SL=", DoubleToString(sl, Digits),
               " TP=", DoubleToString(tp, Digits),
               " Lots=", DoubleToString(lots, g_lotDigits),
               " | ", note);
      return(true);
     }

   int err = GetLastError();
   Print("[", TradeComment, "] Invio ordine limite fallito, errore ", err, ": ", ErrorDescription(err));
   SetReject(REJ_SEND, "ordine limite rifiutato (" + IntegerToString(err) + ")");
   return(false);
  }

//+------------------------------------------------------------------+
//| Ordini pendenti: scadenza manuale e invalidazione della zona     |
//+------------------------------------------------------------------+
void CleanupPendingOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUYLIMIT && OrderType() != OP_SELLLIMIT)
         continue;

      bool drop   = false;
      string why  = "";

      //--- Scadenza per barre trascorse
      if(PendingExpiryBars > 0)
        {
         int barsOpen = iBarShift(Symbol(), g_tf, OrderOpenTime(), false);
         if(barsOpen > PendingExpiryBars)
           { drop = true; why = "scaduto dopo " + IntegerToString(barsOpen) + " barre"; }
        }

      //--- Bias invertito: il motivo dell'ordine non esiste piu'
      if(!drop)
        {
         int wanted = (OrderType() == OP_BUYLIMIT) ? 1 : -1;
         if(g_bias != wanted)
           { drop = true; why = "bias non piu' coerente"; }
        }

      if(drop)
        {
         if(OrderDelete(OrderTicket(), clrGray))
           {
            if(VerboseLog)
               Print("[", TradeComment, "] Ordine pendente ", OrderTicket(), " rimosso: ", why);
           }
         else
            Print("[", TradeComment, "] OrderDelete fallito su ", OrderTicket(),
                  ", errore ", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| Invio ordine a mercato con retry                                 |
//+------------------------------------------------------------------+
int SendOrderWithRetries(int orderType, double lots, double price, double sl, double tp, string comment)
  {
   int ticket = -1;

   for(int attempt = 1; attempt <= MaxRetries; attempt++)
     {
      if(!WaitForTradeContext())
        {
         Print("[", TradeComment, "] Contesto di trading occupato, tentativo ", attempt, " annullato.");
         continue;
        }

      RefreshRates();

      //--- Le DISTANZE si conservano, i prezzi si riallineano al mercato
      double slDist = MathAbs(price - sl);
      double tpDist = MathAbs(price - tp);

      price = NormalizeDouble((orderType == OP_BUY ? Ask : Bid), Digits);

      if(orderType == OP_BUY)
        {
         sl = NormalizeDouble(price - slDist, Digits);
         tp = NormalizeDouble(price + tpDist, Digits);
        }
      else
        {
         sl = NormalizeDouble(price + slDist, Digits);
         tp = NormalizeDouble(price - tpDist, Digits);
        }

      double sendSL = (TwoStepStops ? 0.0 : sl);
      double sendTP = (TwoStepStops ? 0.0 : tp);

      ResetLastError();
      ticket = OrderSend(Symbol(), orderType, lots, price, g_slippagePoints, sendSL, sendTP,
                         comment, MagicNumber, 0, (orderType == OP_BUY ? clrDodgerBlue : clrOrangeRed));

      if(ticket > 0)
        {
         if(TwoStepStops)
           {
            if(!ModifyOrderWithRetries(ticket, sl, tp))
              {
               Print("[", TradeComment, "] ATTENZIONE: SL/TP non impostabili sul ticket ", ticket,
                     ". Chiusura immediata per non lasciare la posizione scoperta.");
               ClosePositionByTicket(ticket);
               return(-1);
              }
           }

         if(VerboseLog)
            Print("[", TradeComment, "] Ordine eseguito. Ticket=", ticket,
                  " Lots=", DoubleToString(lots, g_lotDigits),
                  " Price=", DoubleToString(price, Digits),
                  " SL=", DoubleToString(sl, Digits),
                  " TP=", DoubleToString(tp, Digits));
         return(ticket);
        }

      int err = GetLastError();
      Print("[", TradeComment, "] OrderSend fallito (tentativo ", attempt, "/", MaxRetries,
            ") errore ", err, ": ", ErrorDescription(err),
            " | Price=", DoubleToString(price, Digits),
            " SL=", DoubleToString(sendSL, Digits),
            " TP=", DoubleToString(sendTP, Digits),
            " Lots=", DoubleToString(lots, g_lotDigits));

      //--- Errore 130: apertura senza stop e modifica immediata
      if(err == 130 && !TwoStepStops)
        {
         ResetLastError();
         RefreshRates();
         price = NormalizeDouble((orderType == OP_BUY ? Ask : Bid), Digits);

         double widen = BrokerMinStopDistance() * 1.5;
         if(orderType == OP_BUY)
           {
            sl = NormalizeDouble(price - MathMax(slDist, widen), Digits);
            tp = NormalizeDouble(price + MathMax(tpDist, widen), Digits);
           }
         else
           {
            sl = NormalizeDouble(price + MathMax(slDist, widen), Digits);
            tp = NormalizeDouble(price - MathMax(tpDist, widen), Digits);
           }

         ticket = OrderSend(Symbol(), orderType, lots, price, g_slippagePoints, 0.0, 0.0,
                            comment, MagicNumber, 0, clrGray);
         if(ticket > 0)
           {
            if(!ModifyOrderWithRetries(ticket, sl, tp))
              {
               Print("[", TradeComment, "] ATTENZIONE: SL/TP non impostabili sul ticket ", ticket,
                     ". Chiusura immediata della posizione.");
               ClosePositionByTicket(ticket);
               return(-1);
              }
            Print("[", TradeComment, "] Ordine eseguito in due passaggi. Ticket=", ticket);
            return(ticket);
           }
         err = GetLastError();
         Print("[", TradeComment, "] Anche l'apertura senza stop e' fallita, errore ", err,
               ": ", ErrorDescription(err));
        }

      if(!IsRetryableError(err))
         break;

      Sleep(RetryDelayMs * attempt);
     }

   return(-1);
  }

//+------------------------------------------------------------------+
//| Modifica SL/TP con retry                                         |
//+------------------------------------------------------------------+
bool ModifyOrderWithRetries(int ticket, double sl, double tp)
  {
   for(int attempt = 1; attempt <= MaxRetries; attempt++)
     {
      if(!WaitForTradeContext())
         continue;

      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
        {
         Print("[", TradeComment, "] OrderSelect fallito sul ticket ", ticket,
               ", errore ", GetLastError());
         Sleep(RetryDelayMs);
         continue;
        }

      //--- Niente da fare: evita l'errore 1 (parametri invariati)
      if(MathAbs(OrderStopLoss() - sl) < Point * 0.5 && MathAbs(OrderTakeProfit() - tp) < Point * 0.5)
         return(true);

      RefreshRates();
      ResetLastError();

      if(OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(sl, Digits),
                     NormalizeDouble(tp, Digits), 0, clrDodgerBlue))
         return(true);

      int err = GetLastError();
      if(err == 1)
         return(true);

      Print("[", TradeComment, "] OrderModify fallito (tentativo ", attempt, "/", MaxRetries,
            ") ticket ", ticket, ", errore ", err, ": ", ErrorDescription(err));

      if(!IsRetryableError(err))
         return(false);

      Sleep(RetryDelayMs * attempt);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Chiusura di una posizione per ticket                             |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(int ticket)
  {
   for(int attempt = 1; attempt <= MaxRetries; attempt++)
     {
      if(!WaitForTradeContext())
         continue;
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
         return(false);
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         return(false);

      RefreshRates();
      double price = (OrderType() == OP_BUY) ? Bid : Ask;

      ResetLastError();
      if(OrderClose(ticket, OrderLots(), NormalizeDouble(price, Digits), g_slippagePoints, clrWhite))
         return(true);

      int err = GetLastError();
      Print("[", TradeComment, "] OrderClose fallito (tentativo ", attempt, "/", MaxRetries,
            ") ticket ", ticket, ", errore ", err, ": ", ErrorDescription(err));

      if(!IsRetryableError(err))
         return(false);

      Sleep(RetryDelayMs * attempt);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Chiusura di tutte le posizioni dell'EA                           |
//+------------------------------------------------------------------+
void CloseAllOwnPositions(string reason)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;

      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
        {
         Print("[", TradeComment, "] Chiusura ticket ", OrderTicket(), ": ", reason);
         ClosePositionByTicket(OrderTicket());
        }
      else
         OrderDelete(OrderTicket(), clrGray);
     }
  }

//+------------------------------------------------------------------+
//| Dimensionamento del volume sul rischio percentuale               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice, bool logErrors = true)
  {
   if(FixedLots > 0.0)
      return(NormalizeLots(FixedLots));

   if(slDistancePrice <= 0.0)
      return(0.0);

   double riskMoney = RiskAmount();
   if(riskMoney <= 0.0)
      return(0.0);

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickSize <= 0.0)
      tickSize = Point;

   if(tickValue <= 0.0)
     {
      if(logErrors)
         Print("[", TradeComment, "] TICKVALUE non disponibile per ", Symbol(), ": sizing impossibile.");
      return(0.0);
     }

   //--- Perdita in valuta conto per 1.0 lotto se lo SL viene colpito,
   //    commissione round-turn inclusa nel budget di rischio.
   double lossPerLot = (slDistancePrice / tickSize) * tickValue + CommissionPerLot;
   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;

   double marginPerLot = MarketInfo(Symbol(), MODE_MARGINREQUIRED);
   if(marginPerLot > 0.0)
     {
      double affordable = (AccountFreeMargin() * 0.90) / marginPerLot;
      if(affordable < lots)
        {
         if(VerboseLog && logErrors)
            Print("[", TradeComment, "] Volume ridotto da ", DoubleToString(lots, 4),
                  " a ", DoubleToString(affordable, 4), " per vincolo di margine.");
         lots = affordable;
        }
     }

   if(MaxLotCap > 0.0 && lots > MaxLotCap)
      lots = MaxLotCap;

   lots = NormalizeLots(lots);
   if(lots <= 0.0)
      return(0.0);

   //--- Il lotto minimo del broker puo' eccedere il budget di rischio
   double realRisk = lots * lossPerLot;
   if(realRisk > riskMoney * 1.5)
     {
      if(logErrors)
         Print("[", TradeComment, "] Lotto minimo (", DoubleToString(lots, g_lotDigits),
               ") con rischio ", DoubleToString(realRisk, 2), " ", AccountCurrency(),
               " oltre il budget di ", DoubleToString(riskMoney, 2), ". Operazione annullata.");
      return(0.0);
     }

   return(lots);
  }

double NormalizeLots(double lots)
  {
   if(lots <= 0.0)
      return(0.0);

   lots = MathFloor(lots / g_lotStep + 0.0000001) * g_lotStep;
   lots = NormalizeDouble(lots, g_lotDigits);

   if(lots < g_minLot) lots = g_minLot;
   if(lots > g_maxLot) lots = g_maxLot;

   return(NormalizeDouble(lots, g_lotDigits));
  }

int VolumeDigits(double step)
  {
   for(int d = 0; d <= 8; d++)
     {
      double scaled = step * MathPow(10.0, d);
      if(MathAbs(scaled - MathRound(scaled)) < 0.0000001)
         return(d);
     }
   return(2);
  }

double RiskAmount()
  {
   double capital = (RiskBase == RISK_ON_EQUITY) ? AccountEquity() : AccountBalance();
   if(capital <= 0.0)
      return(0.0);
   return(capital * RiskPercent / 100.0);
  }

//+------------------------------------------------------------------+
//| TRACCIAMENTO DELLE POSIZIONI                                     |
//| In MT4 una chiusura parziale genera un NUOVO ticket: senza un    |
//| tracciamento indipendente si perde il rischio iniziale, e con    |
//| esso il significato di "1R". La chiave e' (tipo, ora, prezzo di  |
//| apertura), che il parziale conserva.                             |
//+------------------------------------------------------------------+
void ClearTracking()
  {
   for(int i = 0; i < MAX_TRACK; i++)
     {
      g_track[i].used        = false;
      g_track[i].ticket      = -1;
      g_track[i].type        = -1;
      g_track[i].openTime    = 0;
      g_track[i].openPrice   = 0.0;
      g_track[i].initLots    = 0.0;
      g_track[i].initRisk    = 0.0;
      g_track[i].partialDone = false;
      g_track[i].beDone      = false;
      g_track[i].seen        = false;
     }
  }

void RegisterPosition(int ticket, int type, double lots, double riskDistance)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return;

   int slot = -1;
   for(int i = 0; i < MAX_TRACK; i++)
      if(!g_track[i].used)
        { slot = i; break; }

   if(slot < 0)
      return;

   g_track[slot].used        = true;
   g_track[slot].ticket      = ticket;
   g_track[slot].type        = type;
   g_track[slot].openTime    = OrderOpenTime();
   g_track[slot].openPrice   = OrderOpenPrice();
   g_track[slot].initLots    = lots;
   g_track[slot].initRisk    = riskDistance;
   g_track[slot].partialDone = false;
   g_track[slot].beDone      = false;
   g_track[slot].seen        = true;
  }

//--- Trova il tracciamento della posizione selezionata, o lo ricostruisce
int FindTrack()
  {
   for(int i = 0; i < MAX_TRACK; i++)
     {
      if(!g_track[i].used)
         continue;
      if(g_track[i].type != OrderType())
         continue;
      if(g_track[i].openTime != OrderOpenTime())
         continue;
      if(MathAbs(g_track[i].openPrice - OrderOpenPrice()) > Point * 0.5)
         continue;

      g_track[i].ticket = OrderTicket();   // il parziale lo ha cambiato
      return(i);
     }

   //--- Ricostruzione dopo un riavvio del terminale: il rischio iniziale
   //    non e' piu' recuperabile, si usa lo stop attuale come stima e si
   //    considera il parziale gia' eseguito per non ripeterlo.
   int slot = -1;
   for(int i = 0; i < MAX_TRACK; i++)
      if(!g_track[i].used)
        { slot = i; break; }

   if(slot < 0)
      return(-1);

   double risk = (OrderStopLoss() > 0.0) ? MathAbs(OrderOpenPrice() - OrderStopLoss())
                                         : AtrE(1) * MaxSL_ATR * 0.5;

   //--- Uno stop gia' portato a pareggio o oltre dice che la posizione e'
   //    stata gestita: parziale e break-even si considerano fatti. Uno stop
   //    ancora sotto l'ingresso dice il contrario, ed e' il caso normale
   //    di un ordine limite appena riempito.
   bool managed = false;
   if(OrderStopLoss() > 0.0)
      managed = (OrderType() == OP_BUY) ? (OrderStopLoss() >= OrderOpenPrice())
                                        : (OrderStopLoss() <= OrderOpenPrice());

   g_track[slot].used        = true;
   g_track[slot].ticket      = OrderTicket();
   g_track[slot].type        = OrderType();
   g_track[slot].openTime    = OrderOpenTime();
   g_track[slot].openPrice   = OrderOpenPrice();
   g_track[slot].initLots    = OrderLots();
   g_track[slot].initRisk    = risk;
   g_track[slot].partialDone = managed;
   g_track[slot].beDone      = managed;
   g_track[slot].seen        = true;

   if(VerboseLog)
      Print("[", TradeComment, "] Posizione ", OrderTicket(),
            " adottata: rischio stimato ", DoubleToString(risk / g_pip, 1),
            " pips, gestione ", (managed ? "gia' avviata" : "da eseguire"), ".");

   return(slot);
  }

//+------------------------------------------------------------------+
//| GESTIONE DELLE POSIZIONI APERTE                                  |
//| Tutto e' espresso in R (multipli del rischio iniziale): le       |
//| soglie restano valide cambiando volatilita', simbolo o           |
//| dimensione del conto.                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   for(int i = 0; i < MAX_TRACK; i++)
      g_track[i].seen = false;

   double atr = AtrE(1);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      int t = FindTrack();
      if(t < 0)
         continue;

      g_track[t].seen = true;

      RefreshRates();

      int    ticket   = OrderTicket();
      bool   isBuy    = (OrderType() == OP_BUY);
      double open     = OrderOpenPrice();
      double sl       = OrderStopLoss();
      double tp       = OrderTakeProfit();
      double risk     = g_track[t].initRisk;
      double current  = isBuy ? Bid : Ask;

      if(risk <= 0.0)
         continue;

      double rMultiple = (isBuy ? (current - open) : (open - current)) / risk;

      //--- 1) Chiusura parziale al primo obiettivo.
      //    Se scatta, il ticket cambia: si riprende al tick successivo.
      if(UsePartialClose && !g_track[t].partialDone && rMultiple >= PartialAtR)
         if(TryPartialClose(t, ticket, isBuy))
            continue;

      //--- 2) Break-even
      double newSL = sl;

      if(UseBreakEven && !g_track[t].beDone && rMultiple >= BE_TriggerR)
        {
         double lock = risk * BE_LockR;
         double be   = isBuy ? (open + lock) : (open - lock);

         if((isBuy && (sl <= 0.0 || be > sl)) || (!isBuy && (sl <= 0.0 || be < sl)))
            newSL = be;
        }

      //--- 3) Trailing stop
      if(TrailMode != TRAIL_OFF && rMultiple >= TrailStartR && atr > 0.0)
        {
         double candidate = ComputeTrailingStop(isBuy, current, atr);

         if(candidate > 0.0)
           {
            double step = atr * TrailStepATR;
            if(isBuy  && candidate > newSL + step) newSL = candidate;
            if(!isBuy && (newSL <= 0.0 || candidate < newSL - step)) newSL = candidate;
           }
        }

      //--- 4) Applicazione, con i vincoli del broker e senza mai arretrare
      if(newSL != sl && newSL > 0.0)
        {
         double minDist = BrokerMinStopDistance();
         double freeze  = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;

         bool tooClose = isBuy ? (current - newSL < minDist) : (newSL - current < minDist);
         bool frozen   = isBuy ? (current - newSL < freeze)  : (newSL - current < freeze);
         bool backward = isBuy ? (sl > 0.0 && newSL <= sl)   : (sl > 0.0 && newSL >= sl);

         if(!tooClose && !frozen && !backward)
           {
            if(ModifyOrderWithRetries(ticket, NormalizeDouble(newSL, Digits), tp))
              {
               if(UseBreakEven && !g_track[t].beDone && rMultiple >= BE_TriggerR)
                  g_track[t].beDone = true;

               if(VerboseLog)
                  Print("[", TradeComment, "] Stop aggiornato su ", ticket,
                        " a ", DoubleToString(newSL, Digits),
                        " (", DoubleToString(rMultiple, 2), "R)");
              }
           }
        }
     }

   //--- Pulizia dei tracciamenti orfani
   for(int i = 0; i < MAX_TRACK; i++)
      if(g_track[i].used && !g_track[i].seen)
        {
         g_track[i].used   = false;
         g_track[i].ticket = -1;
        }
  }

//+------------------------------------------------------------------+
//| Livello di trailing secondo la modalita' scelta                  |
//+------------------------------------------------------------------+
double ComputeTrailingStop(bool isBuy, double current, double atr)
  {
   double buf = atr * TrailBufferATR;

   switch(TrailMode)
     {
      case TRAIL_ATR:
         return(isBuy ? current - atr * TrailATR : current + atr * TrailATR);

      case TRAIL_EMA:
        {
         double ema = EmaFast(1);
         if(ema <= 0.0)
            return(0.0);
         return(isBuy ? ema - buf : ema + buf);
        }

      case TRAIL_STRUCT:
        {
         int    swShift = -1;
         double swing   = isBuy ? LastSwingLow(2, OB_StructureBars, swShift)
                                : LastSwingHigh(2, OB_StructureBars, swShift);
         if(swing <= 0.0)
            return(0.0);
         return(isBuy ? swing - buf : swing + buf);
        }
     }

   return(0.0);
  }

//+------------------------------------------------------------------+
//| Chiusura parziale al raggiungimento di PartialAtR                |
//+------------------------------------------------------------------+
bool TryPartialClose(int t, int ticket, bool isBuy)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return(false);

   double closeLots = NormalizeDouble(g_track[t].initLots * PartialPercent / 100.0, g_lotDigits);
   closeLots = MathFloor(closeLots / g_lotStep + 0.0000001) * g_lotStep;
   closeLots = NormalizeDouble(closeLots, g_lotDigits);

   double remaining = OrderLots() - closeLots;

   //--- Il residuo deve restare un ordine valido, altrimenti il
   //    parziale si trasformerebbe in una chiusura totale mascherata.
   if(closeLots < g_minLot || remaining < g_minLot)
     {
      g_track[t].partialDone = true;
      if(VerboseLog)
         Print("[", TradeComment, "] Parziale saltato su ", ticket,
               ": volume troppo piccolo per lasciare un residuo valido.");
      return(false);
     }

   if(!WaitForTradeContext())
      return(false);

   RefreshRates();
   double price = isBuy ? Bid : Ask;

   ResetLastError();
   if(OrderClose(ticket, closeLots, NormalizeDouble(price, Digits), g_slippagePoints, clrAqua))
     {
      g_track[t].partialDone = true;
      Print("[", TradeComment, "] Parziale eseguito su ", ticket, ": ",
            DoubleToString(closeLots, g_lotDigits), " lotti a ", DoubleToString(PartialAtR, 2), "R");
      return(true);
     }

   int err = GetLastError();
   Print("[", TradeComment, "] Chiusura parziale fallita su ", ticket,
         ", errore ", err, ": ", ErrorDescription(err));
   if(!IsRetryableError(err))
      g_track[t].partialDone = true;   // inutile ritentare ad ogni tick

   return(false);
  }

//+------------------------------------------------------------------+
//| Uscite programmate: tempo, sessione, venerdi', bias invertito    |
//+------------------------------------------------------------------+
void HandleScheduledExits()
  {
   //--- Venerdi'
   if(CloseAllOnFriday && FridayCloseHour > 0 &&
      DayOfWeek() == 5 && TimeHour(TimeCurrent()) >= FridayCloseHour)
     {
      if(CountOwnPositions() > 0 || CountOwnPendings() > 0)
         CloseAllOwnPositions("chiusura di fine settimana");
      return;
     }

   //--- Fine sessione
   if(CloseAtSessionEnd && UseSessionFilter && !IsSessionOpenNow())
     {
      if(CountOwnPositions() > 0 || CountOwnPendings() > 0)
         CloseAllOwnPositions("fine della sessione operativa");
      return;
     }

   if(MaxBarsInTrade <= 0 && !CloseOnBiasFlip)
      return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      //--- Tempo massimo in posizione: un trend continuation che dopo
      //    N barre non ha lavorato non e' piu' quel trade.
      if(MaxBarsInTrade > 0)
        {
         int bars = iBarShift(Symbol(), g_tf, OrderOpenTime(), false);
         if(bars >= MaxBarsInTrade)
           {
            Print("[", TradeComment, "] Uscita per tempo su ", OrderTicket(),
                  ": ", bars, " barre in posizione.");
            ClosePositionByTicket(OrderTicket());
            continue;
           }
        }

      //--- Bias invertito
      if(CloseOnBiasFlip && g_bias != 0)
        {
         int posDir = (OrderType() == OP_BUY) ? 1 : -1;
         if(g_bias == -posDir)
           {
            Print("[", TradeComment, "] Uscita su ", OrderTicket(), ": bias superiore invertito.");
            ClosePositionByTicket(OrderTicket());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Conteggi                                                         |
//+------------------------------------------------------------------+
int CountOwnPositions()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         n++;
     }
   return(n);
  }

int CountOwnPendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() == OP_BUYLIMIT || OrderType() == OP_SELLLIMIT ||
         OrderType() == OP_BUYSTOP  || OrderType() == OP_SELLSTOP)
         n++;
     }
   return(n);
  }

//+------------------------------------------------------------------+
//| Filtri operativi                                                 |
//+------------------------------------------------------------------+
bool IsInCooldown()
  {
   if(CooldownBars <= 0 || g_lastTradeBar == 0)
      return(false);

   int bars = iBarShift(Symbol(), g_tf, g_lastTradeBar, false);
   return(bars >= 0 && bars < CooldownBars);
  }

bool IsSpreadAcceptable()
  {
   double spread = MathMax(Ask - Bid, 0.0);

   if(MaxSpreadPips > 0.0 && spread > MaxSpreadPips * g_pip)
     {
      SetReject(REJ_SPREAD, StringFormat("spread %.1f pips oltre il massimo %.1f",
                                         spread / g_pip, MaxSpreadPips));
      return(false);
     }

   //--- Su M5 e' questo il filtro che conta davvero: uno spread che vale
   //    il 15% dell'ATR si mangia il vantaggio prima ancora di entrare.
   if(MaxSpreadToATR > 0.0)
     {
      double atr = AtrE(1);
      if(atr > 0.0 && spread > atr * MaxSpreadToATR)
        {
         SetReject(REJ_SPREAD_ATR, StringFormat("spread %.1f%% dell'ATR oltre il massimo %.0f%%",
                                                spread / atr * 100.0, MaxSpreadToATR * 100.0));
         return(false);
        }
     }

   return(true);
  }

bool IsSessionOpenNow()
  {
   if(!UseSessionFilter)
      return(true);

   int hour = TimeHour(TimeCurrent());

   if(SessionStartHour < SessionEndHour)
      return(hour >= SessionStartHour && hour < SessionEndHour);

   //--- Sessione a cavallo della mezzanotte
   return(hour >= SessionStartHour || hour < SessionEndHour);
  }

bool IsSessionAllowed()
  {
   if(!IsSessionOpenNow())
      return(false);

   if(FridayCloseHour > 0 && DayOfWeek() == 5 && TimeHour(TimeCurrent()) >= FridayCloseHour)
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| Stato giornaliero e serie di perdite                             |
//+------------------------------------------------------------------+
datetime g_lastLossClose = 0;   // Chiusura dell'ultima perdita conteggiata
datetime g_pauseAnchor   = 0;   // Perdita che ha gia' generato una pausa
double   g_dayRealized   = 0.0; // Realizzato di giornata

void ResetDailyState(bool force)
  {
   datetime now      = TimeCurrent();
   datetime dayStart = now - (now % 86400);

   if(force || dayStart != g_dayStamp)
     {
      g_dayStamp        = dayStart;
      g_dayStartBalance = AccountBalance();
      g_tradesToday     = CountTradesToday();
      g_dailyBlocked    = false;

      if(!force && VerboseLog)
         Print("[", TradeComment, "] Nuova giornata: saldo di partenza ",
               DoubleToString(g_dayStartBalance, 2), " ", AccountCurrency());
     }

   UpdateTradeStats();

   //--- Serie di perdite consecutive
   if(MaxConsecutiveLosses > 0 && g_lossStreak >= MaxConsecutiveLosses &&
      g_lastLossClose > g_pauseAnchor)
     {
      g_pauseAnchor = g_lastLossClose;
      g_pauseUntil  = now + PauseBarsAfterLosses * g_tf * 60;
      Print("[", TradeComment, "] ", g_lossStreak, " perdite consecutive: pausa fino a ",
            TimeToString(g_pauseUntil, TIME_DATE|TIME_MINUTES));
     }

   //--- Limiti giornalieri
   if(g_dayStartBalance <= 0.0)
      return;

   double result = g_dayRealized;
   if(IncludeFloatingInDD)
      result += FloatingProfit();

   double resultPct = result / g_dayStartBalance * 100.0;

   if(MaxDailyLossPercent > 0.0 && resultPct <= -MaxDailyLossPercent && !g_dailyBlocked)
     {
      g_dailyBlocked = true;
      SetReject(REJ_DAILY_LOSS, StringFormat("stop giornaliero: %.2f%% del saldo", resultPct));
      Print("[", TradeComment, "] STOP GIORNALIERO raggiunto (", DoubleToString(resultPct, 2),
            "%): nessun nuovo ingresso fino a domani.");
     }

   if(DailyProfitTarget > 0.0 && resultPct >= DailyProfitTarget && !g_dailyBlocked)
     {
      g_dailyBlocked = true;
      SetReject(REJ_DAILY_TARGET, StringFormat("target giornaliero raggiunto: +%.2f%%", resultPct));
      Print("[", TradeComment, "] TARGET GIORNALIERO raggiunto (+", DoubleToString(resultPct, 2),
            "%): operativita' sospesa fino a domani.");
     }
  }

//+------------------------------------------------------------------+
//| Trade dell'EA aperti oggi                                        |
//+------------------------------------------------------------------+
int CountTradesToday()
  {
   int n = 0;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(OrderOpenTime() >= g_dayStamp)
         n++;
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(OrderOpenTime() >= g_dayStamp)
         n++;
     }

   return(n);
  }

//+------------------------------------------------------------------+
//| Statistiche storiche dell'EA (con cache)                         |
//+------------------------------------------------------------------+
void UpdateTradeStats()
  {
   static datetime lastCalc    = 0;
   static int      lastHistory = -1;

   int history = OrdersHistoryTotal();
   if(history == lastHistory && TimeCurrent() - lastCalc < 5)
      return;

   lastHistory = history;
   lastCalc    = TimeCurrent();

   g_statNet      = 0.0;
   g_statGross    = 0.0;
   g_statLoss     = 0.0;
   g_statWins     = 0;
   g_statLosses   = 0;
   g_dayRealized  = 0.0;

   int todayCount = 0;

   datetime lastCloseSeen = 0;
   int      streak        = 0;
   bool     streakOpen    = true;

   //--- Lo storico e' ordinato per chiusura: si scorre a ritroso per
   //    contare la serie di perdite piu' recente.
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      double net = OrderProfit() + OrderSwap() + OrderCommission();

      g_statNet += net;
      if(net >= 0.0)
        {
         g_statGross += net;
         g_statWins++;
        }
      else
        {
         g_statLoss += MathAbs(net);
         g_statLosses++;
        }

      if(OrderCloseTime() >= g_dayStamp)
         g_dayRealized += net;

      if(OrderOpenTime() >= g_dayStamp)
         todayCount++;

      //--- Serie di perdite: si interrompe al primo risultato positivo
      if(streakOpen)
        {
         if(net < 0.0)
           {
            streak++;
            if(OrderCloseTime() > lastCloseSeen)
               lastCloseSeen = OrderCloseTime();
           }
         else
            streakOpen = false;
        }
     }

   g_lossStreak = streak;
   if(lastCloseSeen > 0)
      g_lastLossClose = lastCloseSeen;

   //--- Posizioni ancora aperte oggi: un trade entrato da ordine limite
   //    non passa da OpenMarketPosition e sfuggirebbe al contatore.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(OrderOpenTime() >= g_dayStamp)
         todayCount++;
     }

   if(todayCount > g_tradesToday)
      g_tradesToday = todayCount;
  }

//+------------------------------------------------------------------+
//| Flottante delle sole posizioni dell'EA                           |
//+------------------------------------------------------------------+
double FloatingProfit()
  {
   double total = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      total += OrderProfit() + OrderSwap() + OrderCommission();
     }

   return(total);
  }

//+------------------------------------------------------------------+
//| Registrazione dello scarto (codice + testo nel journal)          |
//+------------------------------------------------------------------+
void SetReject(int code, string reason)
  {
   if(code == g_reject && reason == g_rejectText)
      return;

   g_reject     = code;
   g_rejectText = reason;

   if(VerboseLog && code != REJ_NONE)
      Print("[", TradeComment, "] Ingresso non eseguito: ", reason);
  }

//+------------------------------------------------------------------+
//| Aggiornamento dello stato di contesto (bias, banda, stato)       |
//| Serve anche quando non si valutano segnali: la dashboard deve    |
//| mostrare cosa sta guardando l'EA, non solo cosa ha fatto.        |
//+------------------------------------------------------------------+
void UpdateContextState()
  {
   g_bias = ComputeBias(g_biasStrength);

   double atr = AtrE(1);
   if(atr > 0.0)
      ComputeZone(1, atr, g_zoneLo, g_zoneHi);

   //--- Stima del prossimo trade: utile per dimensionare a colpo d'occhio
   if(atr > 0.0)
     {
      double refSL = MathMax(atr * MinSL_ATR, BrokerMinStopDistance());
      g_propLots = CalculateLotSize(refSL, false);
     }

   //--- Stato operativo
   if(CountOwnPositions() > 0)
     { g_state = ST_INPOS; return; }

   if(g_dailyBlocked ||
      (MaxTradesPerDay > 0 && g_tradesToday >= MaxTradesPerDay) ||
      (g_pauseUntil > 0 && TimeCurrent() < g_pauseUntil))
     { g_state = ST_BLOCKED; return; }

   if(!IsSessionAllowed())
     { g_state = ST_FILTER; return; }

   if(CountOwnPendings() > 0)
     { g_state = ST_ARMED; return; }

   if(g_bias == 0)
     { g_state = ST_NOBIAS; return; }

   double price = (Bid + Ask) * 0.5;
   if(g_zoneHi > 0.0 && price <= g_zoneHi && price >= g_zoneLo)
      g_state = ST_INZONE;
   else
      g_state = ST_WAITPB;
  }

//+------------------------------------------------------------------+
//|                          TELEMETRIA                              |
//| Tutte le chiavi sono numeriche: le GlobalVariables di MT4 sono   |
//| double. I testi (stato, motivo di scarto) viaggiano come codici  |
//| e vengono tradotti dalla dashboard. Prefisso:                    |
//|    EBOB_<SIMBOLO>_<MAGIC>_<chiave>                               |
//|                                                                  |
//| CHIAVI PUBBLICATE                                                |
//|  hb      heartbeat (TimeCurrent)     ver     versione * 100      |
//|  tfm     TF ingresso (minuti)        btf     TF bias (minuti)    |
//|  dig     Digits                      pip     valore del pip      |
//|  bias    -1/0/+1                     bstr    forza bias 0-100    |
//|  state   codice di stato             rej     codice di scarto    |
//|  score   confluenza 0-100            sig     ultimo segnale      |
//|  atr     ATR in prezzo               spr     spread in prezzo    |
//|  sprr    spread/ATR                  stoplv  stop level broker   |
//|  zlo/zhi banda EMA                   zin     prezzo nella banda  |
//|  bounce  rimbalzo confermato         bos     rottura struttura   |
//|  mom     momentum favorevole                                     |
//|  obn     order block validi          obdir   direzione OB attivo |
//|  oblo/obhi bordi OB attivo           obage   eta' in barre       |
//|  obtch   tocchi                      obimp   impulso in ATR      |
//|  pos     posizioni aperte            pend    ordini pendenti     |
//|  pdir    direzione                   plots   volume              |
//|  popen   prezzo di apertura          psl/ptp stop e target       |
//|  ppl     P/L flottante               pr      multiplo di R       |
//|  pbars   barre in posizione                                      |
//|  eq/bal  equity e saldo              dpl     P/L di giornata     |
//|  dplp    P/L giornata in %           dlim    limite giornaliero  |
//|  trd     trade oggi                  maxtrd  limite trade        |
//|  wins/los vinti e persi              pf      profit factor       |
//|  net     profitto totale             strk    perdite consecutive |
//|  block   operativita' sospesa        sess    sessione aperta     |
//|  cool    barre di cooldown residue   nbar    secondi a nuova barra|
//|  nlots   volume stimato              nrisk   rischio in valuta   |
//+------------------------------------------------------------------+
void PubD(string key, double value)
  {
   GlobalVariableSet(g_gvPrefix + key, value);
  }

void PublishTelemetryData(bool force)
  {
   if(!PublishTelemetry)
      return;

   //--- Nel tester senza grafico la dashboard non puo' esistere
   if(IsTesting() && !IsVisualMode() && !force)
      return;

   if(!force && TimeCurrent() - g_lastPublish < PublishSeconds)
      return;

   g_lastPublish = TimeCurrent();

   double atr    = AtrE(1);
   double spread = MathMax(Ask - Bid, 0.0);

   PubD("hb",   (double)TimeCurrent());
   PubD("ver",  100);
   PubD("tfm",  g_tf);
   PubD("btf",  g_biasTF);
   PubD("dig",  Digits);
   PubD("pip",  g_pip);

   PubD("bias", g_bias);
   PubD("bstr", g_biasStrength);
   PubD("state",g_state);
   PubD("rej",  g_reject);
   PubD("score",g_lastScore);
   PubD("sig",  g_lastSignal);

   PubD("atr",  atr);
   PubD("spr",  spread);
   PubD("sprr", (atr > 0.0 ? spread / atr : 0.0));
   PubD("stoplv", MarketInfo(Symbol(), MODE_STOPLEVEL) * Point);

   PubD("zlo",  g_zoneLo);
   PubD("zhi",  g_zoneHi);
   double mid = (Bid + Ask) * 0.5;
   PubD("zin",  (g_zoneHi > 0.0 && mid <= g_zoneHi && mid >= g_zoneLo) ? 1 : 0);
   PubD("bounce", g_bounceOk ? 1 : 0);
   PubD("bos",    g_bosOk    ? 1 : 0);
   PubD("mom",    g_momOk    ? 1 : 0);

   PubD("obn", CountLiveOB());
   if(g_activeOB >= 0 && g_ob[g_activeOB].used && !g_ob[g_activeOB].dead)
     {
      PubD("obdir", g_ob[g_activeOB].dir);
      PubD("oblo",  g_ob[g_activeOB].lo);
      PubD("obhi",  g_ob[g_activeOB].hi);
      PubD("obage", iBarShift(Symbol(), g_tf, g_ob[g_activeOB].born, false));
      PubD("obtch", g_ob[g_activeOB].touches);
      PubD("obimp", g_ob[g_activeOB].impulse);
     }
   else
     {
      PubD("obdir", 0); PubD("oblo", 0); PubD("obhi", 0);
      PubD("obage", 0); PubD("obtch", 0); PubD("obimp", 0);
     }

   //--- Posizione (la prima dell'EA)
   int    pos = 0, pdir = 0, pbars = 0;
   double plots = 0.0, popen = 0.0, psl = 0.0, ptp = 0.0, ppl = 0.0, pr = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      pos++;
      if(pos > 1)
         continue;

      bool isBuy = (OrderType() == OP_BUY);
      pdir  = isBuy ? 1 : -1;
      plots = OrderLots();
      popen = OrderOpenPrice();
      psl   = OrderStopLoss();
      ptp   = OrderTakeProfit();
      ppl   = OrderProfit() + OrderSwap() + OrderCommission();
      pbars = iBarShift(Symbol(), g_tf, OrderOpenTime(), false);

      int t = FindTrack();
      if(t >= 0 && g_track[t].initRisk > 0.0)
        {
         double cur = isBuy ? Bid : Ask;
         pr = (isBuy ? (cur - popen) : (popen - cur)) / g_track[t].initRisk;
        }
     }

   PubD("pos",  pos);
   PubD("pend", CountOwnPendings());
   PubD("pdir", pdir);
   PubD("plots",plots);
   PubD("popen",popen);
   PubD("psl",  psl);
   PubD("ptp",  ptp);
   PubD("ppl",  ppl);
   PubD("pr",   pr);
   PubD("pbars",pbars);

   //--- Conto e giornata
   double dayResult = g_dayRealized + (IncludeFloatingInDD ? FloatingProfit() : 0.0);

   PubD("eq",   AccountEquity());
   PubD("bal",  AccountBalance());
   PubD("dpl",  dayResult);
   PubD("dplp", (g_dayStartBalance > 0.0 ? dayResult / g_dayStartBalance * 100.0 : 0.0));
   PubD("dlim", MaxDailyLossPercent);
   PubD("trd",  g_tradesToday);
   PubD("maxtrd", MaxTradesPerDay);
   PubD("wins", g_statWins);
   PubD("los",  g_statLosses);
   PubD("pf",   (g_statLoss > 0.0 ? g_statGross / g_statLoss : 0.0));
   PubD("net",  g_statNet);
   PubD("strk", g_lossStreak);
   PubD("block",g_dailyBlocked ? 1 : 0);
   PubD("sess", IsSessionOpenNow() ? 1 : 0);

   int coolLeft = 0;
   if(CooldownBars > 0 && g_lastTradeBar > 0)
     {
      int bars = iBarShift(Symbol(), g_tf, g_lastTradeBar, false);
      coolLeft = (int)MathMax(0, CooldownBars - bars);
     }
   PubD("cool", coolLeft);

   datetime barOpen = iTime(Symbol(), g_tf, 0);
   PubD("nbar", MathMax(0, (int)(barOpen + g_tf * 60 - TimeCurrent())));

   PubD("nlots", g_propLots);
   PubD("nrisk", RiskAmount());
   PubD("psl0",  g_propSL);
   PubD("ptp0",  g_propTP);
  }

//+------------------------------------------------------------------+
//|                    VISUALIZZAZIONE SUL GRAFICO                   |
//| L'EA disegna solo cio' su cui decide: zone e frecce. Il pannello |
//| di stato e' compito della dashboard esterna.                     |
//+------------------------------------------------------------------+
void DrawVisuals()
  {
   if(!ShowOrderBlocks && !ShowZone)
      return;
   if(IsTesting() && !IsVisualMode())
      return;

   datetime rightEdge = TmE(0) + (datetime)(MathMax(1, OB_ExtendBars) * g_tf * 60);

   //--- Order block
   if(ShowOrderBlocks)
     {
      for(int i = 0; i < MAX_OB * 2; i++)
        {
         string name = g_objPrefix + "ob" + IntegerToString(i);

         if(!g_ob[i].used || g_ob[i].dead)
           {
            if(ObjectFind(0, name) >= 0)
               ObjectDelete(0, name);
            continue;
           }

         color clr = (g_ob[i].dir > 0) ? BullOBColor : BearOBColor;

         if(ObjectFind(0, name) < 0)
           {
            if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0,
                             g_ob[i].born, g_ob[i].hi, rightEdge, g_ob[i].lo))
               continue;
           }
         else
           {
            ObjectSetInteger(0, name, OBJPROP_TIME1,  g_ob[i].born);
            ObjectSetDouble (0, name, OBJPROP_PRICE1, g_ob[i].hi);
            ObjectSetInteger(0, name, OBJPROP_TIME2,  rightEdge);
            ObjectSetDouble (0, name, OBJPROP_PRICE2, g_ob[i].lo);
           }

         ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
         ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
         ObjectSetInteger(0, name, OBJPROP_BACK,       true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
        }
     }

   //--- Banda EMA dinamica sulle ultime barre
   if(ShowZone && g_zoneHi > 0.0)
     {
      string zname = g_objPrefix + "zone";
      datetime left = TmE((int)MathMin(iBars(Symbol(), g_tf) - 1, 60));

      if(ObjectFind(0, zname) < 0)
         ObjectCreate(0, zname, OBJ_RECTANGLE, 0, left, g_zoneHi, rightEdge, g_zoneLo);
      else
        {
         ObjectSetInteger(0, zname, OBJPROP_TIME1,  left);
         ObjectSetDouble (0, zname, OBJPROP_PRICE1, g_zoneHi);
         ObjectSetInteger(0, zname, OBJPROP_TIME2,  rightEdge);
         ObjectSetDouble (0, zname, OBJPROP_PRICE2, g_zoneLo);
        }

      ObjectSetInteger(0, zname, OBJPROP_COLOR,      ZoneColor);
      ObjectSetInteger(0, zname, OBJPROP_STYLE,      STYLE_DOT);
      ObjectSetInteger(0, zname, OBJPROP_BACK,       true);
      ObjectSetInteger(0, zname, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, zname, OBJPROP_HIDDEN,     true);
     }

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Freccia di ingresso                                              |
//+------------------------------------------------------------------+
void DrawSignalArrow(int dir, double price)
  {
   if(IsTesting() && !IsVisualMode())
      return;

   string name = g_objPrefix + "sig" + IntegerToString((int)TimeCurrent());

   if(!ObjectCreate(0, name, (dir > 0 ? OBJ_ARROW_BUY : OBJ_ARROW_SELL), 0, TimeCurrent(), price))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR,      (dir > 0 ? clrDodgerBlue : clrOrangeRed));
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetString (0, name, OBJPROP_TEXT,       "confluenza " + IntegerToString(g_lastScore) + "/100");
  }

//+------------------------------------------------------------------+
//| Rimozione dei soli oggetti dell'EA                               |
//+------------------------------------------------------------------+
void DeleteVisuals()
  {
   //--- Salvaguardia: senza prefisso il ciclo cancellerebbe ogni oggetto
   if(StringLen(g_objPrefix) == 0)
      return;

   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_objPrefix, 0) == 0)
         ObjectDelete(0, name);
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
bool WaitForTradeContext()
  {
   int waited = 0;
   while(IsTradeContextBusy() && waited < 5000)
     {
      Sleep(100);
      waited += 100;
     }
   return(!IsTradeContextBusy());
  }

bool IsRetryableError(int err)
  {
   switch(err)
     {
      case 4:    // ERR_SERVER_BUSY
      case 6:    // ERR_NO_CONNECTION
      case 128:  // ERR_TRADE_TIMEOUT
      case 129:  // ERR_INVALID_PRICE
      case 130:  // ERR_INVALID_STOPS
      case 135:  // ERR_PRICE_CHANGED
      case 136:  // ERR_OFF_QUOTES
      case 137:  // ERR_BROKER_BUSY
      case 138:  // ERR_REQUOTE
      case 146:  // ERR_TRADE_CONTEXT_BUSY
         return(true);
     }
   return(false);
  }

string ErrorDescription(int err)
  {
   switch(err)
     {
      case 0:    return("nessun errore");
      case 1:    return("nessun risultato / parametri invariati");
      case 2:    return("errore generico di trading");
      case 3:    return("parametri non validi");
      case 4:    return("server di trading occupato");
      case 5:    return("versione del terminale obsoleta");
      case 6:    return("nessuna connessione al server");
      case 8:    return("richieste troppo frequenti");
      case 64:   return("conto disabilitato");
      case 65:   return("numero di conto non valido");
      case 128:  return("timeout della transazione");
      case 129:  return("prezzo non valido");
      case 130:  return("stop non validi (troppo vicini al prezzo)");
      case 131:  return("volume non valido");
      case 132:  return("mercato chiuso");
      case 133:  return("trading disabilitato");
      case 134:  return("margine insufficiente");
      case 135:  return("prezzo cambiato");
      case 136:  return("quotazioni non disponibili (off quotes)");
      case 137:  return("broker occupato");
      case 138:  return("requote");
      case 139:  return("ordine bloccato ed in elaborazione");
      case 140:  return("consentito solo l'acquisto");
      case 141:  return("troppe richieste");
      case 145:  return("modifica vietata: ordine troppo vicino al mercato");
      case 146:  return("contesto di trading occupato");
      case 147:  return("scadenza non consentita dal broker");
      case 148:  return("numero di ordini aperti al limite");
      case 149:  return("hedging non consentito");
      case 150:  return("chiusura in violazione delle regole FIFO");
      case 4051: return("valore di parametro non valido");
      case 4066: return("dati storici in aggiornamento");
      case 4073: return("dati storici non disponibili");
      case 4108: return("numero di ticket non valido");
      case 4109: return("trading non consentito (abilitare l'AutoTrading)");
     }
   return("errore non catalogato");
  }

string DeinitReasonText(int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return("EA terminato");
      case REASON_REMOVE:      return("EA rimosso dal grafico");
      case REASON_RECOMPILE:   return("EA ricompilato");
      case REASON_CHARTCHANGE: return("simbolo o timeframe modificato");
      case REASON_CHARTCLOSE:  return("grafico chiuso");
      case REASON_PARAMETERS:  return("parametri modificati");
      case REASON_ACCOUNT:     return("account cambiato");
     }
   return("motivo sconosciuto");
  }

string TimeframeToString(int tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
     }
   return("TF" + IntegerToString(tf));
  }
//+------------------------------------------------------------------+
