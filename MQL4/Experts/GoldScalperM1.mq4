//+------------------------------------------------------------------+
//|                                              GoldScalperM1.mq4    |
//|         Expert Advisor di scalping per XAUUSD su M1 e M5 (MT4)    |
//|                            v1.10                                  |
//|                                                                   |
//|  NOVITA' DELLA v1.10                                              |
//|   - PROFILO DI AGGRESSIVITA' (da conservativo a molto aggressivo) |
//|     che agisce insieme su filtri di setup, frequenza e rischio.   |
//|   - ADATTAMENTO AUTOMATICO AL TIMEFRAME: le soglie in pips seguono |
//|     la radice del tempo, i tempi seguono la durata della barra e   |
//|     il timeframe direzionale sale se e' troppo vicino.            |
//|   - FILTRO DI VOLATILITA' RELATIVO: si confronta l'ATR con la sua  |
//|     media, non con un numero fisso di pips. Una soglia assoluta    |
//|     presuppone di sapere quanto vale l'ATR "normale", che cambia   |
//|     con il prezzo dell'oro e con il broker: lasciata fissa,        |
//|     impedisce ogni ingresso per giorni interi.                    |
//|   - Diagnostica all'avvio che segnala subito una soglia che sta    |
//|     bloccando l'operativita'.                                     |
//|                                                                   |
//|  FILOSOFIA                                                        |
//|   Lo scalping su oro in M1 non fallisce per mancanza di segnali:   |
//|   fallisce per i costi e per il rumore. Questo EA e' costruito     |
//|   attorno a quel problema.                                        |
//|                                                                   |
//|   1. DIREZIONE dal timeframe superiore (M15): su M1 la direzione   |
//|      non e' leggibile, quindi non la si legge su M1.               |
//|   2. INGRESSO su M1 solo su pullback + ripartenza: si entra a      |
//|      favore del movimento gia' in corso, dopo un ritracciamento    |
//|      sulla EMA veloce, alla rottura della barra precedente.        |
//|   3. FILTRO COSTI: spread assoluto, spread in rapporto all'ATR e   |
//|      verifica che il take profit valga piu' volte spread +         |
//|      commissione. Se il trade non copre i costi con margine,       |
//|      non viene eseguito.                                          |
//|   4. FILTRO VOLATILITA': banda ATR minima e massima piu' guardia   |
//|      anti-spike, per stare fuori sia dal mercato morto sia dalle   |
//|      candele da notizia.                                          |
//|   5. USCITA RAPIDA: parziale a 1R, break-even, trailing su ATR e   |
//|      uscita a tempo. Uno scalp M1 che dura un'ora non e' piu' uno  |
//|      scalp.                                                       |
//|   6. PROTEZIONI: limite trade giornalieri e orari, stop giornaliero|
//|      in percentuale, target giornaliero, pausa dopo N perdite      |
//|      consecutive.                                                 |
//|                                                                   |
//|  DASHBOARD                                                        |
//|   Pannello grafico ad oggetti con intestazione di stato, tre       |
//|   riquadri KPI, barre di avanzamento (spread, rischio giornaliero, |
//|   trade usati, posizione da SL a TP), checklist dei filtri con     |
//|   semaforo e tre pulsanti operativi (pausa, chiusura, riduci).     |
//+------------------------------------------------------------------+
#property copyright "Gold Scalper M1"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Enumerazioni                                                     |
//+------------------------------------------------------------------+
enum ENUM_RISK_BASE
  {
   RISK_ON_BALANCE = 0,  // Rischio calcolato sul Balance
   RISK_ON_EQUITY  = 1   // Rischio calcolato sull'Equity
  };

enum ENUM_PIP_MODE
  {
   PIP_AUTO   = 0,  // Automatico in base al simbolo
   PIP_POINT  = 1,  // 1 pip = 1 Point
   PIP_CUSTOM = 2   // Valore definito in CustomPipSize
  };

enum ENUM_PANEL_CORNER
  {
   PANEL_TOP_LEFT  = 0,  // Angolo alto a sinistra
   PANEL_TOP_RIGHT = 1   // Angolo alto a destra
  };

enum ENUM_AGGRESSION
  {
   AGGR_CUSTOM       = 0,  // Nessun profilo: usa i parametri come impostati
   AGGR_CONSERVATIVE = 1,  // Conservativo: meno operazioni, filtri stretti
   AGGR_STANDARD     = 2,  // Standard: parametri come impostati, sessioni piene
   AGGR_AGGRESSIVE   = 3,  // Aggressivo: piu' operazioni, filtri larghi, rischio maggiore
   AGGR_EXTREME      = 4   // Molto aggressivo: massima frequenza, drawdown elevato
  };

//+------------------------------------------------------------------+
//| INPUT: Timeframe e profilo operativo                             |
//+------------------------------------------------------------------+
input string          s_tf                 = "===== TIMEFRAME E PROFILO =====";
input ENUM_TIMEFRAMES EntryTimeframe       = PERIOD_M1;   // Timeframe di ingresso (M1 o M5)
input ENUM_TIMEFRAMES TrendTimeframe       = PERIOD_M15;  // Timeframe che detta la direzione
input bool            AutoAdaptToTimeframe = true;        // Riscala i parametri secondo il timeframe scelto
input ENUM_AGGRESSION AggressionProfile    = AGGR_AGGRESSIVE; // Profilo di aggressivita'
input bool            TradeOnNewBarOnly    = true;        // Valuta i segnali solo alla chiusura della barra

//+------------------------------------------------------------------+
//| INPUT: Rischio                                                   |
//+------------------------------------------------------------------+
input string          s_risk               = "===== RISCHIO =====";
input double          RiskPercent          = 0.5;    // Rischio % del capitale per operazione
input ENUM_RISK_BASE  RiskBase             = RISK_ON_BALANCE; // Base di calcolo del rischio
input double          FixedLots            = 0.0;    // Lotto fisso (0 = calcolo automatico)
input double          MaxLotCap            = 5.0;    // Tetto massimo di lotti per operazione
input double          CommissionPerLot     = 0.0;    // Commissione round-turn per lotto (valuta conto)
input int             MagicNumber          = 20260815; // Magic Number (identificativo EA)
input string          TradeComment         = "GoldScalperM1"; // Commento ordini

//+------------------------------------------------------------------+
//| INPUT: Protezioni giornaliere                                    |
//+------------------------------------------------------------------+
input string          s_guard              = "===== PROTEZIONI =====";
input int             MaxTradesPerDay      = 15;     // Massimo trade al giorno (0 = illimitato)
input int             MaxTradesPerHour     = 4;      // Massimo trade nell'ora corrente (0 = illimitato)
input double          MaxDailyLossPercent  = 2.5;    // Stop giornaliero in % del saldo (0 = off)
input double          DailyProfitTargetPct = 3.0;    // Target giornaliero in % del saldo (0 = off)
input bool            IncludeFloatingInDD  = true;   // Includi il flottante nei limiti giornalieri
input int             MaxConsecutiveLosses = 3;      // Perdite consecutive prima della pausa (0 = off)
input int             CooldownMinutes      = 30;     // Durata della pausa dopo le perdite consecutive
input int             CooldownBars         = 3;      // Barre M1 di attesa dopo l'ultimo trade

//+------------------------------------------------------------------+
//| INPUT: Direzione (letta su TrendTimeframe)                       |
//+------------------------------------------------------------------+
input string          s_bias               = "===== DIREZIONE (M15) =====";
input int             BiasFastPeriod       = 21;     // EMA veloce del timeframe direzionale
input int             BiasSlowPeriod       = 50;     // EMA lenta del timeframe direzionale
input int             BiasSlopeBars        = 3;      // Barre su cui misurare la pendenza della EMA lenta
input bool            UseADXFilter         = true;   // Richiedi un minimo di direzionalita' (ADX)
input int             ADX_Period           = 14;     // Periodo ADX sul timeframe direzionale
input double          ADX_Min              = 18.0;   // ADX minimo per considerare valida la direzione

//+------------------------------------------------------------------+
//| INPUT: Ingresso su M1                                            |
//+------------------------------------------------------------------+
input string          s_entry              = "===== INGRESSO (M1) =====";
input int             FastEMA              = 8;      // EMA veloce M1 (riferimento del pullback)
input int             SlowEMA              = 21;     // EMA lenta M1 (allineamento)
input int             PullbackBars         = 3;      // Barre entro cui deve essere avvenuto il pullback
input int             RSI_Period           = 7;      // Periodo RSI su M1
input double          RSI_Mid              = 50.0;   // Soglia centrale RSI (momentum)
input double          RSI_MaxEntry         = 80.0;   // RSI oltre il quale non si compra (estensione)
input double          MinBodyATR           = 0.15;   // Corpo minimo della barra di innesco (in ATR)
input bool            RequireBreakout      = true;   // Richiedi la rottura del massimo/minimo precedente

//+------------------------------------------------------------------+
//| INPUT: Volatilita' e anti-spike                                  |
//+------------------------------------------------------------------+
//| Il filtro principale e' RELATIVO: confronta l'ATR corrente con la |
//| sua media recente. Una soglia assoluta in pips presuppone di      |
//| sapere quanto vale l'ATR "normale", che invece cambia con il      |
//| livello del prezzo dell'oro, con il broker e con il periodo:      |
//| lasciata fissa, blocca l'operativita' per giorni interi.          |
//| Le soglie assolute restano disponibili come rete di sicurezza,    |
//| ma sono disattivate (0) di default.                               |
input string          s_vol                = "===== VOLATILITA' =====";
input int             ATR_Period           = 14;     // Periodo ATR sul timeframe di ingresso
input int             ATR_AvgPeriod        = 100;    // Barre su cui misurare l'ATR abituale
input double          MinATRRatio          = 0.55;   // ATR/media minimo (sotto: mercato morto)
input double          MaxATRRatio          = 2.50;   // ATR/media massimo (sopra: volatilita' anomala)
input double          MinATRPips           = 0.0;    // Limite assoluto minimo in pips (0 = disattivo)
input double          MaxATRPips           = 0.0;    // Limite assoluto massimo in pips (0 = disattivo)
input double          SpikeATRFactor       = 3.0;    // Range barra oltre N*ATR = spike, nessun ingresso

//+------------------------------------------------------------------+
//| INPUT: Stop, target e vincoli del broker                         |
//+------------------------------------------------------------------+
input string          s_stop               = "===== STOP E TARGET =====";
input double          SL_ATR               = 1.20;   // Stop Loss in multipli di ATR
input double          MinSLPips            = 8.0;    // Stop Loss minimo in pips
input double          RewardRatio          = 1.50;   // Take Profit = SL * questo rapporto
input double          StopBufferPips       = 1.0;    // Margine oltre lo STOPLEVEL del broker (pips)
input double          MaxStopLevelATR      = 1.00;   // STOPLEVEL max ammesso come frazione di ATR
input double          MaxStopWideningFactor= 1.60;   // Allargamento massimo dello SL rispetto al teorico
input double          MinTPCostRatio       = 2.50;   // Il TP deve valere N volte spread + commissioni
input double          MinRiskReward        = 1.20;   // R:R minimo accettato dopo gli aggiustamenti

//+------------------------------------------------------------------+
//| INPUT: Gestione della posizione                                  |
//+------------------------------------------------------------------+
input string          s_manage             = "===== GESTIONE =====";
input bool            UsePartialClose      = true;   // Chiusura parziale al raggiungimento di N R
input double          PartialAtR           = 1.00;   // R al quale scatta la parziale
input double          PartialPercent       = 50.0;   // Percentuale del volume chiusa in parziale
input bool            EnableBreakEven      = true;   // Attiva il break-even
input double          BreakEvenR           = 0.70;   // R al quale portare lo stop a pareggio
input double          BreakEvenLockPips    = 1.0;    // Pips bloccati oltre il prezzo di ingresso
input bool            EnableTrailingStop   = true;   // Attiva il trailing stop
input double          TrailStartR          = 1.00;   // R dal quale parte il trailing
input double          TrailATR             = 1.00;   // Distanza del trailing in ATR
input double          TrailStepPips        = 1.0;    // Passo minimo del trailing (pips)
input int             MaxTradeMinutes      = 45;     // Uscita a tempo (0 = off)
input bool            TimeExitOnlyIfProfit = false;  // Uscita a tempo solo se la posizione e' in utile
input int             MaxOpenPositions     = 1;      // Posizioni contemporanee dell'EA

//+------------------------------------------------------------------+
//| INPUT: Sessione (ora del server)                                 |
//+------------------------------------------------------------------+
input string          s_session            = "===== SESSIONE =====";
input bool            UseSessionFilter     = true;   // Opera solo nelle finestre indicate
input bool            UseSession1          = true;   // Finestra 1 (Londra)
input int             Session1StartHour    = 8;      // Finestra 1: ora di inizio
input int             Session1StartMin     = 0;      // Finestra 1: minuto di inizio
input int             Session1EndHour      = 11;     // Finestra 1: ora di fine
input int             Session1EndMin       = 30;     // Finestra 1: minuto di fine
input bool            UseSession2          = true;   // Finestra 2 (New York)
input int             Session2StartHour    = 14;     // Finestra 2: ora di inizio
input int             Session2StartMin     = 30;     // Finestra 2: minuto di inizio
input int             Session2EndHour      = 17;     // Finestra 2: ora di fine
input int             Session2EndMin       = 30;     // Finestra 2: minuto di fine
input int             RolloverBufferMin    = 15;     // Minuti bloccati attorno alla mezzanotte server
input int             FridayCloseHour      = 19;     // Venerdi': stop nuovi ingressi da quest'ora (0 = off)
input bool            CloseAllOnFriday     = true;   // Chiudi le posizioni al FridayCloseHour

//+------------------------------------------------------------------+
//| INPUT: Esecuzione                                                |
//+------------------------------------------------------------------+
input string          s_exec               = "===== ESECUZIONE =====";
input ENUM_PIP_MODE   PipMode              = PIP_AUTO; // Definizione del pip
input double          CustomPipSize        = 0.10;   // Pip personalizzato (se PipMode = PIP_CUSTOM)
input double          MaxSpreadPips        = 6.0;    // Spread massimo assoluto in pips (0 = nessun filtro)
input double          MaxSpreadToATR       = 0.25;   // Spread massimo come frazione di ATR (0 = off)
input double          SlippagePips         = 2.0;    // Slippage tollerato (pips)
input int             MaxRetries           = 3;      // Tentativi di invio ordine
input int             RetryDelayMs         = 300;    // Attesa (ms) tra i tentativi
input bool            TwoStepStops         = false;  // Broker ECN: apri e poi imposta SL/TP
input bool            VerboseLog           = true;   // Log dettagliato nel journal
input bool            LogRejections        = true;   // Registra nel journal i trade scartati

//+------------------------------------------------------------------+
//| INPUT: Dashboard                                                 |
//+------------------------------------------------------------------+
input string          s_panel              = "===== DASHBOARD =====";
input bool            ShowPanel            = true;   // Mostra la dashboard sul grafico
input ENUM_PANEL_CORNER PanelCorner        = PANEL_TOP_LEFT; // Angolo di ancoraggio
input int             PanelX               = 12;     // Distanza orizzontale dal bordo (px)
input int             PanelY               = 18;     // Distanza dal bordo superiore (px)
input int             PanelWidth           = 330;    // Larghezza del pannello (px)
input string          PanelFont            = "Tahoma"; // Font del pannello
input int             PanelFontSize        = 8;      // Dimensione del font
input bool            ShowPanelButtons     = true;   // Mostra i pulsanti operativi
input color           PanelBgColor         = C'16,18,22';    // Sfondo del pannello
input color           PanelBorderColor     = C'52,58,68';    // Bordo del pannello
input color           PanelHeaderColor     = C'26,30,38';    // Sfondo di intestazioni e riquadri
input color           PanelTitleColor      = clrWhite;       // Colore del titolo
input color           PanelAccentColor     = C'240,185,60';  // Colore accento (oro)
input color           PanelCaptionColor    = C'132,140,152'; // Colore delle etichette
input color           PanelValueColor      = C'232,236,242'; // Colore dei valori
input color           PanelPositiveColor   = C'0,205,125';   // Colore dei valori positivi
input color           PanelNegativeColor   = C'240,80,90';   // Colore dei valori negativi
input color           PanelWarningColor    = C'245,170,60';  // Colore dei valori di attenzione

//+------------------------------------------------------------------+
//| Variabili globali                                                |
//+------------------------------------------------------------------+
//--- Profilo del simbolo
double   g_pip            = 0.0;    // Valore di 1 pip in prezzo
double   g_pointsPerPip   = 1.0;    // Points contenuti in 1 pip
int      g_slippagePoints = 0;      // Slippage convertito in points
bool     g_isGold         = false;  // Il simbolo del grafico e' oro

//--- Parametri di volume
int      g_lotDigits      = 2;
double   g_lotStep        = 0.01;
double   g_minLot         = 0.01;
double   g_maxLot         = 100.0;

//--- Timeframe risolti
int      g_entryTF        = 0;
int      g_trendTF        = 0;

//--- PARAMETRI EFFETTIVI
//    Gli input non sono modificabili in MQL4: il profilo di aggressivita' e
//    l'adattamento al timeframe scrivono qui i valori realmente usati, e la
//    dashboard mostra questi, non gli input. Cosi' cio' che si legge sul
//    grafico e' sempre cio' che l'EA sta applicando davvero.
double   g_adxMin         = 0.0;
double   g_minBody        = 0.0;
int      g_pullbackBars   = 0;
double   g_rsiMaxEntry    = 0.0;
bool     g_requireBreak   = true;
bool     g_requireSlope   = true;
int      g_maxTradesDay   = 0;
int      g_maxTradesHour  = 0;
int      g_cooldownBars   = 0;
int      g_maxConsecLoss  = 0;
double   g_minTPCost      = 0.0;
double   g_minRR          = 0.0;
double   g_maxSpreadATR   = 0.0;
double   g_riskPercent    = 0.0;
double   g_minATRRatio    = 0.0;
double   g_maxATRRatio    = 0.0;
double   g_spikeFactor    = 0.0;
double   g_minATRPips     = 0.0;
double   g_maxATRPips     = 0.0;
double   g_minSLPips      = 0.0;
double   g_maxSpreadPips  = 0.0;
double   g_beLockPips     = 0.0;
double   g_trailStepPips  = 0.0;
int      g_maxTradeMin    = 0;
int      g_s1Start        = 0;      // Finestre di sessione in minuti dalla mezzanotte
int      g_s1End          = 0;
int      g_s2Start        = 0;
int      g_s2End          = 0;
string   g_profileName    = "";
string   g_adaptNote      = "";

//--- Stato operativo
datetime g_lastBarTime    = 0;
datetime g_lastTradeTime  = 0;
bool     g_initOk         = false;
bool     g_paused         = false;  // Pausa manuale dal pulsante della dashboard
string   g_lastReject     = "-";    // Ultimo motivo di scarto

//--- Stato giornaliero
datetime g_dayStamp       = 0;      // Inizio della giornata corrente (server time)
datetime g_hourStamp      = 0;      // Inizio dell'ora corrente (server time)
double   g_dayStartBalance= 0.0;    // Saldo all'inizio della giornata
bool     g_dailyBlocked   = false;  // Operativita' sospesa fino a domani
string   g_dailyBlockNote = "";     // Motivo del blocco giornaliero

//--- Pausa dopo perdite consecutive
int      g_consecLosses   = 0;
datetime g_cooldownUntil  = 0;
datetime g_lastLossHandled= 0;

//--- Statistiche (cache)
double   g_peakEquity     = 0.0;
double   g_statNetProfit  = 0.0;
double   g_statGrossWin   = 0.0;
double   g_statGrossLoss  = 0.0;
double   g_statTodayProfit= 0.0;
int      g_statTrades     = 0;
int      g_statWins       = 0;
int      g_tradesToday    = 0;
int      g_tradesThisHour = 0;

//--- Registro delle posizioni aperte dall'EA.
//    La chiave e' l'ora di apertura: sopravvive alla chiusura parziale,
//    che in MT4 assegna un nuovo ticket alla parte residua.
datetime g_regTime[];
double   g_regRisk[];               // Distanza di rischio iniziale (1R in prezzo)
bool     g_regPartial[];            // Parziale gia' eseguita

//--- Dashboard
string   g_prefix         = "";
int      g_rowH           = 16;
int      g_pad            = 10;
int      g_corner         = CORNER_LEFT_UPPER;
bool     g_collapsed      = false;
int      g_panelHeight    = 0;
datetime g_panelRefresh   = 0;      // Ultimo aggiornamento del pannello (1 al secondo)

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_initOk = false;

   g_entryTF = (EntryTimeframe == PERIOD_CURRENT) ? Period() : (int)EntryTimeframe;
   g_trendTF = (TrendTimeframe == PERIOD_CURRENT) ? Period() : (int)TrendTimeframe;

   DetectSymbolProfile();

   //--- Profilo di aggressivita' e adattamento al timeframe: da qui in poi
   //    l'EA lavora sui valori effettivi, non sugli input grezzi.
   ApplyProfileAndTimeframe();

   g_lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   g_minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   g_maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   if(g_lotStep <= 0.0) g_lotStep = 0.01;
   if(g_minLot  <= 0.0) g_minLot  = g_lotStep;
   if(g_maxLot  <= 0.0) g_maxLot  = 100.0;
   g_lotDigits = VolumeDigits(g_lotStep);

   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   g_lastBarTime = iTime(Symbol(), g_entryTF, 0);

   ResetDailyState(true);
   RebuildRegistry();

   g_prefix     = "GSM1_" + IntegerToString(MagicNumber) + "_";
   g_rowH       = PanelFontSize + 9;
   g_corner     = (PanelCorner == PANEL_TOP_RIGHT) ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER;
   g_peakEquity = AccountEquity();

   Comment("");
   if(ShowPanel)
     {
      EventSetTimer(1);
      UpdatePanel();
     }

   g_initOk = true;

   Print("[", TradeComment, "] Init OK | ", Symbol(),
         (g_isGold ? " (oro)" : " (simbolo non oro: parametri da rivedere)"),
         " Digits=", Digits,
         " Point=", DoubleToString(Point, 8),
         " Pip=", DoubleToString(g_pip, Digits),
         " | Ingresso=", TimeframeToString(g_entryTF),
         " Direzione=", TimeframeToString(g_trendTF),
         " | StopLevel=", DoubleToString(MarketInfo(Symbol(), MODE_STOPLEVEL), 0), " points",
         " (", DoubleToString(MarketInfo(Symbol(), MODE_STOPLEVEL) * Point / g_pip, 1), " pips)",
         " | Spread=", DoubleToString(MathMax(Ask - Bid, 0.0) / g_pip, 1), " pips",
         " | Lotti: step=", DoubleToString(g_lotStep, g_lotDigits),
         " min=", DoubleToString(g_minLot, g_lotDigits),
         " max=", DoubleToString(g_maxLot, g_lotDigits),
         " | Magic=", MagicNumber);

   if(CommissionPerLot <= 0.0)
      Print("[", TradeComment, "] NOTA: CommissionPerLot = 0. Su timeframe rapidi la commissione incide ",
            "sul risultato piu' della strategia: impostala con il valore reale round-turn del tuo conto.");

   LogVolatilityDiagnostic();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| DIAGNOSTICA DELLA VOLATILITA' ALL'AVVIO                          |
//| Misura subito i valori reali del simbolo e avvisa se una soglia  |
//| impostata a mano sta per bloccare ogni ingresso: un EA che non   |
//| apre mai deve dirlo all'avvio, non lasciarlo dedurre dal journal.|
//+------------------------------------------------------------------+
void LogVolatilityDiagnostic()
  {
   double atr = iATR(Symbol(), g_entryTF, ATR_Period, 1);
   double avg = GetAverageATR(g_entryTF, ATR_AvgPeriod, 1);

   if(atr <= 0.0 || avg <= 0.0)
     {
      Print("[", TradeComment, "] Diagnostica volatilita' rinviata: storico ",
            TimeframeToString(g_entryTF), " ancora insufficiente. ",
            "Scorri il grafico indietro per far scaricare le barre.");
      return;
     }

   double atrPips = atr / g_pip;
   double avgPips = avg / g_pip;
   double ratio   = atr / avg;
   double spread  = MathMax(Ask - Bid, 0.0) / g_pip;

   Print("[", TradeComment, "] Diagnostica volatilita': ATR ", DoubleToString(atrPips, 1),
         " pips, media a ", ATR_AvgPeriod, " barre ", DoubleToString(avgPips, 1),
         " pips, rapporto ", DoubleToString(ratio, 2), "x",
         " | banda ammessa ", DoubleToString(g_minATRRatio, 2), "-", DoubleToString(g_maxATRRatio, 2), "x",
         " | spread ", DoubleToString(spread, 1), " pips");

   //--- Le soglie assolute sono la causa piu' comune di un EA che non apre mai
   if(g_maxATRPips > 0.0 && atrPips > g_maxATRPips)
      Print("[", TradeComment, "] ATTENZIONE: MaxATRPips = ", DoubleToString(g_maxATRPips, 1),
            " ma l'ATR corrente e' ", DoubleToString(atrPips, 1),
            " pips. Con questa impostazione NON verra' aperta alcuna posizione. ",
            "Portalo a 0 per lasciare decidere il filtro relativo.");

   if(g_minATRPips > 0.0 && atrPips < g_minATRPips)
      Print("[", TradeComment, "] ATTENZIONE: MinATRPips = ", DoubleToString(g_minATRPips, 1),
            " ma l'ATR corrente e' ", DoubleToString(atrPips, 1),
            " pips. Con questa impostazione NON verra' aperta alcuna posizione.");

   if(g_maxSpreadPips > 0.0 && spread > g_maxSpreadPips)
      Print("[", TradeComment, "] ATTENZIONE: spread corrente ", DoubleToString(spread, 1),
            " pips oltre il massimo ", DoubleToString(g_maxSpreadPips, 1),
            ". Se resta cosi' non verra' aperta alcuna posizione: verifica il limite ",
            "o valuta se questo broker sia adatto allo scalping su questo simbolo.");
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Print("[", TradeComment, "] Deinit, motivo=", reason, " (", DeinitReasonText(reason), ")");
   DeletePanel();
   Comment("");
  }

//+------------------------------------------------------------------+
//| OnTimer - la dashboard resta viva anche senza tick               |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_initOk)
      return;

   if(ShowPanel && (!IsTesting() || IsVisualMode()))
      UpdatePanel();
  }

//+------------------------------------------------------------------+
//| OnTick - ciclo principale                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_initOk)
      return;

   //--- 1) Gestione delle posizioni aperte: su ogni tick, sempre
   ManageOpenPositions();

   //--- 2) Stato giornaliero e statistiche
   ResetDailyState(false);

   if(AccountEquity() > g_peakEquity)
      g_peakEquity = AccountEquity();

   //--- 3) Chiusura di fine settimana
   if(CloseAllOnFriday && FridayCloseHour > 0 &&
      DayOfWeek() == 5 && TimeHour(TimeCurrent()) >= FridayCloseHour)
      CloseAllOwnPositions("chiusura di fine settimana");

   //--- 4) Dashboard (in backtest solo in modalita' visuale)
   if(ShowPanel && (!IsTesting() || IsVisualMode()))
      UpdatePanel();

   //--- 5) Condizioni generali
   if(g_paused)
      return;

   if(!IsTradeAllowed() || IsTradeContextBusy())
      return;

   if(!HasEnoughBars())
      return;

   //--- 6) Un solo tentativo per barra M1
   datetime barTime = iTime(Symbol(), g_entryTF, 0);
   if(TradeOnNewBarOnly)
     {
      if(barTime == g_lastBarTime)
         return;
      g_lastBarTime = barTime;
     }

   //--- 7) Filtri, dal piu' economico al piu' costoso
   if(CountOwnPositions() >= MaxOpenPositions)
      return;

   if(g_dailyBlocked)
      return;

   if(!AreTradeCountsOk(false))
      return;

   if(IsInCooldown(false))
      return;

   if(!IsSessionAllowed(false))
      return;

   if(!IsSpreadAcceptable(false))
      return;

   if(!IsVolatilityAcceptable(false))
      return;

   //--- 8) Direzione dal timeframe superiore, poi innesco su M1
   string info = "";
   int bias = GetBias(info, false);
   if(bias == 0)
      return;

   int signal = GetScalpSignal(bias, info, false);
   if(signal == 0)
      return;

   //--- 9) Esecuzione
   OpenPosition(signal > 0 ? OP_BUY : OP_SELL);
  }

//+------------------------------------------------------------------+
//| OnChartEvent - pulsanti della dashboard                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK || StringLen(g_prefix) == 0)
      return;

   if(sparam == g_prefix + "h_btn_pause")
     {
      g_paused = !g_paused;
      Print("[", TradeComment, "] ", (g_paused ? "PAUSA attivata dal pannello: nessun nuovo ingresso."
                                              : "Operativita' ripresa dal pannello."));
     }
   else
      if(sparam == g_prefix + "h_btn_close")
        {
         CloseAllOwnPositions("chiusura manuale dal pannello");
        }
      else
         if(sparam == g_prefix + "h_btn_min")
           {
            g_collapsed = !g_collapsed;
            DeletePanelBody();
           }
         else
            return;

   //--- Il pulsante non deve restare premuto e il pannello deve rispondere subito
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   g_panelRefresh = 0;
   UpdatePanel();
  }

//+------------------------------------------------------------------+
//| PROFILO DEL SIMBOLO                                              |
//+------------------------------------------------------------------+
void DetectSymbolProfile()
  {
   string sym = Symbol();
   StringToUpper(sym);

   g_isGold = (StringFind(sym, "XAU", 0) >= 0 || StringFind(sym, "GOLD", 0) >= 0);

   switch(PipMode)
     {
      case PIP_POINT:
         g_pip = Point;
         break;

      case PIP_CUSTOM:
         g_pip = (CustomPipSize > 0.0 ? CustomPipSize : Point);
         break;

      default: // PIP_AUTO
         if(g_isGold)
            g_pip = 0.10;                                     // 1 pip oro = 0.10 USD (10 cent)
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
//| PROFILO OPERATIVO E ADATTAMENTO AL TIMEFRAME                     |
//|                                                                  |
//| Due trasformazioni distinte sugli stessi parametri:              |
//|                                                                  |
//| 1. TIMEFRAME. Passando da M1 a M5 l'ampiezza dei movimenti non    |
//|    cresce di 5 volte ma di circa la radice di 5: le soglie        |
//|    espresse in pips (banda ATR, stop minimo) vengono riscalate    |
//|    con quella legge. Cio' che invece e' misurato in barre non si  |
//|    tocca, mentre l'uscita a tempo segue linearmente la durata     |
//|    della barra. Il timeframe direzionale viene alzato se e'       |
//|    troppo vicino a quello di ingresso, dove sarebbe rumore.       |
//|                                                                  |
//| 2. AGGRESSIVITA'. Il profilo allarga o stringe i filtri di setup  |
//|    e la frequenza. Restano pero' dei PAVIMENTI invalicabili sulla |
//|    copertura dei costi e sul rischio/rendimento: sono cio' che    |
//|    distingue uno scalper da un regalo di spread al broker, e      |
//|    nessun profilo puo' spingerli sotto la soglia di sostenibilita'|
//+------------------------------------------------------------------+
void ApplyProfileAndTimeframe()
  {
   //=== 1) ADATTAMENTO AL TIMEFRAME ==================================
   double volScale = 1.0;   // Le escursioni crescono con la radice del tempo
   double barScale = 1.0;   // La durata cresce linearmente

   g_adaptNote = "nessun adattamento";

   if(AutoAdaptToTimeframe && g_entryTF > 1)
     {
      volScale = MathSqrt((double)g_entryTF);
      barScale = (double)g_entryTF;
      g_adaptNote = StringFormat("da M1 a %s: soglie in pips x%.2f, tempi x%.0f",
                                 TimeframeToString(g_entryTF), volScale, barScale);
     }

   g_minATRPips    = MinATRPips        * volScale;
   g_maxATRPips    = MaxATRPips        * volScale;
   g_minSLPips     = MinSLPips         * volScale;
   g_beLockPips    = BreakEvenLockPips * volScale;
   g_trailStepPips = TrailStepPips     * volScale;
   g_maxTradeMin   = (int)MathRound(MaxTradeMinutes * barScale);

   //--- Timeframe direzionale: deve stare molto sopra quello di ingresso.
   //    Se l'utente lo ha gia' messo abbastanza in alto, la sua scelta resta.
   if(AutoAdaptToTimeframe && g_trendTF < g_entryTF * 5)
     {
      int ladder[6] = {PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
      int wanted    = g_entryTF * 10;
      int picked    = PERIOD_D1;

      for(int i = 0; i < 6; i++)
         if(ladder[i] >= wanted)
           {
            picked = ladder[i];
            break;
           }

      if(picked != g_trendTF)
        {
         Print("[", TradeComment, "] Timeframe direzionale portato da ", TimeframeToString(g_trendTF),
               " a ", TimeframeToString(picked), ": su ", TimeframeToString(g_entryTF),
               " un contesto troppo vicino sarebbe rumore.");
         g_trendTF = picked;
        }
     }

   //=== 2) PROFILO DI AGGRESSIVITA' ==================================
   double mBody = 1.0, mADX = 1.0, mTPCost = 1.0, mRR = 1.0;
   double mSprATR = 1.0, mRisk = 1.0, mTrades = 1.0, mCool = 1.0;
   double mVolBand = 1.0, mSpike = 1.0;
   int    addPullback = 0, addRSI = 0, addLoss = 0, padSession = 0;
   int    forceBreak  = -1;   // -1 = lascia l'input, 0 = disattiva, 1 = attiva
   bool   wantSlope   = true;

   switch(AggressionProfile)
     {
      case AGGR_CONSERVATIVE:
         g_profileName = "CONSERVATIVO";
         mBody = 1.40; mADX = 1.30; mTPCost = 1.20; mRR = 1.10;
         mSprATR = 0.80; mRisk = 0.70; mTrades = 0.60; mCool = 1.50;
         mVolBand = 0.80; mSpike = 0.85;
         addRSI = -5; addLoss = -1; padSession = -15; forceBreak = 1;
         break;

      case AGGR_STANDARD:
         g_profileName = "STANDARD";
         break;

      case AGGR_AGGRESSIVE:
         g_profileName = "AGGRESSIVO";
         mBody = 0.50; mADX = 0.60; mTPCost = 0.80; mRR = 0.90;
         mSprATR = 1.25; mRisk = 1.50; mTrades = 2.00; mCool = 0.35;
         mVolBand = 1.40; mSpike = 1.25;
         addPullback = 2; addRSI = 8; addLoss = 1; padSession = 45;
         forceBreak = 0; wantSlope = false;
         break;

      case AGGR_EXTREME:
         g_profileName = "MOLTO AGGRESSIVO";
         mBody = 0.25; mADX = 0.30; mTPCost = 0.60; mRR = 0.80;
         mSprATR = 1.50; mRisk = 2.00; mTrades = 3.00; mCool = 0.00;
         mVolBand = 1.90; mSpike = 1.50;
         addPullback = 3; addRSI = 12; addLoss = 2; padSession = 120;
         forceBreak = 0; wantSlope = false;
         break;

      default: // AGGR_CUSTOM
         g_profileName = "PERSONALIZZATO";
         break;
     }

   //--- Banda di volatilita' relativa: il profilo la allarga simmetricamente
   //    attorno a 1.0, che e' la volatilita' abituale dello strumento.
   g_minATRRatio = MathMax(MinATRRatio / mVolBand, 0.05);
   g_maxATRRatio = MaxATRRatio * mVolBand;
   g_spikeFactor = (SpikeATRFactor > 0.0 ? SpikeATRFactor * mSpike : 0.0);

   //--- Filtri di setup
   g_minBody      = MinBodyATR * mBody;
   g_adxMin       = ADX_Min    * mADX;
   g_pullbackBars = PullbackBars + addPullback;
   g_rsiMaxEntry  = MathMin(RSI_MaxEntry + addRSI, 95.0);
   g_requireBreak = (forceBreak < 0 ? RequireBreakout : (forceBreak == 1));
   g_requireSlope = wantSlope;

   if(g_rsiMaxEntry <= RSI_Mid + 5.0)
      g_rsiMaxEntry = RSI_Mid + 5.0;

   //--- Frequenza
   g_maxTradesDay  = (MaxTradesPerDay  > 0 ? (int)MathMax(1, MathRound(MaxTradesPerDay  * mTrades)) : 0);
   g_maxTradesHour = (MaxTradesPerHour > 0 ? (int)MathMax(1, MathRound(MaxTradesPerHour * mTrades)) : 0);
   g_cooldownBars  = (int)MathMax(0, MathRound(CooldownBars * mCool));
   g_maxConsecLoss = (int)MathMax(0, MaxConsecutiveLosses + addLoss);

   //--- Rischio e costi, con i pavimenti che nessun profilo puo' superare
   g_riskPercent  = MathMin(RiskPercent * mRisk, 10.0);
   g_maxSpreadPips= (MaxSpreadPips > 0.0 ? MaxSpreadPips * mSprATR : 0.0);
   g_minTPCost    = MathMax(MinTPCostRatio * mTPCost, 1.20);
   g_minRR        = MathMax(MinRiskReward  * mRR,     1.00);
   g_maxSpreadATR = (MaxSpreadToATR > 0.0 ? MathMin(MaxSpreadToATR * mSprATR, 0.60) : 0.0);

   //--- Sessioni: il profilo le allarga o le stringe ai bordi
   g_s1Start = ClampMinute(Session1StartHour * 60 + Session1StartMin - padSession);
   g_s1End   = ClampMinute(Session1EndHour   * 60 + Session1EndMin   + padSession);
   g_s2Start = ClampMinute(Session2StartHour * 60 + Session2StartMin - padSession);
   g_s2End   = ClampMinute(Session2EndHour   * 60 + Session2EndMin   + padSession);

   //--- Una finestra ridotta a nulla dal profilo conservativo torna al valore base
   if(g_s1End <= g_s1Start)
     {
      g_s1Start = Session1StartHour * 60 + Session1StartMin;
      g_s1End   = Session1EndHour   * 60 + Session1EndMin;
     }
   if(g_s2End <= g_s2Start)
     {
      g_s2Start = Session2StartHour * 60 + Session2StartMin;
      g_s2End   = Session2EndHour   * 60 + Session2EndMin;
     }

   Print("[", TradeComment, "] Profilo ", g_profileName, " | ", g_adaptNote,
         " | Rischio ", DoubleToString(g_riskPercent, 2), "%",
         " | Trade max ", g_maxTradesDay, "/giorno ", g_maxTradesHour, "/ora",
         " | Banda ATR ", DoubleToString(g_minATRRatio, 2), "-", DoubleToString(g_maxATRRatio, 2),
         " volte la media a ", ATR_AvgPeriod, " barre",
         " | SL min ", DoubleToString(g_minSLPips, 1), " pips",
         " | TP/costi x", DoubleToString(g_minTPCost, 2),
         " | R:R min ", DoubleToString(g_minRR, 2),
         " | Uscita a tempo ", g_maxTradeMin, " min",
         " | Sessioni ", MinuteToHM(g_s1Start), "-", MinuteToHM(g_s1End),
         " e ", MinuteToHM(g_s2Start), "-", MinuteToHM(g_s2End));

   if(AggressionProfile == AGGR_EXTREME)
      Print("[", TradeComment, "] ATTENZIONE: profilo MOLTO AGGRESSIVO. Frequenza e drawdown ",
            "crescono insieme, e il rischio per operazione e' il doppio di quello impostato. ",
            "Usalo solo dopo averlo verificato in backtest e in demo.");
  }

//+------------------------------------------------------------------+
//| Minuto del giorno riportato dentro l'intervallo valido           |
//+------------------------------------------------------------------+
int ClampMinute(int minute)
  {
   if(minute < 0)     return(0);
   if(minute > 1439)  return(1439);
   return(minute);
  }

//+------------------------------------------------------------------+
//| Minuto del giorno in formato hh:mm                               |
//+------------------------------------------------------------------+
string MinuteToHM(int minute)
  {
   return(StringFormat("%02d:%02d", minute / 60, minute % 60));
  }

//+------------------------------------------------------------------+
//| Validazione degli input                                          |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   bool ok = true;

   if(RiskPercent <= 0.0 && FixedLots <= 0.0)
     { Print("ERRORE INPUT: impostare RiskPercent > 0 oppure FixedLots > 0."); ok = false; }

   if(RiskPercent > 10.0)
     { Print("ERRORE INPUT: RiskPercent troppo elevato per uno scalper (max consigliato 10%)."); ok = false; }

   if(ATR_Period < 1 || RSI_Period < 2)
     { Print("ERRORE INPUT: ATR_Period >= 1 e RSI_Period >= 2."); ok = false; }

   if(FastEMA < 1 || SlowEMA < 1 || FastEMA >= SlowEMA)
     { Print("ERRORE INPUT: FastEMA deve essere >= 1 e minore di SlowEMA."); ok = false; }

   if(BiasFastPeriod < 1 || BiasSlowPeriod < 1 || BiasFastPeriod >= BiasSlowPeriod)
     { Print("ERRORE INPUT: BiasFastPeriod deve essere >= 1 e minore di BiasSlowPeriod."); ok = false; }

   if(BiasSlopeBars < 1)
     { Print("ERRORE INPUT: BiasSlopeBars deve essere >= 1."); ok = false; }

   if(PullbackBars < 1)
     { Print("ERRORE INPUT: PullbackBars deve essere >= 1."); ok = false; }

   if(SL_ATR <= 0.0 || RewardRatio <= 0.0)
     { Print("ERRORE INPUT: SL_ATR e RewardRatio devono essere > 0."); ok = false; }

   if(MinATRPips > 0.0 && MaxATRPips > 0.0 && MinATRPips >= MaxATRPips)
     { Print("ERRORE INPUT: MinATRPips deve essere minore di MaxATRPips."); ok = false; }

   if(ATR_AvgPeriod < 5)
     { Print("ERRORE INPUT: ATR_AvgPeriod deve essere >= 5 per misurare una volatilita' abituale."); ok = false; }

   if(MinATRRatio <= 0.0 || MaxATRRatio <= 0.0 || MinATRRatio >= MaxATRRatio)
     { Print("ERRORE INPUT: banda ATR non valida (0 < MinATRRatio < MaxATRRatio)."); ok = false; }

   if(RSI_Mid <= 0.0 || RSI_Mid >= 100.0 || RSI_MaxEntry <= RSI_Mid || RSI_MaxEntry >= 100.0)
     { Print("ERRORE INPUT: soglie RSI non valide (0 < RSI_Mid < RSI_MaxEntry < 100)."); ok = false; }

   if(MaxOpenPositions < 1)
     { Print("ERRORE INPUT: MaxOpenPositions deve essere >= 1."); ok = false; }

   if(MaxRetries < 1)
     { Print("ERRORE INPUT: MaxRetries deve essere >= 1."); ok = false; }

   if(UsePartialClose && (PartialPercent <= 0.0 || PartialPercent >= 100.0))
     { Print("ERRORE INPUT: PartialPercent deve essere compreso fra 0 e 100 (esclusi)."); ok = false; }

   if(UsePartialClose && PartialAtR <= 0.0)
     { Print("ERRORE INPUT: PartialAtR deve essere > 0."); ok = false; }

   if(EnableBreakEven && BreakEvenR <= 0.0)
     { Print("ERRORE INPUT: BreakEvenR deve essere > 0."); ok = false; }

   if(EnableTrailingStop && (TrailATR <= 0.0 || TrailStartR <= 0.0))
     { Print("ERRORE INPUT: TrailATR e TrailStartR devono essere > 0."); ok = false; }

   if(!ValidHM(Session1StartHour, Session1StartMin) || !ValidHM(Session1EndHour, Session1EndMin) ||
      !ValidHM(Session2StartHour, Session2StartMin) || !ValidHM(Session2EndHour, Session2EndMin))
     { Print("ERRORE INPUT: orari di sessione fuori intervallo (ore 0-23, minuti 0-59)."); ok = false; }

   if(UseSessionFilter && !UseSession1 && !UseSession2)
     { Print("ERRORE INPUT: filtro di sessione attivo ma nessuna finestra abilitata."); ok = false; }

   if(PanelWidth < 240)
     { Print("ERRORE INPUT: PanelWidth minimo 240 px."); ok = false; }

   //--- Avvertimenti (non bloccanti)
   if(MinRiskReward > RewardRatio)
      Print("ATTENZIONE: MinRiskReward (", DoubleToString(MinRiskReward, 2),
            ") e' superiore a RewardRatio (", DoubleToString(RewardRatio, 2),
            "): ogni trade verrebbe scartato.");

   if(UsePartialClose && PartialAtR >= RewardRatio)
      Print("ATTENZIONE: PartialAtR (", DoubleToString(PartialAtR, 2),
            ") non e' inferiore al target (", DoubleToString(RewardRatio, 2),
            "): la parziale non scattera' mai prima del TP.");

   if(g_entryTF > PERIOD_M5 && !AutoAdaptToTimeframe)
      Print("ATTENZIONE: EntryTimeframe = ", TimeframeToString(g_entryTF),
            " con AutoAdaptToTimeframe disattivo. I parametri restano tarati su M1: ",
            "attiva l'adattamento oppure rivedi banda ATR, stop minimo e uscita a tempo.");

   if(g_trendTF < g_entryTF * 3)
      Print("ATTENZIONE: timeframe direzionale ", TimeframeToString(g_trendTF),
            " troppo vicino a quello di ingresso ", TimeframeToString(g_entryTF),
            ": la direzione che ne esce e' rumore, non contesto.");

   if(!g_isGold)
      Print("ATTENZIONE: ", Symbol(), " non sembra un simbolo su oro. ",
            "Verifica PipMode/CustomPipSize e le soglie in pips prima di operare.");

   return(ok);
  }

//+------------------------------------------------------------------+
//| Ora e minuto validi                                              |
//+------------------------------------------------------------------+
bool ValidHM(int hour, int minute)
  {
   return(hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59);
  }

//+------------------------------------------------------------------+
//| Storico sufficiente su entrambi i timeframe                      |
//+------------------------------------------------------------------+
bool HasEnoughBars()
  {
   //--- La media dell'ATR guarda indietro ATR_AvgPeriod barre oltre l'ATR stesso
   int needEntry = (int)MathMax(SlowEMA, MathMax(ATR_Period + ATR_AvgPeriod, RSI_Period)) + g_pullbackBars + 10;
   int needTrend = (int)MathMax(BiasSlowPeriod + BiasSlopeBars, ADX_Period) + 10;

   bool ok = true;
   if(iBars(Symbol(), g_entryTF) < needEntry) ok = false;
   if(iBars(Symbol(), g_trendTF) < needTrend) ok = false;

   if(!ok)
     {
      static datetime lastWarn = 0;
      if(VerboseLog && TimeCurrent() - lastWarn > 300)
        {
         lastWarn = TimeCurrent();
         Print("[", TradeComment, "] Storico insufficiente: ",
               TimeframeToString(g_entryTF), " ", iBars(Symbol(), g_entryTF), "/", needEntry, " barre, ",
               TimeframeToString(g_trendTF), " ", iBars(Symbol(), g_trendTF), "/", needTrend, " barre.");
        }
     }

   return(ok);
  }

//+------------------------------------------------------------------+
//| DIREZIONE                                                        |
//| Su M1 la direzione e' rumore: si legge su TrendTimeframe con      |
//| EMA veloce/lenta, pendenza della lenta e, se richiesto, ADX.      |
//| Restituisce +1 (rialzo), -1 (ribasso), 0 (nessuna direzione).     |
//+------------------------------------------------------------------+
int GetBias(string &info, bool silent)
  {
   info = "";

   double emaFast = iMA(Symbol(), g_trendTF, BiasFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaSlow = iMA(Symbol(), g_trendTF, BiasSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaSlowPrev = iMA(Symbol(), g_trendTF, BiasSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 1 + BiasSlopeBars);
   double close   = iClose(Symbol(), g_trendTF, 1);

   if(emaFast <= 0.0 || emaSlow <= 0.0 || close <= 0.0)
     {
      info = "dati del timeframe direzionale non disponibili";
      return(0);
     }

   //--- ADX: senza un minimo di direzionalita' il pullback su M1 e' solo rumore
   if(UseADXFilter)
     {
      double adx = iADX(Symbol(), g_trendTF, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
      if(adx < g_adxMin)
        {
         info = StringFormat("ADX %s %.1f sotto il minimo %.1f: mercato senza direzione",
                             TimeframeToString(g_trendTF), adx, g_adxMin);
         if(!silent) SetReject(info);
         return(0);
        }
     }

   //--- La pendenza della EMA lenta e' una conferma in piu': i profili
   //    aggressivi la lasciano cadere e si accontentano dell'allineamento,
   //    accettando piu' ingressi in cambio di piu' falsi segnali.
   bool slopeUp   = (!g_requireSlope || emaSlow > emaSlowPrev);
   bool slopeDown = (!g_requireSlope || emaSlow < emaSlowPrev);

   bool upStack   = (emaFast > emaSlow && close > emaFast && slopeUp);
   bool downStack = (emaFast < emaSlow && close < emaFast && slopeDown);

   if(upStack)
     {
      info = "rialzista";
      return(1);
     }

   if(downStack)
     {
      info = "ribassista";
      return(-1);
     }

   info = "EMA " + TimeframeToString(g_trendTF) + " non allineate: nessuna direzione operativa";
   if(!silent) SetReject(info);
   return(0);
  }

//+------------------------------------------------------------------+
//| INNESCO SU M1                                                    |
//| Pullback sulla EMA veloce e ripartenza nella direzione del bias.  |
//| Tutto e' valutato sulla barra 1, cioe' l'ultima chiusa.           |
//+------------------------------------------------------------------+
int GetScalpSignal(int bias, string &info, bool silent)
  {
   info = "";

   if(bias == 0)
      return(0);

   double atr = iATR(Symbol(), g_entryTF, ATR_Period, 1);
   if(atr <= 0.0)
     {
      info = "ATR non disponibile";
      return(0);
     }

   double emaFast = iMA(Symbol(), g_entryTF, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double emaSlow = iMA(Symbol(), g_entryTF, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double rsi     = iRSI(Symbol(), g_entryTF, RSI_Period, PRICE_CLOSE, 1);

   double open1  = iOpen(Symbol(),  g_entryTF, 1);
   double close1 = iClose(Symbol(), g_entryTF, 1);
   double high1  = iHigh(Symbol(),  g_entryTF, 1);
   double low1   = iLow(Symbol(),   g_entryTF, 1);
   double high2  = iHigh(Symbol(),  g_entryTF, 2);
   double low2   = iLow(Symbol(),   g_entryTF, 2);

   //--- Guardia anti-spike: una candela da notizia non e' un setup
   if(g_spikeFactor > 0.0 && (high1 - low1) > atr * g_spikeFactor)
     {
      info = StringFormat("barra anomala %.1f pips (oltre %.1fx ATR): possibile notizia",
                          (high1 - low1) / g_pip, g_spikeFactor);
      if(!silent) SetReject(info);
      return(0);
     }

   //--- Corpo minimo: le indecisioni non innescano
   if(g_minBody > 0.0 && MathAbs(close1 - open1) < atr * g_minBody)
     {
      info = StringFormat("corpo della barra %.1f pips sotto il minimo richiesto %.1f",
                          MathAbs(close1 - open1) / g_pip, atr * g_minBody / g_pip);
      if(!silent) SetReject(info);
      return(0);
     }

   //--- Il pullback deve essere avvenuto entro le ultime PullbackBars barre:
   //    il prezzo e' tornato a toccare la EMA veloce prima di ripartire.
   bool pullback = false;
   for(int k = 1; k <= g_pullbackBars; k++)
     {
      double emaK = iMA(Symbol(), g_entryTF, FastEMA, 0, MODE_EMA, PRICE_CLOSE, k);
      if(bias > 0 && iLow(Symbol(), g_entryTF, k) <= emaK)
        { pullback = true; break; }
      if(bias < 0 && iHigh(Symbol(), g_entryTF, k) >= emaK)
        { pullback = true; break; }
     }

   if(!pullback)
     {
      info = StringFormat("nessun ritracciamento sulla EMA%d nelle ultime %d barre", FastEMA, g_pullbackBars);
      if(!silent) SetReject(info);
      return(0);
     }

   //--- LONG
   if(bias > 0)
     {
      if(emaFast <= emaSlow)
        {
         info = "EMA M1 non allineate al rialzo";
         if(!silent) SetReject(info);
         return(0);
        }
      if(close1 <= emaFast || close1 <= open1)
        {
         info = "la barra di innesco non ha chiuso sopra la EMA veloce";
         if(!silent) SetReject(info);
         return(0);
        }
      if(g_requireBreak && high1 <= high2)
        {
         info = "manca la rottura del massimo precedente";
         if(!silent) SetReject(info);
         return(0);
        }
      if(rsi <= RSI_Mid)
        {
         info = StringFormat("RSI %.1f sotto la soglia di momentum %.1f", rsi, RSI_Mid);
         if(!silent) SetReject(info);
         return(0);
        }
      if(rsi >= g_rsiMaxEntry)
        {
         info = StringFormat("RSI %.1f oltre %.1f: movimento gia' esteso", rsi, g_rsiMaxEntry);
         if(!silent) SetReject(info);
         return(0);
        }

      info = StringFormat("LONG: pullback su EMA%d, rottura, RSI %.1f", FastEMA, rsi);
      return(1);
     }

   //--- SHORT
   if(emaFast >= emaSlow)
     {
      info = "EMA M1 non allineate al ribasso";
      if(!silent) SetReject(info);
      return(0);
     }
   if(close1 >= emaFast || close1 >= open1)
     {
      info = "la barra di innesco non ha chiuso sotto la EMA veloce";
      if(!silent) SetReject(info);
      return(0);
     }
   if(g_requireBreak && low1 >= low2)
     {
      info = "manca la rottura del minimo precedente";
      if(!silent) SetReject(info);
      return(0);
     }
   if(rsi >= 100.0 - RSI_Mid)
     {
      info = StringFormat("RSI %.1f sopra la soglia di momentum %.1f", rsi, 100.0 - RSI_Mid);
      if(!silent) SetReject(info);
      return(0);
     }
   if(rsi <= 100.0 - g_rsiMaxEntry)
     {
      info = StringFormat("RSI %.1f sotto %.1f: movimento gia' esteso", rsi, 100.0 - g_rsiMaxEntry);
      if(!silent) SetReject(info);
      return(0);
     }

   info = StringFormat("SHORT: pullback su EMA%d, rottura, RSI %.1f", FastEMA, rsi);
   return(-1);
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
//| MOTORE DELLE DISTANZE                                            |
//| Costruisce SL e TP dall'ATR e li confronta con i vincoli reali.   |
//| Su M1 e' il filtro decisivo: uno scalp che non copre spread e     |
//| commissioni con margine e' una perdita statistica, non un trade.  |
//+------------------------------------------------------------------+
bool BuildStopDistances(double atr, double &slDistance, double &tpDistance, string &note)
  {
   slDistance = 0.0;
   tpDistance = 0.0;
   note       = "";

   if(atr <= 0.0)
     {
      note = "ATR non disponibile";
      return(false);
     }

   //--- Stop teorico: ATR, con un pavimento in pips per non finire dentro il rumore
   double baseSL   = MathMax(atr * SL_ATR, g_minSLPips * g_pip);
   double minDist  = BrokerMinStopDistance();
   double spread   = MathMax(Ask - Bid, 0.0);
   double commDist = CommissionPriceEquivalent();

   //--- CONTROLLO 1: il vincolo del broker e' compatibile con la volatilita' di M1?
   if(MaxStopLevelATR > 0.0 && minDist > atr * MaxStopLevelATR)
     {
      note = StringFormat("distanza minima broker %.1f pips oltre il %.0f%% dell'ATR (%.1f pips): M1 non sostenibile qui",
                          minDist / g_pip, MaxStopLevelATR * 100.0, atr / g_pip);
      return(false);
     }

   slDistance   = baseSL;
   bool widened = false;
   if(slDistance < minDist)
     {
      slDistance = minDist;
      widened    = true;
     }

   //--- CONTROLLO 2: di quanto il vincolo ha allargato lo stop teorico
   if(widened && MaxStopWideningFactor > 0.0 && slDistance > baseSL * MaxStopWideningFactor)
     {
      note = StringFormat("SL allargato da %.1f a %.1f pips (x%.2f) oltre il limite x%.2f",
                          baseSL / g_pip, slDistance / g_pip, slDistance / baseSL, MaxStopWideningFactor);
      slDistance = 0.0;
      return(false);
     }

   //--- Target proporzionale allo stop effettivo: il rapporto non si degrada
   tpDistance = slDistance * RewardRatio;
   if(tpDistance < minDist)
      tpDistance = minDist;

   //--- CONTROLLO 3: il target copre i costi con margine?
   double cost = spread + commDist;
   if(g_minTPCost > 0.0 && cost > 0.0 && tpDistance < cost * g_minTPCost)
     {
      note = StringFormat("TP %.1f pips insufficiente: costo operazione %.1f pips (x%.1f, richiesto x%.1f)",
                          tpDistance / g_pip, cost / g_pip, tpDistance / cost, g_minTPCost);
      slDistance = 0.0;
      tpDistance = 0.0;
      return(false);
     }

   //--- CONTROLLO 4: rapporto rischio/rendimento residuo
   double rr = tpDistance / slDistance;
   if(g_minRR > 0.0 && rr < g_minRR)
     {
      note = StringFormat("R:R effettivo 1:%.2f sotto il minimo 1:%.2f", rr, g_minRR);
      slDistance = 0.0;
      tpDistance = 0.0;
      return(false);
     }

   slDistance = NormalizeDouble(slDistance, Digits);
   tpDistance = NormalizeDouble(tpDistance, Digits);

   note = StringFormat("SL %.1f pips, TP %.1f pips, R:R 1:%.2f%s",
                       slDistance / g_pip, tpDistance / g_pip, rr,
                       (widened ? " (SL allargato al minimo broker)" : ""));
   return(true);
  }

//+------------------------------------------------------------------+
//| Apertura della posizione                                         |
//+------------------------------------------------------------------+
bool OpenPosition(int orderType)
  {
   RefreshRates();

   double atr = iATR(Symbol(), g_entryTF, ATR_Period, 1);

   double slDistance = 0.0, tpDistance = 0.0;
   string note = "";

   if(!BuildStopDistances(atr, slDistance, tpDistance, note))
     {
      SetReject(note);
      return(false);
     }

   double price = 0.0, sl = 0.0, tp = 0.0;

   if(orderType == OP_BUY)
     {
      price = NormalizeDouble(Ask, Digits);
      sl    = NormalizeDouble(price - slDistance, Digits);
      tp    = NormalizeDouble(price + tpDistance, Digits);
     }
   else
     {
      price = NormalizeDouble(Bid, Digits);
      sl    = NormalizeDouble(price + slDistance, Digits);
      tp    = NormalizeDouble(price - tpDistance, Digits);
     }

   double effectiveSL = MathAbs(price - sl);
   if(effectiveSL <= 0.0)
     {
      SetReject("distanza SL nulla dopo la normalizzazione");
      return(false);
     }

   double lots = CalculateLotSize(effectiveSL, true);
   if(lots <= 0.0)
     {
      SetReject("volume non calcolabile per il rischio richiesto");
      return(false);
     }

   //--- Se la parziale e' attiva servono almeno 2 lotti minimi, altrimenti
   //    la chiusura parziale sarebbe impossibile e il piano di uscita cambia.
   if(UsePartialClose && lots < g_minLot * 2.0)
     {
      if(VerboseLog)
         Print("[", TradeComment, "] Volume ", DoubleToString(lots, g_lotDigits),
               " troppo piccolo per la chiusura parziale: il trade uscira' interamente al TP.");
     }

   string comment = TradeComment;

   if(VerboseLog)
      Print("[", TradeComment, "] Invio ", (orderType == OP_BUY ? "BUY" : "SELL"),
            " | Lots=", DoubleToString(lots, g_lotDigits),
            " | Price=", DoubleToString(price, Digits),
            " SL=", DoubleToString(sl, Digits),
            " TP=", DoubleToString(tp, Digits),
            " | ATR=", DoubleToString(atr / g_pip, 1), " pips",
            " | Spread=", DoubleToString(MathMax(Ask - Bid, 0.0) / g_pip, 1), " pips",
            " | ", note,
            " | Rischio=", DoubleToString(RiskAmount(), 2), " ", AccountCurrency());

   int ticket = SendOrderWithRetries(orderType, lots, price, sl, tp, comment);

   if(ticket > 0)
     {
      g_lastTradeTime = TimeCurrent();
      g_tradesToday++;
      g_tradesThisHour++;
      g_lastReject = "-";

      //--- Registra 1R per la gestione successiva
      if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
         RegistrySet(OrderOpenTime(), MathAbs(OrderOpenPrice() - OrderStopLoss()), false);

      return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Invio ordine con retry - SL e TP sempre presenti                 |
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

      //--- Le distanze restano quelle calcolate, i prezzi si riallineano al mercato
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

      //--- Errore 130: stop rifiutati. Apertura senza stop e modifica immediata.
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
         Print("[", TradeComment, "] Anche l'apertura senza stop e' fallita, errore ", err, ": ", ErrorDescription(err));
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
         Print("[", TradeComment, "] OrderSelect fallito sul ticket ", ticket, ", errore ", GetLastError());
         Sleep(RetryDelayMs);
         continue;
        }

      //--- Nulla da fare se i livelli coincidono gia'
      if(MathAbs(OrderStopLoss() - sl) < Point / 2.0 && MathAbs(OrderTakeProfit() - tp) < Point / 2.0)
         return(true);

      RefreshRates();
      ResetLastError();

      if(OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(sl, Digits),
                     NormalizeDouble(tp, Digits), 0, clrGold))
         return(true);

      int err = GetLastError();

      //--- 1 = nessuna modifica necessaria: il broker considera i livelli identici
      if(err == 1)
         return(true);

      Print("[", TradeComment, "] OrderModify fallito (tentativo ", attempt, "/", MaxRetries,
            ") ticket ", ticket, " errore ", err, ": ", ErrorDescription(err),
            " | SL=", DoubleToString(sl, Digits), " TP=", DoubleToString(tp, Digits));

      if(!IsRetryableError(err))
         break;

      Sleep(RetryDelayMs * attempt);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Chiusura totale di un ticket                                     |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(int ticket)
  {
   for(int attempt = 1; attempt <= MaxRetries; attempt++)
     {
      if(!WaitForTradeContext())
         continue;

      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
         return(false);

      if(OrderCloseTime() != 0)
         return(true);

      RefreshRates();
      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;

      ResetLastError();
      if(OrderClose(ticket, OrderLots(), NormalizeDouble(closePrice, Digits), g_slippagePoints, clrRed))
         return(true);

      int err = GetLastError();
      Print("[", TradeComment, "] OrderClose fallito (tentativo ", attempt, "/", MaxRetries,
            ") ticket ", ticket, " errore ", err, ": ", ErrorDescription(err));

      if(!IsRetryableError(err))
         break;

      Sleep(RetryDelayMs * attempt);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Chiusura parziale                                                |
//| MT4 assegna un nuovo ticket alla parte residua: per questo il     |
//| registro interno e' indicizzato sull'ora di apertura.             |
//+------------------------------------------------------------------+
bool ClosePartialLots(int ticket, double lotsToClose)
  {
   if(lotsToClose <= 0.0)
      return(false);

   for(int attempt = 1; attempt <= MaxRetries; attempt++)
     {
      if(!WaitForTradeContext())
         continue;

      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
         return(false);

      if(OrderCloseTime() != 0)
         return(false);

      RefreshRates();
      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;

      ResetLastError();
      if(OrderClose(ticket, lotsToClose, NormalizeDouble(closePrice, Digits), g_slippagePoints, clrAqua))
        {
         Print("[", TradeComment, "] Parziale eseguita sul ticket ", ticket,
               ": chiusi ", DoubleToString(lotsToClose, g_lotDigits), " lotti.");
         return(true);
        }

      int err = GetLastError();
      Print("[", TradeComment, "] Chiusura parziale fallita (tentativo ", attempt, "/", MaxRetries,
            ") ticket ", ticket, " errore ", err, ": ", ErrorDescription(err));

      if(!IsRetryableError(err))
         break;

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
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      Print("[", TradeComment, "] Chiusura ticket ", OrderTicket(), ": ", reason);
      ClosePositionByTicket(OrderTicket());
     }
  }

//+------------------------------------------------------------------+
//| CALCOLO DEL LOTTO                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice, bool logErrors)
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

   //--- Perdita in valuta conto generata da 1.0 lotto se lo SL viene colpito,
   //    commissione round-turn inclusa nel budget di rischio.
   double lossPerLot = (slDistancePrice / tickSize) * tickValue + CommissionPerLot;
   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;

   //--- Vincolo di margine libero
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

//+------------------------------------------------------------------+
//| Normalizzazione del volume                                       |
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

//+------------------------------------------------------------------+
//| Decimali impliciti nello step del volume                         |
//+------------------------------------------------------------------+
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
//| Importo a rischio per operazione                                 |
//+------------------------------------------------------------------+
double RiskAmount()
  {
   double capital = (RiskBase == RISK_ON_EQUITY) ? AccountEquity() : AccountBalance();
   if(capital <= 0.0)
      return(0.0);
   return(capital * g_riskPercent / 100.0);
  }

//+------------------------------------------------------------------+
//| REGISTRO DELLE POSIZIONI                                         |
//| Chiave: ora di apertura, invariante alla chiusura parziale.       |
//+------------------------------------------------------------------+
int RegistryFind(datetime openTime)
  {
   for(int i = 0; i < ArraySize(g_regTime); i++)
      if(g_regTime[i] == openTime)
         return(i);
   return(-1);
  }

void RegistrySet(datetime openTime, double riskDistance, bool partialDone)
  {
   int idx = RegistryFind(openTime);

   if(idx < 0)
     {
      idx = ArraySize(g_regTime);
      ArrayResize(g_regTime,    idx + 1);
      ArrayResize(g_regRisk,    idx + 1);
      ArrayResize(g_regPartial, idx + 1);
     }

   g_regTime[idx]    = openTime;
   g_regRisk[idx]    = riskDistance;
   g_regPartial[idx] = partialDone;
  }

//--- Rischio iniziale (1R) della posizione selezionata; se il registro e'
//    vuoto (riavvio del terminale) lo ricostruisce dallo stop corrente.
double RegistryRisk(datetime openTime, double openPrice, double currentSL, double atr)
  {
   int idx = RegistryFind(openTime);
   if(idx >= 0 && g_regRisk[idx] > 0.0)
      return(g_regRisk[idx]);

   double risk = (currentSL > 0.0 ? MathAbs(openPrice - currentSL) : 0.0);
   if(risk <= 0.0)
      risk = MathMax(atr * SL_ATR, g_minSLPips * g_pip);

   RegistrySet(openTime, risk, false);
   return(risk);
  }

bool RegistryPartialDone(datetime openTime)
  {
   int idx = RegistryFind(openTime);
   return(idx >= 0 && g_regPartial[idx]);
  }

void RegistryMarkPartial(datetime openTime)
  {
   int idx = RegistryFind(openTime);
   if(idx >= 0)
      g_regPartial[idx] = true;
  }

//--- Elimina dal registro le posizioni non piu' aperte
void RegistryPrune()
  {
   int size = ArraySize(g_regTime);
   if(size == 0)
      return;

   datetime keepTime[];
   double   keepRisk[];
   bool     keepPart[];
   int      kept = 0;

   for(int i = 0; i < size; i++)
     {
      bool stillOpen = false;

      for(int j = OrdersTotal() - 1; j >= 0; j--)
        {
         if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
            continue;
         if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
            continue;
         if(OrderOpenTime() == g_regTime[i])
           {
            stillOpen = true;
            break;
           }
        }

      if(!stillOpen)
         continue;

      ArrayResize(keepTime, kept + 1);
      ArrayResize(keepRisk, kept + 1);
      ArrayResize(keepPart, kept + 1);
      keepTime[kept] = g_regTime[i];
      keepRisk[kept] = g_regRisk[i];
      keepPart[kept] = g_regPartial[i];
      kept++;
     }

   ArrayResize(g_regTime,    kept);
   ArrayResize(g_regRisk,    kept);
   ArrayResize(g_regPartial, kept);

   for(int k = 0; k < kept; k++)
     {
      g_regTime[k]    = keepTime[k];
      g_regRisk[k]    = keepRisk[k];
      g_regPartial[k] = keepPart[k];
     }
  }

//--- Ricostruzione all'avvio: l'EA puo' essere ricaricato con posizioni aperte
void RebuildRegistry()
  {
   ArrayResize(g_regTime,    0);
   ArrayResize(g_regRisk,    0);
   ArrayResize(g_regPartial, 0);

   double atr = iATR(Symbol(), g_entryTF, ATR_Period, 1);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      double risk = (OrderStopLoss() > 0.0 ? MathAbs(OrderOpenPrice() - OrderStopLoss()) : 0.0);
      if(risk <= 0.0)
         risk = MathMax(atr * SL_ATR, g_minSLPips * g_pip);

      //--- Posizione ereditata: la parziale si considera gia' fatta, per non
      //    ridurre due volte un volume che non sappiamo da dove arrivi.
      RegistrySet(OrderOpenTime(), risk, true);

      Print("[", TradeComment, "] Posizione preesistente rilevata: ticket ", OrderTicket(),
            ", 1R stimato ", DoubleToString(risk / g_pip, 1), " pips.");
     }
  }

//+------------------------------------------------------------------+
//| GESTIONE DELLE POSIZIONI                                         |
//| Ordine delle azioni: uscita a tempo, parziale, break-even,        |
//| trailing. Lo stop non arretra mai.                                |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   RegistryPrune();

   double atr = iATR(Symbol(), g_entryTF, ATR_Period, 1);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      RefreshRates();

      int      ticket    = OrderTicket();
      bool     isBuy     = (OrderType() == OP_BUY);
      datetime openTime  = OrderOpenTime();
      double   openPrice = OrderOpenPrice();
      double   currentSL = OrderStopLoss();
      double   lots      = OrderLots();
      double   riskDist  = RegistryRisk(openTime, openPrice, currentSL, atr);
      double   minDist   = BrokerMinStopDistance();
      double   freeze    = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;

      //--- Profitto corrente in prezzo e in R
      double profitPrice = (isBuy ? Bid - openPrice : openPrice - Ask);
      double rMultiple   = (riskDist > 0.0 ? profitPrice / riskDist : 0.0);

      //--- 1) USCITA A TEMPO: uno scalp M1 che non si risolve va chiuso
      if(g_maxTradeMin > 0 && TimeCurrent() - openTime >= g_maxTradeMin * 60)
        {
         if(!TimeExitOnlyIfProfit || profitPrice > 0.0)
           {
            Print("[", TradeComment, "] Uscita a tempo sul ticket ", ticket,
                  " dopo ", g_maxTradeMin, " minuti (", DoubleToString(rMultiple, 2), " R).");
            ClosePositionByTicket(ticket);
            break;   // La lista degli ordini e' cambiata: si riparte al tick successivo
           }
        }

      //--- 2) PARZIALE: si incassa una parte a PartialAtR e il resto viaggia protetto
      if(UsePartialClose && !RegistryPartialDone(openTime) && rMultiple >= PartialAtR)
        {
         double closeLots = NormalizeDouble(MathFloor((lots * PartialPercent / 100.0) / g_lotStep + 0.0000001) * g_lotStep,
                                            g_lotDigits);
         double remaining = NormalizeDouble(lots - closeLots, g_lotDigits);

         if(closeLots >= g_minLot && remaining >= g_minLot)
           {
            if(ClosePartialLots(ticket, closeLots))
              {
               RegistryMarkPartial(openTime);
               break;   // Il residuo ha un nuovo ticket: sara' gestito al tick successivo
              }
           }
         else
           {
            //--- Volume non divisibile: si annota una sola volta e non ci si riprova
            RegistryMarkPartial(openTime);
            if(VerboseLog)
               Print("[", TradeComment, "] Parziale non eseguibile sul ticket ", ticket,
                     " (volume ", DoubleToString(lots, g_lotDigits),
                     ", minimo ", DoubleToString(g_minLot, g_lotDigits), "): la posizione resta intera.");
           }
        }

      //--- 3) BREAK-EVEN e 4) TRAILING
      double newSL = currentSL;

      if(isBuy)
        {
         if(EnableBreakEven && rMultiple >= BreakEvenR)
           {
            double bePrice = NormalizeDouble(openPrice + g_beLockPips * g_pip, Digits);
            if(bePrice > newSL + Point / 2.0 && Bid - bePrice >= minDist)
               newSL = bePrice;
           }

         if(EnableTrailingStop && rMultiple >= TrailStartR && atr > 0.0)
           {
            double trailPrice = NormalizeDouble(Bid - atr * TrailATR, Digits);
            if(trailPrice > newSL + g_trailStepPips * g_pip - Point / 2.0 && Bid - trailPrice >= minDist)
               newSL = trailPrice;
           }

         if(currentSL > 0.0 && newSL < currentSL + Point / 2.0)
            newSL = currentSL;

         if(newSL > currentSL + Point / 2.0)
           {
            if(freeze > 0.0 && Bid - newSL < freeze)
               continue;
            ModifyOrderWithRetries(ticket, newSL, OrderTakeProfit());
           }
        }
      else
        {
         if(EnableBreakEven && rMultiple >= BreakEvenR)
           {
            double bePriceS = NormalizeDouble(openPrice - g_beLockPips * g_pip, Digits);
            if((newSL <= 0.0 || bePriceS < newSL - Point / 2.0) && bePriceS - Ask >= minDist)
               newSL = bePriceS;
           }

         if(EnableTrailingStop && rMultiple >= TrailStartR && atr > 0.0)
           {
            double trailPriceS = NormalizeDouble(Ask + atr * TrailATR, Digits);
            if((newSL <= 0.0 || trailPriceS < newSL - g_trailStepPips * g_pip + Point / 2.0) &&
               trailPriceS - Ask >= minDist)
               newSL = trailPriceS;
           }

         if(currentSL > 0.0 && newSL > currentSL - Point / 2.0)
            newSL = currentSL;

         if(newSL > 0.0 && (currentSL <= 0.0 || newSL < currentSL - Point / 2.0))
           {
            if(freeze > 0.0 && newSL - Ask < freeze)
               continue;
            ModifyOrderWithRetries(ticket, newSL, OrderTakeProfit());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Conteggio delle posizioni dell'EA                                |
//+------------------------------------------------------------------+
int CountOwnPositions()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| Limiti di frequenza: trade al giorno e trade nell'ora            |
//+------------------------------------------------------------------+
bool AreTradeCountsOk(bool silent)
  {
   if(g_maxTradesDay > 0 && g_tradesToday >= g_maxTradesDay)
     {
      if(!silent)
         SetReject(StringFormat("limite di %d trade giornalieri raggiunto", g_maxTradesDay));
      return(false);
     }

   if(g_maxTradesHour > 0 && g_tradesThisHour >= g_maxTradesHour)
     {
      if(!silent)
         SetReject(StringFormat("limite di %d trade in un'ora raggiunto", g_maxTradesHour));
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Attesa: barre dopo l'ultimo trade e pausa dopo perdite           |
//+------------------------------------------------------------------+
bool IsInCooldown(bool silent)
  {
   //--- Pausa per perdite consecutive
   if(g_cooldownUntil > TimeCurrent())
     {
      if(!silent)
         SetReject(StringFormat("pausa dopo %d perdite consecutive, riprende alle %s",
                                g_consecLosses, TimeToString(g_cooldownUntil, TIME_MINUTES)));
      return(true);
     }

   if(g_cooldownBars <= 0)
      return(false);

   datetime reference = g_lastTradeTime;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderCloseTime() > reference)
         reference = OrderCloseTime();
      break;
     }

   if(reference <= 0)
      return(false);

   if(iBarShift(Symbol(), g_entryTF, reference, false) < g_cooldownBars)
     {
      if(!silent)
         SetReject(StringFormat("attesa di %d barre dopo l'ultima operazione", g_cooldownBars));
      return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Filtro spread: soglia assoluta e soglia relativa all'ATR          |
//| Su M1 e' il filtro che decide la sostenibilita' della strategia.  |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(bool silent)
  {
   double spread = MathMax(Ask - Bid, 0.0);

   if(g_maxSpreadPips > 0.0 && spread / g_pip > g_maxSpreadPips)
     {
      if(!silent)
         SetReject(StringFormat("spread %.1f pips oltre il massimo assoluto %.1f",
                                spread / g_pip, g_maxSpreadPips));
      return(false);
     }

   if(g_maxSpreadATR > 0.0)
     {
      double atr = iATR(Symbol(), g_entryTF, ATR_Period, 1);
      if(atr > 0.0 && spread > atr * g_maxSpreadATR)
        {
         if(!silent)
            SetReject(StringFormat("spread %.1f pips = %.0f%% dell'ATR (max %.0f%%)",
                                   spread / g_pip, spread / atr * 100.0, g_maxSpreadATR * 100.0));
         return(false);
        }
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| ATR abituale: media dell'ATR sulle ultime N barre chiuse          |
//+------------------------------------------------------------------+
double GetAverageATR(int timeframe, int period, int startShift)
  {
   if(period < 1)
      return(0.0);

   double sum   = 0.0;
   int    valid = 0;

   for(int i = 0; i < period; i++)
     {
      double v = iATR(Symbol(), timeframe, ATR_Period, startShift + i);
      if(v > 0.0)
        {
         sum += v;
         valid++;
        }
     }

   return(valid > 0 ? sum / valid : 0.0);
  }

//+------------------------------------------------------------------+
//| FILTRO VOLATILITA'                                                |
//| Il confronto e' con la volatilita' ABITUALE dello strumento, non  |
//| con un numero fisso di pips: l'ATR "normale" dell'oro dipende dal |
//| livello del prezzo, dal broker e dal periodo, e una soglia        |
//| assoluta finirebbe per bloccare l'operativita' per giorni interi  |
//| anche in assenza di qualunque notizia.                            |
//| I limiti assoluti restano applicabili, ma solo se impostati.      |
//+------------------------------------------------------------------+
bool IsVolatilityAcceptable(bool silent)
  {
   double atr = iATR(Symbol(), g_entryTF, ATR_Period, 1);
   if(atr <= 0.0)
      return(false);

   double atrPips = atr / g_pip;
   double avgATR  = GetAverageATR(g_entryTF, ATR_AvgPeriod, 1);
   double ratio   = (avgATR > 0.0 ? atr / avgATR : 0.0);

   //--- Confronto relativo (filtro principale)
   if(ratio > 0.0)
     {
      if(g_minATRRatio > 0.0 && ratio < g_minATRRatio)
        {
         if(!silent)
            SetReject(StringFormat("ATR %.1f pips = %.2fx la media (minimo %.2fx): mercato fermo",
                                   atrPips, ratio, g_minATRRatio));
         return(false);
        }

      if(g_maxATRRatio > 0.0 && ratio > g_maxATRRatio)
        {
         if(!silent)
            SetReject(StringFormat("ATR %.1f pips = %.2fx la media (massimo %.2fx): volatilita' anomala",
                                   atrPips, ratio, g_maxATRRatio));
         return(false);
        }
     }

   //--- Rete di sicurezza assoluta, attiva solo se impostata
   if(g_minATRPips > 0.0 && atrPips < g_minATRPips)
     {
      if(!silent)
         SetReject(StringFormat("ATR %.1f pips sotto il minimo assoluto %.1f",
                                atrPips, g_minATRPips));
      return(false);
     }

   if(g_maxATRPips > 0.0 && atrPips > g_maxATRPips)
     {
      if(!silent)
         SetReject(StringFormat("ATR %.1f pips oltre il massimo assoluto %.1f",
                                atrPips, g_maxATRPips));
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Filtro di sessione (ora del server)                              |
//+------------------------------------------------------------------+
bool IsSessionAllowed(bool silent)
  {
   datetime now    = TimeCurrent();
   int      hour   = TimeHour(now);
   int      minute = TimeMinute(now);
   int      nowMin = hour * 60 + minute;
   int      dow    = DayOfWeek();

   //--- Fine settimana
   if(FridayCloseHour > 0 && dow == 5 && hour >= FridayCloseHour)
     {
      if(!silent)
         SetReject(StringFormat("chiusura settimanale: nessun ingresso il venerdi' dalle %02d:00", FridayCloseHour));
      return(false);
     }

   //--- Rollover: spread allargato e liquidita' assente
   if(RolloverBufferMin > 0)
     {
      if(nowMin < RolloverBufferMin || nowMin >= 1440 - RolloverBufferMin)
        {
         if(!silent)
            SetReject(StringFormat("finestra di rollover (+/- %d minuti dalla mezzanotte server)", RolloverBufferMin));
         return(false);
        }
     }

   if(!UseSessionFilter)
      return(true);

   //--- Finestre effettive: il profilo di aggressivita' le allarga o le stringe
   bool inside = false;

   if(UseSession1 && InWindow(nowMin, g_s1Start, g_s1End))
      inside = true;

   if(!inside && UseSession2 && InWindow(nowMin, g_s2Start, g_s2End))
      inside = true;

   if(!inside && !silent)
      SetReject("fuori dalle finestre operative (" +
                MinuteToHM(g_s1Start) + "-" + MinuteToHM(g_s1End) + " / " +
                MinuteToHM(g_s2Start) + "-" + MinuteToHM(g_s2End) + " ora del server)");

   return(inside);
  }

//+------------------------------------------------------------------+
//| Minuto del giorno dentro una finestra (gestisce la mezzanotte)   |
//+------------------------------------------------------------------+
bool InWindow(int nowMin, int startMin, int endMin)
  {
   if(startMin == endMin)
      return(true);

   if(startMin < endMin)
      return(nowMin >= startMin && nowMin < endMin);

   return(nowMin >= startMin || nowMin < endMin);
  }

//+------------------------------------------------------------------+
//| Stato giornaliero: rollover, statistiche, stop e target           |
//+------------------------------------------------------------------+
void ResetDailyState(bool force)
  {
   datetime now   = TimeCurrent();
   datetime today = now - (now % 86400);
   datetime hour  = now - (now % 3600);

   if(force || today != g_dayStamp)
     {
      g_dayStamp        = today;
      g_dayStartBalance = AccountBalance();
      g_dailyBlocked    = false;
      g_dailyBlockNote  = "";
      if(!force)
         Print("[", TradeComment, "] Nuova giornata di trading. Saldo iniziale: ",
               DoubleToString(g_dayStartBalance, 2), " ", AccountCurrency());
     }

   if(hour != g_hourStamp)
      g_hourStamp = hour;

   UpdateTradeStats();

   if(g_dailyBlocked || g_dayStartBalance <= 0.0)
      return;

   double dayPL = g_statTodayProfit + (IncludeFloatingInDD ? FloatingProfit() : 0.0);

   //--- Stop giornaliero
   if(MaxDailyLossPercent > 0.0)
     {
      double limit = g_dayStartBalance * MaxDailyLossPercent / 100.0;
      if(dayPL <= -limit)
        {
         g_dailyBlocked   = true;
         g_dailyBlockNote = StringFormat("stop giornaliero: %.2f %s sul limite di %.2f",
                                         dayPL, AccountCurrency(), limit);
         SetReject(g_dailyBlockNote);
         Print("[", TradeComment, "] STOP GIORNALIERO raggiunto. Nessun nuovo ingresso fino a domani.");
         return;
        }
     }

   //--- Target giornaliero: incassare la giornata e smettere e' parte del metodo
   if(DailyProfitTargetPct > 0.0)
     {
      double target = g_dayStartBalance * DailyProfitTargetPct / 100.0;
      if(dayPL >= target)
        {
         g_dailyBlocked   = true;
         g_dailyBlockNote = StringFormat("target giornaliero raggiunto: %.2f %s (obiettivo %.2f)",
                                         dayPL, AccountCurrency(), target);
         SetReject(g_dailyBlockNote);
         Print("[", TradeComment, "] TARGET GIORNALIERO raggiunto. Nessun nuovo ingresso fino a domani.");
        }
     }
  }

//+------------------------------------------------------------------+
//| Aggiunge un valore a una lista solo se non e' gia' presente.      |
//| Serve a contare gli INGRESSI e non le operazioni: una chiusura    |
//| parziale lascia in cronologia due record con la stessa ora di     |
//| apertura, e senza questo filtro un solo ingresso consumerebbe due |
//| posti nel limite giornaliero.                                     |
//+------------------------------------------------------------------+
void AddUniqueTime(datetime &list[], int &count, datetime value)
  {
   for(int i = 0; i < count; i++)
      if(list[i] == value)
         return;

   ArrayResize(list, count + 1);
   list[count] = value;
   count++;
  }

//+------------------------------------------------------------------+
//| Statistiche sui trade dell'EA (con cache)                        |
//+------------------------------------------------------------------+
void UpdateTradeStats()
  {
   static datetime lastCalc    = 0;
   static int      lastHistory = -1;
   static int      lastOpen    = -1;

   int history = OrdersHistoryTotal();
   int open    = OrdersTotal();

   if(history == lastHistory && open == lastOpen && TimeCurrent() - lastCalc < 3)
      return;

   lastHistory = history;
   lastOpen    = open;
   lastCalc    = TimeCurrent();

   g_statNetProfit   = 0.0;
   g_statGrossWin    = 0.0;
   g_statGrossLoss   = 0.0;
   g_statTodayProfit = 0.0;
   g_statTrades      = 0;
   g_statWins        = 0;
   g_tradesToday     = 0;
   g_tradesThisHour  = 0;

   //--- Ultime operazioni chiuse, per la sequenza di perdite consecutive.
   //    Array dinamici azzerati con ArrayInitialize: un'inizializzazione a
   //    indice variabile non basta all'analizzatore di MetaEditor, che
   //    segnalerebbe un possibile uso di variabile non inizializzata anche
   //    con la lettura gia' protetta da recentCount. Le ore di chiusura sono
   //    tenute in double per poter usare ArrayInitialize anche su di esse:
   //    un datetime e' un intero ampiamente rappresentabile in doppia precisione.
   double recentTime[];
   double recentNet[];
   ArrayResize(recentTime, 10);
   ArrayResize(recentNet,  10);
   ArrayInitialize(recentTime, 0.0);
   ArrayInitialize(recentNet,  0.0);

   int      recentCount = 0;
   int      recentMax   = (g_maxConsecLoss > 0 ? (int)MathMin(g_maxConsecLoss + 1, 10) : 0);

   //--- Ore di apertura distinte: contano gli ingressi, non i record
   datetime dayOpens[];
   datetime hourOpens[];
   int      dayCount  = 0;
   int      hourCount = 0;

   for(int i = 0; i < history; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      double net = OrderProfit() + OrderSwap() + OrderCommission();

      g_statNetProfit += net;
      g_statTrades++;

      if(net >= 0.0)
        {
         g_statWins++;
         g_statGrossWin += net;
        }
      else
         g_statGrossLoss += -net;

      if(OrderCloseTime() >= g_dayStamp)
         g_statTodayProfit += net;

      if(OrderOpenTime() >= g_dayStamp)
         AddUniqueTime(dayOpens, dayCount, OrderOpenTime());

      if(OrderOpenTime() >= g_hourStamp)
         AddUniqueTime(hourOpens, hourCount, OrderOpenTime());

      //--- Inserimento ordinato per ora di chiusura decrescente
      if(recentMax > 0)
        {
         double ct = (double)OrderCloseTime();
         int pos = recentCount;
         while(pos > 0 && recentTime[pos - 1] < ct)
            pos--;

         if(pos < recentMax)
           {
            int last = (int)MathMin(recentCount, recentMax - 1);
            for(int s = last; s > pos; s--)
              {
               recentTime[s] = recentTime[s - 1];
               recentNet[s]  = recentNet[s - 1];
              }
            recentTime[pos] = ct;
            recentNet[pos]  = net;
            if(recentCount < recentMax)
               recentCount++;
           }
        }
     }

   //--- Le posizioni ancora aperte contano nei limiti di frequenza
   for(int j = OrdersTotal() - 1; j >= 0; j--)
     {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(OrderOpenTime() >= g_dayStamp)
         AddUniqueTime(dayOpens, dayCount, OrderOpenTime());
      if(OrderOpenTime() >= g_hourStamp)
         AddUniqueTime(hourOpens, hourCount, OrderOpenTime());
     }

   g_tradesToday    = dayCount;
   g_tradesThisHour = hourCount;

   //--- Perdite consecutive e attivazione della pausa
   g_consecLosses = 0;
   for(int r = 0; r < recentCount; r++)
     {
      if(recentNet[r] < 0.0)
         g_consecLosses++;
      else
         break;
     }

   datetime lastLossTime = (recentCount > 0 ? (datetime)(long)recentTime[0] : 0);

   if(g_maxConsecLoss > 0 && CooldownMinutes > 0 &&
      g_consecLosses >= g_maxConsecLoss && recentCount > 0 &&
      lastLossTime > g_lastLossHandled)
     {
      g_lastLossHandled = lastLossTime;
      g_cooldownUntil   = lastLossTime + CooldownMinutes * 60;
      Print("[", TradeComment, "] ", g_consecLosses, " perdite consecutive: pausa di ",
            CooldownMinutes, " minuti fino alle ", TimeToString(g_cooldownUntil, TIME_MINUTES), ".");
     }
  }

//+------------------------------------------------------------------+
//| Profitto flottante dell'EA                                       |
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
//| Registra il motivo dell'ultimo scarto                            |
//+------------------------------------------------------------------+
void SetReject(string reason)
  {
   if(reason == "")
      return;

   if(LogRejections && VerboseLog && reason != g_lastReject)
      Print("[", TradeComment, "] Nessun ingresso: ", reason);

   g_lastReject = reason;
  }

//+------------------------------------------------------------------+
//| Attesa del contesto di trading                                   |
//+------------------------------------------------------------------+
bool WaitForTradeContext()
  {
   int waited = 0;
   while(IsTradeContextBusy() && waited < 3000)
     {
      Sleep(50);
      waited += 50;
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
      case 4:    // Server occupato
      case 6:    // Nessuna connessione
      case 128:  // Timeout della transazione
      case 129:  // Prezzo non valido
      case 135:  // Prezzo cambiato
      case 136:  // Quotazione assente
      case 137:  // Broker occupato
      case 138:  // Requote
      case 141:  // Troppe richieste
      case 145:  // Modifica vietata, posizione troppo vicina al mercato
      case 146:  // Sottosistema di trading occupato
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
      case 1:   return("nessun risultato: parametri identici a quelli attuali");
      case 2:   return("errore generico");
      case 3:   return("parametri non validi");
      case 4:   return("server di trading occupato");
      case 5:   return("versione del terminale non aggiornata");
      case 6:   return("nessuna connessione al server");
      case 8:   return("richieste troppo frequenti");
      case 64:  return("conto bloccato");
      case 65:  return("numero di conto non valido");
      case 128: return("timeout della transazione");
      case 129: return("prezzo non valido");
      case 130: return("stop non validi: troppo vicini al prezzo");
      case 131: return("volume non valido");
      case 132: return("mercato chiuso");
      case 133: return("trading disabilitato");
      case 134: return("fondi insufficienti");
      case 135: return("prezzo cambiato");
      case 136: return("quotazione assente");
      case 137: return("broker occupato");
      case 138: return("requote");
      case 139: return("ordine bloccato ed in elaborazione");
      case 140: return("consentito solo l'acquisto");
      case 141: return("troppe richieste");
      case 145: return("modifica vietata: posizione troppo vicina al mercato");
      case 146: return("sottosistema di trading occupato");
      case 147: return("scadenza rifiutata dal broker");
      case 148: return("numero di ordini aperti al limite");
      case 149: return("hedging vietato");
      case 150: return("chiusura vietata per la regola FIFO");
      default:  return("errore " + IntegerToString(err));
     }
  }

//+------------------------------------------------------------------+
//| Motivo di deinizializzazione                                     |
//+------------------------------------------------------------------+
string DeinitReasonText(int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:     return("EA terminato");
      case REASON_REMOVE:      return("EA rimosso dal grafico");
      case REASON_RECOMPILE:   return("EA ricompilato");
      case REASON_CHARTCHANGE: return("simbolo o periodo cambiati");
      case REASON_CHARTCLOSE:  return("grafico chiuso");
      case REASON_PARAMETERS:  return("parametri modificati");
      case REASON_ACCOUNT:     return("conto cambiato");
      default:                 return("motivo " + IntegerToString(reason));
     }
  }

//+------------------------------------------------------------------+
//| Nome del timeframe                                               |
//+------------------------------------------------------------------+
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
      default:         return("TF" + IntegerToString(tf));
     }
  }

//+------------------------------------------------------------------+
//| Formattazioni per la dashboard                                   |
//+------------------------------------------------------------------+
string PipStr(double priceDistance)
  {
   return(DoubleToString(priceDistance / g_pip, 1) + " p");
  }

string MoneyStr(double value)
  {
   return((value > 0.0 ? "+" : "") + DoubleToString(value, 2));
  }

color SignColor(double value)
  {
   if(value > 0.0) return(PanelPositiveColor);
   if(value < 0.0) return(PanelNegativeColor);
   return(PanelValueColor);
  }

string Shorten(string text, int maxChars)
  {
   if(maxChars < 5 || StringLen(text) <= maxChars)
      return(text);
   return(StringSubstr(text, 0, maxChars - 3) + "...");
  }

//--- Caratteri utili per barra e semaforo, tutti ASCII per sicurezza
string BarCountdown()
  {
   int seconds = (int)(iTime(Symbol(), g_entryTF, 0) + g_entryTF * 60 - TimeCurrent());
   if(seconds < 0)
      seconds = 0;

   int mm = seconds / 60;
   int ss = seconds % 60;
   return(StringFormat("%02d:%02d", mm, ss));
  }

double Clamp01(double value)
  {
   if(value < 0.0) return(0.0);
   if(value > 1.0) return(1.0);
   return(value);
  }

//+------------------------------------------------------------------+
//| DASHBOARD: primitive grafiche                                    |
//| Le coordinate sono "logiche": distanza dal bordo sinistro del     |
//| pannello. La conversione all'angolo scelto avviene qui.           |
//+------------------------------------------------------------------+
int RectX(int leftOffset, int width)
  {
   if(g_corner == CORNER_RIGHT_UPPER)
      return(PanelX + PanelWidth - leftOffset - width);
   return(PanelX + leftOffset);
  }

int TextX(int leftOffset)
  {
   if(g_corner == CORNER_RIGHT_UPPER)
      return(PanelX + PanelWidth - leftOffset);
   return(PanelX + leftOffset);
  }

void PanelRect(string name, int leftOffset, int y, int w, int h, color bg, color border, int zorder)
  {
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return;

   ObjectSetInteger(0, name, OBJPROP_CORNER,      g_corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   RectX(leftOffset, w));
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       border);
   ObjectSetInteger(0, name, OBJPROP_STYLE,       STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       1);
   ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,    false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,      zorder);
  }

void PanelText(string name, int leftOffset, int y, string text, color clr, int fontSize, int anchor, string font)
  {
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;

   ObjectSetInteger(0, name, OBJPROP_CORNER,     g_corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  TextX(leftOffset));
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     anchor);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     5);
   ObjectSetString(0,  name, OBJPROP_FONT,       font);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
  }

void PanelButton(string name, int leftOffset, int y, int w, int h, string text, color bg, color txt, string tooltip)
  {
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
         return;

   ObjectSetInteger(0, name, OBJPROP_CORNER,       g_corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    RectX(leftOffset, w));
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        txt);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, PanelBorderColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     PanelFontSize);
   ObjectSetInteger(0, name, OBJPROP_STATE,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,       true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,       6);
   ObjectSetString(0,  name, OBJPROP_FONT,         PanelFont);
   ObjectSetString(0,  name, OBJPROP_TEXT,         text);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP,      tooltip);
  }

//--- Intestazione di sezione
void PanelSection(int &y, string id, string title)
  {
   PanelRect(g_prefix + "b_sec_" + id, 1, y - 3, PanelWidth - 2, g_rowH + 2,
             PanelHeaderColor, PanelHeaderColor, 1);
   PanelText(g_prefix + "b_sect_" + id, g_pad, y, title, PanelAccentColor, PanelFontSize, ANCHOR_LEFT_UPPER, PanelFont);
   y += g_rowH + 5;
  }

//--- Riga etichetta / valore
void PanelRow(int &y, string id, string caption, string value, color valueColor)
  {
   PanelText(g_prefix + "b_cap_" + id, g_pad, y, caption,
             PanelCaptionColor, PanelFontSize, ANCHOR_LEFT_UPPER, PanelFont);
   PanelText(g_prefix + "b_val_" + id, PanelWidth - g_pad, y, value,
             valueColor, PanelFontSize, ANCHOR_RIGHT_UPPER, PanelFont);
   y += g_rowH;
  }

//--- Riga con semaforo: quadratino colorato + esito
void PanelCheckRow(int &y, string id, string caption, bool ok, string value)
  {
   color dot = (ok ? PanelPositiveColor : PanelNegativeColor);

   PanelRect(g_prefix + "b_dot_" + id, g_pad, y + 3, 7, 7, dot, dot, 2);
   PanelText(g_prefix + "b_ccap_" + id, g_pad + 14, y, caption,
             PanelCaptionColor, PanelFontSize, ANCHOR_LEFT_UPPER, PanelFont);
   PanelText(g_prefix + "b_cval_" + id, PanelWidth - g_pad, y, value,
             dot, PanelFontSize, ANCHOR_RIGHT_UPPER, PanelFont);
   y += g_rowH;
  }

//--- Riga con barra di avanzamento sotto
void PanelMeter(int &y, string id, string caption, string value, double ratio, color fill, color valueColor)
  {
   PanelText(g_prefix + "b_mcap_" + id, g_pad, y, caption,
             PanelCaptionColor, PanelFontSize, ANCHOR_LEFT_UPPER, PanelFont);
   PanelText(g_prefix + "b_mval_" + id, PanelWidth - g_pad, y, value,
             valueColor, PanelFontSize, ANCHOR_RIGHT_UPPER, PanelFont);
   y += g_rowH - 2;

   int trackW = PanelWidth - 2 * g_pad;
   int fillW  = (int)MathRound(trackW * Clamp01(ratio));
   if(fillW < 1 && ratio > 0.0)
      fillW = 1;

   PanelRect(g_prefix + "b_mtrk_" + id, g_pad, y, trackW, 4, PanelHeaderColor, PanelHeaderColor, 2);
   if(fillW > 0)
      PanelRect(g_prefix + "b_mfil_" + id, g_pad, y, fillW, 4, fill, fill, 3);
   else
      ObjectDelete(0, g_prefix + "b_mfil_" + id);

   y += 10;
  }

//--- Riquadro KPI (tre per riga)
void PanelTile(int index, int y, int height, string id, string caption, string value, color valueColor)
  {
   int usable = PanelWidth - 2 * g_pad;
   int gap    = 6;
   int tileW  = (usable - 2 * gap) / 3;
   int left   = g_pad + index * (tileW + gap);

   PanelRect(g_prefix + "b_tile_" + id, left, y, tileW, height, PanelHeaderColor, PanelHeaderColor, 1);
   PanelText(g_prefix + "b_tcap_" + id, left + tileW / 2, y + 4, caption,
             PanelCaptionColor, PanelFontSize - 1, ANCHOR_UPPER, PanelFont);
   PanelText(g_prefix + "b_tval_" + id, left + tileW / 2, y + 4 + g_rowH - 2, value,
             valueColor, PanelFontSize + 1, ANCHOR_UPPER, PanelFont);
  }

//+------------------------------------------------------------------+
//| Rimozione degli oggetti del pannello                             |
//+------------------------------------------------------------------+
void DeletePanel()
  {
   if(StringLen(g_prefix) == 0)
      return;

   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_prefix, 0) == 0)
         ObjectDelete(0, name);
     }
   ChartRedraw();
  }

//--- Solo il corpo: l'intestazione resta visibile quando il pannello e' ridotto
void DeletePanelBody()
  {
   if(StringLen(g_prefix) == 0)
      return;

   string bodyPrefix = g_prefix + "b_";
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, bodyPrefix, 0) == 0)
         ObjectDelete(0, name);
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| DASHBOARD: costruzione e aggiornamento                           |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(TimeCurrent() == g_panelRefresh)
      return;
   g_panelRefresh = TimeCurrent();

   UpdateTradeStats();

   //--- Stato generale --------------------------------------------------
   bool   autoOk  = (IsExpertEnabled() && IsTradeAllowed());
   bool   hasBars = HasEnoughBars();
   int    openPos = CountOwnPositions();

   string statusText;
   color  statusColor;

   if(!autoOk)
     { statusText = "AUTOTRADING OFF"; statusColor = PanelNegativeColor; }
   else
      if(g_paused)
        { statusText = "IN PAUSA";      statusColor = PanelWarningColor; }
      else
         if(g_dailyBlocked)
           { statusText = "STOP GIORNO"; statusColor = PanelNegativeColor; }
         else
            if(g_cooldownUntil > TimeCurrent())
              { statusText = "COOLDOWN";  statusColor = PanelWarningColor; }
            else
               if(openPos > 0)
                 { statusText = "IN POSIZIONE"; statusColor = PanelAccentColor; }
               else
                 { statusText = "OPERATIVO";    statusColor = PanelPositiveColor; }

   //--- Intestazione ----------------------------------------------------
   int headerH = g_rowH + 12;
   int y       = PanelY;

   PanelRect(g_prefix + "h_bg", 0, PanelY, PanelWidth, headerH + 4, PanelBgColor, PanelBorderColor, 0);
   PanelRect(g_prefix + "h_hdr", 1, PanelY + 1, PanelWidth - 2, headerH, PanelHeaderColor, PanelHeaderColor, 1);

   PanelText(g_prefix + "h_title", g_pad, PanelY + 6, "GOLD SCALPER " + TimeframeToString(g_entryTF),
             PanelTitleColor, PanelFontSize + 2, ANCHOR_LEFT_UPPER, PanelFont);

   //--- Pulsanti: pausa, chiusura, riduci
   int btnW = 24, btnH = g_rowH, btnGap = 4;
   int btnRight = g_pad;

   if(ShowPanelButtons)
     {
      PanelButton(g_prefix + "h_btn_min", PanelWidth - btnRight - btnW, PanelY + 7, btnW, btnH,
                  (g_collapsed ? "+" : "-"), PanelHeaderColor, PanelValueColor,
                  (g_collapsed ? "Espandi il pannello" : "Riduci il pannello"));

      PanelButton(g_prefix + "h_btn_close", PanelWidth - btnRight - 2 * btnW - btnGap, PanelY + 7, btnW, btnH,
                  "X", PanelHeaderColor, PanelNegativeColor, "Chiudi tutte le posizioni dell'EA");

      PanelButton(g_prefix + "h_btn_pause", PanelWidth - btnRight - 3 * btnW - 2 * btnGap, PanelY + 7, btnW, btnH,
                  (g_paused ? ">" : "II"), PanelHeaderColor,
                  (g_paused ? PanelPositiveColor : PanelWarningColor),
                  (g_paused ? "Riprendi l'operativita'" : "Sospendi i nuovi ingressi"));

      btnRight += 3 * btnW + 2 * btnGap + 8;
     }

   //--- Badge di stato accanto ai pulsanti
   PanelText(g_prefix + "h_status", PanelWidth - btnRight, PanelY + 9, statusText,
             statusColor, PanelFontSize, ANCHOR_RIGHT_UPPER, PanelFont);

   y = PanelY + headerH + 6;

   if(g_collapsed)
     {
      ObjectSetInteger(0, g_prefix + "h_bg", OBJPROP_YSIZE, headerH + 4);
      g_panelHeight = headerH + 4;
      ChartRedraw();
      return;
     }

   //--- Dati di mercato --------------------------------------------------
   double atr    = (hasBars ? iATR(Symbol(), g_entryTF, ATR_Period, 1) : 0.0);
   double spread = MathMax(Ask - Bid, 0.0);
   double adx    = (hasBars ? iADX(Symbol(), g_trendTF, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1) : 0.0);

   string biasInfo   = "";
   string signalInfo = "";
   int    bias       = (hasBars ? GetBias(biasInfo, true) : 0);
   int    signal     = (hasBars && bias != 0 ? GetScalpSignal(bias, signalInfo, true) : 0);

   double slDist = 0.0, tpDist = 0.0;
   string distNote = "";
   bool   distOk   = BuildStopDistances(atr, slDist, tpDist, distNote);
   double nextLots = (distOk ? CalculateLotSize(slDist, false) : 0.0);
   double rrEff    = (distOk && slDist > 0.0 ? tpDist / slDist : 0.0);

   //--- Conto e performance ---------------------------------------------
   double floating = FloatingProfit();
   double totalPL  = g_statNetProfit + floating;
   double equity   = AccountEquity();
   double balance  = AccountBalance();
   double dayPL    = g_statTodayProfit + (IncludeFloatingInDD ? floating : 0.0);
   double dayLimit = (MaxDailyLossPercent > 0.0 ? g_dayStartBalance * MaxDailyLossPercent / 100.0 : 0.0);
   double dayTarget= (DailyProfitTargetPct > 0.0 ? g_dayStartBalance * DailyProfitTargetPct / 100.0 : 0.0);
   double winRate  = (g_statTrades > 0 ? (double)g_statWins / g_statTrades * 100.0 : 0.0);
   double profFact = (g_statGrossLoss > 0.0 ? g_statGrossWin / g_statGrossLoss : 0.0);
   double drawdown = (g_peakEquity > 0.0 ? (g_peakEquity - equity) / g_peakEquity * 100.0 : 0.0);
   if(drawdown < 0.0)
      drawdown = 0.0;

   //--- KPI ---------------------------------------------------------------
   int tileH = g_rowH * 2 + 6;
   PanelTile(0, y, tileH, "eq",  "EQUITY",      DoubleToString(equity, 2),
             (equity >= balance ? PanelPositiveColor : PanelNegativeColor));
   PanelTile(1, y, tileH, "day", "OGGI",        MoneyStr(dayPL),   SignColor(dayPL));
   PanelTile(2, y, tileH, "tot", "TOTALE EA",   MoneyStr(totalPL), SignColor(totalPL));
   y += tileH + 8;

   //--- ASSETTO ------------------------------------------------------------
   //    Cio' che l'EA sta davvero applicando dopo profilo e adattamento.
   PanelSection(y, "cfg", "ASSETTO OPERATIVO");

   color profCol = (AggressionProfile == AGGR_EXTREME ? PanelNegativeColor
                   : (AggressionProfile == AGGR_AGGRESSIVE ? PanelWarningColor : PanelValueColor));
   PanelRow(y, "cprof", "Profilo", g_profileName, profCol);
   PanelRow(y, "cadapt", "Adattamento", (AutoAdaptToTimeframe ? Shorten(g_adaptNote, 26) : "disattivo"),
            PanelCaptionColor);
   PanelRow(y, "climit", "Rischio / trade max",
            DoubleToString(g_riskPercent, 2) + " %   " +
            (g_maxTradesDay > 0 ? IntegerToString(g_maxTradesDay) : "inf") + "/g  " +
            (g_maxTradesHour > 0 ? IntegerToString(g_maxTradesHour) : "inf") + "/h",
            PanelValueColor);

   //--- MERCATO -----------------------------------------------------------
   PanelSection(y, "mkt", "MERCATO   " + Symbol() + "  " + TimeframeToString(g_entryTF) +
                          " / " + TimeframeToString(g_trendTF));

   string biasText = (bias > 0 ? "RIALZO" : (bias < 0 ? "RIBASSO" : "NESSUNA"));
   color  biasCol  = (bias > 0 ? PanelPositiveColor : (bias < 0 ? PanelNegativeColor : PanelWarningColor));
   PanelRow(y, "bias", "Direzione " + TimeframeToString(g_trendTF), biasText, biasCol);

   PanelRow(y, "adx", "ADX(" + IntegerToString(ADX_Period) + ")",
            (hasBars ? DoubleToString(adx, 1) : "-"),
            (!UseADXFilter ? PanelValueColor : (adx >= g_adxMin ? PanelPositiveColor : PanelWarningColor)));

   //--- ATR corrente e, soprattutto, quanto vale rispetto alla sua media:
   //    e' il rapporto a decidere, non il valore assoluto in pips.
   double avgATR   = (hasBars ? GetAverageATR(g_entryTF, ATR_AvgPeriod, 1) : 0.0);
   double atrRatio = (avgATR > 0.0 ? atr / avgATR : 0.0);
   bool   volOutOfBand = (atrRatio > 0.0 &&
                          (atrRatio < g_minATRRatio || atrRatio > g_maxATRRatio));

   PanelRow(y, "atr", "ATR(" + IntegerToString(ATR_Period) + ") " + TimeframeToString(g_entryTF),
            (atr > 0.0 ? PipStr(atr) : "-"), PanelValueColor);

   PanelRow(y, "atrr", "ATR / media (banda " + DoubleToString(g_minATRRatio, 2) +
            "-" + DoubleToString(g_maxATRRatio, 2) + ")",
            (atrRatio > 0.0 ? DoubleToString(atrRatio, 2) + " x" : "-"),
            (atrRatio <= 0.0 ? PanelValueColor : (volOutOfBand ? PanelWarningColor : PanelPositiveColor)));

   //--- Barra dello spread rispetto al limite operativo
   double spreadLimit = g_maxSpreadPips * g_pip;
   if(g_maxSpreadATR > 0.0 && atr > 0.0)
     {
      double relLimit = atr * g_maxSpreadATR;
      if(spreadLimit <= 0.0 || relLimit < spreadLimit)
         spreadLimit = relLimit;
     }
   double spreadRatio = (spreadLimit > 0.0 ? spread / spreadLimit : 0.0);
   color  spreadCol   = (spreadRatio >= 1.0 ? PanelNegativeColor
                                            : (spreadRatio >= 0.75 ? PanelWarningColor : PanelPositiveColor));

   PanelMeter(y, "spr", "Spread  (limite " + (spreadLimit > 0.0 ? PipStr(spreadLimit) : "-") + ")",
              PipStr(spread), spreadRatio, spreadCol, spreadCol);

   PanelRow(y, "bar", "Chiusura barra M1", BarCountdown(), PanelValueColor);

   //--- SETUP: checklist dei filtri ---------------------------------------
   PanelSection(y, "flt", "FILTRI DI INGRESSO");

   bool okSession = IsSessionAllowed(true);
   bool okSpread  = IsSpreadAcceptable(true);
   bool okVol     = IsVolatilityAcceptable(true);
   bool okCounts  = AreTradeCountsOk(true);
   bool okCool    = !IsInCooldown(true);
   bool okSlots   = (openPos < MaxOpenPositions);

   PanelCheckRow(y, "fses", "Sessione operativa", okSession, (okSession ? "aperta" : "chiusa"));
   PanelCheckRow(y, "fspr", "Spread sostenibile", okSpread,  (okSpread  ? "ok" : "alto"));
   PanelCheckRow(y, "fvol", "Volatilita' in banda", okVol,   (okVol     ? "ok" : "fuori"));
   PanelCheckRow(y, "fdir", "Direzione " + TimeframeToString(g_trendTF), (bias != 0),
                 (bias != 0 ? biasText : "assente"));
   PanelCheckRow(y, "fsig", "Setup M1", (signal != 0),
                 (signal > 0 ? "LONG" : (signal < 0 ? "SHORT" : "assente")));
   PanelCheckRow(y, "fcst", "Costi coperti", distOk, (distOk ? "ok" : "no"));
   PanelCheckRow(y, "flim", "Limiti e attese", (okCounts && okCool && okSlots && !g_dailyBlocked),
                 (g_dailyBlocked ? "blocco" : (!okCounts ? "limite" : (!okCool ? "attesa" : (!okSlots ? "occupato" : "ok")))));

   //--- PIANO DEL PROSSIMO TRADE ------------------------------------------
   PanelSection(y, "pln", "PROSSIMA OPERAZIONE");
   PanelRow(y, "psl",  "Stop Loss",        (distOk ? PipStr(slDist) : "-"), (distOk ? PanelValueColor : PanelWarningColor));
   PanelRow(y, "ptp",  "Take Profit",      (distOk ? PipStr(tpDist) : "-"), (distOk ? PanelValueColor : PanelWarningColor));
   PanelRow(y, "prr",  "Rischio/Rendimento", (rrEff > 0.0 ? "1 : " + DoubleToString(rrEff, 2) : "-"),
            (rrEff >= g_minRR ? PanelPositiveColor : PanelWarningColor));
   PanelRow(y, "plot", "Volume stimato",   (nextLots > 0.0 ? DoubleToString(nextLots, g_lotDigits) : "n/d"),
            (nextLots > 0.0 ? PanelValueColor : PanelWarningColor));
   PanelRow(y, "prsk", "Rischio",          DoubleToString(g_riskPercent, 2) + " %  (" +
            DoubleToString(RiskAmount(), 2) + " " + AccountCurrency() + ")", PanelValueColor);

   //--- POSIZIONE APERTA ---------------------------------------------------
   PanelSection(y, "pos", "POSIZIONE");

   if(openPos > 0 && SelectFirstOwnPosition())
     {
      bool     isBuy     = (OrderType() == OP_BUY);
      datetime openTime  = OrderOpenTime();
      double   openPrice = OrderOpenPrice();
      double   riskDist  = RegistryRisk(openTime, openPrice, OrderStopLoss(), atr);
      double   profitPr  = (isBuy ? Bid - openPrice : openPrice - Ask);
      double   rMult     = (riskDist > 0.0 ? profitPr / riskDist : 0.0);
      double   posProfit = OrderProfit() + OrderSwap() + OrderCommission();
      int      minutes   = (int)((TimeCurrent() - openTime) / 60);

      PanelRow(y, "pdir", "Direzione / Volume",
               (isBuy ? "BUY" : "SELL") + "  " + DoubleToString(OrderLots(), g_lotDigits) + " lot",
               (isBuy ? PanelPositiveColor : PanelNegativeColor));
      PanelRow(y, "popn", "Ingresso / Durata",
               DoubleToString(openPrice, Digits) + "   " + IntegerToString(minutes) + " min",
               (g_maxTradeMin > 0 && minutes >= g_maxTradeMin - 5 ? PanelWarningColor : PanelValueColor));
      PanelRow(y, "pstp", "SL / TP",
               (OrderStopLoss() > 0.0 ? DoubleToString(OrderStopLoss(), Digits) : "-") + "  /  " +
               (OrderTakeProfit() > 0.0 ? DoubleToString(OrderTakeProfit(), Digits) : "-"), PanelValueColor);
      PanelRow(y, "ppl", "P/L aperto", MoneyStr(posProfit) + " " + AccountCurrency(), SignColor(posProfit));

      //--- Avanzamento da SL (-1R) a TP (+RewardRatio R)
      double span  = 1.0 + RewardRatio;
      double ratio = (rMult + 1.0) / (span > 0.0 ? span : 1.0);
      color  rCol  = SignColor(rMult);
      PanelMeter(y, "pr", "SL " + StringFormat("%+.2f R", rMult) + "  TP",
                 (RegistryPartialDone(openTime) ? "parziale fatta" : "intera"), ratio, rCol, PanelCaptionColor);
     }
   else
     {
      PanelRow(y, "pnone", "Stato", "nessuna posizione aperta", PanelCaptionColor);
     }

   //--- RISCHIO GIORNALIERO -------------------------------------------------
   PanelSection(y, "day", "GIORNATA");

   if(dayLimit > 0.0)
     {
      double used = (dayPL < 0.0 ? -dayPL / dayLimit : 0.0);
      PanelMeter(y, "dloss", "Perdita giornaliera consumata",
                 DoubleToString(Clamp01(used) * 100.0, 0) + " %  di " + DoubleToString(dayLimit, 2),
                 used, (used >= 0.75 ? PanelNegativeColor : PanelWarningColor), PanelValueColor);
     }

   if(dayTarget > 0.0)
     {
      double reached = (dayPL > 0.0 ? dayPL / dayTarget : 0.0);
      PanelMeter(y, "dtgt", "Target giornaliero raggiunto",
                 DoubleToString(Clamp01(reached) * 100.0, 0) + " %  di " + DoubleToString(dayTarget, 2),
                 reached, PanelPositiveColor, PanelValueColor);
     }

   if(g_maxTradesDay > 0)
      PanelMeter(y, "dtrd", "Trade usati oggi",
                 IntegerToString(g_tradesToday) + " / " + IntegerToString(g_maxTradesDay),
                 (double)g_tradesToday / g_maxTradesDay,
                 (g_tradesToday >= g_maxTradesDay ? PanelNegativeColor : PanelAccentColor), PanelValueColor);
   else
      PanelRow(y, "dtrdn", "Trade oggi", IntegerToString(g_tradesToday), PanelValueColor);

   PanelRow(y, "dhour", "Trade nell'ora",
            IntegerToString(g_tradesThisHour) + (g_maxTradesHour > 0 ? " / " + IntegerToString(g_maxTradesHour) : ""),
            (g_maxTradesHour > 0 && g_tradesThisHour >= g_maxTradesHour ? PanelNegativeColor : PanelValueColor));

   PanelRow(y, "dloss2", "Perdite consecutive",
            IntegerToString(g_consecLosses) + (g_maxConsecLoss > 0 ? " / " + IntegerToString(g_maxConsecLoss) : ""),
            (g_maxConsecLoss > 0 && g_consecLosses >= g_maxConsecLoss ? PanelNegativeColor : PanelValueColor));

   //--- STORICO DELL'EA ------------------------------------------------------
   PanelSection(y, "sta", "STORICO EA  (magic " + IntegerToString(MagicNumber) + ")");
   //--- Come nel report di MT4, una chiusura parziale e' un'operazione a se':
   //    il conteggio e' sulle operazioni, non sugli ingressi.
   PanelRow(y, "strd", "Operazioni chiuse", IntegerToString(g_statTrades) +
            "  (in utile " + IntegerToString(g_statWins) + ")", PanelValueColor);
   PanelRow(y, "swin", "Win rate operazioni", (g_statTrades > 0 ? DoubleToString(winRate, 1) + " %" : "-"),
            (g_statTrades <= 0 ? PanelValueColor : (winRate >= 45.0 ? PanelPositiveColor : PanelWarningColor)));
   PanelRow(y, "spf", "Profit factor", (profFact > 0.0 ? DoubleToString(profFact, 2) : "-"),
            (profFact <= 0.0 ? PanelValueColor : (profFact >= 1.0 ? PanelPositiveColor : PanelNegativeColor)));
   PanelRow(y, "sdd", "Drawdown da picco", DoubleToString(drawdown, 2) + " %",
            (drawdown > 10.0 ? PanelNegativeColor : (drawdown > 5.0 ? PanelWarningColor : PanelValueColor)));
   PanelRow(y, "sflt", "P/L flottante", MoneyStr(floating) + " " + AccountCurrency(), SignColor(floating));
   PanelRow(y, "stim", "Ora server", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), PanelCaptionColor);

   //--- MOTIVO DEL MANCATO INGRESSO -------------------------------------------
   PanelSection(y, "rej", "ULTIMO FILTRO ATTIVATO");

   string rejText = (g_dailyBlocked && g_dailyBlockNote != "" ? g_dailyBlockNote : g_lastReject);
   int    maxChars = (int)((PanelWidth - 2 * g_pad) / (PanelFontSize * 0.62));

   PanelText(g_prefix + "b_rej1", g_pad, y, Shorten(rejText, maxChars),
             (rejText == "-" ? PanelCaptionColor : PanelWarningColor), PanelFontSize, ANCHOR_LEFT_UPPER, PanelFont);
   y += g_rowH;

   if(StringLen(rejText) > maxChars)
     {
      PanelText(g_prefix + "b_rej2", g_pad, y,
                Shorten(StringSubstr(rejText, maxChars - 3), maxChars),
                PanelWarningColor, PanelFontSize, ANCHOR_LEFT_UPPER, PanelFont);
      y += g_rowH;
     }
   else
      ObjectDelete(0, g_prefix + "b_rej2");

   //--- Altezza definitiva del pannello
   g_panelHeight = y - PanelY + g_pad;
   ObjectSetInteger(0, g_prefix + "h_bg", OBJPROP_YSIZE, g_panelHeight);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Seleziona la prima posizione dell'EA (per la dashboard)          |
//+------------------------------------------------------------------+
bool SelectFirstOwnPosition()
  {
   for(int i = 0; i < OrdersTotal(); i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
