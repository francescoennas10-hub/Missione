//+------------------------------------------------------------------+
//|                                            AdaptiveRegimeEA.mq4   |
//|             Adaptive Market Regime Expert Advisor for MT4         |
//|                     v2.00 - XAUUSD / M5-M15 ready                 |
//|                                                                   |
//|  FILOSOFIA                                                        |
//|   L'EA non applica una strategia fissa: classifica prima il       |
//|   REGIME di mercato su un timeframe superiore (ADX + ATR + MA di  |
//|   lungo periodo) e poi entra sul timeframe operativo con la       |
//|   logica coerente:                                                |
//|     REGIME_TREND -> Trend following (cross MA + ADX/DI)           |
//|     REGIME_RANGE -> Mean reversion (RSI + Bande di Bollinger)     |
//|     REGIME_NONE  -> nessuna operazione                            |
//|                                                                   |
//|  NOVITA' DELLA v2.00                                              |
//|   1. Profilo simbolo automatico: il pip viene dedotto dalla       |
//|      classe dello strumento (Forex / oro / argento / generico),   |
//|      cosi' gli stessi parametri hanno senso su EURUSD e su XAUUSD.|
//|   2. Regime su timeframe separato: si entra su M5/M15 ma il       |
//|      contesto si legge su H1, dove l'ADX non e' rumore.           |
//|   3. MOTORE DELLE DISTANZE MINIME: prima di ogni ordine verifica  |
//|      STOPLEVEL/FREEZELEVEL del broker, di quanto costringono ad   |
//|      allargare lo stop rispetto all'ATR, se il take profit copre  |
//|      spread e commissioni e quale rischio/rendimento resta dopo   |
//|      tutti gli aggiustamenti. Se una condizione non regge,        |
//|      l'operazione viene SCARTATA invece di essere eseguita        |
//|      con un profilo di rischio degradato.                         |
//|   4. Gestione posizione in multipli di ATR (indipendente dal      |
//|      simbolo), con modalita' a pips ancora disponibile.           |
//|   5. Filtri pensati per l'intraday veloce: spread in rapporto     |
//|      all'ATR, sessione operativa, limite di trade giornalieri,    |
//|      stop giornaliero in percentuale.                             |
//+------------------------------------------------------------------+
#property copyright "Adaptive Regime EA"
#property link      ""
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Enumerazioni                                                     |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
  {
   REGIME_NONE  = 0,   // Nessun regime chiaro (nessuna operazione)
   REGIME_TREND = 1,   // Mercato direzionale
   REGIME_RANGE = 2    // Mercato laterale
  };

enum ENUM_RISK_BASE
  {
   RISK_ON_BALANCE = 0,  // Rischio calcolato sul Balance
   RISK_ON_EQUITY  = 1   // Rischio calcolato sull'Equity
  };

enum ENUM_PIP_MODE
  {
   PIP_AUTO   = 0,  // Automatico in base alla classe del simbolo
   PIP_FOREX  = 1,  // Forex classico (5/3 cifre = Point*10)
   PIP_POINT  = 2,  // 1 pip = 1 Point
   PIP_CUSTOM = 3   // Valore definito in CustomPipSize
  };

enum ENUM_MANAGE_MODE
  {
   MANAGE_ATR  = 0,  // Break-even e trailing in multipli di ATR
   MANAGE_PIPS = 1   // Break-even e trailing in pips
  };

enum ENUM_SYMBOL_CLASS
  {
   SYMBOL_FOREX  = 0,  // Coppia valutaria
   SYMBOL_GOLD   = 1,  // Oro
   SYMBOL_SILVER = 2,  // Argento
   SYMBOL_OTHER  = 3   // Indice / CFD / altro
  };

//+------------------------------------------------------------------+
//| INPUT: Timeframe operativi                                       |
//+------------------------------------------------------------------+
input string          s_tf                 = "===== TIMEFRAME =====";
input ENUM_TIMEFRAMES SignalTimeframe      = PERIOD_M15;  // Timeframe di ingresso (M5 / M15)
input ENUM_TIMEFRAMES RegimeTimeframe      = PERIOD_H1;   // Timeframe di lettura del regime
input bool            TradeOnNewBarOnly    = true;        // Valuta i segnali solo a nuova barra

//+------------------------------------------------------------------+
//| INPUT: Gestione del rischio                                      |
//+------------------------------------------------------------------+
input string          s_risk               = "===== RISK MANAGEMENT =====";
input double          RiskPercent          = 1.0;    // Rischio % del capitale per operazione
input ENUM_RISK_BASE  RiskBase             = RISK_ON_BALANCE; // Base di calcolo del rischio
input double          FixedLots            = 0.0;    // Lotto fisso (0 = calcolo automatico)
input double          MaxLotCap            = 10.0;   // Tetto massimo di lotti per operazione
input double          CommissionPerLot     = 0.0;    // Commissione round-turn per lotto (valuta conto)
input int             MagicNumber          = 20250815; // Magic Number (identificativo EA)
input string          TradeComment         = "AdaptiveRegimeEA"; // Commento ordini

//+------------------------------------------------------------------+
//| INPUT: Limiti giornalieri                                        |
//+------------------------------------------------------------------+
input string          s_daily              = "===== DAILY LIMITS =====";
input int             MaxTradesPerDay      = 6;      // Numero massimo di trade al giorno (0 = illimitato)
input double          MaxDailyLossPercent  = 3.0;    // Stop giornaliero in % del saldo (0 = disattivo)
input bool            IncludeFloatingInDD  = false;  // Includi il flottante nello stop giornaliero

//+------------------------------------------------------------------+
//| INPUT: Volatilita' e stop dinamici (ATR)                         |
//+------------------------------------------------------------------+
input string          s_atr                = "===== ATR / DYNAMIC STOPS =====";
input int             ATR_Period           = 14;     // Periodo ATR sul timeframe di ingresso
input double          ATR_Multiplier_SL    = 1.8;    // Moltiplicatore ATR per lo Stop Loss
input double          ATR_Multiplier_TP    = 3.2;    // Moltiplicatore ATR per il Take Profit
input int             ATR_AvgPeriod        = 50;     // Periodo di media ATR (misura del regime)
input double          ATR_TrendFactor      = 1.0;    // ATR/ATRmedio minimo per validare il Trend
input double          ATR_RangeFactor      = 1.2;    // ATR/ATRmedio massimo per validare il Range

//+------------------------------------------------------------------+
//| INPUT: Controllo delle distanze minime del broker                |
//| Il cuore della v2.00: decide se il trade e' ancora sensato dopo  |
//| aver applicato i vincoli imposti dal broker.                     |
//+------------------------------------------------------------------+
input string          s_dist               = "===== MIN DISTANCE CONTROL =====";
input double          StopBufferPips       = 2.0;    // Margine di sicurezza oltre lo STOPLEVEL (pips)
input double          MaxStopLevelATR      = 0.80;   // STOPLEVEL max ammesso come frazione di ATR
input double          MaxStopWideningFactor= 1.50;   // Allargamento max dello SL rispetto a 1.8*ATR
input bool            PreserveRiskReward   = true;   // Se lo SL si allarga, allarga anche il TP
input double          MinRiskReward        = 1.40;   // Rapporto R:R minimo accettato
input double          MinTPCostRatio       = 4.0;    // Il TP deve valere N volte spread+commissioni
input bool            LogRejections        = true;   // Registra nel journal i trade scartati

//+------------------------------------------------------------------+
//| INPUT: Regime filter (calcolato su RegimeTimeframe)              |
//+------------------------------------------------------------------+
input string          s_regime             = "===== REGIME FILTER =====";
input int             ADX_Period           = 14;     // Periodo ADX
input double          ADX_Threshold        = 25.0;   // Soglia ADX: sopra = Trend
input double          ADX_RangeThreshold   = 20.0;   // Soglia ADX: sotto = Range
input int             MA_Long_Period       = 200;    // MA di lungo periodo (bias strutturale)
input ENUM_MA_METHOD  MA_Long_Method       = MODE_EMA; // Metodo MA lunga
input double          RangeMaxDistanceATR  = 2.0;    // Distanza max dalla MA lunga (in ATR) per il Range

//+------------------------------------------------------------------+
//| INPUT: Strategia Trend Following                                 |
//+------------------------------------------------------------------+
input string          s_trend              = "===== TREND STRATEGY =====";
input bool            EnableTrendStrategy  = true;   // Abilita la gamba trend following
input int             MA_Fast_Period       = 20;     // MA veloce (timeframe di ingresso)
input int             MA_Slow_Period       = 50;     // MA lenta (timeframe di ingresso)
input ENUM_MA_METHOD  MA_Cross_Method      = MODE_EMA; // Metodo MA veloce/lenta
input bool            UseDIConfirmation    = true;   // Conferma con +DI / -DI

//+------------------------------------------------------------------+
//| INPUT: Strategia Mean Reversion                                  |
//+------------------------------------------------------------------+
input string          s_range              = "===== RANGE STRATEGY =====";
input bool            EnableRangeStrategy  = true;   // Abilita la gamba mean reversion
input int             RSI_Period           = 14;     // Periodo RSI
input double          RSI_Oversold         = 30.0;   // Soglia ipervenduto
input double          RSI_Overbought       = 70.0;   // Soglia ipercomprato
input int             BB_Period            = 20;     // Periodo Bande di Bollinger
input double          BB_Deviation         = 2.0;    // Deviazione standard Bollinger

//+------------------------------------------------------------------+
//| INPUT: Filtro di sessione (ora del server)                       |
//+------------------------------------------------------------------+
input string          s_session            = "===== SESSION FILTER =====";
input bool            UseSessionFilter     = true;   // Opera solo nella finestra oraria indicata
input int             SessionStartHour     = 8;      // Ora di inizio (server time)
input int             SessionEndHour       = 21;     // Ora di fine (server time, esclusa)
input int             FridayCloseHour      = 20;     // Venerdi': stop nuovi ingressi da quest'ora (0 = off)
input bool            CloseAllOnFriday     = false;  // Chiudi le posizioni al FridayCloseHour

//+------------------------------------------------------------------+
//| INPUT: Gestione della posizione                                  |
//+------------------------------------------------------------------+
input string          s_manage             = "===== POSITION MANAGEMENT =====";
input ENUM_MANAGE_MODE ManagementMode      = MANAGE_ATR; // Unita' di misura di BE e trailing
input bool            EnableBreakEven      = true;   // Attiva il Break-Even
input double          BreakEvenATR         = 0.80;   // BE dopo N * ATR di profitto (modalita' ATR)
input double          BreakEvenLockATR     = 0.10;   // Profitto bloccato al BE (N * ATR)
input double          BreakEvenPips        = 15.0;   // BE dopo N pips (modalita' PIPS)
input double          BreakEvenLockPips    = 2.0;    // Pips bloccati al BE (modalita' PIPS)
input bool            EnableTrailingStop   = true;   // Attiva il Trailing Stop
input double          TrailingStartATR     = 1.20;   // Avvio trailing dopo N * ATR (modalita' ATR)
input double          TrailingATR          = 1.00;   // Distanza del trailing (N * ATR)
input double          TrailingStepATR      = 0.20;   // Passo minimo del trailing (N * ATR)
input double          TrailingStartPips    = 20.0;   // Avvio trailing (modalita' PIPS)
input double          TrailingStopPips     = 20.0;   // Distanza trailing (modalita' PIPS)
input double          TrailingStepPips     = 5.0;    // Passo minimo trailing (modalita' PIPS)
input int             MaxOpenPositions     = 1;      // Numero massimo di posizioni contemporanee
input int             CooldownBars         = 3;      // Barre di attesa dopo l'ultimo trade

//+------------------------------------------------------------------+
//| INPUT: Esecuzione, spread e profilo del simbolo                  |
//+------------------------------------------------------------------+
input string          s_exec               = "===== EXECUTION =====";
input ENUM_PIP_MODE   PipMode              = PIP_AUTO; // Definizione del pip
input double          CustomPipSize        = 0.10;   // Pip personalizzato (se PipMode = PIP_CUSTOM)
input double          MaxSpreadPips        = 4.0;    // Spread massimo assoluto (0 = nessun filtro)
input double          MaxSpreadToATR       = 0.12;   // Spread massimo come frazione di ATR (0 = off)
input double          SlippagePips         = 3.0;    // Slippage tollerato (pips)
input int             MaxRetries           = 3;      // Tentativi di invio ordine
input int             RetryDelayMs         = 500;    // Attesa (ms) tra i tentativi
input bool            TwoStepStops         = false;  // Broker ECN: apri e poi imposta SL/TP
input bool            VerboseLog           = true;   // Log dettagliato nel journal

//+------------------------------------------------------------------+
//| INPUT: Dashboard grafica                                         |
//+------------------------------------------------------------------+
input string          s_panel              = "===== DASHBOARD =====";
input bool            ShowPanel            = true;   // Mostra la dashboard sul grafico
input int             PanelX               = 10;     // Distanza dal bordo sinistro (px)
input int             PanelY               = 20;     // Distanza dal bordo superiore (px)
input int             PanelWidth           = 300;    // Larghezza del pannello (px)
input string          PanelFont            = "Tahoma"; // Font del pannello
input int             PanelFontSize        = 8;      // Dimensione del font
input color           PanelBgColor         = clrBlack;       // Sfondo del pannello
input color           PanelBorderColor     = C'55,55,55';    // Bordo del pannello
input color           PanelSectionBgColor  = C'22,22,22';    // Sfondo delle intestazioni
input color           PanelTitleColor      = clrWhite;       // Colore del titolo
input color           PanelSectionColor    = clrDeepSkyBlue; // Colore dei titoli di sezione
input color           PanelCaptionColor    = C'150,150,150'; // Colore delle etichette
input color           PanelValueColor      = clrWhiteSmoke;  // Colore dei valori
input color           PanelPositiveColor   = C'0,220,120';   // Colore dei valori positivi
input color           PanelNegativeColor   = C'255,80,80';   // Colore dei valori negativi
input color           PanelNeutralColor    = clrGoldenrod;   // Colore dei valori di attenzione

//+------------------------------------------------------------------+
//| Variabili globali                                                |
//+------------------------------------------------------------------+
//--- Profilo del simbolo
double   g_pip            = 0.0;    // Valore di 1 pip in prezzo
double   g_pointsPerPip   = 1.0;    // Points contenuti in 1 pip
int      g_slippagePoints = 0;      // Slippage convertito in points
ENUM_SYMBOL_CLASS g_symClass = SYMBOL_FOREX; // Classe dello strumento
string   g_symClassName   = "Forex";// Etichetta della classe

//--- Parametri di volume
int      g_lotDigits      = 2;
double   g_lotStep        = 0.01;
double   g_minLot         = 0.01;
double   g_maxLot         = 100.0;

//--- Timeframe risolti
int      g_signalTF       = 0;
int      g_regimeTF       = 0;

//--- Stato operativo
datetime g_lastBarTime    = 0;
datetime g_lastTradeTime  = 0;
bool     g_initOk         = false;
string   g_lastReject     = "-";    // Ultimo motivo di scarto (per dashboard e log)

//--- Stato giornaliero
datetime g_dayStamp       = 0;      // Inizio della giornata corrente (server time)
double   g_dayStartBalance= 0.0;    // Saldo all'inizio della giornata
bool     g_dailyBlocked   = false;  // Operativita' sospesa fino a domani

//--- Dashboard
string   g_panelPrefix    = "";
int      g_rowHeight      = 16;
int      g_panelPad       = 8;

//--- Statistiche (cache)
double   g_peakEquity     = 0.0;
double   g_statNetProfit  = 0.0;
double   g_statGrossWin   = 0.0;
double   g_statGrossLoss  = 0.0;
double   g_statTodayProfit= 0.0;
int      g_statTrades     = 0;
int      g_statWins       = 0;
int      g_tradesToday    = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_initOk = false;

   //--- Timeframe: PERIOD_CURRENT viene risolto nel periodo del grafico
   g_signalTF = (SignalTimeframe == PERIOD_CURRENT) ? Period() : (int)SignalTimeframe;
   g_regimeTF = (RegimeTimeframe == PERIOD_CURRENT) ? Period() : (int)RegimeTimeframe;

   //--- Profilo del simbolo: pip, classe, slippage
   DetectSymbolProfile();

   //--- Parametri di volume del broker
   g_lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   g_minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   g_maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   if(g_lotStep <= 0.0) g_lotStep = 0.01;
   if(g_minLot  <= 0.0) g_minLot  = g_lotStep;
   if(g_maxLot  <= 0.0) g_maxLot  = 100.0;
   g_lotDigits = VolumeDigits(g_lotStep);

   //--- Validazione
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   g_lastBarTime = iTime(Symbol(), g_signalTF, 0);

   //--- Stato giornaliero e dashboard
   ResetDailyState(true);
   g_panelPrefix = "ARE" + IntegerToString(MagicNumber) + "_";
   g_rowHeight   = PanelFontSize + 8;
   g_peakEquity  = AccountEquity();

   Comment("");
   if(ShowPanel)
      UpdatePanel();

   g_initOk = true;

   Print("[", TradeComment, "] Init OK | ", Symbol(), " (", g_symClassName, ")",
         " Digits=", Digits,
         " Point=", DoubleToString(Point, 8),
         " Pip=", DoubleToString(g_pip, Digits),
         " | Ingresso=", TimeframeToString(g_signalTF),
         " Regime=", TimeframeToString(g_regimeTF),
         " | StopLevel=", DoubleToString(MarketInfo(Symbol(), MODE_STOPLEVEL), 0), " points",
         " (", DoubleToString(MarketInfo(Symbol(), MODE_STOPLEVEL) * Point / g_pip, 1), " pips)",
         " | Lotti: step=", DoubleToString(g_lotStep, g_lotDigits),
         " min=", DoubleToString(g_minLot, g_lotDigits),
         " max=", DoubleToString(g_maxLot, g_lotDigits),
         " | Magic=", MagicNumber);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("[", TradeComment, "] Deinit, motivo=", reason, " (", DeinitReasonText(reason), ")");
   DeletePanel();
   Comment("");
  }

//+------------------------------------------------------------------+
//| OnTick - Ciclo principale                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_initOk)
      return;

   //--- 1) Gestione delle posizioni aperte: lavora su ogni tick
   ManageOpenPositions();

   //--- 2) Stato giornaliero (rollover di giornata, limiti, statistiche)
   ResetDailyState(false);

   if(AccountEquity() > g_peakEquity)
      g_peakEquity = AccountEquity();

   //--- 3) Chiusura del venerdi', se richiesta
   if(CloseAllOnFriday && FridayCloseHour > 0 &&
      DayOfWeek() == 5 && TimeHour(TimeCurrent()) >= FridayCloseHour)
      CloseAllOwnPositions("chiusura di fine settimana");

   //--- 4) Dashboard
   if(ShowPanel && (!IsTesting() || IsVisualMode()))
      UpdatePanel();

   //--- 5) Condizioni generali di operativita'
   if(!IsTradeAllowed() || IsTradeContextBusy())
      return;

   if(!HasEnoughBars())
      return;

   //--- 6) Valutazione dei segnali solo a nuova barra del timeframe di ingresso
   datetime barTime = iTime(Symbol(), g_signalTF, 0);
   if(TradeOnNewBarOnly)
     {
      if(barTime == g_lastBarTime)
         return;
      g_lastBarTime = barTime;
     }

   //--- 7) Filtri di contesto (ordine dal piu' economico al piu' costoso)
   if(CountOwnPositions() >= MaxOpenPositions)
      return;

   if(g_dailyBlocked)
      return;

   if(MaxTradesPerDay > 0 && g_tradesToday >= MaxTradesPerDay)
     {
      SetReject("limite di " + IntegerToString(MaxTradesPerDay) + " trade giornalieri raggiunto");
      return;
     }

   if(!IsSessionAllowed())
      return;

   if(IsInCooldown())
      return;

   if(!IsSpreadAcceptable())
      return;

   //--- 8) Regime e segnale coerente
   ENUM_MARKET_REGIME regime = DetectMarketRegime();
   if(regime == REGIME_NONE)
      return;

   int signal = 0;
   if(regime == REGIME_TREND && EnableTrendStrategy)
      signal = GetTrendSignal();
   else
      if(regime == REGIME_RANGE && EnableRangeStrategy)
         signal = GetRangeSignal();

   if(signal == 0)
      return;

   //--- 9) Esecuzione
   OpenPosition((signal > 0 ? OP_BUY : OP_SELL), regime);
  }

//+------------------------------------------------------------------+
//| PROFILO DEL SIMBOLO                                              |
//| Deduce la classe dello strumento e il valore di 1 pip, cosi' che |
//| gli stessi parametri restino sensati su Forex e su metalli.      |
//+------------------------------------------------------------------+
void DetectSymbolProfile()
  {
   string sym = Symbol();
   StringToUpper(sym);

   //--- Classificazione
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

   //--- Valore del pip
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
            g_pip = 0.10;                 // convenzione: 1 pip oro = 0.10 USD
         else
            if(g_symClass == SYMBOL_SILVER)
               g_pip = 0.01;              // 1 pip argento = 0.01 USD
            else
               g_pip = ((Digits == 3 || Digits == 5) ? Point * 10.0 : Point);
         break;
     }

   //--- Coerenza: il pip non puo' essere piu' piccolo di un point
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

   if(RiskPercent > 20.0)
     { Print("ERRORE INPUT: RiskPercent troppo elevato (max consigliato 20%)."); ok = false; }

   if(ATR_Period < 1 || ATR_AvgPeriod < 1)
     { Print("ERRORE INPUT: ATR_Period e ATR_AvgPeriod devono essere >= 1."); ok = false; }

   if(ATR_Multiplier_SL <= 0.0 || ATR_Multiplier_TP <= 0.0)
     { Print("ERRORE INPUT: i moltiplicatori ATR devono essere > 0."); ok = false; }

   if(ATR_Multiplier_TP <= ATR_Multiplier_SL)
     { Print("ATTENZIONE: ATR_Multiplier_TP <= ATR_Multiplier_SL, il rapporto R:R nasce sotto 1."); }

   if(ADX_Period < 1)
     { Print("ERRORE INPUT: ADX_Period deve essere >= 1."); ok = false; }

   if(ADX_RangeThreshold > ADX_Threshold)
     { Print("ERRORE INPUT: ADX_RangeThreshold deve essere <= ADX_Threshold."); ok = false; }

   if(MA_Fast_Period < 1 || MA_Slow_Period < 1 || MA_Long_Period < 1)
     { Print("ERRORE INPUT: i periodi delle medie mobili devono essere >= 1."); ok = false; }

   if(MA_Fast_Period >= MA_Slow_Period)
     { Print("ERRORE INPUT: MA_Fast_Period deve essere < MA_Slow_Period."); ok = false; }

   if(RSI_Period < 2 || BB_Period < 2)
     { Print("ERRORE INPUT: RSI_Period e BB_Period devono essere >= 2."); ok = false; }

   if(RSI_Oversold <= 0.0 || RSI_Overbought >= 100.0 || RSI_Oversold >= RSI_Overbought)
     { Print("ERRORE INPUT: soglie RSI non valide."); ok = false; }

   if(BB_Deviation <= 0.0)
     { Print("ERRORE INPUT: BB_Deviation deve essere > 0."); ok = false; }

   if(MaxOpenPositions < 1)
     { Print("ERRORE INPUT: MaxOpenPositions deve essere >= 1."); ok = false; }

   if(MaxRetries < 1)
     { Print("ERRORE INPUT: MaxRetries deve essere >= 1."); ok = false; }

   if(!EnableTrendStrategy && !EnableRangeStrategy)
     { Print("ERRORE INPUT: entrambe le strategie disabilitate, l'EA non potrebbe operare."); ok = false; }

   if(UseSessionFilter && (SessionStartHour < 0 || SessionStartHour > 23 ||
                           SessionEndHour   < 0 || SessionEndHour   > 23))
     { Print("ERRORE INPUT: ore di sessione fuori dall'intervallo 0-23."); ok = false; }

   if(ManagementMode == MANAGE_ATR)
     {
      if(EnableBreakEven && BreakEvenATR <= 0.0)
        { Print("ERRORE INPUT: BreakEvenATR deve essere > 0."); ok = false; }
      if(EnableTrailingStop && TrailingATR <= 0.0)
        { Print("ERRORE INPUT: TrailingATR deve essere > 0."); ok = false; }
     }
   else
     {
      if(EnableBreakEven && BreakEvenPips <= 0.0)
        { Print("ERRORE INPUT: BreakEvenPips deve essere > 0."); ok = false; }
      if(EnableTrailingStop && TrailingStopPips <= 0.0)
        { Print("ERRORE INPUT: TrailingStopPips deve essere > 0."); ok = false; }
     }

   if(MinRiskReward > 0.0 && MinRiskReward > ATR_Multiplier_TP / ATR_Multiplier_SL)
     { Print("ATTENZIONE: MinRiskReward (", DoubleToString(MinRiskReward, 2),
             ") e' superiore al R:R nominale (", DoubleToString(ATR_Multiplier_TP / ATR_Multiplier_SL, 2),
             "): senza PreserveRiskReward molti trade verranno scartati."); }

   //--- Avviso specifico per timeframe rapidi: verifica del costo rispetto allo stop
   if(g_signalTF <= PERIOD_M15)
     {
      double spread = MathMax(Ask - Bid, 0.0);
      if(spread > 0.0)
         Print("[", TradeComment, "] Nota TF rapido: spread attuale ",
               DoubleToString(spread / g_pip, 1), " pips. Su ", TimeframeToString(g_signalTF),
               " il filtro MaxSpreadToATR (", DoubleToString(MaxSpreadToATR, 2),
               ") e' la difesa principale contro i costi di transazione.");
     }

   return(ok);
  }

//+------------------------------------------------------------------+
//| Storico sufficiente su entrambi i timeframe                      |
//+------------------------------------------------------------------+
bool HasEnoughBars()
  {
   int needSignal = (int)MathMax(MA_Slow_Period, MathMax(BB_Period, MathMax(RSI_Period, ATR_Period))) + 10;
   int needRegime = (int)MathMax(MA_Long_Period, ATR_Period + ATR_AvgPeriod) + ADX_Period + 10;

   bool ok = true;
   if(iBars(Symbol(), g_signalTF) < needSignal) ok = false;
   if(iBars(Symbol(), g_regimeTF) < needRegime) ok = false;

   if(!ok)
     {
      static datetime lastWarn = 0;
      if(VerboseLog && TimeCurrent() - lastWarn > 300)
        {
         lastWarn = TimeCurrent();
         Print("[", TradeComment, "] Storico insufficiente: ",
               TimeframeToString(g_signalTF), " ", iBars(Symbol(), g_signalTF), "/", needSignal, " barre, ",
               TimeframeToString(g_regimeTF), " ", iBars(Symbol(), g_regimeTF), "/", needRegime, " barre.");
        }
     }
   return(ok);
  }

//+------------------------------------------------------------------+
//| REGIME FILTER - calcolato sul timeframe superiore                |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME DetectMarketRegime()
  {
   double adx    = iADX(Symbol(), g_regimeTF, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   double atr    = iATR(Symbol(), g_regimeTF, ATR_Period, 1);
   double atrAvg = GetAverageATR(g_regimeTF, ATR_AvgPeriod, 1);
   double maLong = iMA(Symbol(), g_regimeTF, MA_Long_Period, 0, MA_Long_Method, PRICE_CLOSE, 1);
   double close  = iClose(Symbol(), g_regimeTF, 1);

   if(atr <= 0.0 || atrAvg <= 0.0 || maLong <= 0.0)
      return(REGIME_NONE);

   double atrRatio = atr / atrAvg;                    // espansione / compressione
   double distToMA = MathAbs(close - maLong) / atr;   // distanza dalla MA lunga in ATR

   //--- TREND
   if(adx >= ADX_Threshold && atrRatio >= ATR_TrendFactor && distToMA >= 0.5)
      return(REGIME_TREND);

   //--- RANGE
   if(adx <= ADX_RangeThreshold && atrRatio <= ATR_RangeFactor && distToMA <= RangeMaxDistanceATR)
      return(REGIME_RANGE);

   //--- Zona grigia
   return(REGIME_NONE);
  }

//+------------------------------------------------------------------+
//| SEGNALE TREND (timeframe di ingresso)                            |
//+------------------------------------------------------------------+
int GetTrendSignal()
  {
   double fast1 = iMA(Symbol(), g_signalTF, MA_Fast_Period, 0, MA_Cross_Method, PRICE_CLOSE, 1);
   double fast2 = iMA(Symbol(), g_signalTF, MA_Fast_Period, 0, MA_Cross_Method, PRICE_CLOSE, 2);
   double slow1 = iMA(Symbol(), g_signalTF, MA_Slow_Period, 0, MA_Cross_Method, PRICE_CLOSE, 1);
   double slow2 = iMA(Symbol(), g_signalTF, MA_Slow_Period, 0, MA_Cross_Method, PRICE_CLOSE, 2);

   //--- Bias strutturale letto sul timeframe del regime
   double maLong  = iMA(Symbol(), g_regimeTF, MA_Long_Period, 0, MA_Long_Method, PRICE_CLOSE, 1);
   double closeR  = iClose(Symbol(), g_regimeTF, 1);

   double plusDI  = iADX(Symbol(), g_regimeTF, ADX_Period, PRICE_CLOSE, MODE_PLUSDI,  1);
   double minusDI = iADX(Symbol(), g_regimeTF, ADX_Period, PRICE_CLOSE, MODE_MINUSDI, 1);

   bool crossUp   = (fast2 <= slow2 && fast1 > slow1);
   bool crossDown = (fast2 >= slow2 && fast1 < slow1);

   bool diLong    = (!UseDIConfirmation || plusDI  > minusDI);
   bool diShort   = (!UseDIConfirmation || minusDI > plusDI);

   if(crossUp && closeR > maLong && diLong)
     {
      LogSignal("TREND", "BUY", "cross MA up + prezzo sopra MA lunga + DI+");
      return(1);
     }

   if(crossDown && closeR < maLong && diShort)
     {
      LogSignal("TREND", "SELL", "cross MA down + prezzo sotto MA lunga + DI-");
      return(-1);
     }

   return(0);
  }

//+------------------------------------------------------------------+
//| SEGNALE RANGE (timeframe di ingresso)                            |
//+------------------------------------------------------------------+
int GetRangeSignal()
  {
   double upper1 = iBands(Symbol(), g_signalTF, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double lower1 = iBands(Symbol(), g_signalTF, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double upper2 = iBands(Symbol(), g_signalTF, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double lower2 = iBands(Symbol(), g_signalTF, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_LOWER, 2);

   double rsi1   = iRSI(Symbol(), g_signalTF, RSI_Period, PRICE_CLOSE, 1);
   double rsi2   = iRSI(Symbol(), g_signalTF, RSI_Period, PRICE_CLOSE, 2);

   double close1 = iClose(Symbol(), g_signalTF, 1);
   double close2 = iClose(Symbol(), g_signalTF, 2);
   double low1   = iLow(Symbol(),   g_signalTF, 1);
   double high1  = iHigh(Symbol(),  g_signalTF, 1);

   if(upper1 <= 0.0 || lower1 <= 0.0 || upper2 <= 0.0 || lower2 <= 0.0)
      return(0);

   //--- Long: estensione sotto la banda, RSI ipervenduto in ripresa, rientro nel canale
   bool touchedLower = (low1 <= lower1 || close2 < lower2);
   if(touchedLower && rsi1 <= RSI_Oversold && rsi1 > rsi2 && close1 > lower1)
     {
      LogSignal("RANGE", "BUY", "rifiuto banda inferiore + RSI ipervenduto in ripresa");
      return(1);
     }

   //--- Short: speculare
   bool touchedUpper = (high1 >= upper1 || close2 > upper2);
   if(touchedUpper && rsi1 >= RSI_Overbought && rsi1 < rsi2 && close1 < upper1)
     {
      LogSignal("RANGE", "SELL", "rifiuto banda superiore + RSI ipercomprato in flessione");
      return(-1);
     }

   return(0);
  }

//+------------------------------------------------------------------+
//| DISTANZA MINIMA IMPOSTA DAL BROKER                               |
//| STOPLEVEL / FREEZELEVEL + spread + margine di sicurezza.         |
//+------------------------------------------------------------------+
double BrokerMinStopDistance()
  {
   double stopLevel   = MarketInfo(Symbol(), MODE_STOPLEVEL)   * Point;
   double freezeLevel = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
   double spread      = MathMax(Ask - Bid, 0.0);

   double minDist = MathMax(stopLevel, freezeLevel) + spread + StopBufferPips * g_pip;

   //--- Non scendere mai sotto 1 pip
   if(minDist < g_pip)
      minDist = g_pip;

   return(NormalizeDouble(minDist, Digits));
  }

//+------------------------------------------------------------------+
//| Distanza di prezzo equivalente al costo di commissione per lotto |
//+------------------------------------------------------------------+
double CommissionPriceEquivalent()
  {
   if(CommissionPerLot <= 0.0)
      return(0.0);

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0)
      return(0.0);

   //--- Perdita per lotto su distanza d = (d / tickSize) * tickValue  ->  d = C * tickSize / tickValue
   return(CommissionPerLot * tickSize / tickValue);
  }

//+------------------------------------------------------------------+
//| MOTORE DELLE DISTANZE                                            |
//| Costruisce SL e TP partendo dall'ATR e li confronta con i        |
//| vincoli del broker. Restituisce false quando il trade non e'     |
//| piu' sensato: meglio nessuna operazione che un'operazione con    |
//| rischio/rendimento degradato dai vincoli tecnici.                |
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

   double baseSL   = atr * ATR_Multiplier_SL;
   double baseTP   = atr * ATR_Multiplier_TP;
   double minDist  = BrokerMinStopDistance();
   double spread   = MathMax(Ask - Bid, 0.0);
   double commDist = CommissionPriceEquivalent();
   double nominalRR= ATR_Multiplier_TP / ATR_Multiplier_SL;

   //--- CONTROLLO 1: il vincolo del broker e' compatibile con la volatilita' del timeframe?
   //    Uno STOPLEVEL che vale quasi quanto l'ATR rende impossibile uno stop tecnico:
   //    su M5/M15 e' la causa piu' frequente di stop innaturalmente larghi.
   if(MaxStopLevelATR > 0.0 && minDist > atr * MaxStopLevelATR)
     {
      note = StringFormat("distanza minima broker %.1f pips > %.0f%% dell'ATR (%.1f pips): timeframe troppo stretto per questo broker",
                          minDist / g_pip, MaxStopLevelATR * 100.0, atr / g_pip);
      return(false);
     }

   //--- Stop tecnico, allargato al minimo consentito se necessario
   slDistance    = baseSL;
   bool widened  = false;
   if(slDistance < minDist)
     {
      slDistance = minDist;
      widened    = true;
     }

   //--- CONTROLLO 2: di quanto il vincolo ha allargato lo stop teorico?
   //    Oltre la soglia il rischio per trade resta l'1% ma il lotto crolla e il
   //    trade perde ogni relazione con la volatilita' che lo ha generato.
   if(widened && MaxStopWideningFactor > 0.0 && slDistance > baseSL * MaxStopWideningFactor)
     {
      note = StringFormat("SL allargato da %.1f a %.1f pips (x%.2f) oltre il limite x%.2f",
                          baseSL / g_pip, slDistance / g_pip, slDistance / baseSL, MaxStopWideningFactor);
      slDistance = 0.0;
      return(false);
     }

   //--- Take profit: se lo SL e' stato allargato, il TP lo segue per non
   //    schiacciare il rapporto rischio/rendimento.
   if(PreserveRiskReward)
      tpDistance = slDistance * nominalRR;
   else
      tpDistance = baseTP;

   if(tpDistance < minDist)
      tpDistance = minDist;

   //--- CONTROLLO 3: il target copre i costi di transazione con margine?
   double cost = spread + commDist;
   if(MinTPCostRatio > 0.0 && cost > 0.0 && tpDistance < cost * MinTPCostRatio)
     {
      note = StringFormat("TP %.1f pips insufficiente: costo operazione %.1f pips (x%.1f richiesto x%.1f)",
                          tpDistance / g_pip, cost / g_pip, tpDistance / cost, MinTPCostRatio);
      slDistance = 0.0;
      tpDistance = 0.0;
      return(false);
     }

   //--- CONTROLLO 4: rapporto rischio/rendimento effettivo dopo ogni aggiustamento
   double rr = tpDistance / slDistance;
   if(MinRiskReward > 0.0 && rr < MinRiskReward)
     {
      note = StringFormat("R:R effettivo 1:%.2f sotto il minimo 1:%.2f", rr, MinRiskReward);
      slDistance = 0.0;
      tpDistance = 0.0;
      return(false);
     }

   //--- Normalizzazione finale
   slDistance = NormalizeDouble(slDistance, Digits);
   tpDistance = NormalizeDouble(tpDistance, Digits);

   if(widened)
      note = StringFormat("SL allargato al minimo broker: %.1f pips (teorico %.1f), R:R 1:%.2f",
                          slDistance / g_pip, baseSL / g_pip, rr);
   else
      note = StringFormat("SL %.1f pips, TP %.1f pips, R:R 1:%.2f",
                          slDistance / g_pip, tpDistance / g_pip, rr);

   return(true);
  }

//+------------------------------------------------------------------+
//| Apertura della posizione                                         |
//+------------------------------------------------------------------+
bool OpenPosition(int orderType, ENUM_MARKET_REGIME regime)
  {
   RefreshRates();

   double atr = GetATR(g_signalTF, 1);

   //--- Costruzione e validazione delle distanze
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

   //--- Il sizing usa la distanza reale dopo la normalizzazione
   double effectiveSL = MathAbs(price - sl);
   if(effectiveSL <= 0.0)
     {
      SetReject("distanza SL nulla dopo la normalizzazione");
      return(false);
     }

   double lots = CalculateLotSize(effectiveSL);
   if(lots <= 0.0)
     {
      SetReject("volume non calcolabile per il rischio richiesto");
      return(false);
     }

   string comment = TradeComment + (regime == REGIME_TREND ? "-TRD" : "-RNG");

   if(VerboseLog)
      Print("[", TradeComment, "] Invio ", (orderType == OP_BUY ? "BUY" : "SELL"),
            " | Regime=", RegimeToString(regime),
            " | Lots=", DoubleToString(lots, g_lotDigits),
            " | Price=", DoubleToString(price, Digits),
            " SL=", DoubleToString(sl, Digits),
            " TP=", DoubleToString(tp, Digits),
            " | ATR=", DoubleToString(atr / g_pip, 1), " pips",
            " | ", note,
            " | Rischio=", DoubleToString(RiskAmount(), 2), " ", AccountCurrency());

   int ticket = SendOrderWithRetries(orderType, lots, price, sl, tp, comment);

   if(ticket > 0)
     {
      g_lastTradeTime = TimeCurrent();
      g_tradesToday++;
      g_lastReject = "-";
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

      //--- Distanze conservate, prezzi riallineati al mercato corrente
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

      //--- Errore 130: stop rifiutati. Apertura senza stop + modifica immediata.
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

      if(MathAbs(OrderStopLoss() - newSL) < Point / 2.0 && MathAbs(OrderTakeProfit() - newTP) < Point / 2.0)
         return(true);

      ResetLastError();
      if(OrderModify(ticket, OrderOpenPrice(), newSL, newTP, 0, clrLimeGreen))
        {
         if(VerboseLog)
            Print("[", TradeComment, "] OrderModify OK. Ticket=", ticket,
                  " SL=", DoubleToString(newSL, Digits), " TP=", DoubleToString(newTP, Digits));
         return(true);
        }

      int err = GetLastError();
      if(err == 1)
         return(true);

      Print("[", TradeComment, "] OrderModify fallito (tentativo ", attempt, "/", MaxRetries,
            ") ticket ", ticket, " errore ", err, ": ", ErrorDescription(err));

      if(!IsRetryableError(err))
         break;

      Sleep(RetryDelayMs * attempt);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Chiusura di una posizione                                        |
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
   return(capital * RiskPercent / 100.0);
  }

//+------------------------------------------------------------------+
//| GESTIONE POSIZIONI: Break-Even e Trailing Stop                   |
//| In modalita' ATR le soglie seguono la volatilita' corrente,      |
//| quindi non vanno ritarate cambiando simbolo o timeframe.         |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   if(!EnableBreakEven && !EnableTrailingStop)
      return;

   //--- Soglie espresse in prezzo
   double atr = GetATR(g_signalTF, 1);

   double beTrigger, beLock, trailStart, trailDist, trailStep;

   if(ManagementMode == MANAGE_ATR)
     {
      if(atr <= 0.0)
         return;
      beTrigger  = atr * BreakEvenATR;
      beLock     = atr * BreakEvenLockATR;
      trailStart = atr * TrailingStartATR;
      trailDist  = atr * TrailingATR;
      trailStep  = atr * TrailingStepATR;
     }
   else
     {
      beTrigger  = BreakEvenPips     * g_pip;
      beLock     = BreakEvenLockPips * g_pip;
      trailStart = TrailingStartPips * g_pip;
      trailDist  = TrailingStopPips  * g_pip;
      trailStep  = TrailingStepPips  * g_pip;
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      RefreshRates();

      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      double newSL     = currentSL;
      double minDist   = BrokerMinStopDistance();
      double freeze    = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;

      if(OrderType() == OP_BUY)
        {
         double profit = Bid - openPrice;

         //--- Break-even
         if(EnableBreakEven && profit >= beTrigger)
           {
            double bePrice = NormalizeDouble(openPrice + beLock, Digits);
            if(bePrice > newSL + Point / 2.0 && Bid - bePrice >= minDist)
               newSL = bePrice;
           }

         //--- Trailing
         if(EnableTrailingStop && profit >= trailStart)
           {
            double trailPrice = NormalizeDouble(Bid - trailDist, Digits);
            if(trailPrice > newSL + trailStep - Point / 2.0 && Bid - trailPrice >= minDist)
               newSL = trailPrice;
           }

         //--- Lo stop non arretra mai
         if(currentSL > 0.0 && newSL < currentSL + Point / 2.0)
            newSL = currentSL;

         if(newSL > currentSL + Point / 2.0)
           {
            if(freeze > 0.0 && Bid - newSL < freeze)
               continue;
            ModifyOrderWithRetries(OrderTicket(), newSL, OrderTakeProfit());
           }
        }
      else // OP_SELL
        {
         double profitS = openPrice - Ask;

         if(EnableBreakEven && profitS >= beTrigger)
           {
            double bePriceS = NormalizeDouble(openPrice - beLock, Digits);
            if((newSL <= 0.0 || bePriceS < newSL - Point / 2.0) && bePriceS - Ask >= minDist)
               newSL = bePriceS;
           }

         if(EnableTrailingStop && profitS >= trailStart)
           {
            double trailPriceS = NormalizeDouble(Ask + trailDist, Digits);
            if((newSL <= 0.0 || trailPriceS < newSL - trailStep + Point / 2.0) && trailPriceS - Ask >= minDist)
               newSL = trailPriceS;
           }

         if(currentSL > 0.0 && newSL > currentSL - Point / 2.0)
            newSL = currentSL;

         if(newSL > 0.0 && (currentSL <= 0.0 || newSL < currentSL - Point / 2.0))
           {
            if(freeze > 0.0 && newSL - Ask < freeze)
               continue;
            ModifyOrderWithRetries(OrderTicket(), newSL, OrderTakeProfit());
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
//| Cooldown in barre dopo l'ultimo trade                            |
//+------------------------------------------------------------------+
bool IsInCooldown()
  {
   if(CooldownBars <= 0)
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

   return(iBarShift(Symbol(), g_signalTF, reference, false) < CooldownBars);
  }

//+------------------------------------------------------------------+
//| Filtro spread: soglia assoluta e soglia relativa all'ATR         |
//| Su M5/M15 la seconda e' quella che conta davvero.                |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
  {
   double spread = MathMax(Ask - Bid, 0.0);

   if(MaxSpreadPips > 0.0 && spread / g_pip > MaxSpreadPips)
     {
      SetReject(StringFormat("spread %.1f pips oltre il massimo assoluto %.1f",
                             spread / g_pip, MaxSpreadPips));
      return(false);
     }

   if(MaxSpreadToATR > 0.0)
     {
      double atr = GetATR(g_signalTF, 1);
      if(atr > 0.0 && spread > atr * MaxSpreadToATR)
        {
         SetReject(StringFormat("spread %.1f pips = %.0f%% dell'ATR (max %.0f%%)",
                                spread / g_pip, spread / atr * 100.0, MaxSpreadToATR * 100.0));
         return(false);
        }
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Filtro di sessione (ora del server)                              |
//+------------------------------------------------------------------+
bool IsSessionAllowed()
  {
   int hour = TimeHour(TimeCurrent());
   int dow  = DayOfWeek();

   //--- Venerdi': niente nuovi ingressi oltre l'orario indicato
   if(FridayCloseHour > 0 && dow == 5 && hour >= FridayCloseHour)
     {
      SetReject("chiusura settimanale: nessun nuovo ingresso il venerdi' dalle " +
                IntegerToString(FridayCloseHour));
      return(false);
     }

   if(!UseSessionFilter)
      return(true);

   if(SessionStartHour == SessionEndHour)
      return(true);

   bool inside;
   if(SessionStartHour < SessionEndHour)
      inside = (hour >= SessionStartHour && hour < SessionEndHour);
   else
      inside = (hour >= SessionStartHour || hour < SessionEndHour); // sessione a cavallo di mezzanotte

   if(!inside)
      SetReject(StringFormat("fuori sessione operativa (%02d:00-%02d:00 server)",
                             SessionStartHour, SessionEndHour));

   return(inside);
  }

//+------------------------------------------------------------------+
//| Stato giornaliero: rollover, statistiche, stop giornaliero       |
//+------------------------------------------------------------------+
void ResetDailyState(bool force)
  {
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);

   if(force || today != g_dayStamp)
     {
      g_dayStamp        = today;
      g_dayStartBalance = AccountBalance();
      g_dailyBlocked    = false;
      if(!force)
         Print("[", TradeComment, "] Nuova giornata di trading. Saldo iniziale: ",
               DoubleToString(g_dayStartBalance, 2), " ", AccountCurrency());
     }

   //--- Aggiorna statistiche e conteggio trade odierni (con cache interna)
   UpdateTradeStats();

   //--- Stop giornaliero
   if(!g_dailyBlocked && MaxDailyLossPercent > 0.0 && g_dayStartBalance > 0.0)
     {
      double dayPL = g_statTodayProfit + (IncludeFloatingInDD ? FloatingProfit() : 0.0);
      double limit = g_dayStartBalance * MaxDailyLossPercent / 100.0;

      if(dayPL <= -limit)
        {
         g_dailyBlocked = true;
         SetReject(StringFormat("stop giornaliero raggiunto: %.2f %s (limite %.2f)",
                                dayPL, AccountCurrency(), -limit));
         Print("[", TradeComment, "] STOP GIORNALIERO: perdita ", DoubleToString(dayPL, 2),
               " ", AccountCurrency(), " sul limite di ", DoubleToString(limit, 2),
               ". Nessun nuovo ingresso fino a domani.");
        }
     }
  }

//+------------------------------------------------------------------+
//| Registra il motivo dell'ultimo scarto                            |
//+------------------------------------------------------------------+
void SetReject(string reason)
  {
   if(reason == "")
      return;

   if(LogRejections && VerboseLog && reason != g_lastReject)
      Print("[", TradeComment, "] Trade non eseguito: ", reason);

   g_lastReject = reason;
  }

//+------------------------------------------------------------------+
//| ATR su un timeframe indicato                                     |
//+------------------------------------------------------------------+
double GetATR(int timeframe, int shift)
  {
   return(iATR(Symbol(), timeframe, ATR_Period, shift));
  }

//+------------------------------------------------------------------+
//| Media dell'ATR su N barre                                        |
//+------------------------------------------------------------------+
double GetAverageATR(int timeframe, int period, int startShift)
  {
   if(period < 1)
      return(0.0);

   double sum = 0.0;
   for(int i = 0; i < period; i++)
      sum += iATR(Symbol(), timeframe, ATR_Period, startShift + i);

   return(sum / period);
  }

//+------------------------------------------------------------------+
//| Attesa del contesto di trading                                   |
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

//+------------------------------------------------------------------+
//| Errori per i quali ha senso ritentare                            |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Descrizione dei codici di errore                                 |
//+------------------------------------------------------------------+
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
      case 4110: return("acquisti a lungo termine non consentiti");
      case 4111: return("vendite a lungo termine non consentite");
     }
   return("errore non catalogato");
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
      case REASON_CHARTCHANGE: return("simbolo o timeframe modificato");
      case REASON_CHARTCLOSE:  return("grafico chiuso");
      case REASON_PARAMETERS:  return("parametri modificati");
      case REASON_ACCOUNT:     return("account cambiato");
     }
   return("motivo sconosciuto");
  }

//+------------------------------------------------------------------+
//| Utility di formattazione                                         |
//+------------------------------------------------------------------+
string RegimeToString(ENUM_MARKET_REGIME regime)
  {
   if(regime == REGIME_TREND) return("TREND");
   if(regime == REGIME_RANGE) return("RANGE");
   return("NESSUNO");
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

//--- Distanza in pips, con il prezzo tra parentesi sui metalli
string DistStr(double priceDistance)
  {
   if(priceDistance <= 0.0)
      return("-");

   string txt = DoubleToString(priceDistance / g_pip, 1) + " p";
   if(g_symClass == SYMBOL_GOLD || g_symClass == SYMBOL_SILVER)
      txt += " ($" + DoubleToString(priceDistance, 2) + ")";
   return(txt);
  }

void LogSignal(string regime, string side, string reason)
  {
   if(VerboseLog)
      Print("[", TradeComment, "] Segnale ", side, " in regime ", regime, ": ", reason);
  }

//+------------------------------------------------------------------+
//|                        DASHBOARD GRAFICA                         |
//+------------------------------------------------------------------+
void PanelRect(string name, int x, int y, int w, int h, color bg, color border, int zorder)
  {
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return;

   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
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

void PanelText(string name, int x, int y, string text, color clr, int fontSize, int anchor)
  {
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;

   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     anchor);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     3);
   ObjectSetString(0,  name, OBJPROP_FONT,       PanelFont);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
  }

void PanelSection(int &y, string id, string title)
  {
   PanelRect(g_panelPrefix + "sec_" + id, PanelX + 1, y - 2, PanelWidth - 2, g_rowHeight + 2,
             PanelSectionBgColor, PanelSectionBgColor, 1);
   PanelText(g_panelPrefix + "sect_" + id, PanelX + g_panelPad, y + 1, title,
             PanelSectionColor, PanelFontSize, ANCHOR_LEFT_UPPER);
   y += g_rowHeight + 4;
  }

void PanelRow(int &y, string id, string caption, string value, color valueColor)
  {
   PanelText(g_panelPrefix + "cap_" + id, PanelX + g_panelPad, y, caption,
             PanelCaptionColor, PanelFontSize, ANCHOR_LEFT_UPPER);
   PanelText(g_panelPrefix + "val_" + id, PanelX + PanelWidth - g_panelPad, y, value,
             valueColor, PanelFontSize, ANCHOR_RIGHT_UPPER);
   y += g_rowHeight;
  }

void DeletePanel()
  {
   //--- Salvaguardia: senza prefisso il ciclo cancellerebbe ogni oggetto del grafico
   if(StringLen(g_panelPrefix) == 0)
      return;

   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_panelPrefix, 0) == 0)
         ObjectDelete(0, name);
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Statistiche sui trade dell'EA (con cache)                        |
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

   g_statNetProfit   = 0.0;
   g_statGrossWin    = 0.0;
   g_statGrossLoss   = 0.0;
   g_statTodayProfit = 0.0;
   g_statTrades      = 0;
   g_statWins        = 0;
   g_tradesToday     = 0;

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
         g_tradesToday++;
     }

   //--- Le posizioni ancora aperte contano nel limite giornaliero
   for(int j = OrdersTotal() - 1; j >= 0; j--)
     {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(OrderOpenTime() >= g_dayStamp)
         g_tradesToday++;
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

color SignColor(double value)
  {
   if(value > 0.0) return(PanelPositiveColor);
   if(value < 0.0) return(PanelNegativeColor);
   return(PanelValueColor);
  }

string MoneyStr(double value)
  {
   return((value > 0.0 ? "+" : "") + DoubleToString(value, 2) + " " + AccountCurrency());
  }

string BarCountdown()
  {
   int seconds = (int)(iTime(Symbol(), g_signalTF, 0) + g_signalTF * 60 - TimeCurrent());
   if(seconds < 0)
      seconds = 0;

   int hh = seconds / 3600;
   int mm = (seconds % 3600) / 60;
   int ss = seconds % 60;

   if(hh > 0)
      return(StringFormat("%02d:%02d:%02d", hh, mm, ss));
   return(StringFormat("%02d:%02d", mm, ss));
  }

//+------------------------------------------------------------------+
//| Testo troncato alla larghezza utile del pannello                 |
//+------------------------------------------------------------------+
string Shorten(string text, int maxChars)
  {
   if(maxChars < 5 || StringLen(text) <= maxChars)
      return(text);
   return(StringSubstr(text, 0, maxChars - 3) + "...");
  }

//+------------------------------------------------------------------+
//| DASHBOARD: costruzione e aggiornamento                           |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   static datetime lastRefresh = 0;
   if(TimeCurrent() == lastRefresh)
      return;
   lastRefresh = TimeCurrent();

   UpdateTradeStats();

   //--- Dati di mercato -----------------------------------------------
   ENUM_MARKET_REGIME regime = REGIME_NONE;
   double atr = 0.0, adx = 0.0;

   if(HasEnoughBars())
     {
      regime = DetectMarketRegime();
      atr    = GetATR(g_signalTF, 1);
      adx    = iADX(Symbol(), g_regimeTF, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
     }

   double spread     = MathMax(Ask - Bid, 0.0);
   double spreadATR  = (atr > 0.0 ? spread / atr * 100.0 : 0.0);
   double minDist    = BrokerMinStopDistance();
   double stopLevel  = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   //--- Distanze proposte per il prossimo trade
   double slDist = 0.0, tpDist = 0.0;
   string note   = "";
   bool   tradeOk = BuildStopDistances(atr, slDist, tpDist, note);
   double nextLots = (tradeOk ? CalculateLotSize(slDist, false) : 0.0);
   double rrEff    = (tradeOk && slDist > 0.0 ? tpDist / slDist : 0.0);

   double floating   = FloatingProfit();
   double totalPL    = g_statNetProfit + floating;
   double equity     = AccountEquity();
   double balance    = AccountBalance();
   double marginUsed = AccountMargin();
   double marginFree = AccountFreeMargin();
   double marginLvl  = (marginUsed > 0.0 ? equity / marginUsed * 100.0 : 0.0);
   double drawdown   = (g_peakEquity > 0.0 ? (g_peakEquity - equity) / g_peakEquity * 100.0 : 0.0);
   if(drawdown < 0.0)
      drawdown = 0.0;

   double dayPL      = g_statTodayProfit + (IncludeFloatingInDD ? floating : 0.0);
   double dayLimit   = g_dayStartBalance * MaxDailyLossPercent / 100.0;
   double winRate    = (g_statTrades > 0 ? (double)g_statWins / g_statTrades * 100.0 : 0.0);
   double profitFact = (g_statGrossLoss > 0.0 ? g_statGrossWin / g_statGrossLoss : 0.0);
   int    openPos    = CountOwnPositions();

   //--- Layout ---------------------------------------------------------
   int y = PanelY + g_panelPad + g_rowHeight + 6;
   PanelRect(g_panelPrefix + "bg", PanelX, PanelY, PanelWidth, 100, PanelBgColor, PanelBorderColor, 0);

   PanelRect(g_panelPrefix + "hdr", PanelX + 1, PanelY + 1, PanelWidth - 2, g_rowHeight + 6,
             PanelSectionBgColor, PanelSectionBgColor, 1);
   PanelText(g_panelPrefix + "title", PanelX + g_panelPad, PanelY + 5,
             "ADAPTIVE REGIME EA v2", PanelTitleColor, PanelFontSize + 1, ANCHOR_LEFT_UPPER);
   PanelText(g_panelPrefix + "titler", PanelX + PanelWidth - g_panelPad, PanelY + 5,
             Symbol() + " " + TimeframeToString(g_signalTF) + "/" + TimeframeToString(g_regimeTF),
             PanelSectionColor, PanelFontSize, ANCHOR_RIGHT_UPPER);

   //--- CONTO ----------------------------------------------------------
   PanelSection(y, "acc", "CONTO");
   PanelRow(y, "accnum", "Conto",           IntegerToString(AccountNumber()) + " (" + Shorten(AccountCompany(), 18) + ")", PanelValueColor);
   PanelRow(y, "accsrv", "Server / Leva",   Shorten(AccountServer(), 16) + "  1:" + IntegerToString(AccountLeverage()), PanelValueColor);
   PanelRow(y, "accbal", "Saldo",           DoubleToString(balance, 2) + " " + AccountCurrency(), PanelValueColor);
   PanelRow(y, "accequ", "Equity",          DoubleToString(equity, 2) + " " + AccountCurrency(),
            (equity >= balance ? PanelPositiveColor : PanelNegativeColor));
   PanelRow(y, "accmgf", "Margine libero",  DoubleToString(marginFree, 2) + " " + AccountCurrency(), PanelValueColor);
   PanelRow(y, "accmgl", "Livello margine", (marginUsed > 0.0 ? DoubleToString(marginLvl, 1) + " %" : "-"),
            (marginUsed <= 0.0 ? PanelValueColor : (marginLvl < 200.0 ? PanelNegativeColor : PanelPositiveColor)));
   PanelRow(y, "accdd",  "Drawdown",        DoubleToString(drawdown, 2) + " %",
            (drawdown > 10.0 ? PanelNegativeColor : (drawdown > 5.0 ? PanelNeutralColor : PanelValueColor)));

   //--- PERFORMANCE ----------------------------------------------------
   PanelSection(y, "perf", "PERFORMANCE EA (magic " + IntegerToString(MagicNumber) + ")");
   PanelRow(y, "pfltp", "P/L flottante",   MoneyStr(floating),          SignColor(floating));
   PanelRow(y, "pfday", "Profitto oggi",   MoneyStr(g_statTodayProfit), SignColor(g_statTodayProfit));
   PanelRow(y, "pfcls", "Profitto chiuso", MoneyStr(g_statNetProfit),   SignColor(g_statNetProfit));
   PanelRow(y, "pftot", "PROFITTO TOTALE", MoneyStr(totalPL),           SignColor(totalPL));
   PanelRow(y, "pftrd", "Trade chiusi",    IntegerToString(g_statTrades) + "  (vinti " + IntegerToString(g_statWins) + ")", PanelValueColor);
   PanelRow(y, "pfwin", "Win rate",        (g_statTrades > 0 ? DoubleToString(winRate, 1) + " %" : "-"),
            (g_statTrades <= 0 ? PanelValueColor : (winRate >= 40.0 ? PanelPositiveColor : PanelNeutralColor)));
   PanelRow(y, "pfpf",  "Profit factor",   (profitFact > 0.0 ? DoubleToString(profitFact, 2) : "-"),
            (profitFact <= 0.0 ? PanelValueColor : (profitFact >= 1.0 ? PanelPositiveColor : PanelNegativeColor)));

   //--- MERCATO --------------------------------------------------------
   PanelSection(y, "mkt", "MERCATO  (" + g_symClassName + ", 1 pip = " + DoubleToString(g_pip, Digits) + ")");
   PanelRow(y, "mkreg", "Regime (" + TimeframeToString(g_regimeTF) + ")", RegimeToString(regime),
            (regime == REGIME_TREND ? PanelPositiveColor : (regime == REGIME_RANGE ? PanelSectionColor : PanelNeutralColor)));
   PanelRow(y, "mkstr", "Strategia",       (regime == REGIME_TREND ? (EnableTrendStrategy ? "Trend following" : "trend disabilitata") :
                                           (regime == REGIME_RANGE ? (EnableRangeStrategy ? "Mean reversion" : "range disabilitata") : "In attesa")),
            PanelValueColor);
   PanelRow(y, "mkadx", "ADX(" + IntegerToString(ADX_Period) + ")", DoubleToString(adx, 1),
            (adx >= ADX_Threshold ? PanelPositiveColor : PanelValueColor));
   PanelRow(y, "mkatr", "ATR(" + IntegerToString(ATR_Period) + ") " + TimeframeToString(g_signalTF), DistStr(atr), PanelValueColor);
   PanelRow(y, "mkspr", "Spread",          DistStr(spread) + "  " + DoubleToString(spreadATR, 0) + "% ATR",
            (MaxSpreadToATR > 0.0 && atr > 0.0 && spread > atr * MaxSpreadToATR ? PanelNegativeColor : PanelValueColor));
   PanelRow(y, "mkbar", "Prossima barra",  BarCountdown(), PanelValueColor);

   //--- DISTANZE E RISCHIO ---------------------------------------------
   PanelSection(y, "dist", "DISTANZE E RISCHIO");
   PanelRow(y, "dslvl", "Stop level broker", DistStr(stopLevel), (stopLevel > 0.0 ? PanelNeutralColor : PanelValueColor));
   PanelRow(y, "dmin",  "Distanza minima",   DistStr(minDist),
            (atr > 0.0 && MaxStopLevelATR > 0.0 && minDist > atr * MaxStopLevelATR ? PanelNegativeColor : PanelValueColor));
   PanelRow(y, "dsl",   "SL proposto",       (tradeOk ? DistStr(slDist) : "-"), (tradeOk ? PanelValueColor : PanelNeutralColor));
   PanelRow(y, "dtp",   "TP proposto",       (tradeOk ? DistStr(tpDist) : "-"), (tradeOk ? PanelValueColor : PanelNeutralColor));
   PanelRow(y, "drr",   "R:R effettivo",     (rrEff > 0.0 ? "1 : " + DoubleToString(rrEff, 2) : "-"),
            (rrEff >= MinRiskReward ? PanelPositiveColor : PanelNeutralColor));
   PanelRow(y, "dlot",  "Lotto stimato",     (nextLots > 0.0 ? DoubleToString(nextLots, g_lotDigits) : "n/d"),
            (nextLots > 0.0 ? PanelValueColor : PanelNeutralColor));
   PanelRow(y, "drisk", "Rischio per trade", DoubleToString(RiskPercent, 2) + " %  (" + DoubleToString(RiskAmount(), 2) + ")", PanelValueColor);

   //--- STATO OPERATIVO -------------------------------------------------
   PanelSection(y, "sta", "STATO OPERATIVO");
   PanelRow(y, "stpos", "Posizioni aperte", IntegerToString(openPos) + " / " + IntegerToString(MaxOpenPositions),
            (openPos > 0 ? PanelSectionColor : PanelValueColor));
   PanelRow(y, "sttrd", "Trade oggi",       IntegerToString(g_tradesToday) + (MaxTradesPerDay > 0 ? " / " + IntegerToString(MaxTradesPerDay) : ""),
            (MaxTradesPerDay > 0 && g_tradesToday >= MaxTradesPerDay ? PanelNegativeColor : PanelValueColor));
   PanelRow(y, "stday", "P/L giornaliero",  MoneyStr(dayPL) + (MaxDailyLossPercent > 0.0 ? "  (lim " + DoubleToString(dayLimit, 0) + ")" : ""),
            (g_dailyBlocked ? PanelNegativeColor : SignColor(dayPL)));
   PanelRow(y, "stses", "Sessione",         (IsSessionOpenNow() ? "APERTA" : "CHIUSA"),
            (IsSessionOpenNow() ? PanelPositiveColor : PanelNeutralColor));
   PanelRow(y, "stmng", "BE / Trailing",    (ManagementMode == MANAGE_ATR ? "ATR" : "PIPS") + ": " +
            (EnableBreakEven ? "BE on" : "BE off") + ", " + (EnableTrailingStop ? "TR on" : "TR off"), PanelValueColor);
   PanelRow(y, "staut", "AutoTrading",      (IsExpertEnabled() && IsTradeAllowed() ? "ATTIVO" : "DISATTIVO"),
            (IsExpertEnabled() && IsTradeAllowed() ? PanelPositiveColor : PanelNegativeColor));
   PanelRow(y, "stcon", "Connessione",      (IsConnected() ? "ONLINE" : "OFFLINE"),
            (IsConnected() ? PanelPositiveColor : PanelNegativeColor));
   PanelRow(y, "sttim", "Ora server",       TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), PanelValueColor);

   //--- Ultimo motivo di scarto -----------------------------------------
   PanelSection(y, "rej", "ULTIMO FILTRO ATTIVATO");
   PanelText(g_panelPrefix + "rejtxt", PanelX + g_panelPad, y,
             Shorten(g_lastReject, (int)((PanelWidth - 2 * g_panelPad) / (PanelFontSize * 0.62))),
             (g_lastReject == "-" ? PanelCaptionColor : PanelNeutralColor), PanelFontSize, ANCHOR_LEFT_UPPER);
   y += g_rowHeight;

   //--- Altezza finale
   ObjectSetInteger(0, g_panelPrefix + "bg", OBJPROP_YSIZE, y - PanelY + g_panelPad);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Sessione aperta adesso (senza effetti collaterali sul log)       |
//+------------------------------------------------------------------+
bool IsSessionOpenNow()
  {
   int hour = TimeHour(TimeCurrent());

   if(FridayCloseHour > 0 && DayOfWeek() == 5 && hour >= FridayCloseHour)
      return(false);

   if(!UseSessionFilter || SessionStartHour == SessionEndHour)
      return(true);

   if(SessionStartHour < SessionEndHour)
      return(hour >= SessionStartHour && hour < SessionEndHour);

   return(hour >= SessionStartHour || hour < SessionEndHour);
  }
//+------------------------------------------------------------------+
