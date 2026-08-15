//+------------------------------------------------------------------+
//|                                          AdaptiveEurUsdEA.mq4     |
//|            Adaptive Multi-Regime Expert Advisor - EURUSD          |
//|                  Regime H1  ->  Segnale M15  ->  Score            |
//|                            v1.00                                  |
//+------------------------------------------------------------------+
//                                                                    |
//  FILOSOFIA                                                         |
//  ---------                                                         |
//  L'EA non applica una strategia fissa. Prima classifica il REGIME   |
//  di mercato sul timeframe superiore (H1), poi attiva SOLO il motore |
//  di segnale coerente con quel regime sul timeframe operativo (M15): |
//                                                                    |
//     REG_TREND_UP / REG_TREND_DN -> Trend following su pullback      |
//     REG_BREAKOUT                -> Breakout / transizione           |
//     REG_RANGE                   -> Mean reversion                   |
//     REG_NONE                    -> nessuna operazione               |
//                                                                    |
//  L'adattivita' sta nella SELEZIONE DELLA STRATEGIA, non             |
//  nell'auto-modifica dei parametri sulla base degli ultimi trade.    |
//  Nessuna forma di ottimizzazione online: sarebbe solo overfitting   |
//  mascherato da intelligenza artificiale.                            |
//                                                                    |
//  ARCHITETTURA A DUE LIVELLI: GATE + SCORE                           |
//  ----------------------------------------                          |
//  1) HARD GATE (binari, non negoziabili): spread, sessione, ATR      |
//     sano, perdita giornaliera/settimanale, drawdown, posizioni      |
//     gia' aperte, coerenza con il regime. Se un gate fallisce il     |
//     trade e' scartato, qualunque sia il punteggio.                  |
//  2) SCORE (0..10, continuo): misura la QUALITA' del setup. Ogni     |
//     motore e' normalizzato sulla stessa scala 0..10, cosi' una      |
//     sola soglia (InpMinSignalScore) e' confrontabile tra strategie  |
//     diverse. Questo evita di dover ottimizzare tre soglie separate. |
//                                                                    |
//  ANTI-LOOK-AHEAD (fondamentale)                                     |
//  ------------------------------                                    |
//  * Ogni lettura di indicatore o di prezzo usa shift >= 1: la barra  |
//    in formazione (shift 0) non viene MAI usata per decidere.        |
//    Vale sia per M15 sia per H1: usare la candela H1 corrente come   |
//    se fosse chiusa e' l'errore piu' comune nei sistemi MTF.         |
//  * Gli swing (massimi/minimi strutturali) sono confermati con N     |
//    barre a destra gia' chiuse: uno swing non e' mai "scoperto"      |
//    prima che il mercato lo abbia confermato -> niente repainting.   |
//  * Le decisioni di ingresso avvengono solo alla chiusura di una     |
//    barra M15. La gestione della posizione, invece, gira a ogni tick.|
//                                                                    |
//  NOTA SULL'OBIETTIVO                                                |
//  -------------------                                               |
//  Il codice e' scritto per essere robusto, non per massimizzare il   |
//  profitto storico. Diverse soglie sono costanti interne e NON input |
//  ottimizzabili: e' una scelta deliberata per ridurre la superficie  |
//  di overfitting. Gli input realmente destinati all'ottimizzazione   |
//  sono marcati [OPT]; gli altri sono marcati [FIX] e andrebbero      |
//  toccati solo con una motivazione strutturale.                      |
//+------------------------------------------------------------------+
#property copyright "Adaptive EURUSD EA"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Enumerazioni                                                     |
//+------------------------------------------------------------------+
enum ENUM_REGIME
  {
   REG_NONE     = 0,   // Nessun regime chiaro -> NO TRADE
   REG_TREND_UP = 1,   // Trend rialzista consolidato
   REG_TREND_DN = 2,   // Trend ribassista consolidato
   REG_RANGE    = 3,   // Mercato laterale
   REG_BREAKOUT = 4    // Transizione / breakout in corso
  };

enum ENUM_STRATEGY
  {
   STRAT_NONE     = 0,  // Nessuna
   STRAT_TREND    = 1,  // Trend following su pullback
   STRAT_BREAKOUT = 2,  // Breakout / retest
   STRAT_MEANREV  = 3   // Mean reversion nel range
  };

enum ENUM_RISK_BASE
  {
   RISK_ON_EQUITY  = 0, // Rischio calcolato sull'Equity
   RISK_ON_BALANCE = 1  // Rischio calcolato sul Balance
  };

//+------------------------------------------------------------------+
//| INPUT: generale                                                  |
//+------------------------------------------------------------------+
input string          h_gen            = "===== GENERALE =====";          // .
input ENUM_TIMEFRAMES InpEntryTF       = PERIOD_M15;   // [FIX] Timeframe di ingresso
input ENUM_TIMEFRAMES InpRegimeTF      = PERIOD_H1;    // [FIX] Timeframe del regime
input int             InpMagic         = 20250816;     // Magic Number
input string          InpComment       = "AdaptEU";    // Prefisso commento ordini

//+------------------------------------------------------------------+
//| INPUT: market regime engine (H1)                                 |
//+------------------------------------------------------------------+
input string          h_reg            = "===== MARKET REGIME (H1) =====";// .
input int             InpAdxPeriod     = 14;    // [FIX] Periodo ADX
input double          InpAdxTrend      = 23.0;  // [OPT] ADX sopra il quale c'e' trend
input double          InpAdxRange      = 18.0;  // [OPT] ADX sotto il quale c'e' range
input int             InpEmaFast       = 20;    // [FIX] EMA veloce
input int             InpEmaMid        = 50;    // [OPT] EMA intermedia
input int             InpEmaSlow       = 200;   // [FIX] EMA lenta (bias strutturale)
input int             InpAtrPeriod     = 14;    // [FIX] Periodo ATR
input int             InpRegimeLookback= 20;    // [OPT] Barre H1 per struttura e range
input int             InpMinTrendScore = 4;     // [OPT] Punteggio minimo del trend H1 (0..6)

//+------------------------------------------------------------------+
//| INPUT: signal engine e scoring (M15)                             |
//+------------------------------------------------------------------+
input string          h_sig            = "===== SIGNAL / SCORING =====";  // .
input double          InpMinSignalScore= 6.0;   // [OPT] Punteggio minimo per operare (0..10)
input bool            InpEnableTrend   = true;  // Abilita motore Trend Following
input bool            InpEnableBreakout= true;  // Abilita motore Breakout
input bool            InpEnableMeanRev = true;  // Abilita motore Mean Reversion
input bool            InpUseVolumeFilter=true;  // Usa il tick volume nello scoring

//+------------------------------------------------------------------+
//| INPUT: trend strategy (M15)                                      |
//+------------------------------------------------------------------+
input string          h_trend          = "===== TREND STRATEGY =====";    // .
input int             InpPullbackBars  = 6;     // [OPT] Barre M15 in cui cercare il pullback
input int             InpTrendBreakBars= 3;     // [FIX] Barre del massimo/minimo locale da rompere

//+------------------------------------------------------------------+
//| INPUT: breakout strategy (M15)                                   |
//+------------------------------------------------------------------+
input string          h_brk            = "===== BREAKOUT STRATEGY =====";  // .
input int             InpBreakLookback = 20;    // [OPT] Barre M15 del livello da rompere
input double          InpBreakBodyATR  = 0.45;  // [OPT] Corpo minimo della candela (x ATR M15)
input bool            InpUseRetest     = false; // [OPT] Entra sul retest invece che sulla rottura
input int             InpRetestMaxBars = 6;     // [FIX] Validita' del retest (barre M15)

//+------------------------------------------------------------------+
//| INPUT: range strategy (M15)                                      |
//+------------------------------------------------------------------+
input string          h_rng            = "===== RANGE STRATEGY =====";    // .
input int             InpBBPeriod      = 20;    // [FIX] Periodo Bande di Bollinger
input double          InpBBDev         = 2.0;   // [FIX] Deviazione Bollinger
input int             InpRsiPeriod     = 14;    // [FIX] Periodo RSI
input double          InpRsiLevel      = 60.0;  // [FIX] Livello RSI (simmetrico: 60 / 40)

//+------------------------------------------------------------------+
//| INPUT: risk management                                           |
//+------------------------------------------------------------------+
input string          h_risk           = "===== RISK MANAGEMENT =====";   // .
input double          InpRiskPercent   = 0.50;  // [OPT] Rischio % per operazione
input ENUM_RISK_BASE  InpRiskBase      = RISK_ON_EQUITY; // Base di calcolo del rischio
input double          InpMaxDailyLoss  = 2.0;   // [FIX] Perdita massima giornaliera %
input double          InpMaxWeeklyLoss = 5.0;   // [FIX] Perdita massima settimanale %
input double          InpMaxDrawdown   = 10.0;  // [FIX] Drawdown massimo % (da picco equity)
input int             InpDDPauseHours  = 24;    // [FIX] Pausa dopo il drawdown massimo (ore)
input int             InpMaxOpenTrades = 2;     // [FIX] Posizioni contemporanee massime
input bool            InpAllowOpposite = false; // Hedging: con false il massimo reale e' 1
input int             InpMaxTradesPerDay=6;     // [FIX] Trade massimi al giorno (0 = illimitato)
input int             InpLossStreakLimit=4;     // [FIX] Perdite consecutive prima di ridurre (0=off)
input double          InpLossStreakFactor=0.5;  // [FIX] Fattore di riduzione del rischio
input double          InpMaxLotCap     = 5.0;   // Tetto massimo di lotti
input double          InpCommissionPerLot=0.0;  // Commissione round-turn per lotto

//+------------------------------------------------------------------+
//| INPUT: stop loss e take profit                                   |
//+------------------------------------------------------------------+
input string          h_stop           = "===== STOP / TARGET =====";     // .
input double          InpSL_ATR_Trend  = 1.5;   // [OPT] SL trend  (x ATR M15)
input double          InpSL_ATR_Range  = 1.0;   // [FIX] SL range  (x ATR M15)
input double          InpSL_ATR_Break  = 1.8;   // [FIX] SL breakout (x ATR M15)
input bool            InpUseStructuralSL=true;  // Adatta lo SL alla struttura di mercato
input double          InpTP_R_Trend    = 3.0;   // [FIX] TP trend come multiplo di R (rete di sicurezza)
input double          InpTP_R_Break    = 2.0;   // [OPT] TP breakout come multiplo di R
input double          InpRangeTP_MinR  = 1.0;   // [FIX] R minimo accettato nel range

//+------------------------------------------------------------------+
//| INPUT: position management                                       |
//+------------------------------------------------------------------+
input string          h_pos            = "===== POSITION MANAGEMENT =====";// .
input bool            InpUseBreakEven  = true;  // Attiva il break-even
input double          InpBE_TriggerR   = 0.8;   // [FIX] Break-even dopo N x R di profitto
input double          InpBE_LockR      = 0.10;  // [FIX] Profitto bloccato al break-even (N x R)
input bool            InpUseTrailing   = true;  // Attiva il trailing stop
input double          InpTrailStartR   = 1.0;   // [OPT] Avvio trailing dopo N x R
input double          InpTrailATR      = 1.5;   // [OPT] Distanza del trailing (x ATR M15)
input double          InpTrailStepATR  = 0.25;  // [FIX] Passo minimo del trailing (x ATR M15)
input bool            InpUsePartialTP  = false; // Chiusura parziale al primo target
input double          InpPartialR      = 1.0;   // [FIX] Parziale a N x R
input double          InpPartialPct    = 50.0;  // [FIX] Percentuale chiusa al parziale
input bool            InpExitOnFlip    = true;  // Esci se il regime H1 si ribalta contro

//+------------------------------------------------------------------+
//| INPUT: session filter (ora del server)                           |
//+------------------------------------------------------------------+
input string          h_sess           = "===== SESSION FILTER =====";    // .
input bool            InpUseSession    = true;  // Attiva il filtro orario
input int             InpSessionStart  = 7;     // [OPT] Ora di inizio (server)
input int             InpSessionEnd    = 20;    // [OPT] Ora di fine (server, esclusa)
input int             InpFridayStopHour= 19;    // [FIX] Venerdi': stop ingressi (0 = off)
input bool            InpCloseOnFriday = false; // Chiudi tutto al FridayStopHour

//+------------------------------------------------------------------+
//| INPUT: safety filters                                            |
//+------------------------------------------------------------------+
input string          h_safe           = "===== SAFETY FILTERS =====";    // .
input double          InpMaxSpreadPips = 2.0;   // [FIX] Spread massimo assoluto (pips, 0=off)
input double          InpMaxSpreadToATR= 0.10;  // [FIX] Spread massimo come frazione di ATR (0=off)
input double          InpMinAtrRatio   = 0.55;  // [FIX] ATR/ATRmedio minimo (mercato troppo fermo)
input double          InpMaxAtrRatio   = 2.50;  // [FIX] ATR/ATRmedio massimo (volatilita' estrema)
input int             InpMinBarsBetween= 2;     // [FIX] Barre M15 minime tra due ingressi
input double          InpStopBufferPips= 1.0;   // [FIX] Margine oltre lo STOPLEVEL del broker
input double          InpMaxStopWiden  = 1.50;  // [FIX] Allargamento massimo dello SL per vincoli broker
input double          InpMinRiskReward = 1.00;  // [FIX] R:R minimo dopo tutti gli aggiustamenti
input double          InpSlippagePips  = 2.0;   // Slippage tollerato (pips)
input int             InpMaxRetries    = 3;     // Tentativi su errori recuperabili
input int             InpRetryDelayMs  = 300;   // Attesa tra i tentativi (ms)
input bool            InpUseNewsFilter = false; // News filter (NON implementato in v1)

//+------------------------------------------------------------------+
//| INPUT: debug                                                     |
//+------------------------------------------------------------------+
input string          h_dbg            = "===== DEBUG =====";             // .
input bool            InpDebugMode     = false; // Log dettagliato a ogni barra M15
input bool            InpLogRejections = true;  // Log dei trade scartati

//+------------------------------------------------------------------+
//| COSTANTI INTERNE                                                 |
//| Deliberatamente NON esposte come input: sono soglie strutturali. |
//| Trasformarle in parametri ottimizzabili aumenterebbe di molto la |
//| superficie di overfitting a fronte di un guadagno informativo    |
//| minimo. Chi vuole testarne la sensibilita' le modifica qui e     |
//| ricompila, con piena consapevolezza di cosa sta facendo.         |
//+------------------------------------------------------------------+
#define SWING_LEFT          2      // Barre a sinistra per validare uno swing
#define SWING_RIGHT         2      // Barre a destra (gia' chiuse) per confermarlo
#define VOL_MIN_TREND       0.80   // ATR/ATRmedio minimo per un trend credibile
#define VOL_MAX_RANGE       1.30   // ATR/ATRmedio massimo per un range credibile
#define VOL_MIN_BREAK       1.10   // ATR/ATRmedio minimo per un breakout credibile
#define SLOPE_FLAT_MAX      0.30   // Pendenza EMA20 (in ATR) sotto cui e' "piatta"
#define SLOPE_LOOKBACK      10     // Barre su cui misurare la pendenza della EMA
#define EMA_TANGLE_ATR      0.50   // |EMA20-EMA50| < N*ATR -> medie intrecciate
#define RANGE_WIDTH_MIN_ATR 1.50   // Ampiezza minima del range in ATR
#define RANGE_WIDTH_MAX_ATR 6.00   // Ampiezza massima del range in ATR
#define RANGE_EDGE_PCT      0.20   // Zona operativa ai bordi del range (% ampiezza)
#define ADX_RISE_DELTA      2.0    // Incremento ADX su 3 barre per dirlo "in salita"
#define ATR_AVG_PERIOD      100    // Barre per la media dell'ATR (volatilita' relativa)
#define SL_STRUCT_MIN_F     0.70   // Lo SL strutturale non scende sotto N x SL base
#define SL_STRUCT_MAX_F     1.80   // ...ne' sale sopra N x SL base
#define STRUCT_LOOKBACK     8      // Barre M15 per il minimo/massimo strutturale
#define BREAK_BUFFER_ATR    0.10   // Buffer oltre il livello rotto (x ATR)
#define BREAK_MAX_EXT_ATR   1.50   // Estensione massima oltre il livello (anti-spike)
#define VOL_SMA_PERIOD      20     // Media del tick volume
#define VOL_RATIO_GOOD      1.20   // Tick volume / media per essere "favorevole"
#define MR_EXT_ATR          1.20   // Distanza minima dalla EMA20 per dirlo "esteso"
#define MR_WICK_PCT         0.35   // Ombra minima della candela di rifiuto
#define CANDLE_BODY_PCT     0.40   // Corpo minimo della candela di conferma
#define CANDLE_CLOSE_PCT    0.60   // Chiusura nel N% favorevole del range di barra
#define MAX_TRACKED         64     // Posizioni tracciate contemporaneamente

//+------------------------------------------------------------------+
//| Strutture dati                                                   |
//+------------------------------------------------------------------+
struct RegimeInfo
  {
   ENUM_REGIME regime;      // Regime classificato
   int         dir;         // +1 rialzista, -1 ribassista, 0 neutro
   double      score;       // Qualita' del trend 0..6
   double      adx;         // ADX H1 (barra chiusa)
   double      adxSlope;    // Variazione ADX su 3 barre
   double      atr;         // ATR H1
   double      atrRatio;    // ATR / ATR medio
   double      ema20;
   double      ema50;
   double      ema200;
   double      emaSlope;    // Pendenza EMA20 in unita' di ATR
   double      rangeHigh;   // Estremo superiore struttura H1
   double      rangeLow;    // Estremo inferiore struttura H1
   double      rangeMid;    // Centro della struttura
   double      rangeWidth;  // Ampiezza in prezzo
   bool        hh;          // Higher High
   bool        hl;          // Higher Low
   bool        lh;          // Lower High
   bool        ll;          // Lower Low
   bool        valid;       // Dati sufficienti
  };

struct SignalInfo
  {
   ENUM_STRATEGY strategy;  // Motore che ha generato il segnale
   int           dir;       // +1 long, -1 short
   double        score;     // Punteggio 0..10
   double        stopRef;   // Livello strutturale di riferimento per lo SL
   double        targetRef; // Livello di target (0 = usa multiplo di R)
   double        slAtrMult; // Moltiplicatore ATR di base per lo SL
   bool          valid;
  };

//+------------------------------------------------------------------+
//| Variabili globali                                                |
//+------------------------------------------------------------------+
int      g_entryTF        = PERIOD_M15;   // Timeframe operativo effettivo
int      g_regimeTF       = PERIOD_H1;    // Timeframe del regime effettivo
double   g_pip            = 0.0001;       // Valore di 1 pip in prezzo
double   g_minLot         = 0.01;
double   g_maxLot         = 100.0;
double   g_lotStep        = 0.01;
int      g_lotDigits      = 2;
int      g_slippagePoints = 20;
bool     g_initOk         = false;

datetime g_lastBarTime    = 0;            // Ultima barra M15 elaborata
datetime g_lastEntryBar   = 0;            // Barra M15 dell'ultimo ingresso
datetime g_dayStart       = 0;            // Inizio della giornata corrente
datetime g_weekStart      = 0;            // Inizio della settimana corrente

//--- Contatori incrementali (aggiornati dai trade chiusi, O(1) per barra)
double   g_realizedDay    = 0.0;          // P/L realizzato di giornata
double   g_realizedWeek   = 0.0;          // P/L realizzato di settimana
int      g_tradesToday    = 0;            // Trade chiusi + aperti oggi
int      g_consecLosses   = 0;            // Perdite consecutive
datetime g_lastClosedTime = 0;            // Ultimo trade chiuso processato
int      g_lastClosedTick = 0;            // Ticket dell'ultimo trade processato

//--- Protezione drawdown
double   g_peakEquity     = 0.0;
datetime g_ddPauseUntil   = 0;
bool     g_ddPauseLogged  = false;

//--- Baseline per i limiti percentuali giornalieri/settimanali
double   g_dayBaseline    = 0.0;
double   g_weekBaseline   = 0.0;

//--- Stato del retest armato (breakout)
int      g_retestDir      = 0;            // Direzione armata
double   g_retestLevel    = 0.0;          // Livello rotto da ritestare
datetime g_retestArmed    = 0;            // Barra in cui e' stato armato
int      g_retestScore    = 0;            // Punteggio della rottura originale

//--- Tracciamento posizioni (R iniziale e parziale gia' eseguito)
int      g_trkTicket[MAX_TRACKED];
double   g_trkRisk[MAX_TRACKED];          // Distanza SL iniziale in prezzo
datetime g_trkOpenTime[MAX_TRACKED];
bool     g_trkPartial[MAX_TRACKED];
int      g_trkCount       = 0;

//--- Diagnostica dell'ultima decisione
string   g_rejectReason   = "";
string   g_signalNote     = "";

//--- Regime memorizzato all'ultima barra chiusa. Serve alla gestione
//    delle posizioni, che gira a ogni tick e non puo' permettersi di
//    ricalcolare la media dell'ATR su 100 barre ogni volta.
ENUM_REGIME g_curRegime      = REG_NONE;
double      g_curRegimeScore = 0.0;

//--- Cache per evitare la rilettura dello storico a ogni tick
int      g_lastHistTotal  = -1;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_entryTF  = (InpEntryTF  == PERIOD_CURRENT) ? Period() : (int)InpEntryTF;
   g_regimeTF = (InpRegimeTF == PERIOD_CURRENT) ? Period() : (int)InpRegimeTF;

   DetectSymbolProfile();

   if(!ValidateInputs())
     {
      g_initOk = false;
      return(INIT_PARAMETERS_INCORRECT);
     }

   //--- Stato iniziale ricostruito dallo storico: l'EA puo' essere
   //    riavviato a meta' giornata senza azzerare i limiti di rischio.
   g_dayStart  = DayStart(TimeCurrent());
   g_weekStart = WeekStart(TimeCurrent());
   RebuildStateFromHistory();

   g_peakEquity = AccountEquity();
   if(g_peakEquity <= 0.0)
      g_peakEquity = AccountBalance();

   g_dayBaseline  = AccountBalance() - g_realizedDay;
   g_weekBaseline = AccountBalance() - g_realizedWeek;

   g_lastBarTime = 0;
   g_trkCount    = 0;
   ResetRetest();
   RebuildTrackingFromOpenPositions();

   Print("======================================================");
   Print("[", InpComment, "] Adaptive EURUSD EA v1.00 avviato");
   Print("[", InpComment, "] Simbolo=", _Symbol,
         "  Regime=", TimeframeToString(g_regimeTF),
         "  Ingresso=", TimeframeToString(g_entryTF));
   Print("[", InpComment, "] Digits=", IntegerToString(Digits),
         "  Point=", DoubleToString(Point, 8),
         "  Pip=", DoubleToString(g_pip, 8));
   Print("[", InpComment, "] Lotti: min=", DoubleToString(g_minLot, g_lotDigits),
         " max=", DoubleToString(g_maxLot, g_lotDigits),
         " step=", DoubleToString(g_lotStep, g_lotDigits));
   Print("[", InpComment, "] Rischio=", DoubleToString(InpRiskPercent, 2),
         "%  DailyMax=", DoubleToString(InpMaxDailyLoss, 2),
         "%  WeeklyMax=", DoubleToString(InpMaxWeeklyLoss, 2),
         "%  DD=", DoubleToString(InpMaxDrawdown, 2), "%");
   if(StringFind(_Symbol, "EURUSD") < 0)
      Print("[", InpComment, "] NOTA: l'EA e' calibrato su EURUSD. Su ", _Symbol,
            " le soglie di volatilita' vanno riverificate prima dell'uso.");
   if(InpUseNewsFilter)
      Print("[", InpComment, "] ATTENZIONE: il news filter NON e' implementato in v1. ",
            "L'input e' solo un punto di estensione: nessun dato news viene usato.");
   Print("======================================================");

   g_initOk = true;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("[", InpComment, "] EA rimosso. Motivo: ", DeinitReasonText(reason));
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//| Due velocita' distinte:                                          |
//|  * la GESTIONE delle posizioni gira a ogni tick (uno stop deve   |
//|    poter essere spostato senza aspettare la chiusura di barra);  |
//|  * la DECISIONE di ingresso gira solo alla chiusura di una barra |
//|    M15, cosi' il sistema non reagisce al rumore intrabar e i     |
//|    risultati del tester non dipendono dalla qualita' dei tick.   |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_initOk)
      return;

   UpdatePeriodState();
   UpdateClosedTradeStats();
   SyncTracking();

   ManageOpenPositions();

   //--- Chiusura preventiva del fine settimana
   if(InpCloseOnFriday && InpFridayStopHour > 0 &&
      TimeDayOfWeek(TimeCurrent()) == 5 && TimeHour(TimeCurrent()) >= InpFridayStopHour)
     {
      CloseAllOwnPositions("chiusura di fine settimana");
      return;
     }

   //--- Da qui in poi si lavora solo alla nuova barra M15
   datetime barTime = iTime(_Symbol, g_entryTF, 0);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   OnNewEntryBar();
  }

//+------------------------------------------------------------------+
//| Logica eseguita una sola volta per barra M15 chiusa              |
//+------------------------------------------------------------------+
void OnNewEntryBar()
  {
   g_rejectReason = "";
   g_signalNote   = "";

   RegimeInfo reg;
   SignalInfo sig;
   ResetRegime(reg);
   ResetSignal(sig);

   if(!HasEnoughHistory())
     {
      SetReject("storico insufficiente su uno dei due timeframe");
      DebugDump(reg, sig);
      return;
     }

   //--- 1) REGIME H1
   BuildRegime(reg);
   g_curRegime      = reg.regime;
   g_curRegimeScore = reg.score;

   //--- 2) Aggiornamento dello stato di retest (va fatto anche quando
   //       poi il trade verra' scartato, altrimenti lo stato resta appeso)
   UpdateRetestState(reg);

   //--- 3) SEGNALE M15 coerente con il regime
   if(reg.valid && reg.regime != REG_NONE)
      BuildSignal(reg, sig);

   //--- 4) GATE + esecuzione
   bool willTrade = false;
   if(sig.valid && sig.score >= InpMinSignalScore)
     {
      if(PassesAllGates(reg, sig))
         willTrade = true;
     }
   else
      if(sig.valid)
         SetReject(StringFormat("punteggio %.1f sotto la soglia %.1f", sig.score, InpMinSignalScore));

   DebugDump(reg, sig);

   if(willTrade)
      ExecuteSignal(reg, sig);
  }

//+------------------------------------------------------------------+
//| Profilo del simbolo: pip, lotti, slippage                        |
//| Nessun valore hard-coded: tutto letto dalle proprieta' del       |
//| simbolo, cosi' l'EA regge broker 4 e 5 cifre senza modifiche.    |
//+------------------------------------------------------------------+
void DetectSymbolProfile()
  {
   g_pip = (Digits == 3 || Digits == 5) ? Point * 10.0 : Point;
   if(g_pip <= 0.0)
      g_pip = (Point > 0.0 ? Point : 0.0001);

   g_minLot  = MarketInfo(_Symbol, MODE_MINLOT);
   g_maxLot  = MarketInfo(_Symbol, MODE_MAXLOT);
   g_lotStep = MarketInfo(_Symbol, MODE_LOTSTEP);

   if(g_minLot  <= 0.0) g_minLot  = 0.01;
   if(g_maxLot  <= 0.0) g_maxLot  = 100.0;
   if(g_lotStep <= 0.0) g_lotStep = 0.01;

   g_lotDigits      = VolumeDigits(g_lotStep);
   g_slippagePoints = (int)MathRound(InpSlippagePips * g_pip / Point);
   if(g_slippagePoints < 0)
      g_slippagePoints = 0;
  }

//+------------------------------------------------------------------+
//| Validazione degli input                                          |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   string e = "";

   if(g_entryTF >= g_regimeTF)
      e = e + "Il timeframe di ingresso deve essere inferiore a quello del regime.\n";
   if(InpAdxPeriod < 2)      e = e + "InpAdxPeriod deve essere >= 2.\n";
   if(InpAtrPeriod < 2)      e = e + "InpAtrPeriod deve essere >= 2.\n";
   if(InpEmaFast < 2 || InpEmaMid < 2 || InpEmaSlow < 2)
      e = e + "I periodi delle EMA devono essere >= 2.\n";
   if(InpEmaFast >= InpEmaMid || InpEmaMid >= InpEmaSlow)
      e = e + "Le EMA devono essere crescenti: veloce < intermedia < lenta.\n";
   if(InpAdxRange >= InpAdxTrend)
      e = e + "InpAdxRange deve essere inferiore a InpAdxTrend.\n";
   if(InpMinTrendScore < 0 || InpMinTrendScore > 6)
      e = e + "InpMinTrendScore deve essere compreso tra 0 e 6.\n";
   if(InpMinSignalScore < 0.0 || InpMinSignalScore > 10.0)
      e = e + "InpMinSignalScore deve essere compreso tra 0 e 10.\n";
   if(InpRegimeLookback < 10)  e = e + "InpRegimeLookback deve essere >= 10.\n";
   if(InpBreakLookback  < 5)   e = e + "InpBreakLookback deve essere >= 5.\n";
   if(InpPullbackBars   < 2)   e = e + "InpPullbackBars deve essere >= 2.\n";
   if(InpTrendBreakBars < 1)   e = e + "InpTrendBreakBars deve essere >= 1.\n";
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 5.0)
      e = e + "InpRiskPercent deve essere compreso tra 0 e 5 (valori superiori non sono difendibili).\n";
   if(InpMaxOpenTrades < 1)    e = e + "InpMaxOpenTrades deve essere >= 1.\n";
   if(InpSL_ATR_Trend <= 0.0 || InpSL_ATR_Range <= 0.0 || InpSL_ATR_Break <= 0.0)
      e = e + "I moltiplicatori ATR dello stop devono essere positivi.\n";
   if(InpUsePartialTP && (InpPartialPct <= 0.0 || InpPartialPct >= 100.0))
      e = e + "InpPartialPct deve essere compreso tra 0 e 100 (esclusi).\n";
   if(InpLossStreakFactor <= 0.0 || InpLossStreakFactor > 1.0)
      e = e + "InpLossStreakFactor deve essere compreso tra 0 e 1.\n";
   if(InpUseSession && (InpSessionStart < 0 || InpSessionStart > 23 ||
                        InpSessionEnd   < 0 || InpSessionEnd   > 24))
      e = e + "Le ore di sessione devono essere comprese tra 0 e 24.\n";
   if(!InpEnableTrend && !InpEnableBreakout && !InpEnableMeanRev)
      e = e + "Almeno un motore di segnale deve essere abilitato.\n";

   if(e != "")
     {
      Print("[", InpComment, "] PARAMETRI NON VALIDI:");
      Print(e);
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Storico sufficiente su entrambi i timeframe                      |
//| Se i dati non bastano l'EA non opera: meglio nessun trade che un |
//| trade deciso su indicatori calcolati a meta'.                    |
//+------------------------------------------------------------------+
bool HasEnoughHistory()
  {
   int needRegime = (int)MathMax(InpEmaSlow, ATR_AVG_PERIOD + InpAtrPeriod);
   needRegime = (int)MathMax(needRegime, InpRegimeLookback + SWING_LEFT + SWING_RIGHT + 10);
   needRegime += 10;

   int needEntry = (int)MathMax(InpBreakLookback + 5, InpBBPeriod + 5);
   needEntry = (int)MathMax(needEntry, ATR_AVG_PERIOD + InpAtrPeriod);
   needEntry = (int)MathMax(needEntry, InpEmaMid + 5);
   needEntry += 10;

   if(iBars(_Symbol, g_regimeTF) < needRegime)
      return(false);
   if(iBars(_Symbol, g_entryTF) < needEntry)
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//|                    MARKET REGIME ENGINE (H1)                     |
//|                                                                  |
//|  Ordine di priorita' nella classificazione:                      |
//|     1. TREND   (struttura + medie + ADX gia' consolidati)        |
//|     2. BREAKOUT/TRANSITION (volatilita' in espansione, ADX in    |
//|        salita, rottura della struttura H1)                       |
//|     3. RANGE   (ADX basso, medie piatte e intrecciate)           |
//|     4. NONE    (nessuna delle precedenti)                        |
//|                                                                  |
//|  La priorita' non e' arbitraria: un trend gia' in corso rompe di |
//|  continuo i propri estremi, quindi senza questo ordine ogni trend |
//|  verrebbe riclassificato come "breakout" a ogni nuovo massimo.    |
//|  Assegnando la precedenza al trend, il regime BREAKOUT resta      |
//|  quello che deve essere: l'uscita da una fase di compressione.    |
//+------------------------------------------------------------------+
void ResetRegime(RegimeInfo &r)
  {
   r.regime     = REG_NONE;
   r.dir        = 0;
   r.score      = 0.0;
   r.adx        = 0.0;
   r.adxSlope   = 0.0;
   r.atr        = 0.0;
   r.atrRatio   = 0.0;
   r.ema20      = 0.0;
   r.ema50      = 0.0;
   r.ema200     = 0.0;
   r.emaSlope   = 0.0;
   r.rangeHigh  = 0.0;
   r.rangeLow   = 0.0;
   r.rangeMid   = 0.0;
   r.rangeWidth = 0.0;
   r.hh         = false;
   r.hl         = false;
   r.lh         = false;
   r.ll         = false;
   r.valid      = false;
  }

void BuildRegime(RegimeInfo &r)
  {
   ResetRegime(r);

   //--- SHIFT 1 OVUNQUE: la barra H1 in formazione non esiste per l'EA.
   const int s = 1;

   r.ema20  = iMA(_Symbol, g_regimeTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE, s);
   r.ema50  = iMA(_Symbol, g_regimeTF, InpEmaMid,  0, MODE_EMA, PRICE_CLOSE, s);
   r.ema200 = iMA(_Symbol, g_regimeTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE, s);
   r.adx    = iADX(_Symbol, g_regimeTF, InpAdxPeriod, PRICE_CLOSE, MODE_MAIN, s);
   r.atr    = iATR(_Symbol, g_regimeTF, InpAtrPeriod, s);

   double adxPast = iADX(_Symbol, g_regimeTF, InpAdxPeriod, PRICE_CLOSE, MODE_MAIN, s + 3);
   r.adxSlope     = r.adx - adxPast;

   if(r.atr <= 0.0 || r.ema200 <= 0.0)
      return;

   double atrAvg = AverageATR(g_regimeTF, InpAtrPeriod, ATR_AVG_PERIOD, s);
   r.atrRatio    = (atrAvg > 0.0 ? r.atr / atrAvg : 1.0);

   //--- Pendenza della EMA20 misurata in unita' di ATR: adimensionale,
   //    quindi la stessa soglia vale su qualunque simbolo e volatilita'.
   double emaPast = iMA(_Symbol, g_regimeTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE, s + SLOPE_LOOKBACK);
   r.emaSlope     = (r.ema20 - emaPast) / r.atr;

   //--- Struttura H1: estremi del canale e sequenza degli swing
   int hiShift = iHighest(_Symbol, g_regimeTF, MODE_HIGH, InpRegimeLookback, s);
   int loShift = iLowest(_Symbol, g_regimeTF, MODE_LOW,  InpRegimeLookback, s);
   if(hiShift < 0 || loShift < 0)
      return;

   r.rangeHigh  = iHigh(_Symbol, g_regimeTF, hiShift);
   r.rangeLow   = iLow(_Symbol, g_regimeTF, loShift);
   r.rangeWidth = r.rangeHigh - r.rangeLow;
   r.rangeMid   = (r.rangeHigh + r.rangeLow) / 2.0;
   if(r.rangeWidth <= 0.0)
      return;

   double sh1 = 0.0, sh2 = 0.0, sl1 = 0.0, sl2 = 0.0;
   bool okH1 = GetSwingHigh(g_regimeTF, 1, sh1);
   bool okH2 = GetSwingHigh(g_regimeTF, 2, sh2);
   bool okL1 = GetSwingLow(g_regimeTF, 1, sl1);
   bool okL2 = GetSwingLow(g_regimeTF, 2, sl2);

   if(okH1 && okH2)
     {
      r.hh = (sh1 > sh2);
      r.lh = (sh1 < sh2);
     }
   if(okL1 && okL2)
     {
      r.hl = (sl1 > sl2);
      r.ll = (sl1 < sl2);
     }

   r.valid = true;

   double close1 = iClose(_Symbol, g_regimeTF, s);

   //================================================================
   // 1) TREND  -  scoring 0..6
   //================================================================
   double bullScore = 0.0;
   double bearScore = 0.0;

   //--- Allineamento delle medie (0..2)
   if(r.ema20 > r.ema50 && r.ema50 > r.ema200)      bullScore += 2.0;
   else if(r.ema20 > r.ema50 && close1 > r.ema200)  bullScore += 1.0;

   if(r.ema20 < r.ema50 && r.ema50 < r.ema200)      bearScore += 2.0;
   else if(r.ema20 < r.ema50 && close1 < r.ema200)  bearScore += 1.0;

   //--- Forza direzionale ADX (0..2), con una fascia intermedia che
   //    evita il comportamento a scalino sulla soglia esatta.
   double adxPoints = 0.0;
   if(r.adx >= InpAdxTrend)            adxPoints = 2.0;
   else if(r.adx >= InpAdxTrend - 5.0) adxPoints = 1.0;
   bullScore += adxPoints;
   bearScore += adxPoints;

   //--- Struttura (0..2)
   if(r.hh) bullScore += 1.0;
   if(r.hl) bullScore += 1.0;
   if(r.lh) bearScore += 1.0;
   if(r.ll) bearScore += 1.0;

   //--- La volatilita' non entra nel punteggio ma agisce da gate: un trend
   //    tecnicamente perfetto con ATR compresso non e' percorribile, perche'
   //    lo stop necessario resterebbe sproporzionato rispetto al movimento.
   bool volOkTrend  = (r.atrRatio >= VOL_MIN_TREND);
   bool adxMinTrend = (r.adx >= InpAdxTrend - 5.0);

   if(r.ema20 > r.ema50 && bullScore >= InpMinTrendScore && adxMinTrend && volOkTrend)
     {
      r.regime = REG_TREND_UP;
      r.dir    = 1;
      r.score  = bullScore;
      return;
     }
   if(r.ema20 < r.ema50 && bearScore >= InpMinTrendScore && adxMinTrend && volOkTrend)
     {
      r.regime = REG_TREND_DN;
      r.dir    = -1;
      r.score  = bearScore;
      return;
     }

   //================================================================
   // 2) BREAKOUT / TRANSITION
   //    Espansione di volatilita' + ADX in risveglio + rottura della
   //    struttura H1 precedente. Non e' un trend maturo: e' il momento
   //    in cui il mercato decide di esserlo.
   //================================================================
   //--- iHighest/iLowest restituiscono -1 se i dati non bastano. Senza
   //    questo controllo prevHigh varrebbe 0 e OGNI chiusura risulterebbe
   //    una rottura rialzista: un bug silenzioso che genererebbe trade.
   int pHiShift = iHighest(_Symbol, g_regimeTF, MODE_HIGH, InpRegimeLookback, s + 1);
   int pLoShift = iLowest(_Symbol,  g_regimeTF, MODE_LOW,  InpRegimeLookback, s + 1);
   if(pHiShift < 0 || pLoShift < 0)
     {
      r.regime = REG_NONE;
      r.dir    = 0;
      return;
     }

   double prevHigh = iHigh(_Symbol, g_regimeTF, pHiShift);
   double prevLow  = iLow(_Symbol,  g_regimeTF, pLoShift);

   bool volExpanding = (r.atrRatio >= VOL_MIN_BREAK);
   bool adxWaking    = (r.adxSlope >= ADX_RISE_DELTA);
   bool brokeUp      = (close1 > prevHigh);
   bool brokeDown    = (close1 < prevLow);

   if(volExpanding && adxWaking && brokeUp && r.ema20 >= r.ema50)
     {
      r.regime = REG_BREAKOUT;
      r.dir    = 1;
      r.score  = bullScore;
      return;
     }
   if(volExpanding && adxWaking && brokeDown && r.ema20 <= r.ema50)
     {
      r.regime = REG_BREAKOUT;
      r.dir    = -1;
      r.score  = bearScore;
      return;
     }

   //================================================================
   // 3) RANGE
   //    Tutte le condizioni devono valere insieme. Un range mal
   //    riconosciuto porta a vendere sui minimi di un trend: qui la
   //    severita' costa poco (qualche trade perso) e protegge molto.
   //================================================================
   bool adxLow     = (r.adx < InpAdxRange);
   bool flat       = (MathAbs(r.emaSlope) < SLOPE_FLAT_MAX);
   bool tangled    = (MathAbs(r.ema20 - r.ema50) < EMA_TANGLE_ATR * r.atr);
   bool volOkRange = (r.atrRatio <= VOL_MAX_RANGE);
   double widthATR = r.rangeWidth / r.atr;
   bool widthOk    = (widthATR >= RANGE_WIDTH_MIN_ATR && widthATR <= RANGE_WIDTH_MAX_ATR);

   if(adxLow && flat && tangled && volOkRange && widthOk)
     {
      r.regime = REG_RANGE;
      r.dir    = 0;
      r.score  = 0.0;
      return;
     }

   //================================================================
   // 4) NO TRADE
   //================================================================
   r.regime = REG_NONE;
   r.dir    = 0;
   r.score  = MathMax(bullScore, bearScore);
  }

//+------------------------------------------------------------------+
//| SWING STRUTTURALI                                                |
//| Uno swing high alla barra i e' valido solo se SWING_RIGHT barre  |
//| gia' chiuse alla sua destra sono piu' basse. La ricerca parte    |
//| quindi da shift = 1 + SWING_RIGHT: e' proprio questo ritardo a   |
//| rendere la struttura non-repainting. Un'implementazione che      |
//| guarda anche la barra corrente "scopre" massimi che il mercato   |
//| non ha ancora confermato e produce backtest non riproducibili.   |
//+------------------------------------------------------------------+
bool GetSwingHigh(int tf, int occurrence, double &price)
  {
   price = 0.0;
   if(occurrence < 1)
      return(false);

   int found   = 0;
   int maxBars = (int)MathMin(iBars(_Symbol, tf) - SWING_LEFT - 2, 200);

   for(int i = 1 + SWING_RIGHT; i <= maxBars; i++)
     {
      double h = iHigh(_Symbol, tf, i);
      bool isSwing = true;

      for(int k = 1; k <= SWING_RIGHT && isSwing; k++)
         if(iHigh(_Symbol, tf, i - k) >= h)
            isSwing = false;

      for(int j = 1; j <= SWING_LEFT && isSwing; j++)
         if(iHigh(_Symbol, tf, i + j) > h)
            isSwing = false;

      if(isSwing)
        {
         found++;
         if(found == occurrence)
           {
            price = h;
            return(true);
           }
        }
     }
   return(false);
  }

bool GetSwingLow(int tf, int occurrence, double &price)
  {
   price = 0.0;
   if(occurrence < 1)
      return(false);

   int found   = 0;
   int maxBars = (int)MathMin(iBars(_Symbol, tf) - SWING_LEFT - 2, 200);

   for(int i = 1 + SWING_RIGHT; i <= maxBars; i++)
     {
      double l = iLow(_Symbol, tf, i);
      bool isSwing = true;

      for(int k = 1; k <= SWING_RIGHT && isSwing; k++)
         if(iLow(_Symbol, tf, i - k) <= l)
            isSwing = false;

      for(int j = 1; j <= SWING_LEFT && isSwing; j++)
         if(iLow(_Symbol, tf, i + j) < l)
            isSwing = false;

      if(isSwing)
        {
         found++;
         if(found == occurrence)
           {
            price = l;
            return(true);
           }
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//|                    SIGNAL ENGINE (M15)                           |
//|                                                                  |
//|  Un solo motore e' attivo per volta, scelto dal regime. Non e'   |
//|  previsto che due strategie competano sullo stesso momento: e'   |
//|  proprio la separazione a rendere leggibile il risultato per     |
//|  regime nell'analisi post-backtest.                              |
//|  Ogni motore restituisce un punteggio normalizzato 0..10.        |
//+------------------------------------------------------------------+
void ResetSignal(SignalInfo &s)
  {
   s.strategy  = STRAT_NONE;
   s.dir       = 0;
   s.score     = 0.0;
   s.stopRef   = 0.0;
   s.targetRef = 0.0;
   s.slAtrMult = InpSL_ATR_Trend;
   s.valid     = false;
  }

void BuildSignal(RegimeInfo &r, SignalInfo &s)
  {
   ResetSignal(s);

   switch(r.regime)
     {
      case REG_TREND_UP:
      case REG_TREND_DN:
         //--- Nel trend maturo si privilegia il pullback. La rottura di
         //    continuazione resta disponibile perche' in un trend forte
         //    il pullback profondo puo' non arrivare mai.
         if(InpEnableTrend)
            TrendSignal(r, s);
         if(!s.valid && InpEnableBreakout)
            BreakoutSignal(r, s);
         break;

      case REG_BREAKOUT:
         if(InpEnableBreakout)
            BreakoutSignal(r, s);
         break;

      case REG_RANGE:
         if(InpEnableMeanRev)
            MeanReversionSignal(r, s);
         break;

      default:
         break;
     }
  }

//+------------------------------------------------------------------+
//| MOTORE 1: TREND FOLLOWING SU PULLBACK                            |
//|                                                                  |
//|   H1 in trend  ->  pullback M15 verso EMA20/EMA50  ->  la        |
//|   struttura rialzista tiene  ->  rottura del massimo locale.     |
//|                                                                  |
//|  Pullback e trigger sono condizioni NECESSARIE (gate): senza di  |
//|  esse non c'e' setup, non un setup di qualita' inferiore.        |
//|  Il punteggio misura quanto e' pulito il setup, non se esiste.   |
//+------------------------------------------------------------------+
void TrendSignal(RegimeInfo &r, SignalInfo &s)
  {
   int dir = r.dir;
   if(dir == 0)
      return;

   const int s1 = 1;

   double atr = iATR(_Symbol, g_entryTF, InpAtrPeriod, s1);
   if(atr <= 0.0)
      return;

   double ema20 = iMA(_Symbol, g_entryTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE, s1);
   double ema50 = iMA(_Symbol, g_entryTF, InpEmaMid,  0, MODE_EMA, PRICE_CLOSE, s1);

   double o1 = iOpen(_Symbol,  g_entryTF, s1);
   double h1 = iHigh(_Symbol,  g_entryTF, s1);
   double l1 = iLow(_Symbol,   g_entryTF, s1);
   double c1 = iClose(_Symbol, g_entryTF, s1);
   double barRange = h1 - l1;
   if(barRange <= 0.0)
      return;

   //--- GATE 1: il pullback deve essere avvenuto nelle ultime N barre.
   //    Si accetta un ritracciamento verso la piu' lontana tra EMA20 ed
   //    EMA50, con una tolleranza di 0.25 ATR per non pretendere il
   //    tocco esatto (che accade raramente).
   bool pullbackOk = false;
   if(dir > 0)
     {
      double zone = MathMax(ema20, ema50) + 0.25 * atr;
      int    lo   = iLowest(_Symbol, g_entryTF, MODE_LOW, InpPullbackBars, s1);
      if(lo >= 0 && iLow(_Symbol, g_entryTF, lo) <= zone)
         pullbackOk = true;
     }
   else
     {
      double zone = MathMin(ema20, ema50) - 0.25 * atr;
      int    hi   = iHighest(_Symbol, g_entryTF, MODE_HIGH, InpPullbackBars, s1);
      if(hi >= 0 && iHigh(_Symbol, g_entryTF, hi) >= zone)
         pullbackOk = true;
     }
   if(!pullbackOk)
      return;

   //--- GATE 2: rottura del massimo (o minimo) locale formato dalle barre
   //    precedenti a quella di segnale. Tutte barre chiuse.
   bool triggerOk = false;
   if(dir > 0)
     {
      int hi = iHighest(_Symbol, g_entryTF, MODE_HIGH, InpTrendBreakBars, s1 + 1);
      if(hi >= 0 && c1 > iHigh(_Symbol, g_entryTF, hi))
         triggerOk = true;
     }
   else
     {
      int lo = iLowest(_Symbol, g_entryTF, MODE_LOW, InpTrendBreakBars, s1 + 1);
      if(lo >= 0 && c1 < iLow(_Symbol, g_entryTF, lo))
         triggerOk = true;
     }
   if(!triggerOk)
      return;

   //--- GATE 3: la candela di segnale deve andare nella direzione giusta
   if(dir > 0 && c1 <= o1) return;
   if(dir < 0 && c1 >= o1) return;

   //--- SCORING 0..10
   double score = 0.0;

   //  a) Qualita' del regime H1 (0..3)
   score += (r.score / 6.0) * 3.0;

   //  b) Pullback valido (gate gia' superato)  +2
   score += 2.0;

   //  c) Rottura della struttura locale (gate gia' superato)  +2
   score += 2.0;

   //  d) Qualita' della candela  +1
   double body    = MathAbs(c1 - o1);
   double closePos = (dir > 0 ? (c1 - l1) / barRange : (h1 - c1) / barRange);
   if(body >= CANDLE_BODY_PCT * barRange && closePos >= CANDLE_CLOSE_PCT)
      score += 1.0;

   //  e) Momentum M15 allineato  +1
   bool momOk = (dir > 0 ? (c1 > ema20 && ema20 > ema50) : (c1 < ema20 && ema20 < ema50));
   if(momOk)
      score += 1.0;

   //  f) Tick volume sopra la media  +1
   score += VolumeScore(s1);

   //--- Riferimento strutturale per lo stop
   double stopRef = 0.0;
   if(dir > 0)
     {
      int lo = iLowest(_Symbol, g_entryTF, MODE_LOW, STRUCT_LOOKBACK, s1);
      stopRef = (lo >= 0 ? iLow(_Symbol, g_entryTF, lo) : l1);
     }
   else
     {
      int hi = iHighest(_Symbol, g_entryTF, MODE_HIGH, STRUCT_LOOKBACK, s1);
      stopRef = (hi >= 0 ? iHigh(_Symbol, g_entryTF, hi) : h1);
     }

   s.strategy  = STRAT_TREND;
   s.dir       = dir;
   s.score     = NormScore(score);
   s.stopRef   = stopRef;
   s.targetRef = 0.0;                 // gestito a multipli di R + trailing
   s.slAtrMult = InpSL_ATR_Trend;
   s.valid     = true;

   g_signalNote = StringFormat("pullback+rottura locale, momentum=%s", momOk ? "si" : "no");
  }

//+------------------------------------------------------------------+
//| MOTORE 2: BREAKOUT                                               |
//|                                                                  |
//|  "breakout = BUY" e' esattamente cio' che il sistema NON fa.     |
//|  Filtri applicati: significativita' del livello, corpo della     |
//|  candela, ATR non depresso, anti-spike (una rottura troppo       |
//|  estesa e' gia' un movimento consumato, non un ingresso), volume |
//|  di conferma, coerenza con il contesto H1.                       |
//|                                                                  |
//|  Modalita' retest: invece di ordini pendenti (che i broker ECN   |
//|  gestiscono in modo eterogeneo e che il tester modella in modo   |
//|  ottimistico) si usa una macchina a stati. Alla rottura il       |
//|  segnale viene ARMATO; l'ingresso avviene a mercato solo se il   |
//|  prezzo torna sul livello e lo rifiuta entro N barre.            |
//+------------------------------------------------------------------+
void BreakoutSignal(RegimeInfo &r, SignalInfo &s)
  {
   const int s1 = 1;

   double atr = iATR(_Symbol, g_entryTF, InpAtrPeriod, s1);
   if(atr <= 0.0)
      return;

   //--- In modalita' retest, se esiste uno stato armato si valuta prima quello
   if(InpUseRetest && g_retestDir != 0)
     {
      if(EvaluateRetestEntry(s, atr))
         return;
     }

   double o1 = iOpen(_Symbol,  g_entryTF, s1);
   double h1 = iHigh(_Symbol,  g_entryTF, s1);
   double l1 = iLow(_Symbol,   g_entryTF, s1);
   double c1 = iClose(_Symbol, g_entryTF, s1);
   double barRange = h1 - l1;
   if(barRange <= 0.0)
      return;

   //--- Livello significativo: estremo delle N barre PRECEDENTI a quella di segnale
   int hiShift = iHighest(_Symbol, g_entryTF, MODE_HIGH, InpBreakLookback, s1 + 1);
   int loShift = iLowest(_Symbol,  g_entryTF, MODE_LOW,  InpBreakLookback, s1 + 1);
   if(hiShift < 0 || loShift < 0)
      return;

   double upLevel = iHigh(_Symbol, g_entryTF, hiShift);
   double dnLevel = iLow(_Symbol,  g_entryTF, loShift);
   double buffer  = BREAK_BUFFER_ATR * atr;

   int    dir   = 0;
   double level = 0.0;

   if(c1 > upLevel + buffer)
     {
      dir   = 1;
      level = upLevel;
     }
   else
      if(c1 < dnLevel - buffer)
        {
         dir   = -1;
         level = dnLevel;
        }

   if(dir == 0)
      return;

   //--- GATE: il contesto H1 non deve essere contrario alla rottura.
   //    Un breakout rialzista dentro un trend H1 ribassista consolidato
   //    e' quasi sempre una trappola di liquidita'.
   if(r.regime == REG_TREND_UP && dir < 0) return;
   if(r.regime == REG_TREND_DN && dir > 0) return;
   if(r.regime == REG_BREAKOUT && r.dir != dir) return;

   //--- GATE: corpo della candela sufficiente
   double body = MathAbs(c1 - o1);
   if(body < InpBreakBodyATR * atr)
      return;

   //--- GATE: candela nella direzione della rottura
   if(dir > 0 && c1 <= o1) return;
   if(dir < 0 && c1 >= o1) return;

   //--- GATE anti-spike: se il prezzo ha gia' percorso oltre 1.5 ATR
   //    dal livello, l'ingresso arriverebbe a movimento fatto e con
   //    uno stop innaturalmente lontano.
   double extension = MathAbs(c1 - level);
   if(extension > BREAK_MAX_EXT_ATR * atr)
      return;

   //--- GATE: volatilita' non depressa sul timeframe operativo
   double atrAvgM15 = AverageATR(g_entryTF, InpAtrPeriod, ATR_AVG_PERIOD, s1);
   double atrRatio  = (atrAvgM15 > 0.0 ? atr / atrAvgM15 : 1.0);
   if(atrRatio < InpMinAtrRatio)
      return;

   //--- SCORING 0..10
   double score = 0.0;

   //  a) Contesto H1 concorde  +2 (parziale se solo non contrario)
   if((r.regime == REG_BREAKOUT && r.dir == dir) ||
      (r.regime == REG_TREND_UP && dir > 0) ||
      (r.regime == REG_TREND_DN && dir < 0))
      score += 2.0;
   else
      score += 1.0;

   //  b) Rottura oltre il buffer (gate gia' superato)  +2
   score += 2.0;

   //  c) Corpo adeguato  +1
   score += 1.0;

   //  d) Non iper-esteso  +1  (proporzionale: piu' vicino al livello, meglio e')
   if(extension <= 0.75 * BREAK_MAX_EXT_ATR * atr)
      score += 1.0;
   else
      score += 0.5;

   //  e) Volume di conferma  +1
   score += VolumeScore(s1);

   //  f) ATR in espansione  +1
   if(atrRatio >= VOL_MIN_BREAK)
      score += 1.0;
   else if(atrRatio >= 1.0)
      score += 0.5;

   //  g) Chiusura decisa sull'estremo della candela  +2
   double closePos = (dir > 0 ? (c1 - l1) / barRange : (h1 - c1) / barRange);
   if(closePos >= CANDLE_CLOSE_PCT)
      score += 2.0;
   else
      score += 1.0;

   //--- Modalita' retest: si arma e si esce senza segnale
   if(InpUseRetest)
     {
      ArmRetest(dir, level, (int)MathRound(score));
      g_signalNote = StringFormat("breakout armato a %s, attesa retest", DoubleToString(level, Digits));
      return;
     }

   //--- Riferimento strutturale per lo stop: sotto il livello rotto
   double stopRef = (dir > 0 ? MathMin(l1, level) - 0.25 * atr
                             : MathMax(h1, level) + 0.25 * atr);

   s.strategy  = STRAT_BREAKOUT;
   s.dir       = dir;
   s.score     = NormScore(score);
   s.stopRef   = stopRef;
   s.targetRef = 0.0;
   s.slAtrMult = InpSL_ATR_Break;
   s.valid     = true;

   g_signalNote = StringFormat("rottura di %s, estensione %.2f ATR",
                               DoubleToString(level, Digits), extension / atr);
  }

//+------------------------------------------------------------------+
//| Retest: armamento, scadenza e valutazione dell'ingresso          |
//+------------------------------------------------------------------+
void ResetRetest()
  {
   g_retestDir   = 0;
   g_retestLevel = 0.0;
   g_retestArmed = 0;
   g_retestScore = 0;
  }

void ArmRetest(int dir, double level, int score)
  {
   g_retestDir   = dir;
   g_retestLevel = level;
   g_retestArmed = iTime(_Symbol, g_entryTF, 1);
   g_retestScore = score;
  }

//+------------------------------------------------------------------+
//| Scadenza e invalidazione dello stato armato                      |
//| Va chiamata a ogni barra, anche quando non si opera, altrimenti  |
//| un livello armato resta valido all'infinito.                     |
//+------------------------------------------------------------------+
void UpdateRetestState(RegimeInfo &r)
  {
   if(g_retestDir == 0)
      return;

   //--- Scadenza temporale
   int barsElapsed = iBarShift(_Symbol, g_entryTF, g_retestArmed, false);
   if(barsElapsed < 0 || barsElapsed > InpRetestMaxBars)
     {
      if(InpDebugMode)
         Print("[", InpComment, "] Retest scaduto sul livello ", DoubleToString(g_retestLevel, Digits));
      ResetRetest();
      return;
     }

   //--- Invalidazione: il prezzo e' rientrato stabilmente oltre il livello
   double c1 = iClose(_Symbol, g_entryTF, 1);
   if(g_retestDir > 0 && c1 < g_retestLevel)
     {
      if(InpDebugMode)
         Print("[", InpComment, "] Retest invalidato: rientro sotto il livello rotto");
      ResetRetest();
      return;
     }
   if(g_retestDir < 0 && c1 > g_retestLevel)
     {
      if(InpDebugMode)
         Print("[", InpComment, "] Retest invalidato: rientro sopra il livello rotto");
      ResetRetest();
      return;
     }

   //--- Invalidazione da contesto: il regime si e' girato contro
   if((g_retestDir > 0 && r.regime == REG_TREND_DN) ||
      (g_retestDir < 0 && r.regime == REG_TREND_UP))
      ResetRetest();
  }

//+------------------------------------------------------------------+
//| Valuta l'ingresso sul retest del livello rotto                   |
//+------------------------------------------------------------------+
bool EvaluateRetestEntry(SignalInfo &s, double atr)
  {
   if(g_retestDir == 0)
      return(false);

   const int s1 = 1;
   double o1 = iOpen(_Symbol,  g_entryTF, s1);
   double h1 = iHigh(_Symbol,  g_entryTF, s1);
   double l1 = iLow(_Symbol,   g_entryTF, s1);
   double c1 = iClose(_Symbol, g_entryTF, s1);
   double barRange = h1 - l1;
   if(barRange <= 0.0)
      return(false);

   double tol = 0.30 * atr;
   int    dir = g_retestDir;

   //--- Il prezzo deve essere tornato a toccare la zona del livello...
   bool touched = (dir > 0 ? (l1 <= g_retestLevel + tol)
                           : (h1 >= g_retestLevel - tol));
   //--- ...e averla rifiutata chiudendo di nuovo dalla parte giusta
   bool rejected = (dir > 0 ? (c1 > g_retestLevel && c1 > o1)
                            : (c1 < g_retestLevel && c1 < o1));

   if(!touched || !rejected)
      return(false);

   double score = (double)g_retestScore;
   double closePos = (dir > 0 ? (c1 - l1) / barRange : (h1 - c1) / barRange);
   if(closePos < CANDLE_CLOSE_PCT)
      score -= 1.0;

   double stopRef = (dir > 0 ? MathMin(l1, g_retestLevel) - 0.25 * atr
                             : MathMax(h1, g_retestLevel) + 0.25 * atr);

   s.strategy  = STRAT_BREAKOUT;
   s.dir       = dir;
   s.score     = NormScore(score);
   s.stopRef   = stopRef;
   s.targetRef = 0.0;
   s.slAtrMult = InpSL_ATR_Break;
   s.valid     = true;

   g_signalNote = StringFormat("retest confermato su %s", DoubleToString(g_retestLevel, Digits));
   ResetRetest();
   return(true);
  }

//+------------------------------------------------------------------+
//| MOTORE 3: MEAN REVERSION                                         |
//|                                                                  |
//|  Attivo solo con regime H1 = RANGE. Il target naturale e' il     |
//|  centro del range: e' un'ipotesi verificabile, non una scelta    |
//|  estetica. Le Bande di Bollinger sono usate come misura di       |
//|  estensione, mai come segnale autonomo.                          |
//+------------------------------------------------------------------+
void MeanReversionSignal(RegimeInfo &r, SignalInfo &s)
  {
   if(r.regime != REG_RANGE)
      return;

   //--- Salvaguardia esplicita: mai mean reversion contro un H1 direzionale.
   //    Ridondante con REG_RANGE per costruzione, ma il costo e' nullo e
   //    protegge da future modifiche alla classificazione del regime.
   if(r.adx >= InpAdxTrend)
      return;

   const int s1 = 1;

   double atr = iATR(_Symbol, g_entryTF, InpAtrPeriod, s1);
   if(atr <= 0.0 || r.rangeWidth <= 0.0)
      return;

   double o1 = iOpen(_Symbol,  g_entryTF, s1);
   double h1 = iHigh(_Symbol,  g_entryTF, s1);
   double l1 = iLow(_Symbol,   g_entryTF, s1);
   double c1 = iClose(_Symbol, g_entryTF, s1);
   double barRange = h1 - l1;
   if(barRange <= 0.0)
      return;

   double ema20   = iMA(_Symbol, g_entryTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE, s1);
   double bbUpper = iBands(_Symbol, g_entryTF, InpBBPeriod, InpBBDev, 0, PRICE_CLOSE, MODE_UPPER, s1);
   double bbLower = iBands(_Symbol, g_entryTF, InpBBPeriod, InpBBDev, 0, PRICE_CLOSE, MODE_LOWER, s1);
   double rsi     = iRSI(_Symbol, g_entryTF, InpRsiPeriod, PRICE_CLOSE, s1);

   double edge = RANGE_EDGE_PCT * r.rangeWidth;

   int dir = 0;
   if(h1 >= r.rangeHigh - edge)
      dir = -1;                       // zona alta -> si cerca lo short
   else
      if(l1 <= r.rangeLow + edge)
         dir = 1;                     // zona bassa -> si cerca il long

   if(dir == 0)
      return;

   //--- GATE: estensione rispetto alla media. Senza estensione non c'e'
   //    niente da far rientrare: sarebbe un ingresso a meta' del range.
   bool extBB  = (dir < 0 ? (h1 > bbUpper) : (l1 < bbLower));
   bool extATR = (dir < 0 ? ((c1 - ema20) / atr >  MR_EXT_ATR)
                          : ((ema20 - c1) / atr >  MR_EXT_ATR));
   if(!extBB && !extATR)
      return;

   //--- GATE: candela di rifiuto (ombra significativa oppure rientro)
   double upWick = h1 - MathMax(o1, c1);
   double dnWick = MathMin(o1, c1) - l1;
   bool rejection = false;
   if(dir < 0)
      rejection = ((c1 < o1 && upWick >= MR_WICK_PCT * barRange) ||
                   (h1 > bbUpper && c1 < bbUpper));
   else
      rejection = ((c1 > o1 && dnWick >= MR_WICK_PCT * barRange) ||
                   (l1 < bbLower && c1 > bbLower));
   if(!rejection)
      return;

   //--- GATE: il target (centro del range) deve essere ancora davanti
   if(dir < 0 && c1 <= r.rangeMid) return;
   if(dir > 0 && c1 >= r.rangeMid) return;

   //--- SCORING 0..10
   double score = 0.0;

   //  a) Range H1 ben definito  +2
   if(r.adx <= InpAdxRange && MathAbs(r.emaSlope) < SLOPE_FLAT_MAX * 0.6)
      score += 2.0;
   else
      score += 1.0;

   //  b) Prezzo in zona estrema  +2 (2 se nel 10% esterno, 1 nel resto della fascia)
   double distFromEdge = (dir < 0 ? (r.rangeHigh - h1) : (l1 - r.rangeLow));
   if(distFromEdge <= 0.5 * edge)
      score += 2.0;
   else
      score += 1.0;

   //  c) Estensione  +2 (entrambe le misure = 2, una sola = 1)
   if(extBB && extATR) score += 2.0;
   else                score += 1.0;

   //  d) Candela di rifiuto  +2
   double wickPct = (dir < 0 ? upWick / barRange : dnWick / barRange);
   if(wickPct >= 0.50) score += 2.0;
   else                score += 1.0;

   //  e) RSI in zona  +1
   bool rsiOk = (dir < 0 ? (rsi >= InpRsiLevel) : (rsi <= 100.0 - InpRsiLevel));
   if(rsiOk)
      score += 1.0;

   //  f) ATR sano  +1
   double atrAvgM15 = AverageATR(g_entryTF, InpAtrPeriod, ATR_AVG_PERIOD, s1);
   double atrRatio  = (atrAvgM15 > 0.0 ? atr / atrAvgM15 : 1.0);
   if(atrRatio >= InpMinAtrRatio && atrRatio <= VOL_MAX_RANGE)
      score += 1.0;

   //--- Stop oltre l'estremo del range, target al centro
   double stopRef = (dir < 0 ? MathMax(r.rangeHigh, h1) : MathMin(r.rangeLow, l1));

   s.strategy  = STRAT_MEANREV;
   s.dir       = dir;
   s.score     = NormScore(score);
   s.stopRef   = stopRef;
   s.targetRef = r.rangeMid;
   s.slAtrMult = InpSL_ATR_Range;
   s.valid     = true;

   g_signalNote = StringFormat("rifiuto del bordo range, RSI=%.1f, mid=%s",
                               rsi, DoubleToString(r.rangeMid, Digits));
  }

//+------------------------------------------------------------------+
//| Punteggio del volume (tick volume)                               |
//| Se il filtro e' disattivato il punto viene assegnato comunque:   |
//| in caso contrario la scala 0..10 si accorcerebbe e la soglia     |
//| InpMinSignalScore cambierebbe significato senza preavviso.       |
//+------------------------------------------------------------------+
double VolumeScore(int shift)
  {
   if(!InpUseVolumeFilter)
      return(1.0);

   double avg = VolumeSMA(g_entryTF, VOL_SMA_PERIOD, shift + 1);
   if(avg <= 0.0)
      return(1.0);

   double v = (double)iVolume(_Symbol, g_entryTF, shift);
   if(v >= VOL_RATIO_GOOD * avg)
      return(1.0);
   if(v >= avg)
      return(0.5);
   return(0.0);
  }

double VolumeSMA(int tf, int period, int startShift)
  {
   if(period <= 0)
      return(0.0);

   double sum = 0.0;
   for(int i = 0; i < period; i++)
      sum += (double)iVolume(_Symbol, tf, startShift + i);

   return(sum / period);
  }

//+------------------------------------------------------------------+
//| Media dell'ATR: misura della volatilita' RELATIVA                |
//| Il rapporto ATR/ATRmedio e' adimensionale, quindi le soglie non  |
//| vanno ritarate cambiando simbolo, timeframe o epoca storica.     |
//+------------------------------------------------------------------+
double AverageATR(int tf, int atrPeriod, int avgPeriod, int startShift)
  {
   if(avgPeriod <= 0)
      return(0.0);

   double sum = 0.0;
   int    n   = 0;

   for(int i = 0; i < avgPeriod; i++)
     {
      double v = iATR(_Symbol, tf, atrPeriod, startShift + i);
      if(v > 0.0)
        {
         sum += v;
         n++;
        }
     }
   return(n > 0 ? sum / n : 0.0);
  }

//+------------------------------------------------------------------+
//| Normalizza il punteggio nell'intervallo 0..10                    |
//+------------------------------------------------------------------+
double NormScore(double v)
  {
   if(v < 0.0)  return(0.0);
   if(v > 10.0) return(10.0);
   return(v);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//|                        RISK FILTERS (GATE)                       |
//|                                                                  |
//|  Condizioni binarie e non negoziabili. Sono tenute separate      |
//|  dallo scoring di proposito: un punteggio alto non deve mai      |
//|  poter "comprare" il permesso di operare con spread anomalo o    |
//|  con la perdita giornaliera gia' raggiunta.                      |
//+------------------------------------------------------------------+
bool PassesAllGates(RegimeInfo &r, SignalInfo &s)
  {
   //--- 1. Terminale operativo
   if(!IsTradeAllowed())
     {
      SetReject("trading non consentito dal terminale");
      return(false);
     }

   //--- 2. News filter: architettura predisposta, dati NON implementati.
   if(IsNewsBlackout())
     {
      SetReject("finestra news attiva");
      return(false);
     }

   //--- 3. Sessione
   if(!IsSessionAllowed())
     {
      SetReject("fuori dalla finestra operativa");
      return(false);
     }

   //--- 4. Protezioni di conto
   if(!AccountGuardsOk())
      return(false);

   //--- 5. Frequenza: un solo ingresso per barra e distanza minima
   if(g_lastEntryBar > 0)
     {
      int barsSince = iBarShift(_Symbol, g_entryTF, g_lastEntryBar, false);
      if(barsSince >= 0 && barsSince < InpMinBarsBetween)
        {
         SetReject(StringFormat("solo %d barre dall'ultimo ingresso (minimo %d)",
                                barsSince, InpMinBarsBetween));
         return(false);
        }
     }

   //--- 6. Esposizione
   int nSame = CountOwnPositions(s.dir);
   int nOpp  = CountOwnPositions(-s.dir);
   int nTot  = nSame + nOpp;

   if(nSame > 0)
     {
      SetReject("posizione gia' aperta nella stessa direzione");
      return(false);
     }
   if(nOpp > 0 && !InpAllowOpposite)
     {
      SetReject("posizione aperta in direzione opposta (hedging disabilitato)");
      return(false);
     }
   if(nTot >= InpMaxOpenTrades)
     {
      SetReject(StringFormat("numero massimo di posizioni raggiunto (%d)", InpMaxOpenTrades));
      return(false);
     }

   //--- 7. Spread
   if(!IsSpreadAcceptable())
      return(false);

   //--- 8. Volatilita' anomala sul timeframe operativo
   if(!IsVolatilitySane())
      return(false);

   //--- 9. Coerenza finale segnale/regime (difesa in profondita')
   if(!IsSignalCoherent(r, s))
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| Protezioni di conto: perdita giornaliera, settimanale, drawdown, |
//| numero di trade, pausa attiva.                                   |
//+------------------------------------------------------------------+
bool AccountGuardsOk()
  {
   if(TimeCurrent() < g_ddPauseUntil)
     {
      SetReject(StringFormat("pausa da drawdown attiva fino alle %s",
                             TimeToString(g_ddPauseUntil, TIME_DATE | TIME_MINUTES)));
      return(false);
     }

   double floating = FloatingPnL();

   if(InpMaxDailyLoss > 0.0 && g_dayBaseline > 0.0)
     {
      double dayPnl = g_realizedDay + floating;
      if(dayPnl < 0.0 && (-dayPnl / g_dayBaseline * 100.0) >= InpMaxDailyLoss)
        {
         SetReject(StringFormat("perdita giornaliera %.2f%% oltre il limite %.2f%%",
                                -dayPnl / g_dayBaseline * 100.0, InpMaxDailyLoss));
         return(false);
        }
     }

   if(InpMaxWeeklyLoss > 0.0 && g_weekBaseline > 0.0)
     {
      double weekPnl = g_realizedWeek + floating;
      if(weekPnl < 0.0 && (-weekPnl / g_weekBaseline * 100.0) >= InpMaxWeeklyLoss)
        {
         SetReject(StringFormat("perdita settimanale %.2f%% oltre il limite %.2f%%",
                                -weekPnl / g_weekBaseline * 100.0, InpMaxWeeklyLoss));
         return(false);
        }
     }

   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
     {
      SetReject(StringFormat("raggiunti %d trade giornalieri", InpMaxTradesPerDay));
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Filtro spread: assoluto e relativo alla volatilita'              |
//| Il controllo relativo e' quello che conta davvero: 2 pip di      |
//| spread sono accettabili con ATR 20 pip e proibitivi con ATR 6.   |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
  {
   RefreshRates();
   double spread = Ask - Bid;
   if(spread < 0.0)
      spread = 0.0;

   if(InpMaxSpreadPips > 0.0 && spread > InpMaxSpreadPips * g_pip)
     {
      SetReject(StringFormat("spread %.1f pips oltre il limite %.1f",
                             spread / g_pip, InpMaxSpreadPips));
      return(false);
     }

   if(InpMaxSpreadToATR > 0.0)
     {
      double atr = iATR(_Symbol, g_entryTF, InpAtrPeriod, 1);
      if(atr > 0.0 && spread > atr * InpMaxSpreadToATR)
        {
         SetReject(StringFormat("spread %.1f pips oltre il %.0f%% dell'ATR (%.1f pips)",
                                spread / g_pip, InpMaxSpreadToATR * 100.0, atr / g_pip));
         return(false);
        }
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Volatilita' nella norma sul timeframe operativo                  |
//+------------------------------------------------------------------+
bool IsVolatilitySane()
  {
   double atr    = iATR(_Symbol, g_entryTF, InpAtrPeriod, 1);
   double atrAvg = AverageATR(g_entryTF, InpAtrPeriod, ATR_AVG_PERIOD, 1);

   if(atr <= 0.0 || atrAvg <= 0.0)
     {
      SetReject("ATR non disponibile");
      return(false);
     }

   double ratio = atr / atrAvg;

   if(InpMinAtrRatio > 0.0 && ratio < InpMinAtrRatio)
     {
      SetReject(StringFormat("mercato troppo fermo: ATR al %.0f%% della media", ratio * 100.0));
      return(false);
     }
   if(InpMaxAtrRatio > 0.0 && ratio > InpMaxAtrRatio)
     {
      SetReject(StringFormat("volatilita' estrema: ATR al %.0f%% della media", ratio * 100.0));
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Coerenza tra strategia e regime                                  |
//+------------------------------------------------------------------+
bool IsSignalCoherent(RegimeInfo &r, SignalInfo &s)
  {
   if(s.strategy == STRAT_MEANREV && r.regime != REG_RANGE)
     {
      SetReject("mean reversion fuori dal regime range");
      return(false);
     }
   if(s.strategy == STRAT_TREND &&
      !((r.regime == REG_TREND_UP && s.dir > 0) || (r.regime == REG_TREND_DN && s.dir < 0)))
     {
      SetReject("segnale trend non allineato al regime H1");
      return(false);
     }
   if((r.regime == REG_TREND_UP && s.dir < 0) || (r.regime == REG_TREND_DN && s.dir > 0))
     {
      SetReject("segnale contrario al trend H1");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Filtro di sessione (ora del server)                              |
//+------------------------------------------------------------------+
bool IsSessionAllowed()
  {
   if(!InpUseSession)
      return(true);

   datetime now = TimeCurrent();
   int hour = TimeHour(now);
   int dow  = TimeDayOfWeek(now);

   if(dow == 0 || dow == 6)
      return(false);

   if(dow == 5 && InpFridayStopHour > 0 && hour >= InpFridayStopHour)
      return(false);

   //--- Finestra che non attraversa la mezzanotte
   if(InpSessionStart < InpSessionEnd)
      return(hour >= InpSessionStart && hour < InpSessionEnd);

   //--- Finestra a cavallo della mezzanotte
   if(InpSessionStart > InpSessionEnd)
      return(hour >= InpSessionStart || hour < InpSessionEnd);

   return(true);
  }

//+------------------------------------------------------------------+
//| NEWS FILTER - punto di estensione                                |
//|                                                                  |
//|  In v1 restituisce SEMPRE false: nessun dato macro viene letto e |
//|  nessuna finestra viene simulata. Fingere di avere le news       |
//|  (per esempio bloccando ogni primo venerdi' del mese) darebbe    |
//|  un backtest piu' bello e una falsa sicurezza: e' esattamente il |
//|  tipo di scorciatoia che questo progetto vuole evitare.          |
//|                                                                  |
//|  Per implementarlo in futuro senza toccare il resto dell'EA:     |
//|   1. caricare un CSV in MQL4/Files con data, ora, valuta, impatto|
//|   2. leggerlo in OnInit dentro array globali                     |
//|   3. qui confrontare TimeCurrent() con le finestre +/- N minuti  |
//|  L'unico contratto richiesto e' questa firma booleana.           |
//+------------------------------------------------------------------+
bool IsNewsBlackout()
  {
   return(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//|                       TRADE EXECUTION                            |
//|                                                                  |
//+------------------------------------------------------------------+
void ExecuteSignal(RegimeInfo &r, SignalInfo &s)
  {
   RefreshRates();

   double atr = iATR(_Symbol, g_entryTF, InpAtrPeriod, 1);
   if(atr <= 0.0)
     {
      SetReject("ATR non disponibile in esecuzione");
      LogReject();
      return;
     }

   double entry  = (s.dir > 0 ? Ask : Bid);
   double slDist = 0.0;
   double tpDist = 0.0;
   string note   = "";

   if(!BuildStopDistances(s, atr, entry, slDist, tpDist, note))
     {
      SetReject(note);
      LogReject();
      return;
     }

   double lots = CalculateLotSize(slDist);
   if(lots <= 0.0)
     {
      SetReject("volume calcolato nullo: rischio non allocabile");
      LogReject();
      return;
     }

   double sl = NormalizeDouble(s.dir > 0 ? entry - slDist : entry + slDist, Digits);
   double tp = NormalizeDouble(s.dir > 0 ? entry + tpDist : entry - tpDist, Digits);

   string cmt = BuildOrderComment(s.strategy, slDist);
   int    ticket = SendOrderWithRetries(s.dir > 0 ? OP_BUY : OP_SELL, lots, entry, sl, tp, cmt);

   if(ticket <= 0)
     {
      SetReject("invio ordine fallito");
      return;
     }

   g_lastEntryBar = iTime(_Symbol, g_entryTF, 0);
   g_tradesToday++;

   datetime openTime = 0;
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      openTime = OrderOpenTime();
   TrackAdd(ticket, slDist, openTime);

   Print("[", InpComment, "] TRADE APERTO #", IntegerToString(ticket),
         " ", (s.dir > 0 ? "LONG" : "SHORT"),
         " ", StrategyToString(s.strategy),
         " | regime=", RegimeToString(r.regime),
         " score=", DoubleToString(s.score, 1),
         " lots=", DoubleToString(lots, g_lotDigits),
         " SL=", DoubleToString(sl, Digits),
         " TP=", DoubleToString(tp, Digits),
         " | ", note);
  }

//+------------------------------------------------------------------+
//| MOTORE DELLE DISTANZE                                            |
//|                                                                  |
//|  Costruisce SL e TP combinando VOLATILITA' e STRUTTURA, poi li   |
//|  confronta con i vincoli reali del broker. Se dopo tutti gli     |
//|  aggiustamenti l'operazione non ha piu' un profilo sensato,      |
//|  restituisce false: meglio nessun trade che un trade con         |
//|  rischio/rendimento degradato dai vincoli tecnici.               |
//|                                                                  |
//|  Lo stop strutturale viene "agganciato" alla volatilita': non    |
//|  puo' scendere sotto 0.70 ne' salire sopra 1.80 volte lo stop    |
//|  ATR di riferimento. Senza questo vincolo un minimo strutturale  |
//|  lontano produrrebbe stop enormi e lotti irrisori, un minimo     |
//|  vicinissimo produrrebbe stop dentro il rumore di mercato.       |
//+------------------------------------------------------------------+
bool BuildStopDistances(SignalInfo &s, double atr, double entry,
                        double &slDistance, double &tpDistance, string &note)
  {
   slDistance = 0.0;
   tpDistance = 0.0;
   note       = "";

   double baseSL = s.slAtrMult * atr;
   if(baseSL <= 0.0)
     {
      note = "moltiplicatore ATR non valido";
      return(false);
     }

   //--- 1) Stop strutturale, ancorato alla volatilita'
   double slDist = baseSL;
   if(InpUseStructuralSL && s.stopRef > 0.0)
     {
      double structDist = (s.dir > 0 ? entry - s.stopRef : s.stopRef - entry) + 0.25 * atr;
      if(structDist > 0.0)
        {
         double lo = SL_STRUCT_MIN_F * baseSL;
         double hi = SL_STRUCT_MAX_F * baseSL;
         if(structDist < lo) structDist = lo;
         if(structDist > hi) structDist = hi;
         slDist = structDist;
        }
     }

   //--- 2) Vincoli del broker
   double minDist = BrokerMinStopDistance();

   if(minDist > atr * 0.80)
     {
      note = StringFormat("distanza minima broker %.1f pips troppo grande rispetto all'ATR (%.1f pips)",
                          minDist / g_pip, atr / g_pip);
      return(false);
     }

   bool widened = false;
   if(slDist < minDist)
     {
      slDist  = minDist;
      widened = true;
     }

   if(widened && InpMaxStopWiden > 0.0 && slDist > baseSL * InpMaxStopWiden)
     {
      note = StringFormat("SL allargato da %.1f a %.1f pips (x%.2f), oltre il limite x%.2f",
                          baseSL / g_pip, slDist / g_pip, slDist / baseSL, InpMaxStopWiden);
      return(false);
     }

   //--- 3) Take profit
   double tpDist = 0.0;
   if(s.targetRef > 0.0)
     {
      //--- Target strutturale (centro del range nella mean reversion)
      tpDist = (s.dir > 0 ? s.targetRef - entry : entry - s.targetRef);
      if(tpDist <= 0.0)
        {
         note = "target strutturale gia' superato dal prezzo";
         return(false);
        }
      if(tpDist < InpRangeTP_MinR * slDist)
        {
         note = StringFormat("target a %.2fR sotto il minimo di %.2fR",
                             tpDist / slDist, InpRangeTP_MinR);
         return(false);
        }
     }
   else
     {
      double rMult = (s.strategy == STRAT_BREAKOUT ? InpTP_R_Break : InpTP_R_Trend);
      tpDist = rMult * slDist;
     }

   if(tpDist < minDist)
      tpDist = minDist;

   //--- 4) Il target deve coprire i costi di transazione con margine
   double cost = MathMax(Ask - Bid, 0.0) + CommissionPriceEquivalent();
   if(cost > 0.0 && tpDist < cost * 3.0)
     {
      note = StringFormat("TP %.1f pips insufficiente: costo operazione %.1f pips",
                          tpDist / g_pip, cost / g_pip);
      return(false);
     }

   //--- 5) Rapporto rischio/rendimento effettivo
   double rr = tpDist / slDist;
   if(InpMinRiskReward > 0.0 && rr < InpMinRiskReward)
     {
      note = StringFormat("R:R effettivo 1:%.2f sotto il minimo 1:%.2f", rr, InpMinRiskReward);
      return(false);
     }

   slDistance = NormalizeDouble(slDist, Digits);
   tpDistance = NormalizeDouble(tpDist, Digits);

   note = StringFormat("SL %.1f pips, TP %.1f pips, R:R 1:%.2f%s",
                       slDistance / g_pip, tpDistance / g_pip, rr,
                       widened ? " (SL allargato dal broker)" : "");
   return(true);
  }

//+------------------------------------------------------------------+
//| Distanza minima imposta dal broker                               |
//+------------------------------------------------------------------+
double BrokerMinStopDistance()
  {
   double stopLevel   = MarketInfo(_Symbol, MODE_STOPLEVEL)   * Point;
   double freezeLevel = MarketInfo(_Symbol, MODE_FREEZELEVEL) * Point;
   double spread      = MathMax(Ask - Bid, 0.0);

   double minDist = MathMax(stopLevel, freezeLevel) + spread + InpStopBufferPips * g_pip;
   if(minDist < g_pip)
      minDist = g_pip;

   return(NormalizeDouble(minDist, Digits));
  }

//+------------------------------------------------------------------+
//| Distanza di prezzo equivalente alla commissione per lotto        |
//+------------------------------------------------------------------+
double CommissionPriceEquivalent()
  {
   if(InpCommissionPerLot <= 0.0)
      return(0.0);

   double tickValue = MarketInfo(_Symbol, MODE_TICKVALUE);
   double tickSize  = MarketInfo(_Symbol, MODE_TICKSIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return(0.0);

   return(InpCommissionPerLot * tickSize / tickValue);
  }

//+------------------------------------------------------------------+
//| CALCOLO DEL LOTTO                                                |
//|                                                                  |
//|  lotto = rischio_in_valuta / perdita_per_lotto_allo_stop         |
//|  perdita_per_lotto = (distanzaSL / tickSize) * tickValue         |
//|                                                                  |
//|  tickValue e tickSize sono letti dal broker: nessuna ipotesi su  |
//|  contract size, valuta del conto o numero di cifre.              |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
  {
   if(slDistancePrice <= 0.0)
      return(0.0);

   double riskMoney = RiskAmount();
   if(riskMoney <= 0.0)
      return(0.0);

   double tickValue = MarketInfo(_Symbol, MODE_TICKVALUE);
   double tickSize  = MarketInfo(_Symbol, MODE_TICKSIZE);
   if(tickSize <= 0.0)
      tickSize = Point;

   if(tickValue <= 0.0)
     {
      Print("[", InpComment, "] TICKVALUE non disponibile: impossibile dimensionare la posizione.");
      return(0.0);
     }

   double lossPerLot = (slDistancePrice / tickSize) * tickValue + InpCommissionPerLot;
   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;

   //--- Vincolo di margine libero (90% del disponibile)
   double marginPerLot = MarketInfo(_Symbol, MODE_MARGINREQUIRED);
   if(marginPerLot > 0.0)
     {
      double affordable = (AccountFreeMargin() * 0.90) / marginPerLot;
      if(affordable < lots)
         lots = affordable;
     }

   if(InpMaxLotCap > 0.0 && lots > InpMaxLotCap)
      lots = InpMaxLotCap;

   lots = NormalizeLots(lots);
   if(lots <= 0.0)
      return(0.0);

   //--- Il lotto minimo del broker puo' eccedere il budget di rischio:
   //    in quel caso NON si opera, invece di rischiare piu' del previsto.
   double realRisk = lots * lossPerLot;
   if(realRisk > riskMoney * 1.5)
     {
      Print("[", InpComment, "] Lotto minimo ", DoubleToString(lots, g_lotDigits),
            " comporta un rischio di ", DoubleToString(realRisk, 2), " ", AccountCurrency(),
            " contro un budget di ", DoubleToString(riskMoney, 2), ": operazione annullata.");
      return(0.0);
     }

   return(lots);
  }

//+------------------------------------------------------------------+
//| Importo a rischio, con riduzione dopo perdite consecutive        |
//|                                                                  |
//|  Nota critica: la riduzione dopo N perdite non ha una            |
//|  giustificazione statistica forte se i trade sono indipendenti.  |
//|  E' inclusa perche' richiesta e perche' e' ANTI-martingala (il   |
//|  rischio scende, non sale), quindi non puo' amplificare le       |
//|  perdite. Consiglio: il test di riferimento va fatto con         |
//|  InpLossStreakLimit = 0, e l'opzione va attivata solo se         |
//|  migliora il drawdown senza distruggere il profit factor.        |
//+------------------------------------------------------------------+
double RiskAmount()
  {
   double capital = (InpRiskBase == RISK_ON_EQUITY ? AccountEquity() : AccountBalance());
   if(capital <= 0.0)
      return(0.0);

   double factor = 1.0;
   if(InpLossStreakLimit > 0 && g_consecLosses >= InpLossStreakLimit)
      factor = InpLossStreakFactor;

   return(capital * InpRiskPercent / 100.0 * factor);
  }

//+------------------------------------------------------------------+
//| Normalizzazione del volume sullo step del broker                 |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Invio ordine con gestione degli errori e dei requote             |
//+------------------------------------------------------------------+
int SendOrderWithRetries(int orderType, double lots, double price, double sl, double tp, string comment)
  {
   double slDist = MathAbs(price - sl);
   double tpDist = MathAbs(price - tp);

   for(int attempt = 1; attempt <= InpMaxRetries; attempt++)
     {
      if(!WaitForTradeContext())
         continue;

      RefreshRates();

      //--- Il prezzo viene riallineato al mercato corrente, ma le DISTANZE
      //    restano quelle decise dal motore: il rischio non cambia per un
      //    requote di mezzo pip.
      price = NormalizeDouble(orderType == OP_BUY ? Ask : Bid, Digits);
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

      ResetLastError();
      int ticket = OrderSend(_Symbol, orderType, lots, price, g_slippagePoints, sl, tp,
                             comment, InpMagic, 0,
                             orderType == OP_BUY ? clrDodgerBlue : clrOrangeRed);

      if(ticket > 0)
         return(ticket);

      int err = GetLastError();
      Print("[", InpComment, "] OrderSend fallito (", IntegerToString(attempt), "/",
            IntegerToString(InpMaxRetries), ") errore ", IntegerToString(err), ": ", ErrorDescription(err),
            " | price=", DoubleToString(price, Digits),
            " SL=", DoubleToString(sl, Digits),
            " TP=", DoubleToString(tp, Digits),
            " lots=", DoubleToString(lots, g_lotDigits));

      //--- Errore 130 (invalid stops): apertura senza stop e modifica
      //    immediata. Se anche la modifica fallisce la posizione viene
      //    chiusa subito: mai lasciare una posizione senza protezione.
      if(err == 130)
        {
         ResetLastError();
         RefreshRates();
         price = NormalizeDouble(orderType == OP_BUY ? Ask : Bid, Digits);

         double widen = BrokerMinStopDistance() * 1.5;
         double useSL = MathMax(slDist, widen);
         double useTP = MathMax(tpDist, widen);

         ticket = OrderSend(_Symbol, orderType, lots, price, g_slippagePoints, 0.0, 0.0,
                            comment, InpMagic, 0, clrGray);
         if(ticket > 0)
           {
            double nsl = NormalizeDouble(orderType == OP_BUY ? price - useSL : price + useSL, Digits);
            double ntp = NormalizeDouble(orderType == OP_BUY ? price + useTP : price - useTP, Digits);
            if(!ModifyOrderWithRetries(ticket, nsl, ntp))
              {
               Print("[", InpComment, "] SL/TP non impostabili sul ticket ",
                     IntegerToString(ticket), ": chiusura immediata.");
               ClosePositionByTicket(ticket);
               return(-1);
              }
            return(ticket);
           }
         err = GetLastError();
         Print("[", InpComment, "] Anche l'apertura senza stop e' fallita, errore ",
               IntegerToString(err), ": ", ErrorDescription(err));
        }

      if(!IsRetryableError(err))
         break;

      Sleep(InpRetryDelayMs * attempt);
     }

   return(-1);
  }

//+------------------------------------------------------------------+
//| Modifica di SL/TP con retry e rispetto delle distanze minime     |
//+------------------------------------------------------------------+
bool ModifyOrderWithRetries(int ticket, double sl, double tp)
  {
   for(int attempt = 1; attempt <= InpMaxRetries; attempt++)
     {
      if(!WaitForTradeContext())
         continue;

      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
        {
         Sleep(InpRetryDelayMs);
         continue;
        }

      RefreshRates();

      double minDist = BrokerMinStopDistance();
      double newSL   = NormalizeDouble(sl, Digits);
      double newTP   = NormalizeDouble(tp, Digits);

      if(OrderType() == OP_BUY)
        {
         if(newSL > 0.0 && Bid - newSL < minDist) newSL = NormalizeDouble(Bid - minDist, Digits);
         if(newTP > 0.0 && newTP - Ask < minDist) newTP = NormalizeDouble(Ask + minDist, Digits);
        }
      else
         if(OrderType() == OP_SELL)
           {
            if(newSL > 0.0 && newSL - Ask < minDist) newSL = NormalizeDouble(Ask + minDist, Digits);
            if(newTP > 0.0 && Bid - newTP < minDist) newTP = NormalizeDouble(Bid - minDist, Digits);
           }

      //--- Niente da fare: evita OrderModify inutili (errore 1)
      if(MathAbs(OrderStopLoss() - newSL) < Point / 2.0 &&
         MathAbs(OrderTakeProfit() - newTP) < Point / 2.0)
         return(true);

      ResetLastError();
      if(OrderModify(ticket, OrderOpenPrice(), newSL, newTP, 0, clrLimeGreen))
         return(true);

      int err = GetLastError();
      if(err == 1)
         return(true);

      Print("[", InpComment, "] OrderModify fallito (", IntegerToString(attempt), "/",
            IntegerToString(InpMaxRetries), ") ticket ", IntegerToString(ticket),
            " errore ", IntegerToString(err), ": ", ErrorDescription(err));

      if(!IsRetryableError(err))
         break;

      Sleep(InpRetryDelayMs * attempt);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Chiusura totale di una posizione                                 |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(int ticket)
  {
   for(int attempt = 1; attempt <= InpMaxRetries; attempt++)
     {
      if(!WaitForTradeContext())
         continue;

      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
         return(false);
      if(OrderCloseTime() != 0)
         return(true);

      RefreshRates();
      double price = (OrderType() == OP_BUY ? Bid : Ask);

      ResetLastError();
      if(OrderClose(ticket, OrderLots(), NormalizeDouble(price, Digits), g_slippagePoints, clrWhite))
         return(true);

      int err = GetLastError();
      Print("[", InpComment, "] OrderClose fallito (", IntegerToString(attempt), "/",
            IntegerToString(InpMaxRetries), ") ticket ", IntegerToString(ticket),
            " errore ", IntegerToString(err), ": ", ErrorDescription(err));

      if(!IsRetryableError(err))
         break;

      Sleep(InpRetryDelayMs * attempt);
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
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      int tk = OrderTicket();
      if(ClosePositionByTicket(tk))
         Print("[", InpComment, "] Posizione #", IntegerToString(tk), " chiusa: ", reason);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//|                     POSITION MANAGEMENT                          |
//|                                                                  |
//|  Gira a ogni tick. Ordine delle operazioni:                      |
//|    1. uscita per ribaltamento del regime (la piu' urgente)       |
//|    2. chiusura parziale al primo target                          |
//|    3. break-even                                                 |
//|    4. trailing stop                                              |
//|  Lo stop non arretra MAI: ogni modifica deve migliorare la       |
//|  protezione, altrimenti viene ignorata.                          |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   double atr = iATR(_Symbol, g_entryTF, InpAtrPeriod, 1);
   if(atr <= 0.0)
      return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagic) continue;

      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;

      int      ticket = OrderTicket();
      int      dir    = (type == OP_BUY ? 1 : -1);
      double   open   = OrderOpenPrice();
      double   curSL  = OrderStopLoss();
      double   curTP  = OrderTakeProfit();
      double   lots   = OrderLots();
      datetime otime  = OrderOpenTime();
      string   ocmt   = OrderComment();

      //--- Rischio iniziale della posizione (1R)
      double risk = GetPositionRisk(ticket, ocmt, atr);
      if(risk <= 0.0)
         continue;

      RefreshRates();
      double cur     = (dir > 0 ? Bid : Ask);
      double profitR = (dir > 0 ? (cur - open) : (open - cur)) / risk;

      //--- 1) Uscita per ribaltamento del regime H1
      if(InpExitOnFlip && IsRegimeAgainst(dir))
        {
         if(ClosePositionByTicket(ticket))
           {
            Print("[", InpComment, "] Posizione #", IntegerToString(ticket),
                  " chiusa: regime H1 ribaltato contro (", RegimeToString(g_curRegime), ").");
            continue;
           }
        }

      //--- 2) Chiusura parziale
      if(InpUsePartialTP && profitR >= InpPartialR && !IsPartialDone(ticket, ocmt))
        {
         double closeLots = NormalizeDouble(MathFloor((lots * InpPartialPct / 100.0) / g_lotStep) * g_lotStep, g_lotDigits);
         double remainder = NormalizeDouble(lots - closeLots, g_lotDigits);

         if(closeLots >= g_minLot && remainder >= g_minLot)
           {
            if(WaitForTradeContext())
              {
               RefreshRates();
               double px = (dir > 0 ? Bid : Ask);
               ResetLastError();
               if(OrderClose(ticket, closeLots, NormalizeDouble(px, Digits), g_slippagePoints, clrGold))
                 {
                  Print("[", InpComment, "] Parziale eseguito su #", IntegerToString(ticket),
                        ": chiusi ", DoubleToString(closeLots, g_lotDigits), " lotti a ",
                        DoubleToString(profitR, 2), "R.");
                  //--- MT4 assegna un NUOVO ticket al residuo: va ritracciato
                  //    subito, altrimenti perde il proprio 1R di riferimento.
                  RetrackAfterPartial(otime, open, risk);
                  continue;
                 }
               int err = GetLastError();
               Print("[", InpComment, "] Chiusura parziale fallita su #", IntegerToString(ticket),
                     " errore ", IntegerToString(err), ": ", ErrorDescription(err));
              }
           }
        }

      //--- 3) e 4) Break-even e trailing: si calcola il miglior SL possibile
      double bestSL = curSL;

      if(InpUseBreakEven && profitR >= InpBE_TriggerR)
        {
         double beSL = (dir > 0 ? open + InpBE_LockR * risk : open - InpBE_LockR * risk);
         if(IsBetterStop(dir, beSL, bestSL))
            bestSL = beSL;
        }

      if(InpUseTrailing && profitR >= InpTrailStartR)
        {
         double trailSL = (dir > 0 ? cur - InpTrailATR * atr : cur + InpTrailATR * atr);

         //--- Il trailing si muove solo a passi minimi: evita una raffica di
         //    OrderModify a ogni tick e il conseguente carico sul server.
         bool stepOk = (curSL == 0.0) ||
                       (MathAbs(trailSL - bestSL) >= InpTrailStepATR * atr);

         if(stepOk && IsBetterStop(dir, trailSL, bestSL))
            bestSL = trailSL;
        }

      if(IsBetterStop(dir, bestSL, curSL) && bestSL != 0.0)
         ModifyOrderWithRetries(ticket, bestSL, curTP);
     }
  }

//+------------------------------------------------------------------+
//| Uno stop e' migliore solo se protegge di piu'                    |
//+------------------------------------------------------------------+
bool IsBetterStop(int dir, double candidate, double current)
  {
   if(candidate <= 0.0)
      return(false);
   if(current <= 0.0)
      return(true);

   if(dir > 0)
      return(candidate > current + Point / 2.0);

   return(candidate < current - Point / 2.0);
  }

//+------------------------------------------------------------------+
//| Il regime corrente e' contrario alla posizione?                  |
//| Usa il regime memorizzato all'ultima barra chiusa: ricalcolarlo  |
//| a ogni tick sarebbe costoso e non cambierebbe il risultato.      |
//+------------------------------------------------------------------+
bool IsRegimeAgainst(int dir)
  {
   if(dir > 0 && g_curRegime == REG_TREND_DN && g_curRegimeScore >= InpMinTrendScore)
      return(true);
   if(dir < 0 && g_curRegime == REG_TREND_UP && g_curRegimeScore >= InpMinTrendScore)
      return(true);
   return(false);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//|             TRACCIAMENTO DELLE POSIZIONI (1R iniziale)           |
//|                                                                  |
//|  Il rischio iniziale serve a break-even, trailing e parziale.    |
//|  Viene conservato su tre livelli di ridondanza:                  |
//|    1. array in memoria (fonte primaria)                          |
//|    2. commento dell'ordine, dove e' codificato in punti          |
//|    3. stima da ATR corrente (ultima risorsa dopo un riavvio)     |
//|  Senza questa ridondanza un riavvio del terminale trasformerebbe |
//|  la gestione delle posizioni aperte in un comportamento casuale. |
//+------------------------------------------------------------------+
string BuildOrderComment(ENUM_STRATEGY st, double slDist)
  {
   int pts = (int)MathRound(slDist / Point);

   //--- MT4 tronca i commenti oltre i 31 caratteri: il prefisso viene
   //    accorciato per primo, cosi' il campo "|R<punti>" - da cui si
   //    ricostruisce 1R dopo un riavvio - sopravvive sempre.
   string tail   = "|" + StrategyTag(st) + "|R" + IntegerToString(pts);
   string prefix = InpComment;
   int    room   = 31 - StringLen(tail);
   if(room < 0)  room = 0;
   if(StringLen(prefix) > room)
      prefix = StringSubstr(prefix, 0, room);

   return(prefix + tail);
  }

string StrategyTag(ENUM_STRATEGY st)
  {
   if(st == STRAT_TREND)    return("T");
   if(st == STRAT_BREAKOUT) return("B");
   if(st == STRAT_MEANREV)  return("M");
   return("X");
  }

void TrackAdd(int ticket, double risk, datetime openTime)
  {
   int idx = TrackFind(ticket);
   if(idx < 0)
     {
      if(g_trkCount >= MAX_TRACKED)
         return;
      idx = g_trkCount;
      g_trkCount++;
      g_trkPartial[idx] = false;
     }

   g_trkTicket[idx]   = ticket;
   g_trkRisk[idx]     = risk;
   g_trkOpenTime[idx] = openTime;
  }

int TrackFind(int ticket)
  {
   for(int i = 0; i < g_trkCount; i++)
      if(g_trkTicket[i] == ticket)
         return(i);
   return(-1);
  }

//+------------------------------------------------------------------+
//| Rimuove dal tracciamento i ticket non piu' aperti                |
//+------------------------------------------------------------------+
void SyncTracking()
  {
   int w = 0;
   for(int i = 0; i < g_trkCount; i++)
     {
      bool alive = false;
      if(OrderSelect(g_trkTicket[i], SELECT_BY_TICKET, MODE_TRADES))
         if(OrderCloseTime() == 0 && OrderSymbol() == _Symbol && OrderMagicNumber() == InpMagic)
            alive = true;

      if(alive)
        {
         if(w != i)
           {
            g_trkTicket[w]   = g_trkTicket[i];
            g_trkRisk[w]     = g_trkRisk[i];
            g_trkOpenTime[w] = g_trkOpenTime[i];
            g_trkPartial[w]  = g_trkPartial[i];
           }
         w++;
        }
     }
   g_trkCount = w;
  }

//+------------------------------------------------------------------+
//| Dopo una chiusura parziale MT4 crea un nuovo ticket per il       |
//| residuo: lo si ritrova per data e prezzo di apertura, che        |
//| restano invariati, e lo si registra come "parziale gia' fatto".  |
//+------------------------------------------------------------------+
void RetrackAfterPartial(datetime openTime, double openPrice, double risk)
  {
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderOpenTime() != openTime) continue;
      if(MathAbs(OrderOpenPrice() - openPrice) > Point / 2.0) continue;

      int tk = OrderTicket();
      TrackAdd(tk, risk, openTime);
      int idx = TrackFind(tk);
      if(idx >= 0)
         g_trkPartial[idx] = true;
      return;
     }
  }

//+------------------------------------------------------------------+
//| Il parziale e' gia' stato eseguito su questa posizione?          |
//| Doppio controllo: array in memoria e commento del residuo, che   |
//| molti broker riscrivono come "from #<ticket>".                   |
//+------------------------------------------------------------------+
bool IsPartialDone(int ticket, string cmt)
  {
   int idx = TrackFind(ticket);
   if(idx >= 0 && g_trkPartial[idx])
      return(true);

   if(StringFind(cmt, "from #") >= 0)
      return(true);

   return(false);
  }

//+------------------------------------------------------------------+
//| Recupero del rischio iniziale (1R) di una posizione              |
//+------------------------------------------------------------------+
double GetPositionRisk(int ticket, string cmt, double atr)
  {
   //--- 1) Memoria
   int idx = TrackFind(ticket);
   if(idx >= 0 && g_trkRisk[idx] > 0.0)
      return(g_trkRisk[idx]);

   //--- 2) Commento dell'ordine: "...|R1234" con 1234 in punti
   int pos = StringFind(cmt, "|R");
   if(pos >= 0)
     {
      string tail = StringSubstr(cmt, pos + 2);
      int    pts  = (int)StringToInteger(tail);
      if(pts > 0)
        {
         double risk = pts * Point;
         TrackAdd(ticket, risk, 0);
         return(risk);
        }
     }

   //--- 3) Ultima risorsa: stima dall'ATR corrente. Approssimata per
   //       definizione, ma sufficiente a non lasciare la posizione senza
   //       gestione dopo un riavvio del terminale.
   double fallback = InpSL_ATR_Trend * atr;
   if(fallback > 0.0)
     {
      TrackAdd(ticket, fallback, 0);
      if(InpDebugMode)
         Print("[", InpComment, "] 1R ricostruito da ATR sul ticket ", IntegerToString(ticket));
     }
   return(fallback);
  }

//+------------------------------------------------------------------+
//| Ricostruzione del tracciamento all'avvio                         |
//+------------------------------------------------------------------+
void RebuildTrackingFromOpenPositions()
  {
   double atr = iATR(_Symbol, g_entryTF, InpAtrPeriod, 1);

   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      GetPositionRisk(OrderTicket(), OrderComment(), atr);
     }
  }

//+------------------------------------------------------------------+
//| Conteggio delle posizioni proprie                                |
//| dir = +1 long, -1 short, 0 tutte                                 |
//+------------------------------------------------------------------+
int CountOwnPositions(int dir)
  {
   int n = 0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagic) continue;

      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;

      if(dir > 0 && type != OP_BUY)  continue;
      if(dir < 0 && type != OP_SELL) continue;

      n++;
     }
   return(n);
  }

//+------------------------------------------------------------------+
//| Profitto flottante delle sole posizioni dell'EA                  |
//+------------------------------------------------------------------+
double FloatingPnL()
  {
   double total = 0.0;
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      total += OrderProfit() + OrderSwap() + OrderCommission();
     }
   return(total);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//|                  STATO DI CONTO E PERIODI                        |
//|                                                                  |
//+------------------------------------------------------------------+
void UpdatePeriodState()
  {
   datetime now = TimeCurrent();

   datetime d = DayStart(now);
   if(d != g_dayStart)
     {
      g_dayStart    = d;
      g_realizedDay = 0.0;
      g_tradesToday = 0;
      g_dayBaseline = AccountBalance();
     }

   datetime w = WeekStart(now);
   if(w != g_weekStart)
     {
      g_weekStart    = w;
      g_realizedWeek = 0.0;
      g_weekBaseline = AccountBalance();
     }

   if(g_dayBaseline  <= 0.0) g_dayBaseline  = AccountBalance();
   if(g_weekBaseline <= 0.0) g_weekBaseline = AccountBalance();

   //--- Controllo del drawdown sul picco di equity
   double eq = AccountEquity();
   if(eq > g_peakEquity)
     {
      g_peakEquity   = eq;
      g_ddPauseLogged = false;
     }

   if(InpMaxDrawdown > 0.0 && g_peakEquity > 0.0)
     {
      double dd = (g_peakEquity - eq) / g_peakEquity * 100.0;
      if(dd >= InpMaxDrawdown && now >= g_ddPauseUntil)
        {
         g_ddPauseUntil = (datetime)(now + InpDDPauseHours * 3600);
         if(!g_ddPauseLogged)
           {
            Print("[", InpComment, "] STOP TRADING: drawdown ", DoubleToString(dd, 2),
                  "% oltre il limite di ", DoubleToString(InpMaxDrawdown, 2),
                  "%. Pausa fino alle ", TimeToString(g_ddPauseUntil, TIME_DATE | TIME_MINUTES));
            g_ddPauseLogged = true;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Aggiornamento incrementale delle statistiche sui trade chiusi    |
//|                                                                  |
//|  Lo storico viene riletto SOLO quando il numero di operazioni    |
//|  chiuse cambia. Una scansione a ogni tick renderebbe il backtest |
//|  pluriennale ingestibile.                                        |
//+------------------------------------------------------------------+
void UpdateClosedTradeStats()
  {
   int total = OrdersHistoryTotal();
   if(total == g_lastHistTotal)
      return;
   g_lastHistTotal = total;

   //--- I trade chiusi vengono processati in ordine cronologico
   for(int guard = 0; guard < 100; guard++)
     {
      int      bestPos  = -1;
      datetime bestTime = 0;
      int      bestTk   = 0;

      for(int i = 0; i < total; i++)
        {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagic) continue;
         if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

         datetime ct = OrderCloseTime();
         int      tk = OrderTicket();
         if(ct < g_lastClosedTime) continue;
         if(ct == g_lastClosedTime && tk <= g_lastClosedTick) continue;

         if(bestPos < 0 || ct < bestTime || (ct == bestTime && tk < bestTk))
           {
            bestPos  = i;
            bestTime = ct;
            bestTk   = tk;
           }
        }

      if(bestPos < 0)
         break;

      if(!OrderSelect(bestPos, SELECT_BY_POS, MODE_HISTORY))
         break;

      ApplyClosedTrade(bestTime, OrderProfit() + OrderSwap() + OrderCommission());
      g_lastClosedTime = bestTime;
      g_lastClosedTick = bestTk;
     }
  }

void ApplyClosedTrade(datetime closeTime, double pl)
  {
   if(closeTime >= g_dayStart)
      g_realizedDay += pl;
   if(closeTime >= g_weekStart)
      g_realizedWeek += pl;

   if(pl < 0.0)
      g_consecLosses++;
   else
      if(pl > 0.0)
         g_consecLosses = 0;

   if(InpDebugMode)
      Print("[", InpComment, "] Trade chiuso: P/L=", DoubleToString(pl, 2),
            " | perdite consecutive=", IntegerToString(g_consecLosses),
            " | giorno=", DoubleToString(g_realizedDay, 2),
            " settimana=", DoubleToString(g_realizedWeek, 2));
  }

//+------------------------------------------------------------------+
//| Ricostruzione dello stato dallo storico (una sola volta in init) |
//+------------------------------------------------------------------+
void RebuildStateFromHistory()
  {
   g_realizedDay    = 0.0;
   g_realizedWeek   = 0.0;
   g_tradesToday    = 0;
   g_consecLosses   = 0;
   g_lastClosedTime = 0;
   g_lastClosedTick = 0;

   int total = OrdersHistoryTotal();
   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      datetime ct = OrderCloseTime();
      double   pl = OrderProfit() + OrderSwap() + OrderCommission();
      int      tk = OrderTicket();

      if(ct >= g_dayStart)
        {
         g_realizedDay += pl;
         g_tradesToday++;
        }
      if(ct >= g_weekStart)
         g_realizedWeek += pl;

      if(ct > g_lastClosedTime || (ct == g_lastClosedTime && tk > g_lastClosedTick))
        {
         g_lastClosedTime = ct;
         g_lastClosedTick = tk;
        }
     }

   g_consecLosses  = CountRecentLossStreak();
   g_lastHistTotal = total;
  }

//+------------------------------------------------------------------+
//| Serie di perdite consecutive piu' recente                        |
//+------------------------------------------------------------------+
int CountRecentLossStreak()
  {
   int      streak   = 0;
   datetime cursor   = (datetime)(TimeCurrent() + 86400);
   int      cursorTk = 2147483647;
   int      total    = OrdersHistoryTotal();

   for(int step = 0; step < 30; step++)
     {
      int      bestPos  = -1;
      datetime bestTime = 0;
      int      bestTk   = 0;

      for(int i = 0; i < total; i++)
        {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
         if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagic) continue;
         if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

         datetime ct = OrderCloseTime();
         int      tk = OrderTicket();
         if(ct > cursor) continue;
         if(ct == cursor && tk >= cursorTk) continue;

         if(bestPos < 0 || ct > bestTime || (ct == bestTime && tk > bestTk))
           {
            bestPos  = i;
            bestTime = ct;
            bestTk   = tk;
           }
        }

      if(bestPos < 0)
         break;
      if(!OrderSelect(bestPos, SELECT_BY_POS, MODE_HISTORY))
         break;

      double pl = OrderProfit() + OrderSwap() + OrderCommission();
      if(pl < 0.0)
         streak++;
      else
         break;

      cursor   = bestTime;
      cursorTk = bestTk;
     }

   return(streak);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//|                       LOG E DEBUG                                |
//|                                                                  |
//+------------------------------------------------------------------+
void SetReject(string reason)
  {
   g_rejectReason = reason;
  }

void LogReject()
  {
   if(InpLogRejections && g_rejectReason != "")
      Print("[", InpComment, "] Trade scartato: ", g_rejectReason);
  }

//+------------------------------------------------------------------+
//| Blocco diagnostico completo, stampato solo con DebugMode = true  |
//+------------------------------------------------------------------+
void DebugDump(RegimeInfo &r, SignalInfo &s)
  {
   if(!InpDebugMode)
     {
      //--- Con il debug spento resta comunque traccia dei rifiuti
      //    quando esisteva un segnale valido: e' l'informazione che
      //    serve davvero per capire perche' l'EA non ha operato.
      if(s.valid && s.score >= InpMinSignalScore && g_rejectReason != "")
         LogReject();
      return;
     }

   Print("---------------- ", TimeToString(iTime(_Symbol, g_entryTF, 0), TIME_DATE | TIME_MINUTES),
         " ----------------");
   Print("Regime ", TimeframeToString(g_regimeTF), ": ", RegimeToString(r.regime),
         "  (score ", DoubleToString(r.score, 1), "/6)");
   Print("  ADX=", DoubleToString(r.adx, 1),
         " (slope ", DoubleToString(r.adxSlope, 1), ")",
         "  ATR=", DoubleToString(r.atr / g_pip, 1), " pips",
         "  ATR/media=", DoubleToString(r.atrRatio, 2));
   Print("  EMA20=", DoubleToString(r.ema20, Digits),
         "  EMA50=", DoubleToString(r.ema50, Digits),
         "  EMA200=", DoubleToString(r.ema200, Digits),
         "  pendenza=", DoubleToString(r.emaSlope, 2), " ATR");
   Print("  Struttura: HH=", (r.hh ? "si" : "no"), " HL=", (r.hl ? "si" : "no"),
         " LH=", (r.lh ? "si" : "no"), " LL=", (r.ll ? "si" : "no"),
         "  Range=[", DoubleToString(r.rangeLow, Digits), " ; ",
         DoubleToString(r.rangeHigh, Digits), "]");

   if(s.valid)
     {
      Print("Segnale ", TimeframeToString(g_entryTF), ": ",
            (s.dir > 0 ? "LONG" : "SHORT"), " ", StrategyToString(s.strategy),
            "  score ", DoubleToString(s.score, 1), "/10 (soglia ",
            DoubleToString(InpMinSignalScore, 1), ")");
      if(g_signalNote != "")
         Print("  Dettaglio: ", g_signalNote);
     }
   else
      Print("Segnale ", TimeframeToString(g_entryTF), ": nessuno");

   double spread = MathMax(Ask - Bid, 0.0);
   Print("  Spread=", DoubleToString(spread / g_pip, 1), " pips",
         "  Rischio=", DoubleToString(InpRiskPercent, 2), "%",
         (g_consecLosses >= InpLossStreakLimit && InpLossStreakLimit > 0
          ? " (ridotto x" + DoubleToString(InpLossStreakFactor, 2) + ")" : ""),
         "  Perdite consecutive=", IntegerToString(g_consecLosses));
   Print("  Giorno=", DoubleToString(g_realizedDay, 2),
         "  Settimana=", DoubleToString(g_realizedWeek, 2),
         "  Trade oggi=", IntegerToString(g_tradesToday),
         "  Posizioni=", IntegerToString(CountOwnPositions(0)));

   if(g_rejectReason != "")
      Print("  DECISIONE: NO TRADE -> ", g_rejectReason);
   else
      if(s.valid && s.score >= InpMinSignalScore)
         Print("  DECISIONE: TRADE");
      else
         Print("  DECISIONE: NO TRADE");
  }

//+------------------------------------------------------------------+
//|                                                                  |
//|                          UTILITY                                 |
//|                                                                  |
//+------------------------------------------------------------------+
datetime DayStart(datetime t)
  {
   return((datetime)((long)t - ((long)t % 86400)));
  }

//+------------------------------------------------------------------+
//| Inizio settimana: domenica 00:00 del server. La settimana di     |
//| trading apre domenica sera, quindi ancorarla alla domenica evita |
//| che le operazioni notturne finiscano nel conteggio sbagliato.    |
//+------------------------------------------------------------------+
datetime WeekStart(datetime t)
  {
   int dow = TimeDayOfWeek(t);
   if(dow < 0) dow = 0;
   return((datetime)((long)DayStart(t) - (long)dow * 86400));
  }

//+------------------------------------------------------------------+
//| Attende che il contesto di trading sia libero                    |
//+------------------------------------------------------------------+
bool WaitForTradeContext()
  {
   int waited = 0;
   while(IsTradeContextBusy() && waited < 2000)
     {
      Sleep(100);
      waited += 100;
     }
   return(!IsTradeContextBusy());
  }

//+------------------------------------------------------------------+
//| Errori per cui ha senso riprovare                                |
//+------------------------------------------------------------------+
bool IsRetryableError(int err)
  {
   switch(err)
     {
      case 4:      // server occupato
      case 6:      // nessuna connessione
      case 128:    // timeout della transazione
      case 129:    // prezzo non valido
      case 135:    // prezzo cambiato
      case 136:    // quotazione assente
      case 137:    // broker occupato
      case 138:    // requote
      case 146:    // sottosistema occupato
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Descrizione degli errori piu' frequenti                          |
//+------------------------------------------------------------------+
string ErrorDescription(int err)
  {
   switch(err)
     {
      case 0:   return("nessun errore");
      case 1:   return("nessun cambiamento richiesto");
      case 2:   return("errore generico");
      case 3:   return("parametri non validi");
      case 4:   return("server occupato");
      case 5:   return("versione del terminale obsoleta");
      case 6:   return("nessuna connessione al server");
      case 8:   return("richieste troppo frequenti");
      case 64:  return("conto bloccato");
      case 65:  return("numero di conto non valido");
      case 128: return("timeout della transazione");
      case 129: return("prezzo non valido");
      case 130: return("stop non validi (troppo vicini al prezzo)");
      case 131: return("volume non valido");
      case 132: return("mercato chiuso");
      case 133: return("trading disabilitato");
      case 134: return("fondi insufficienti");
      case 135: return("prezzo cambiato");
      case 136: return("quotazione assente");
      case 137: return("broker occupato");
      case 138: return("requote");
      case 139: return("ordine bloccato ed in elaborazione");
      case 141: return("troppe richieste");
      case 145: return("modifica vietata: ordine troppo vicino al mercato");
      case 146: return("sottosistema di trading occupato");
      case 147: return("scadenza dell'ordine non accettata dal broker");
      case 148: return("numero di ordini aperti oltre il limite del broker");
     }
   return("errore " + IntegerToString(err));
  }

string DeinitReasonText(int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return("chiusura da programma");
      case REASON_REMOVE:      return("EA rimosso dal grafico");
      case REASON_RECOMPILE:   return("ricompilazione");
      case REASON_CHARTCHANGE: return("cambio simbolo o timeframe");
      case REASON_CHARTCLOSE:  return("grafico chiuso");
      case REASON_PARAMETERS:  return("parametri modificati");
      case REASON_ACCOUNT:     return("cambio di conto");
     }
   return("motivo " + IntegerToString(reason));
  }

string RegimeToString(ENUM_REGIME r)
  {
   switch(r)
     {
      case REG_TREND_UP: return("TREND BULLISH");
      case REG_TREND_DN: return("TREND BEARISH");
      case REG_RANGE:    return("RANGE");
      case REG_BREAKOUT: return("BREAKOUT / TRANSITION");
     }
   return("NO TRADE");
  }

string StrategyToString(ENUM_STRATEGY s)
  {
   switch(s)
     {
      case STRAT_TREND:    return("Trend Following");
      case STRAT_BREAKOUT: return("Breakout");
      case STRAT_MEANREV:  return("Mean Reversion");
     }
   return("nessuna");
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
