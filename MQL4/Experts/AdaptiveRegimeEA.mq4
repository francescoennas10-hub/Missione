//+------------------------------------------------------------------+
//|                                            AdaptiveRegimeEA.mq4   |
//|                Adaptive Market Regime Expert Advisor for MT4      |
//|                                                                   |
//|  Filosofia:                                                       |
//|   - Nessuna logica rigida: l'EA classifica prima il REGIME di     |
//|     mercato (Trend / Range / Nessuno) tramite ADX + ATR + MA      |
//|     di lungo periodo, poi seleziona la strategia coerente:        |
//|       * REGIME_TREND -> Trend Following (cross MA + ADX/DI)       |
//|       * REGIME_RANGE -> Mean Reversion (RSI + Bande di Bollinger) |
//|       * REGIME_NONE  -> nessuna operazione (mercato ambiguo)      |
//|   - Rischio governato dalla volatilita': SL/TP dinamici su ATR,   |
//|     lotto calcolato sulla distanza reale dello Stop Loss.         |
//|   - Nessun ordine "nudo": SL e TP sono sempre presenti.           |
//+------------------------------------------------------------------+
#property copyright "Adaptive Regime EA"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Enumerazioni                                                     |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
  {
   REGIME_NONE  = 0,   // Nessun regime chiaro (no trading)
   REGIME_TREND = 1,   // Mercato direzionale
   REGIME_RANGE = 2    // Mercato laterale
  };

enum ENUM_RISK_BASE
  {
   RISK_ON_BALANCE = 0,  // Rischio calcolato sul Balance
   RISK_ON_EQUITY  = 1   // Rischio calcolato sull'Equity
  };

//+------------------------------------------------------------------+
//| INPUT: Gestione del rischio                                      |
//+------------------------------------------------------------------+
input string          s_risk               = "===== RISK MANAGEMENT =====";
input double          RiskPercent          = 1.0;    // Rischio % del capitale per operazione
input ENUM_RISK_BASE  RiskBase             = RISK_ON_BALANCE; // Base di calcolo del rischio
input double          FixedLots            = 0.0;    // Lotto fisso (0 = usa il calcolo automatico)
input double          MaxLotCap            = 10.0;   // Tetto massimo di lotti per operazione
input int             MagicNumber          = 20250814; // Magic Number (identificativo EA)
input string          TradeComment         = "AdaptiveRegimeEA"; // Commento ordini

//+------------------------------------------------------------------+
//| INPUT: Volatilita' / Stop dinamici (ATR)                         |
//+------------------------------------------------------------------+
input string          s_atr                = "===== ATR / DYNAMIC STOPS =====";
input int             ATR_Period           = 14;     // Periodo ATR
input double          ATR_Multiplier_SL    = 1.5;    // Moltiplicatore ATR per lo Stop Loss
input double          ATR_Multiplier_TP    = 3.0;    // Moltiplicatore ATR per il Take Profit
input int             ATR_AvgPeriod        = 50;     // Periodo di media dell'ATR (misura del regime)
input double          ATR_TrendFactor      = 1.0;    // ATR/ATRmedio minimo per validare il Trend
input double          ATR_RangeFactor      = 1.2;    // ATR/ATRmedio massimo per validare il Range

//+------------------------------------------------------------------+
//| INPUT: Regime filter                                             |
//+------------------------------------------------------------------+
input string          s_regime             = "===== REGIME FILTER =====";
input ENUM_TIMEFRAMES SignalTimeframe      = PERIOD_CURRENT; // Timeframe di analisi
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
input int             MA_Fast_Period       = 20;     // MA veloce
input int             MA_Slow_Period       = 50;     // MA lenta
input ENUM_MA_METHOD  MA_Cross_Method      = MODE_EMA; // Metodo MA veloce/lenta
input bool            UseDIConfirmation    = true;   // Conferma con +DI / -DI

//+------------------------------------------------------------------+
//| INPUT: Strategia Mean Reversion                                  |
//+------------------------------------------------------------------+
input string          s_range              = "===== RANGE STRATEGY =====";
input int             RSI_Period           = 14;     // Periodo RSI
input double          RSI_Oversold         = 30.0;   // Soglia ipervenduto
input double          RSI_Overbought       = 70.0;   // Soglia ipercomprato
input int             BB_Period            = 20;     // Periodo Bande di Bollinger
input double          BB_Deviation         = 2.0;    // Deviazione standard Bollinger

//+------------------------------------------------------------------+
//| INPUT: Gestione della posizione                                  |
//+------------------------------------------------------------------+
input string          s_manage             = "===== POSITION MANAGEMENT =====";
input bool            EnableTrailingStop   = true;   // Attiva il Trailing Stop
input double          TrailingStartPips    = 20.0;   // Profitto (pips) per avviare il trailing
input double          TrailingStopPips     = 20.0;   // Distanza (pips) del trailing dal prezzo
input double          TrailingStepPips     = 5.0;    // Passo minimo (pips) tra due trailing
input bool            EnableBreakEven      = true;   // Attiva il Break-Even
input double          BreakEvenPips        = 15.0;   // Profitto (pips) per spostare lo SL a BE
input double          BreakEvenLockPips    = 2.0;    // Pips bloccati sopra l'entrata al BE
input int             MaxOpenPositions     = 1;      // Numero massimo di posizioni contemporanee

//+------------------------------------------------------------------+
//| INPUT: Esecuzione / sicurezza                                    |
//+------------------------------------------------------------------+
input string          s_exec               = "===== EXECUTION =====";
input double          SlippagePips         = 3.0;    // Slippage tollerato (pips)
input double          MaxSpreadPips        = 3.0;    // Spread massimo ammesso (0 = nessun filtro)
input int             MaxRetries           = 3;      // Tentativi di invio ordine
input int             RetryDelayMs         = 500;    // Attesa (ms) tra i tentativi
input bool            TwoStepStops         = false;  // Broker ECN: apri e poi imposta SL/TP
input int             CooldownBars         = 1;      // Barre di attesa dopo la chiusura di un trade
input bool            TradeOnNewBarOnly    = true;   // Valuta i segnali solo a nuova barra
input bool            VerboseLog           = true;   // Log dettagliato nel journal

//+------------------------------------------------------------------+
//| Variabili globali                                                |
//+------------------------------------------------------------------+
double   g_pip            = 0.0;   // Valore di 1 pip in prezzo (gestisce broker 4/5 cifre)
double   g_pointsPerPip   = 1.0;   // Points contenuti in 1 pip (1 oppure 10)
int      g_slippagePoints = 0;     // Slippage convertito in points
int      g_lotDigits      = 2;     // Decimali ammessi per il volume
double   g_lotStep        = 0.01;  // Step del volume
double   g_minLot         = 0.01;  // Volume minimo
double   g_maxLot         = 100.0; // Volume massimo
datetime g_lastBarTime    = 0;     // Timestamp dell'ultima barra elaborata
datetime g_lastTradeTime  = 0;     // Timestamp di apertura dell'ultimo trade
int      g_timeframe      = 0;     // Timeframe effettivo dei segnali
bool     g_initOk         = false; // Stato di inizializzazione

//+------------------------------------------------------------------+
//| OnInit - Inizializzazione e validazione                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_initOk = false;

   //--- Adattamento automatico ai broker a 4 e 5 cifre (3 per JPY)
   if(Digits == 3 || Digits == 5)
     {
      g_pip          = Point * 10.0;
      g_pointsPerPip = 10.0;
     }
   else
     {
      g_pip          = Point;
      g_pointsPerPip = 1.0;
     }

   g_slippagePoints = (int)MathRound(SlippagePips * g_pointsPerPip);
   if(g_slippagePoints < 0)
      g_slippagePoints = 0;

   //--- Parametri di volume del simbolo
   g_lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   g_minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   g_maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);

   if(g_lotStep <= 0.0) g_lotStep = 0.01;
   if(g_minLot  <= 0.0) g_minLot  = g_lotStep;
   if(g_maxLot  <= 0.0) g_maxLot  = 100.0;

   g_lotDigits = VolumeDigits(g_lotStep);

   //--- Timeframe di analisi
   g_timeframe = (SignalTimeframe == PERIOD_CURRENT) ? Period() : (int)SignalTimeframe;

   //--- Validazione degli input critici
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   g_lastBarTime = iTime(Symbol(), g_timeframe, 0);
   g_initOk      = true;

   Print("[", TradeComment, "] Init OK | Symbol=", Symbol(),
         " Digits=", Digits,
         " Pip=", DoubleToString(g_pip, Digits),
         " LotStep=", DoubleToString(g_lotStep, g_lotDigits),
         " MinLot=", DoubleToString(g_minLot, g_lotDigits),
         " MaxLot=", DoubleToString(g_maxLot, g_lotDigits),
         " TF=", TimeframeToString(g_timeframe),
         " Magic=", MagicNumber);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit - Chiusura pulita                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("[", TradeComment, "] Deinit, motivo=", reason, " (", DeinitReasonText(reason), ")");
   Comment("");
  }

//+------------------------------------------------------------------+
//| OnTick - Ciclo principale                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_initOk)
      return;

   //--- 1) La gestione delle posizioni aperte lavora su OGNI tick
   ManageOpenPositions();

   //--- 2) Il pannello informativo si aggiorna sempre
   if(!IsTesting() || IsVisualMode())
      ShowDashboard();

   //--- 3) Controlli generali di operativita'
   if(!IsTradeAllowed())
      return;

   if(IsTradeContextBusy())
      return;

   //--- 4) Dati storici sufficienti per tutti gli indicatori?
   if(!HasEnoughBars())
      return;

   //--- 5) Valutazione dei segnali: solo alla chiusura di una barra
   datetime barTime = iTime(Symbol(), g_timeframe, 0);
   if(TradeOnNewBarOnly)
     {
      if(barTime == g_lastBarTime)
         return;
      g_lastBarTime = barTime;
     }

   //--- 6) Limite di esposizione: massimo N posizioni contemporanee
   if(CountOwnPositions() >= MaxOpenPositions)
      return;

   //--- 7) Cooldown dopo l'ultimo trade
   if(IsInCooldown())
      return;

   //--- 8) Filtro sullo spread corrente
   if(!IsSpreadAcceptable())
      return;

   //--- 9) Regime di mercato e segnale coerente con esso
   ENUM_MARKET_REGIME regime = DetectMarketRegime();
   if(regime == REGIME_NONE)
      return;

   int signal = 0; // +1 = BUY, -1 = SELL, 0 = nessun segnale

   if(regime == REGIME_TREND)
      signal = GetTrendSignal();
   else
      if(regime == REGIME_RANGE)
         signal = GetRangeSignal();

   if(signal == 0)
      return;

   //--- 10) Esecuzione
   if(signal > 0)
      OpenPosition(OP_BUY, regime);
   else
      OpenPosition(OP_SELL, regime);
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

   if(EnableTrailingStop && TrailingStopPips <= 0.0)
     { Print("ERRORE INPUT: TrailingStopPips deve essere > 0 se il trailing e' attivo."); ok = false; }

   if(EnableBreakEven && BreakEvenPips <= 0.0)
     { Print("ERRORE INPUT: BreakEvenPips deve essere > 0 se il break-even e' attivo."); ok = false; }

   if(MaxRetries < 1)
     { Print("ERRORE INPUT: MaxRetries deve essere >= 1."); ok = false; }

   return(ok);
  }

//+------------------------------------------------------------------+
//| Numero di barre necessarie e disponibilita' dello storico        |
//+------------------------------------------------------------------+
bool HasEnoughBars()
  {
   int needed = (int)MathMax(MA_Long_Period, MathMax(MA_Slow_Period, MathMax(BB_Period, MathMax(RSI_Period, ATR_Period + ATR_AvgPeriod))));
   needed += ADX_Period + 10;

   if(iBars(Symbol(), g_timeframe) < needed)
     {
      static datetime lastWarn = 0;
      if(VerboseLog && TimeCurrent() - lastWarn > 300)
        {
         lastWarn = TimeCurrent();
         Print("[", TradeComment, "] Storico insufficiente: servono ", needed,
               " barre su ", TimeframeToString(g_timeframe), ", disponibili ", iBars(Symbol(), g_timeframe));
        }
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| REGIME FILTER: classifica il mercato in Trend / Range / Nessuno  |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME DetectMarketRegime()
  {
   double adx    = iADX(Symbol(), g_timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   double atr    = GetATR(1);
   double atrAvg = GetAverageATR(ATR_AvgPeriod, 1);
   double maLong = iMA(Symbol(), g_timeframe, MA_Long_Period, 0, MA_Long_Method, PRICE_CLOSE, 1);
   double close  = iClose(Symbol(), g_timeframe, 1);

   if(atr <= 0.0 || atrAvg <= 0.0 || maLong <= 0.0)
      return(REGIME_NONE);

   double atrRatio  = atr / atrAvg;              // espansione/compressione di volatilita'
   double distToMA  = MathAbs(close - maLong) / atr; // distanza dalla MA lunga misurata in ATR

   //--- TREND: ADX sopra soglia, volatilita' non compressa, prezzo staccato dalla MA lunga
   if(adx >= ADX_Threshold && atrRatio >= ATR_TrendFactor && distToMA >= 0.5)
      return(REGIME_TREND);

   //--- RANGE: ADX sotto soglia, volatilita' non esplosiva, prezzo attorno alla MA lunga
   if(adx <= ADX_RangeThreshold && atrRatio <= ATR_RangeFactor && distToMA <= RangeMaxDistanceATR)
      return(REGIME_RANGE);

   //--- Zona grigia: nessuna operazione (evita il curve fitting su fasi ambigue)
   return(REGIME_NONE);
  }

//+------------------------------------------------------------------+
//| SEGNALE TREND: incrocio MA veloce/lenta + conferma ADX/DI e bias |
//+------------------------------------------------------------------+
int GetTrendSignal()
  {
   double fast1 = iMA(Symbol(), g_timeframe, MA_Fast_Period, 0, MA_Cross_Method, PRICE_CLOSE, 1);
   double fast2 = iMA(Symbol(), g_timeframe, MA_Fast_Period, 0, MA_Cross_Method, PRICE_CLOSE, 2);
   double slow1 = iMA(Symbol(), g_timeframe, MA_Slow_Period, 0, MA_Cross_Method, PRICE_CLOSE, 1);
   double slow2 = iMA(Symbol(), g_timeframe, MA_Slow_Period, 0, MA_Cross_Method, PRICE_CLOSE, 2);

   double maLong = iMA(Symbol(), g_timeframe, MA_Long_Period, 0, MA_Long_Method, PRICE_CLOSE, 1);
   double close1 = iClose(Symbol(), g_timeframe, 1);

   double plusDI  = iADX(Symbol(), g_timeframe, ADX_Period, PRICE_CLOSE, MODE_PLUSDI,  1);
   double minusDI = iADX(Symbol(), g_timeframe, ADX_Period, PRICE_CLOSE, MODE_MINUSDI, 1);

   bool crossUp   = (fast2 <= slow2 && fast1 > slow1);
   bool crossDown = (fast2 >= slow2 && fast1 < slow1);

   bool diLong    = (!UseDIConfirmation || plusDI  > minusDI);
   bool diShort   = (!UseDIConfirmation || minusDI > plusDI);

   //--- Long: cross rialzista, prezzo sopra la MA di lungo periodo, +DI dominante
   if(crossUp && close1 > maLong && diLong)
     {
      LogSignal("TREND", "BUY", "cross MA up + close>MA200 + DI+");
      return(1);
     }

   //--- Short: cross ribassista, prezzo sotto la MA di lungo periodo, -DI dominante
   if(crossDown && close1 < maLong && diShort)
     {
      LogSignal("TREND", "SELL", "cross MA down + close<MA200 + DI-");
      return(-1);
     }

   return(0);
  }

//+------------------------------------------------------------------+
//| SEGNALE RANGE: mean reversion con RSI sulle Bande di Bollinger   |
//+------------------------------------------------------------------+
int GetRangeSignal()
  {
   double upper1 = iBands(Symbol(), g_timeframe, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double lower1 = iBands(Symbol(), g_timeframe, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double upper2 = iBands(Symbol(), g_timeframe, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double lower2 = iBands(Symbol(), g_timeframe, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_LOWER, 2);

   double rsi1   = iRSI(Symbol(), g_timeframe, RSI_Period, PRICE_CLOSE, 1);
   double rsi2   = iRSI(Symbol(), g_timeframe, RSI_Period, PRICE_CLOSE, 2);

   double close1 = iClose(Symbol(), g_timeframe, 1);
   double close2 = iClose(Symbol(), g_timeframe, 2);
   double low1   = iLow(Symbol(),  g_timeframe, 1);
   double high1  = iHigh(Symbol(), g_timeframe, 1);

   if(upper1 <= 0.0 || lower1 <= 0.0 || upper2 <= 0.0 || lower2 <= 0.0)
      return(0);

   //--- Long: estensione sotto la banda inferiore, RSI ipervenduto in ripresa,
   //          chiusura che rientra nel canale (conferma del rifiuto)
   bool touchedLower = (low1 <= lower1 || close2 < lower2);
   if(touchedLower && rsi1 <= RSI_Oversold && rsi1 > rsi2 && close1 > lower1)
     {
      LogSignal("RANGE", "BUY", "rifiuto banda inferiore + RSI ipervenduto in ripresa");
      return(1);
     }

   //--- Short: estensione sopra la banda superiore, RSI ipercomprato in flessione,
   //           chiusura che rientra nel canale
   bool touchedUpper = (high1 >= upper1 || close2 > upper2);
   if(touchedUpper && rsi1 >= RSI_Overbought && rsi1 < rsi2 && close1 < upper1)
     {
      LogSignal("RANGE", "SELL", "rifiuto banda superiore + RSI ipercomprato in flessione");
      return(-1);
     }

   return(0);
  }

//+------------------------------------------------------------------+
//| Apertura della posizione con SL/TP dinamici su ATR               |
//+------------------------------------------------------------------+
bool OpenPosition(int orderType, ENUM_MARKET_REGIME regime)
  {
   RefreshRates();

   double atr = GetATR(1);
   if(atr <= 0.0)
     {
      Print("[", TradeComment, "] ATR non valido, ordine annullato.");
      return(false);
     }

   double slDistance = atr * ATR_Multiplier_SL;   // distanza SL in prezzo
   double tpDistance = atr * ATR_Multiplier_TP;   // distanza TP in prezzo

   //--- Distanza minima imposta dal broker (stop level) + margine per lo spread
   double minDistance = MinStopDistance();
   if(slDistance < minDistance) slDistance = minDistance;
   if(tpDistance < minDistance) tpDistance = minDistance;

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

   //--- Distanza effettiva dello SL dopo la normalizzazione: base del sizing
   double effectiveSLDistance = MathAbs(price - sl);
   if(effectiveSLDistance <= 0.0)
     {
      Print("[", TradeComment, "] Distanza SL nulla, ordine annullato.");
      return(false);
     }

   //--- Calcolo del volume in funzione del rischio e della distanza dallo SL
   double lots = CalculateLotSize(effectiveSLDistance);
   if(lots <= 0.0)
     {
      Print("[", TradeComment, "] Volume calcolato non valido (", DoubleToString(lots, g_lotDigits), "), ordine annullato.");
      return(false);
     }

   string comment = TradeComment + (regime == REGIME_TREND ? "-TRD" : "-RNG");

   if(VerboseLog)
      Print("[", TradeComment, "] Invio ordine ", (orderType == OP_BUY ? "BUY" : "SELL"),
            " | Regime=", RegimeToString(regime),
            " | Lots=", DoubleToString(lots, g_lotDigits),
            " | Price=", DoubleToString(price, Digits),
            " | SL=", DoubleToString(sl, Digits),
            " | TP=", DoubleToString(tp, Digits),
            " | ATR=", DoubleToString(atr, Digits),
            " | Rischio=", DoubleToString(RiskAmount(), 2), " ", AccountCurrency());

   int ticket = SendOrderWithRetries(orderType, lots, price, sl, tp, comment);

   if(ticket > 0)
     {
      g_lastTradeTime = TimeCurrent();
      return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Invio ordine con retry, gestione slippage ed errori              |
//| Garantisce SEMPRE la presenza di SL e TP (nessun ordine "nudo"). |
//+------------------------------------------------------------------+
int SendOrderWithRetries(int orderType, double lots, double price, double sl, double tp, string comment)
  {
   int ticket = -1;

   for(int attempt = 1; attempt <= MaxRetries; attempt++)
     {
      //--- Attende che il contesto di trading sia libero
      if(!WaitForTradeContext())
        {
         Print("[", TradeComment, "] Contesto di trading occupato, tentativo ", attempt, " annullato.");
         continue;
        }

      RefreshRates();

      //--- Prezzi e stop ricalcolati ad ogni tentativo sui dati aggiornati
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
         //--- Modalita' due passaggi (o stop rifiutati): imposta subito SL/TP
         if(TwoStepStops)
           {
            if(!ModifyOrderWithRetries(ticket, sl, tp))
              {
               Print("[", TradeComment, "] ATTENZIONE: impossibile impostare SL/TP sul ticket ",
                     ticket, ". Chiusura immediata per non lasciare la posizione scoperta.");
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

      //--- Stop non validi: riprova aprendo prima la posizione e impostando poi gli stop
      if(err == 130 && !TwoStepStops)
        {
         ResetLastError();
         RefreshRates();
         price = NormalizeDouble((orderType == OP_BUY ? Ask : Bid), Digits);

         double widen = MinStopDistance() * 1.5;
         if(orderType == OP_BUY)
           {
            sl = NormalizeDouble(price - MathMax(MathAbs(price - sl), widen), Digits);
            tp = NormalizeDouble(price + MathMax(MathAbs(price - tp), widen), Digits);
           }
         else
           {
            sl = NormalizeDouble(price + MathMax(MathAbs(price - sl), widen), Digits);
            tp = NormalizeDouble(price - MathMax(MathAbs(price - tp), widen), Digits);
           }

         ticket = OrderSend(Symbol(), orderType, lots, price, g_slippagePoints, 0.0, 0.0,
                            comment, MagicNumber, 0, clrGray);
         if(ticket > 0)
           {
            if(!ModifyOrderWithRetries(ticket, sl, tp))
              {
               Print("[", TradeComment, "] ATTENZIONE: SL/TP non impostabili sul ticket ",
                     ticket, ". Chiusura immediata della posizione.");
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

      Sleep(RetryDelayMs * attempt); // backoff progressivo
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

      RefreshRates();

      //--- Rispetto della distanza minima dal prezzo corrente
      double minDist = MinStopDistance();
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

      //--- Nessuna modifica necessaria
      if(MathAbs(OrderStopLoss() - newSL) < Point / 2.0 && MathAbs(OrderTakeProfit() - newTP) < Point / 2.0)
         return(true);

      ResetLastError();
      if(OrderModify(ticket, OrderOpenPrice(), newSL, newTP, 0, clrLimeGreen))
        {
         if(VerboseLog)
            Print("[", TradeComment, "] OrderModify OK. Ticket=", ticket,
                  " SL=", DoubleToString(newSL, Digits),
                  " TP=", DoubleToString(newTP, Digits));
         return(true);
        }

      int err = GetLastError();
      if(err == 1) // ERR_NO_RESULT: valori gia' presenti
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
//| Chiusura di emergenza di una posizione                           |
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
         return(true); // gia' chiusa

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
//| CALCOLO DEL LOTTO                                                |
//| Rischio monetario / perdita per lotto alla distanza dello SL.    |
//| Gestisce LOTSTEP, MINLOT, MAXLOT e il margine disponibile.       |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
  {
   //--- Modalita' a lotto fisso
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
      Print("[", TradeComment, "] TICKVALUE non disponibile per ", Symbol(), ": impossibile dimensionare il lotto.");
      return(0.0);
     }

   //--- Perdita, in valuta del conto, generata da 1.0 lotto se lo SL viene colpito
   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;

   //--- Vincolo di margine libero: non impegnare piu' del 90% disponibile
   double marginPerLot = MarketInfo(Symbol(), MODE_MARGINREQUIRED);
   if(marginPerLot > 0.0)
     {
      double affordable = (AccountFreeMargin() * 0.90) / marginPerLot;
      if(affordable < lots)
        {
         if(VerboseLog)
            Print("[", TradeComment, "] Volume ridotto da ", DoubleToString(lots, 4),
                  " a ", DoubleToString(affordable, 4), " per vincolo di margine libero.");
         lots = affordable;
        }
     }

   //--- Tetto massimo di sicurezza definito dall'utente
   if(MaxLotCap > 0.0 && lots > MaxLotCap)
      lots = MaxLotCap;

   lots = NormalizeLots(lots);

   //--- Verifica finale: il lotto minimo del broker potrebbe eccedere il rischio richiesto
   if(lots <= 0.0)
      return(0.0);

   double realRisk = lots * lossPerLot;
   if(realRisk > riskMoney * 1.5)
     {
      Print("[", TradeComment, "] Il lotto minimo (", DoubleToString(lots, g_lotDigits),
            ") comporta un rischio di ", DoubleToString(realRisk, 2), " ", AccountCurrency(),
            " superiore al budget di ", DoubleToString(riskMoney, 2), ". Operazione annullata.");
      return(0.0);
     }

   return(lots);
  }

//+------------------------------------------------------------------+
//| Normalizzazione del volume su LOTSTEP / MINLOT / MAXLOT          |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   if(lots <= 0.0)
      return(0.0);

   //--- Arrotondamento per difetto allo step del broker (mai rischiare di piu')
   lots = MathFloor(lots / g_lotStep + 0.0000001) * g_lotStep;
   lots = NormalizeDouble(lots, g_lotDigits);

   if(lots < g_minLot)
      lots = g_minLot;

   if(lots > g_maxLot)
      lots = g_maxLot;

   return(NormalizeDouble(lots, g_lotDigits));
  }

//+------------------------------------------------------------------+
//| Numero di decimali implicito nello step del volume               |
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
//| Importo monetario a rischio per singola operazione               |
//+------------------------------------------------------------------+
double RiskAmount()
  {
   double capital = (RiskBase == RISK_ON_EQUITY) ? AccountEquity() : AccountBalance();
   if(capital <= 0.0)
      return(0.0);
   return(capital * RiskPercent / 100.0);
  }

//+------------------------------------------------------------------+
//| GESTIONE POSIZIONI APERTE: Break-Even e Trailing Stop            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   if(!EnableBreakEven && !EnableTrailingStop)
      return;

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
      double minDist   = MinStopDistance();
      double freeze    = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;

      if(OrderType() == OP_BUY)
        {
         double profitPips = (Bid - openPrice) / g_pip;

         //--- Break-Even: sposta lo SL all'entrata (+ lock) raggiunto il profitto richiesto
         if(EnableBreakEven && profitPips >= BreakEvenPips)
           {
            double bePrice = NormalizeDouble(openPrice + BreakEvenLockPips * g_pip, Digits);
            if(bePrice > newSL + Point / 2.0 && Bid - bePrice >= minDist)
               newSL = bePrice;
           }

         //--- Trailing Stop: insegue il prezzo mantenendo la distanza impostata
         if(EnableTrailingStop && profitPips >= TrailingStartPips)
           {
            double trailPrice = NormalizeDouble(Bid - TrailingStopPips * g_pip, Digits);
            if(trailPrice > newSL + TrailingStepPips * g_pip - Point / 2.0 &&
               Bid - trailPrice >= minDist)
               newSL = trailPrice;
           }

         //--- Lo stop non arretra mai
         if(currentSL > 0.0 && newSL < currentSL + Point / 2.0)
            newSL = currentSL;

         if(newSL > currentSL + Point / 2.0)
           {
            if(freeze > 0.0 && Bid - newSL < freeze)
               continue; // zona di congelamento: modifica non ammessa
            ModifyOrderWithRetries(OrderTicket(), newSL, OrderTakeProfit());
           }
        }
      else // OP_SELL
        {
         double profitPipsS = (openPrice - Ask) / g_pip;

         if(EnableBreakEven && profitPipsS >= BreakEvenPips)
           {
            double bePriceS = NormalizeDouble(openPrice - BreakEvenLockPips * g_pip, Digits);
            if((newSL <= 0.0 || bePriceS < newSL - Point / 2.0) && bePriceS - Ask >= minDist)
               newSL = bePriceS;
           }

         if(EnableTrailingStop && profitPipsS >= TrailingStartPips)
           {
            double trailPriceS = NormalizeDouble(Ask + TrailingStopPips * g_pip, Digits);
            if((newSL <= 0.0 || trailPriceS < newSL - TrailingStepPips * g_pip + Point / 2.0) &&
               trailPriceS - Ask >= minDist)
               newSL = trailPriceS;
           }

         //--- Lo stop non arretra mai
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
//| Conteggio delle posizioni gestite da questo EA                   |
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
//| Cooldown: attende N barre dopo l'ultimo trade                    |
//+------------------------------------------------------------------+
bool IsInCooldown()
  {
   if(CooldownBars <= 0)
      return(false);

   //--- Riferimento: ultimo trade aperto in questa sessione oppure chiuso nello storico
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

   int barsSince = iBarShift(Symbol(), g_timeframe, reference, false);
   if(barsSince < CooldownBars)
      return(true);

   return(false);
  }

//+------------------------------------------------------------------+
//| Filtro sullo spread corrente                                     |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
  {
   if(MaxSpreadPips <= 0.0)
      return(true);

   double spreadPips = (Ask - Bid) / g_pip;
   if(spreadPips > MaxSpreadPips)
     {
      if(VerboseLog)
         Print("[", TradeComment, "] Spread troppo alto: ", DoubleToString(spreadPips, 1),
               " pips (max ", DoubleToString(MaxSpreadPips, 1), "). Nessuna operazione.");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Distanza minima ammessa dal broker per SL/TP (in prezzo)         |
//+------------------------------------------------------------------+
double MinStopDistance()
  {
   double stopLevel   = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double freezeLevel = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
   double spread      = MathMax(Ask - Bid, 0.0);

   double minDist = MathMax(stopLevel, freezeLevel) + spread;

   //--- Margine di sicurezza minimo pari a 1 pip
   double safety = g_pip;
   if(minDist < safety)
      minDist = safety;

   return(NormalizeDouble(minDist, Digits));
  }

//+------------------------------------------------------------------+
//| ATR corrente sullo shift indicato                                |
//+------------------------------------------------------------------+
double GetATR(int shift)
  {
   return(iATR(Symbol(), g_timeframe, ATR_Period, shift));
  }

//+------------------------------------------------------------------+
//| Media dell'ATR su N barre (riferimento del regime volatilita')   |
//+------------------------------------------------------------------+
double GetAverageATR(int period, int startShift)
  {
   if(period < 1)
      return(0.0);

   double sum = 0.0;
   for(int i = 0; i < period; i++)
      sum += iATR(Symbol(), g_timeframe, ATR_Period, startShift + i);

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
//| Descrizione testuale dei codici di errore piu' comuni            |
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
//| Descrizione del motivo di deinizializzazione                     |
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

void LogSignal(string regime, string side, string reason)
  {
   if(VerboseLog)
      Print("[", TradeComment, "] Segnale ", side, " in regime ", regime, ": ", reason);
  }

//+------------------------------------------------------------------+
//| Pannello informativo sul grafico                                 |
//+------------------------------------------------------------------+
void ShowDashboard()
  {
   static datetime lastUpdate = 0;
   if(TimeCurrent() == lastUpdate)
      return;
   lastUpdate = TimeCurrent();

   ENUM_MARKET_REGIME regime = HasEnoughBars() ? DetectMarketRegime() : REGIME_NONE;

   double atr        = GetATR(1);
   double adx        = iADX(Symbol(), g_timeframe, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
   double spreadPips = (Ask - Bid) / g_pip;

   string txt = "=== Adaptive Regime EA ===\n";
   txt += "Simbolo: " + Symbol() + "  TF: " + TimeframeToString(g_timeframe) + "  Digits: " + IntegerToString(Digits) + "\n";
   txt += "Regime: " + RegimeToString(regime) + "   ADX: " + DoubleToString(adx, 1) + "\n";
   txt += "ATR(" + IntegerToString(ATR_Period) + "): " + DoubleToString(atr / g_pip, 1) + " pips\n";
   txt += "SL dinamico: " + DoubleToString(atr * ATR_Multiplier_SL / g_pip, 1) + " pips   ";
   txt += "TP dinamico: " + DoubleToString(atr * ATR_Multiplier_TP / g_pip, 1) + " pips\n";
   txt += "Spread: " + DoubleToString(spreadPips, 1) + " pips\n";
   txt += "Rischio per trade: " + DoubleToString(RiskPercent, 2) + "%  (" + DoubleToString(RiskAmount(), 2) + " " + AccountCurrency() + ")\n";
   txt += "Posizioni aperte: " + IntegerToString(CountOwnPositions()) + " / " + IntegerToString(MaxOpenPositions) + "\n";
   txt += "Trailing: " + (EnableTrailingStop ? "ON" : "OFF") + "   Break-Even: " + (EnableBreakEven ? "ON" : "OFF") + "\n";
   txt += "Equity: " + DoubleToString(AccountEquity(), 2) + "   Balance: " + DoubleToString(AccountBalance(), 2) + "\n";

   Comment(txt);
  }
//+------------------------------------------------------------------+
