//+------------------------------------------------------------------+
//|                                                     ScalpEA.mq4   |
//|         Scalper a posizione singola con Stop&Reverse per MT4      |
//|                                v1.10                              |
//|                                                                   |
//|  COSA FA                                                          |
//|   Scalper intraday ricostruito sul comportamento osservato nella  |
//|   registrazione dello Strategy Tester (XAUUSD+ M5) e sul set di   |
//|   parametri fornito. Quattro meccanismi lo governano:             |
//|                                                                   |
//|   1. INGRESSO SU BREAKOUT, UNA POSIZIONE ALLA VOLTA               |
//|      L'ingresso scatta quando il prezzo supera di EntryDistance   |
//|      punti l'estremo delle ultime SignalBars barre. Con           |
//|      maxOrders = 1 l'EA resta su una sola posizione per volta,    |
//|      come nel video. Alzando maxOrders si abilita la griglia:     |
//|      ogni ordine aggiuntivo dello stesso verso richiede altri     |
//|      EntryDistance punti di distanza dal piu' vicino.             |
//|                                                                   |
//|   2. NESSUN TAKE PROFIT                                           |
//|      La posizione non ha un obiettivo fisso: resta aperta finche' |
//|      il prezzo va nella direzione giusta. Si chiude solo in due   |
//|      modi, sul trailing stop che segue il profitto o sullo stop   |
//|      loss iniziale. Il take profit resta come input, ma spento.   |
//|                                                                   |
//|   3. LIVELLI VIRTUALI                                             |
//|      Nel video il grafico mostra la linea di apertura della       |
//|      posizione ma nessuna linea di stop loss o take profit: i     |
//|      livelli non vengono inviati al broker. Qui il comportamento  |
//|      e' riprodotto con UseVirtualLevels: stop e trailing sono     |
//|      calcolati e sorvegliati dall'EA, che chiude a mercato con    |
//|      la stessa semantica del server (buy sul Bid, sell sull'Ask). |
//|      Resta disponibile uno stop reale di emergenza, molto piu'    |
//|      largo, come rete di sicurezza in caso di disconnessione.     |
//|                                                                   |
//|   4. SAR (Stop And Reverse)                                       |
//|      Quando una posizione viene chiusa in perdita sul proprio     |
//|      stop, l'EA apre immediatamente la posizione opposta. E' cio' |
//|      che nel video produce le catene di frecce blu e rosse        |
//|      alternate sugli stessi livelli di prezzo. Un'uscita in       |
//|      profitto, trailing compreso, non innesca alcun reversal.     |
//|                                                                   |
//|  STOP LOSS                                                        |
//|   Distanza fissa in prezzo, StopLossPriceDistance: con 0.90 una   |
//|   vendita a 4578.50 ha lo stop a 4579.40. Esprimerlo in prezzo    |
//|   e non in punti lo rende indipendente dalle cifre decimali del   |
//|   broker. Portando StopLoss su Automatic si torna alla distanza   |
//|   proporzionale all'ATR.                                          |
//|                                                                   |
//|  I primi 40 input riproducono nome, ordine ed etichetta del       |
//|  preset allegato; il blocco "ADVANCED" in fondo espone i          |
//|  coefficienti del motore automatico e le opzioni di sicurezza.    |
//+------------------------------------------------------------------+
#property copyright "Scalp EA"
#property link      ""
#property version   "1.10"
#property strict

//+------------------------------------------------------------------+
//| Enumerazioni                                                     |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIRECTION
  {
   DIR_BUY_AND_SELL = 0,   // BuyAndSell
   DIR_BUY_ONLY     = 1,   // BuyOnly
   DIR_SELL_ONLY    = 2    // SellOnly
  };

enum ENUM_LEVEL_MODE
  {
   LEVEL_AUTOMATIC = 0,    // Automatic
   LEVEL_MANUAL    = 1,    // Manual
   LEVEL_DISABLED  = 2     // Disabled
  };

//+------------------------------------------------------------------+
//| INPUT - blocco riprodotto dal preset                             |
//+------------------------------------------------------------------+
input ENUM_TRADE_DIRECTION TradeDirection = DIR_BUY_AND_SELL; // TradeDirection
input bool             SAR                = true;             // SAR
input double           Lots               = 0.01;             // Lots
input int              Magic              = 888777;           // Magic
input string           TradeComment       = "Scalp EA";       // TradeComment
input int              EntryDistance      = 30;               // EntryDistance
input ENUM_LEVEL_MODE  TakeProfit         = LEVEL_DISABLED;   // TakeProfit
input ENUM_LEVEL_MODE  StopLoss           = LEVEL_MANUAL;     // StopLoss
input ENUM_LEVEL_MODE  TrailingStop       = LEVEL_AUTOMATIC;  // TrailingStop
input int              maxOrders          = 1;                // maxOrders
input double           DailyProfit        = 0.0;              // DailyProfit [if 0 - not active]
input double           MaxDD              = 0.0;              // MaxDD [if 0 - not active]
input int              TotalSL            = 0;                // Total SL [points]
input bool             Trading24h         = true;             // Trading24h
input bool             Monday             = true;             // Monday
input string           MondayStartTime    = "08:00";          // MondayStartTime
input string           MondayEndTime      = "22:00";          // MondayEndTime
input bool             Tuesday            = true;             // Tuesday
input string           TuesdayStartTime   = "08:00";          // TuesdayStartTime
input string           TuesdayEndTime     = "22:00";          // TuesdayEndTime
input bool             Wednesday          = true;             // Wednesday
input string           WednesdayStartTime = "08:00";          // WednesdayStartTime
input string           WednesdayEndTime   = "22:00";          // WednesdayEndTime
input bool             Thursday           = true;             // Thursday
input string           ThursdayStartTime  = "08:00";          // ThursdayStartTime
input string           ThursdayEndTime    = "22:00";          // ThursdayEndTime
input bool             Friday             = true;             // Friday
input string           FridayStartTime    = "08:00";          // FridayStartTime
input string           FridayEndTime      = "20:00";          // FridayEndTime
input bool             TradingNonFarmFriday  = true;          // TradingNonFarmFriday
input bool             TradingDuringHolidays = true;          // TradingDuringHolidays [12Dec-12Jan]
input string           NewsFilterParams   = "--- NewsFilter -------------------"; // NewsFilterParams
input bool             NewsFilter         = true;             // NewsFilter
input int              doNotTradeBeforeInMinutes = 60;        // doNotTradeBeforeInMinutes
input int              doNotTradeAfterInMinutes  = 60;        // doNotTradeAfterInMinutes
input bool             ReportUSD          = true;             // Report for USD
input bool             ReportEUR          = true;             // Report for EUR
input bool             ReportGBP          = false;            // Report for GBP
input bool             ReportJPY          = false;            // Report for JPY
input bool             showPanel          = true;             // showPanel

//+------------------------------------------------------------------+
//| INPUT - ADVANCED: motore automatico e sicurezze                  |
//+------------------------------------------------------------------+
input string  s_engine            = "===== MOTORE DEL SEGNALE =====";
input int     SignalBars          = 1;      // Barre del canale di breakout
input int     MinSecondsBetweenTrades = 0;  // Pausa minima tra due ingressi (secondi)
input int     MaxSarChain         = 0;      // Reversal SAR consecutivi (0 = illimitati)
input int     Slippage            = 5;      // Slippage massimo (punti)
input double  MaxSpreadPoints     = 0;      // Spread massimo ammesso (punti, 0 = disattivo)

input string  s_levels            = "===== LIVELLI AUTOMATICI (ATR) =====";
input int     ATR_Period          = 14;     // Periodo ATR
input double  AutoTP_ATR          = 0.25;   // TP automatico = fattore * ATR
input double  AutoSL_ATR          = 0.50;   // SL automatico = fattore * ATR
input double  AutoTS_ATR          = 0.35;   // Trailing automatico = fattore * ATR
input double  AutoTP_MinSpreadRatio = 2.0;  // TP minimo = rapporto * spread
input int     ManualTakeProfitPoints = 50;  // TP in punti se TakeProfit = Manual
input int     ManualStopLossPoints   = 90;  // SL in punti se StopLoss = Manual
input double  StopLossPriceDistance  = 0.90;// SL in prezzo (ha la precedenza se > 0)
input int     ManualTrailingPoints   = 60;  // Trailing in punti se TrailingStop = Manual
input double  TrailingPriceDistance = 0.0; // Trailing in prezzo (ha la precedenza se > 0)
input int     TrailingStepPoints     = 5;   // Passo minimo di avanzamento del trailing

input string  s_safety            = "===== SICUREZZE =====";
input bool    UseVirtualLevels    = true;   // TP/SL virtuali (non inviati al broker)
input bool    UseEmergencyBrokerStop = true;// Stop reale di emergenza
input double  EmergencyStopFactor  = 3.0;   // Stop di emergenza = fattore * SL logico
input bool    DailyLimitsInPercent = false; // DailyProfit/MaxDD in % del saldo iniziale
input bool    CloseBeforeNews      = false; // Chiudi le posizioni all'inizio del blocco news

input string  s_news              = "===== CALENDARIO NOTIZIE =====";
input string  NewsCalendarUrl     = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml"; // URL del calendario
input bool    NewsHighImpactOnly  = true;   // Considera solo le notizie ad alto impatto
input double  NewsFeedGmtOffset   = 0.0;    // Fuso orario del feed rispetto a GMT (ore)
input string  ManualNewsTimes     = "";     // Notizie manuali "YYYY.MM.DD HH:MM;..."

input string  s_ui                = "===== INTERFACCIA =====";
input int     PanelCorner         = 0;      // Angolo del pannello (0=TL 1=TR 2=BL 3=BR)
input color   PanelTextColor      = clrWhite;   // Colore del testo
input color   PanelAccentColor    = clrDeepSkyBlue; // Colore dei titoli

//+------------------------------------------------------------------+
//| Stato globale                                                    |
//+------------------------------------------------------------------+
#define PANEL_PREFIX "SEA_"
#define GV_PREFIX    "ScalpEA_"

double   g_point          = 0.0;   // valore di un punto
int      g_digits         = 0;     // cifre decimali del simbolo
double   g_stopLevel      = 0.0;   // MODE_STOPLEVEL in punti
double   g_freezeLevel    = 0.0;   // MODE_FREEZELEVEL in punti
double   g_spreadPoints   = 0.0;   // spread corrente in punti
double   g_lots           = 0.0;   // Lots normalizzato sul passo del broker

int      g_dayStamp       = -1;    // giorno di riferimento (aaaammgg)
double   g_dayStartBalance= 0.0;   // saldo all'inizio della giornata
bool     g_dayBlocked     = false; // giornata chiusa da DailyProfit o MaxDD
string   g_dayBlockReason = "";
int      g_tradesToday    = 0;

datetime g_lastTradeTime  = 0;
int      g_sarChain       = 0;     // reversal consecutivi gia' eseguiti
string   g_lastBlock      = "-";   // ultimo filtro che ha bloccato un ingresso

int      g_snapTicket[];           // tickets aperti al termine del tick precedente
int      g_snapType[];
double   g_snapOpen[];
int      g_closedByEa[];           // tickets chiusi dall'EA in questo tick

int      g_sarQueue[];             // reversal da eseguire (OP_BUY / OP_SELL)

datetime g_newsTime[];             // calendario in ora server
string   g_newsTitle[];
string   g_newsCurrency[];
string   g_newsImpact[];
datetime g_newsLastLoad   = 0;
bool     g_newsAvailable  = false;
string   g_newsStatus     = "non caricato";
datetime g_nextNewsTime   = 0;
string   g_nextNewsLabel  = "-";

int      g_serverGmtOffset= 0;     // secondi tra ora server e GMT
datetime g_lastPanelPaint = 0;

double   g_realizedCache     = 0.0; // realizzato di giornata gia' calcolato
datetime g_realizedCacheTime = 0;   // istante del calcolo (0 = da rifare)

//+------------------------------------------------------------------+
//| Inizializzazione                                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   g_point  = MarketInfo(Symbol(), MODE_POINT);
   if(g_point <= 0.0)
      g_point = Point;

   if(Lots <= 0.0)
     {
      Print("ScalpEA: Lots deve essere maggiore di zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(maxOrders <= 0)
     {
      Print("ScalpEA: maxOrders deve essere maggiore di zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(EntryDistance <= 0)
     {
      Print("ScalpEA: EntryDistance deve essere maggiore di zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(SignalBars <= 0)
     {
      Print("ScalpEA: SignalBars deve essere maggiore di zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // Il lotto va allineato al passo del broker: 0.015 su un passo di 0.01
   // non viene rifiutato dall'EA ma dal server, a mercato gia' aperto.
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   g_lots = Lots;
   if(lotStep > 0.0)
      g_lots = MathRound(g_lots / lotStep) * lotStep;
   if(minLot > 0.0 && g_lots < minLot)
      g_lots = minLot;
   if(maxLot > 0.0 && g_lots > maxLot)
      g_lots = maxLot;
   int lotDigits = 3;
   if(lotStep >= 0.1)       lotDigits = 1;
   else if(lotStep >= 0.01) lotDigits = 2;
   g_lots = NormalizeDouble(g_lots, lotDigits);
   if(MathAbs(g_lots - Lots) > 0.0000001)
      Print("ScalpEA: Lots ", DoubleToString(Lots, 3), " adattato a ",
            DoubleToString(g_lots, 2), " dai vincoli del broker.");

   ArrayResize(g_snapTicket, 0);
   ArrayResize(g_snapType,   0);
   ArrayResize(g_snapOpen,   0);
   ArrayResize(g_closedByEa, 0);
   ArrayResize(g_sarQueue,   0);

   UpdateServerGmtOffset();
   ResetDayState(true);
   SnapshotOpenTickets();

   if(NewsFilter)
      LoadNewsCalendar();

   if(showPanel && !IsOptimization())
      BuildPanel();

   Print("ScalpEA v1.10 avviato su ", Symbol(), " ", TimeframeToString((ENUM_TIMEFRAMES)Period()),
         " | Magic ", Magic, " | livelli ", (UseVirtualLevels ? "virtuali" : "sul broker"));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinizializzazione                                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PANEL_PREFIX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Utility di base                                                  |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
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
   return("TF" + IntegerToString((int)tf));
  }

//| Aggiorna spread, stop level e freeze level dal broker.
void UpdateSymbolInfo()
  {
   g_stopLevel    = MarketInfo(Symbol(), MODE_STOPLEVEL);
   g_freezeLevel  = MarketInfo(Symbol(), MODE_FREEZELEVEL);
   double spread  = MarketInfo(Symbol(), MODE_SPREAD);
   if(spread <= 0.0 && g_point > 0.0)
      spread = (Ask - Bid) / g_point;
   g_spreadPoints = spread;
  }

//| Differenza tra ora del server e GMT, arrotondata alla mezz'ora.
void UpdateServerGmtOffset()
  {
   datetime gmt = TimeGMT();
   if(gmt <= 0)
     {
      g_serverGmtOffset = 0;
      return;
     }
   double diff = (double)(TimeCurrent() - gmt);
   g_serverGmtOffset = (int)(MathRound(diff / 1800.0) * 1800.0);
  }

//| Numero intero aaaammgg che identifica la giornata di trading.
int DayStamp(datetime t)
  {
   MqlDateTime st;
   TimeToStruct(t, st);
   return(st.year * 10000 + st.mon * 100 + st.day);
  }

//| true se il ticket compare nell'array indicato.
bool ArrayHasInt(const int &arr[], int value)
  {
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++)
      if(arr[i] == value)
         return(true);
   return(false);
  }

void ArrayPushInt(int &arr[], int value)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n] = value;
  }

//+------------------------------------------------------------------+
//| Livelli: da modalita' e ATR ai punti effettivi                   |
//+------------------------------------------------------------------+
//| ATR del timeframe operativo espresso in punti.
double AtrPoints()
  {
   double atr = iATR(Symbol(), (ENUM_TIMEFRAMES)Period(), ATR_Period, 1);
   if(atr <= 0.0)
      atr = iATR(Symbol(), (ENUM_TIMEFRAMES)Period(), ATR_Period, 0);
   if(atr <= 0.0 || g_point <= 0.0)
      return(0.0);
   return(atr / g_point);
  }

//| Distanza minima utilizzabile: stop level del broker piu' un punto.
double MinBrokerDistance()
  {
   double d = g_stopLevel;
   if(g_freezeLevel > d)
      d = g_freezeLevel;
   return(d + 1.0);
  }

//| Take profit in punti secondo la modalita' scelta.
double TakeProfitPoints()
  {
   if(TakeProfit == LEVEL_DISABLED)
      return(0.0);

   double tp;
   if(TakeProfit == LEVEL_MANUAL)
      tp = (double)ManualTakeProfitPoints;
   else
      tp = AutoTP_ATR * AtrPoints();

   // Un take profit che non copre lo spread non e' un target, e' un costo.
   double minBySpread = AutoTP_MinSpreadRatio * g_spreadPoints;
   if(tp < minBySpread)
      tp = minBySpread;

   double minBroker = MinBrokerDistance();
   if(!UseVirtualLevels && tp < minBroker)
      tp = minBroker;

   if(tp < 1.0)
      tp = 0.0;
   return(tp);
  }

//| Stop loss in punti secondo la modalita' scelta.
double StopLossPoints()
  {
   if(StopLoss == LEVEL_DISABLED)
      return(0.0);

   double sl;
   if(StopLoss == LEVEL_MANUAL)
     {
      // La distanza in prezzo e' indipendente dalle cifre decimali del
      // broker: 0.90 su XAUUSD vale 0.90 dollari sia a 2 sia a 3 decimali,
      // mentre 90 punti valgono 0.90 o 0.09 a seconda del server.
      if(StopLossPriceDistance > 0.0 && g_point > 0.0)
         sl = StopLossPriceDistance / g_point;
      else
         sl = (double)ManualStopLossPoints;
     }
   else
      sl = AutoSL_ATR * AtrPoints();

   double minBroker = MinBrokerDistance();
   if(!UseVirtualLevels && sl < minBroker)
      sl = minBroker;

   if(sl < 1.0)
      sl = 0.0;
   return(sl);
  }

//| Distanza del trailing stop in punti.
double TrailingPoints()
  {
   if(TrailingStop == LEVEL_DISABLED)
      return(0.0);

   double ts;
   if(TrailingStop == LEVEL_MANUAL)
     {
      if(TrailingPriceDistance > 0.0 && g_point > 0.0)
         ts = TrailingPriceDistance / g_point;
      else
         ts = (double)ManualTrailingPoints;
     }
   else
      ts = AutoTS_ATR * AtrPoints();

   double minBroker = MinBrokerDistance();
   if(!UseVirtualLevels && ts < minBroker)
      ts = minBroker;

   if(ts < 1.0)
      ts = 0.0;
   return(ts);
  }

//+------------------------------------------------------------------+
//| Filtro orario: giorni, finestre, NFP, festivita'                 |
//+------------------------------------------------------------------+
//| Converte "HH:MM" nei minuti trascorsi da mezzanotte. -1 se invalido.
int ParseHhMm(string value)
  {
   string s = value;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) < 3)
      return(-1);

   int sep = StringFind(s, ":");
   if(sep < 0)
      return(-1);

   int hh = (int)StringToInteger(StringSubstr(s, 0, sep));
   int mm = (int)StringToInteger(StringSubstr(s, sep + 1));
   if(hh < 0 || hh > 24 || mm < 0 || mm > 59)
      return(-1);

   return(hh * 60 + mm);
  }

//| Il giorno della settimana e' abilitato negli input?
bool DayEnabled(int dayOfWeek)
  {
   switch(dayOfWeek)
     {
      case 1: return(Monday);
      case 2: return(Tuesday);
      case 3: return(Wednesday);
      case 4: return(Thursday);
      case 5: return(Friday);
     }
   return(false); // sabato e domenica
  }

string DayStartTime(int dayOfWeek)
  {
   switch(dayOfWeek)
     {
      case 1: return(MondayStartTime);
      case 2: return(TuesdayStartTime);
      case 3: return(WednesdayStartTime);
      case 4: return(ThursdayStartTime);
      case 5: return(FridayStartTime);
     }
   return("");
  }

string DayEndTime(int dayOfWeek)
  {
   switch(dayOfWeek)
     {
      case 1: return(MondayEndTime);
      case 2: return(TuesdayEndTime);
      case 3: return(WednesdayEndTime);
      case 4: return(ThursdayEndTime);
      case 5: return(FridayEndTime);
     }
   return("");
  }

//| true se la data e' il primo venerdi' del mese (giorno dei Non Farm Payrolls).
bool IsNonFarmFriday(datetime t)
  {
   MqlDateTime st;
   TimeToStruct(t, st);
   if(st.day_of_week != 5)
      return(false);
   return(st.day <= 7);
  }

//| Finestra festiva di fine anno: dal 12 dicembre al 12 gennaio.
bool IsHolidayPeriod(datetime t)
  {
   MqlDateTime st;
   TimeToStruct(t, st);
   if(st.mon == 12 && st.day >= 12)
      return(true);
   if(st.mon == 1 && st.day <= 12)
      return(true);
   return(false);
  }

//| Filtro orario completo. reason riceve il motivo del blocco.
bool TimeAllowed(datetime now, string &reason)
  {
   MqlDateTime st;
   TimeToStruct(now, st);
   int dow = st.day_of_week;

   if(!DayEnabled(dow))
     {
      reason = "giorno disabilitato";
      return(false);
     }
   if(!TradingNonFarmFriday && IsNonFarmFriday(now))
     {
      reason = "venerdi' NFP";
      return(false);
     }
   if(!TradingDuringHolidays && IsHolidayPeriod(now))
     {
      reason = "periodo festivo";
      return(false);
     }
   if(Trading24h)
      return(true);

   int start = ParseHhMm(DayStartTime(dow));
   int end   = ParseHhMm(DayEndTime(dow));
   if(start < 0 || end < 0)
     {
      reason = "orario non valido";
      return(false);
     }
   if(start == end)
      return(true); // finestra di 24 ore

   int nowMin = st.hour * 60 + st.min;
   bool inside;
   if(start < end)
      inside = (nowMin >= start && nowMin < end);
   else
      inside = (nowMin >= start || nowMin < end); // finestra a cavallo della mezzanotte

   if(!inside)
     {
      reason = "fuori sessione";
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Filtro notizie                                                   |
//+------------------------------------------------------------------+
//| Estrae il contenuto di <tag>...</tag>, gestendo i blocchi CDATA.
string XmlTagValue(string block, string tag)
  {
   string open  = "<"  + tag + ">";
   string close = "</" + tag + ">";

   int a = StringFind(block, open);
   if(a < 0)
      return("");
   a += StringLen(open);

   int b = StringFind(block, close, a);
   if(b < 0)
      return("");

   string v = StringSubstr(block, a, b - a);
   int c = StringFind(v, "<![CDATA[");
   if(c >= 0)
     {
      v = StringSubstr(v, c + 9);
      int d = StringFind(v, "]]>");
      if(d >= 0)
         v = StringSubstr(v, 0, d);
     }
   StringTrimLeft(v);
   StringTrimRight(v);
   return(v);
  }

//| Converte "MM-DD-YYYY" + "1:30pm" nell'ora del feed. 0 se non valido.
datetime ParseFeedDateTime(string dateStr, string timeStr)
  {
   if(StringLen(dateStr) < 8 || StringLen(timeStr) < 3)
      return(0);

   string parts[];
   if(StringSplit(dateStr, '-', parts) != 3)
      return(0);

   int mm = (int)StringToInteger(parts[0]);
   int dd = (int)StringToInteger(parts[1]);
   int yy = (int)StringToInteger(parts[2]);
   if(mm < 1 || mm > 12 || dd < 1 || dd > 31 || yy < 2000)
      return(0);

   string t = timeStr;
   StringToLower(t);
   StringTrimLeft(t);
   StringTrimRight(t);
   if(StringFind(t, "day") >= 0 || StringFind(t, "tentative") >= 0)
      return(0); // "All Day" / "Tentative": nessun orario utilizzabile

   bool pm = (StringFind(t, "pm") >= 0);
   bool am = (StringFind(t, "am") >= 0);
   StringReplace(t, "pm", "");
   StringReplace(t, "am", "");
   StringTrimLeft(t);
   StringTrimRight(t);

   int sep = StringFind(t, ":");
   if(sep < 0)
      return(0);

   int hh = (int)StringToInteger(StringSubstr(t, 0, sep));
   int mi = (int)StringToInteger(StringSubstr(t, sep + 1));
   if(pm && hh < 12)
      hh += 12;
   if(am && hh == 12)
      hh = 0;
   if(hh < 0 || hh > 23 || mi < 0 || mi > 59)
      return(0);

   string iso = StringFormat("%04d.%02d.%02d %02d:%02d", yy, mm, dd, hh, mi);
   return(StringToTime(iso));
  }

//| La valuta dell'evento e' tra quelle sorvegliate?
bool CurrencyWatched(string cur)
  {
   if(cur == "USD") return(ReportUSD);
   if(cur == "EUR") return(ReportEUR);
   if(cur == "GBP") return(ReportGBP);
   if(cur == "JPY") return(ReportJPY);
   return(false);
  }

void NewsListClear()
  {
   ArrayResize(g_newsTime, 0);
   ArrayResize(g_newsTitle, 0);
   ArrayResize(g_newsCurrency, 0);
   ArrayResize(g_newsImpact, 0);
  }

void NewsListAdd(datetime t, string title, string cur, string impact)
  {
   int n = ArraySize(g_newsTime);
   ArrayResize(g_newsTime,     n + 1);
   ArrayResize(g_newsTitle,    n + 1);
   ArrayResize(g_newsCurrency, n + 1);
   ArrayResize(g_newsImpact,   n + 1);
   g_newsTime[n]     = t;
   g_newsTitle[n]    = title;
   g_newsCurrency[n] = cur;
   g_newsImpact[n]   = impact;
  }

//| Aggiunge le notizie inserite a mano in ManualNewsTimes.
void LoadManualNews()
  {
   if(StringLen(ManualNewsTimes) == 0)
      return;

   string items[];
   int n = StringSplit(ManualNewsTimes, ';', items);
   for(int i = 0; i < n; i++)
     {
      string s = items[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(StringLen(s) < 10)
         continue;
      datetime t = StringToTime(s);
      if(t > 0)
         NewsListAdd(t, "Manuale", "---", "High");
     }
  }

//| Scarica e interpreta il calendario. WebRequest non e' disponibile
//| nello Strategy Tester: in quel caso restano solo le notizie manuali.
void LoadNewsCalendar()
  {
   NewsListClear();
   g_newsAvailable = false;
   g_newsLastLoad  = TimeCurrent();

   LoadManualNews();

   if(IsTesting() || IsOptimization())
     {
      g_newsStatus = "tester: solo notizie manuali";
      g_newsAvailable = (ArraySize(g_newsTime) > 0);
      return;
     }
   if(StringLen(NewsCalendarUrl) == 0)
     {
      g_newsStatus = "URL non impostato";
      g_newsAvailable = (ArraySize(g_newsTime) > 0);
      return;
     }

   char   post[];
   char   result[];
   string resultHeaders = "";
   ResetLastError();
   int code = WebRequest("GET", NewsCalendarUrl, "", 8000, post, result, resultHeaders);

   if(code != 200)
     {
      int err = GetLastError();
      if(err == 4060)
         g_newsStatus = "URL non autorizzato in MT4";
      else
         g_newsStatus = "download fallito (HTTP " + IntegerToString(code) + ", err " + IntegerToString(err) + ")";
      Print("ScalpEA: calendario notizie non disponibile - ", g_newsStatus,
            ". Aggiungere l'URL in Strumenti > Opzioni > Expert Advisors > URL consentiti.");
      g_newsAvailable = (ArraySize(g_newsTime) > 0);
      return;
     }

   string xml = CharArrayToString(result, 0, ArraySize(result), CP_UTF8);
   int shift  = g_serverGmtOffset - (int)MathRound(NewsFeedGmtOffset * 3600.0);
   int parsed = 0;
   int pos    = 0;

   while(true)
     {
      int a = StringFind(xml, "<event>", pos);
      if(a < 0)
         break;
      int b = StringFind(xml, "</event>", a);
      if(b < 0)
         break;

      string block = StringSubstr(xml, a, b - a);
      pos = b + 8;

      string impact = XmlTagValue(block, "impact");
      if(NewsHighImpactOnly && StringFind(impact, "High") < 0)
         continue;

      string cur = XmlTagValue(block, "country");
      if(!CurrencyWatched(cur))
         continue;

      datetime feedTime = ParseFeedDateTime(XmlTagValue(block, "date"), XmlTagValue(block, "time"));
      if(feedTime <= 0)
         continue;

      NewsListAdd(feedTime + shift, XmlTagValue(block, "title"), cur, impact);
      parsed++;
     }

   g_newsAvailable = (ArraySize(g_newsTime) > 0);
   g_newsStatus    = IntegerToString(parsed) + " eventi caricati";
   Print("ScalpEA: calendario notizie aggiornato, ", parsed, " eventi rilevanti (ora server).");
  }

//| true se il momento indicato ricade nella finestra di blocco di una notizia.
bool NewsBlocked(datetime now, string &label)
  {
   g_nextNewsTime  = 0;
   g_nextNewsLabel = "-";

   if(!NewsFilter)
      return(false);

   int before = doNotTradeBeforeInMinutes * 60;
   int after  = doNotTradeAfterInMinutes  * 60;
   int n      = ArraySize(g_newsTime);
   bool blocked = false;

   for(int i = 0; i < n; i++)
     {
      datetime t = g_newsTime[i];
      if(now >= t - before && now <= t + after)
        {
         blocked = true;
         label   = g_newsCurrency[i] + " " + g_newsTitle[i] + " " + TimeToString(t, TIME_MINUTES);
         g_nextNewsTime  = t;
         g_nextNewsLabel = label;
         return(true);
        }
      if(t > now && (g_nextNewsTime == 0 || t < g_nextNewsTime))
        {
         g_nextNewsTime  = t;
         g_nextNewsLabel = g_newsCurrency[i] + " " + g_newsTitle[i] + " " + TimeToString(t, TIME_MINUTES);
        }
     }
   return(blocked);
  }

//+------------------------------------------------------------------+
//| Gestione degli ordini                                            |
//+------------------------------------------------------------------+
//| Nome della variabile globale che conserva un livello virtuale.
string GvName(int ticket, string suffix)
  {
   return(GV_PREFIX + IntegerToString(Magic) + "_" + IntegerToString(ticket) + "_" + suffix);
  }

void ForgetLevels(int ticket)
  {
   string a = GvName(ticket, "TP");
   string b = GvName(ticket, "SL");
   if(GlobalVariableCheck(a)) GlobalVariableDel(a);
   if(GlobalVariableCheck(b)) GlobalVariableDel(b);
  }

void StoreLevels(int ticket, double tp, double sl)
  {
   GlobalVariableSet(GvName(ticket, "TP"), tp);
   GlobalVariableSet(GvName(ticket, "SL"), sl);
  }

//| Recupera i livelli virtuali del ticket; se mancano li ricostruisce
//| dai parametri correnti (caso tipico: EA riavviato a mercato aperto).
void EnsureLevels(int ticket, int type, double openPrice, double &tp, double &sl)
  {
   string nameTp = GvName(ticket, "TP");
   string nameSl = GvName(ticket, "SL");

   if(GlobalVariableCheck(nameTp) && GlobalVariableCheck(nameSl))
     {
      tp = GlobalVariableGet(nameTp);
      sl = GlobalVariableGet(nameSl);
      return;
     }

   double tpPts = TakeProfitPoints();
   double slPts = StopLossPoints();
   tp = 0.0;
   sl = 0.0;
   if(type == OP_BUY)
     {
      if(tpPts > 0.0) tp = openPrice + tpPts * g_point;
      if(slPts > 0.0) sl = openPrice - slPts * g_point;
     }
   else
     {
      if(tpPts > 0.0) tp = openPrice - tpPts * g_point;
      if(slPts > 0.0) sl = openPrice + slPts * g_point;
     }
   StoreLevels(ticket, tp, sl);
  }

//| Numero di posizioni aperte dall'EA. type = -1 per contarle tutte.
int CountOurOrders(int type = -1)
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != Magic || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(type >= 0 && OrderType() != type)
         continue;
      count++;
     }
   return(count);
  }

//| Profitto flottante complessivo delle posizioni dell'EA.
double FloatingProfit()
  {
   double sum = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != Magic || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
     }
   return(sum);
  }

//| Somma algebrica dei punti a mercato: base di "Total SL [points]".
double FloatingPoints()
  {
   double sum = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != Magic || OrderSymbol() != Symbol())
         continue;
      if(OrderType() == OP_BUY)
         sum += (Bid - OrderOpenPrice()) / g_point;
      else
         if(OrderType() == OP_SELL)
            sum += (OrderOpenPrice() - Ask) / g_point;
     }
   return(sum);
  }

//| Profitto realizzato oggi dalle operazioni dell'EA. La storia viene
//| riletta al massimo una volta al secondo, e sempre dopo una chiusura.
double RealizedToday()
  {
   if(g_realizedCacheTime == TimeCurrent())
      return(g_realizedCache);

   double sum = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderMagicNumber() != Magic || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      if(DayStamp(OrderCloseTime()) != g_dayStamp)
         continue;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
     }

   g_realizedCache     = sum;
   g_realizedCacheTime = TimeCurrent();
   return(sum);
  }

//| Risultato della giornata: realizzato piu' flottante.
double DayProfit()
  {
   return(RealizedToday() + FloatingProfit());
  }

//| Fotografa i ticket aperti: serve a riconoscere le chiusure del broker.
void SnapshotOpenTickets()
  {
   ArrayResize(g_snapTicket, 0);
   ArrayResize(g_snapType,   0);
   ArrayResize(g_snapOpen,   0);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != Magic || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      int n = ArraySize(g_snapTicket);
      ArrayResize(g_snapTicket, n + 1);
      ArrayResize(g_snapType,   n + 1);
      ArrayResize(g_snapOpen,   n + 1);
      g_snapTicket[n] = OrderTicket();
      g_snapType[n]   = OrderType();
      g_snapOpen[n]   = OrderOpenPrice();
     }
  }

//| Il ticket risulta ancora aperto?
bool TicketStillOpen(int ticket)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return(false);
   return(OrderCloseTime() == 0);
  }

//| Chiusure avvenute lato broker (stop di emergenza, stop out, intervento
//| manuale): se in perdita alimentano la coda SAR come le chiusure interne.
void DetectBrokerClosures()
  {
   int n = ArraySize(g_snapTicket);
   for(int i = 0; i < n; i++)
     {
      int ticket = g_snapTicket[i];
      if(TicketStillOpen(ticket))
         continue;
      if(ArrayHasInt(g_closedByEa, ticket))
         continue; // gia' gestita dall'EA in questo tick

      double profit = 0.0;
      bool   known  = false;
      if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
        {
         profit = OrderProfit() + OrderSwap() + OrderCommission();
         known  = true;
        }
      ForgetLevels(ticket);
      g_realizedCacheTime = 0;

      if(!known)
         continue;
      if(profit >= 0.0)
         g_sarChain = 0;
      else
        {
         int opposite = (g_snapType[i] == OP_BUY ? OP_SELL : OP_BUY);
         QueueSar(opposite, "chiusura broker in perdita");
        }
     }
  }

//| Accoda un reversal, rispettando il limite di catena.
void QueueSar(int type, string why)
  {
   if(!SAR)
      return;
   if(MaxSarChain > 0 && g_sarChain >= MaxSarChain)
     {
      g_lastBlock = "catena SAR esaurita";
      return;
     }
   ArrayPushInt(g_sarQueue, type);
   if(!IsOptimization())
      Print("ScalpEA: SAR accodato (", (type == OP_BUY ? "BUY" : "SELL"), ") - ", why);
  }

//| Chiude una posizione a mercato. sarOnLoss abilita il reversal.
bool ClosePositionByTicket(int ticket, string reason, bool sarOnLoss)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
      return(false);
   if(OrderCloseTime() != 0)
      return(false);

   int    type   = OrderType();
   double lots   = OrderLots();
   double profit = OrderProfit() + OrderSwap() + OrderCommission();

   for(int attempt = 0; attempt < 3; attempt++)
     {
      if(IsTradeContextBusy())
        {
         Sleep(200);
         continue;
        }
      RefreshRates();
      double price = (type == OP_BUY ? Bid : Ask);
      if(OrderClose(ticket, lots, NormalizeDouble(price, g_digits), Slippage,
                    (type == OP_BUY ? clrDodgerBlue : clrOrangeRed)))
        {
         ArrayPushInt(g_closedByEa, ticket);
         ForgetLevels(ticket);
         g_realizedCacheTime = 0;
         if(!IsOptimization())
            Print("ScalpEA: chiusa #", ticket, " (", reason, ") P/L ",
                  DoubleToString(profit, 2));
         if(profit >= 0.0)
            g_sarChain = 0;
         else
            if(sarOnLoss)
               QueueSar(type == OP_BUY ? OP_SELL : OP_BUY, reason);
         return(true);
        }
      int err = GetLastError();
      if(err != ERR_REQUOTE && err != ERR_PRICE_CHANGED && err != ERR_OFF_QUOTES &&
         err != ERR_TRADE_CONTEXT_BUSY)
        {
         Print("ScalpEA: OrderClose #", ticket, " fallita, errore ", err);
         break;
        }
      Sleep(200);
     }
   return(false);
  }

//| Chiude tutte le posizioni dell'EA senza innescare reversal.
int CloseAllPositions(string reason)
  {
   int closed = 0;
   for(int pass = 0; pass < 3; pass++)
     {
      bool again = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            continue;
         if(OrderMagicNumber() != Magic || OrderSymbol() != Symbol())
            continue;
         if(OrderType() != OP_BUY && OrderType() != OP_SELL)
            continue;
         if(ClosePositionByTicket(OrderTicket(), reason, false))
            closed++;
         else
            again = true;
        }
      if(!again)
         break;
     }
   return(closed);
  }

//| La direzione richiesta e' consentita da TradeDirection?
bool DirectionAllowed(int type)
  {
   if(TradeDirection == DIR_BUY_ONLY)
      return(type == OP_BUY);
   if(TradeDirection == DIR_SELL_ONLY)
      return(type == OP_SELL);
   return(true);
  }

//| Nessun ordine dello stesso verso entro EntryDistance punti dal prezzo.
bool SpacingOk(int type)
  {
   double ref     = (type == OP_BUY ? Ask : Bid);
   double minDist = EntryDistance * g_point;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != Magic || OrderSymbol() != Symbol())
         continue;
      if(OrderType() != type)
         continue;
      if(MathAbs(OrderOpenPrice() - ref) < minDist)
         return(false);
     }
   return(true);
  }

//| Apre una posizione a mercato. isSar salta il controllo di distanza,
//| perche' il reversal deve poter nascere sul livello appena stoppato.
bool TryOpenPosition(int type, string why, bool isSar)
  {
   if(!DirectionAllowed(type))
     {
      g_lastBlock = "direzione non consentita";
      return(false);
     }
   if(!IsTradeAllowed())
     {
      g_lastBlock = "trading non consentito dal terminale";
      return(false);
     }
   if(CountOurOrders() >= maxOrders)
     {
      g_lastBlock = "maxOrders raggiunto";
      return(false);
     }
   if(MaxSpreadPoints > 0.0 && g_spreadPoints > MaxSpreadPoints)
     {
      g_lastBlock = "spread " + DoubleToString(g_spreadPoints, 1) + " pt";
      return(false);
     }
   if(MinSecondsBetweenTrades > 0 &&
      (int)(TimeCurrent() - g_lastTradeTime) < MinSecondsBetweenTrades)
     {
      g_lastBlock = "pausa tra ingressi";
      return(false);
     }
   if(!isSar && !SpacingOk(type))
     {
      g_lastBlock = "distanza < EntryDistance";
      return(false);
     }

   double tpPts = TakeProfitPoints();
   double slPts = StopLossPoints();

   double sendSl = 0.0;
   double sendTp = 0.0;
   double virtTp = 0.0;
   double virtSl = 0.0;

   for(int attempt = 0; attempt < 3; attempt++)
     {
      if(IsTradeContextBusy())
        {
         Sleep(200);
         continue;
        }
      RefreshRates();
      double price = NormalizeDouble(type == OP_BUY ? Ask : Bid, g_digits);
      sendSl = 0.0;
      sendTp = 0.0;

      if(UseVirtualLevels)
        {
         if(UseEmergencyBrokerStop && slPts > 0.0)
           {
            double emPts = slPts * EmergencyStopFactor;
            double minPts = MinBrokerDistance();
            if(emPts < minPts)
               emPts = minPts;
            sendSl = NormalizeDouble(type == OP_BUY ? price - emPts * g_point
                                                    : price + emPts * g_point, g_digits);
           }
        }
      else
        {
         if(tpPts > 0.0)
            sendTp = NormalizeDouble(type == OP_BUY ? price + tpPts * g_point
                                                    : price - tpPts * g_point, g_digits);
         if(slPts > 0.0)
            sendSl = NormalizeDouble(type == OP_BUY ? price - slPts * g_point
                                                    : price + slPts * g_point, g_digits);
        }

      int ticket = OrderSend(Symbol(), type, g_lots, price, Slippage, sendSl, sendTp,
                             TradeComment, Magic, 0,
                             (type == OP_BUY ? clrDodgerBlue : clrOrangeRed));
      if(ticket > 0)
        {
         if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
            price = OrderOpenPrice();

         if(tpPts > 0.0)
            virtTp = NormalizeDouble(type == OP_BUY ? price + tpPts * g_point
                                                    : price - tpPts * g_point, g_digits);
         if(slPts > 0.0)
            virtSl = NormalizeDouble(type == OP_BUY ? price - slPts * g_point
                                                    : price + slPts * g_point, g_digits);
         StoreLevels(ticket, virtTp, virtSl);

         g_lastTradeTime = TimeCurrent();
         g_tradesToday++;
         if(isSar)
            g_sarChain++;
         else
            g_sarChain = 0;

         if(!IsOptimization())
            Print("ScalpEA: aperta #", ticket, " ", (type == OP_BUY ? "BUY" : "SELL"),
                  " a ", DoubleToString(price, g_digits),
                  " TP ", DoubleToString(virtTp, g_digits),
                  " SL ", DoubleToString(virtSl, g_digits),
                  " (", why, ")");
         return(true);
        }

      int err = GetLastError();
      if(err != ERR_REQUOTE && err != ERR_PRICE_CHANGED && err != ERR_OFF_QUOTES &&
         err != ERR_TRADE_CONTEXT_BUSY)
        {
         Print("ScalpEA: OrderSend fallita, errore ", err);
         g_lastBlock = "errore ordine " + IntegerToString(err);
         break;
        }
      Sleep(200);
     }
   return(false);
  }

//| Sorveglianza dei livelli: take profit, stop loss e trailing.
void ManageOpenPositions()
  {
   double tsPts   = TrailingPoints();
   double stepPts = (double)TrailingStepPoints;
   if(stepPts < 1.0)
      stepPts = 1.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != Magic || OrderSymbol() != Symbol())
         continue;

      int    type   = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;

      int    ticket = OrderTicket();
      double open   = OrderOpenPrice();
      double tp = 0.0, sl = 0.0;
      EnsureLevels(ticket, type, open, tp, sl);

      if(UseVirtualLevels)
        {
         // 1. Uscita in profitto
         if(tp > 0.0 &&
            ((type == OP_BUY && Bid >= tp) || (type == OP_SELL && Ask <= tp)))
           {
            ClosePositionByTicket(ticket, "take profit", false);
            continue;
           }
         // 2. Uscita sullo stop. Se il trailing lo ha gia' portato oltre il
         //    prezzo di apertura non e' piu' lo stop iniziale ma la presa di
         //    profitto del sistema: va detto cosi' nel journal.
         if(sl > 0.0 &&
            ((type == OP_BUY && Bid <= sl) || (type == OP_SELL && Ask >= sl)))
           {
            bool trailed = (type == OP_BUY ? sl > open : sl < open);
            ClosePositionByTicket(ticket, (trailed ? "trailing stop" : "stop loss"), true);
            continue;
           }
         // 3. Trailing sul livello virtuale
         if(tsPts > 0.0)
           {
            if(type == OP_BUY)
              {
               double gainPts = (Bid - open) / g_point;
               if(gainPts >= tsPts + g_spreadPoints)
                 {
                  double newSl = NormalizeDouble(Bid - tsPts * g_point, g_digits);
                  if(newSl > sl + stepPts * g_point || sl == 0.0)
                    {
                     sl = newSl;
                     StoreLevels(ticket, tp, sl);
                    }
                 }
              }
            else
              {
               double gainPts = (open - Ask) / g_point;
               if(gainPts >= tsPts + g_spreadPoints)
                 {
                  double newSl = NormalizeDouble(Ask + tsPts * g_point, g_digits);
                  if(sl == 0.0 || newSl < sl - stepPts * g_point)
                    {
                     sl = newSl;
                     StoreLevels(ticket, tp, sl);
                    }
                 }
              }
           }
         continue;
        }

      // Livelli reali sul broker: il trailing passa da OrderModify.
      if(tsPts <= 0.0)
         continue;

      double curSl  = OrderStopLoss();
      double curTp  = OrderTakeProfit();
      double minPts = MinBrokerDistance();

      if(type == OP_BUY)
        {
         double gainPts = (Bid - open) / g_point;
         if(gainPts < tsPts + g_spreadPoints)
            continue;
         double newSl = NormalizeDouble(Bid - tsPts * g_point, g_digits);
         if(Bid - newSl < minPts * g_point)
            newSl = NormalizeDouble(Bid - minPts * g_point, g_digits);
         if(newSl <= curSl + stepPts * g_point && curSl != 0.0)
            continue;
         if(!OrderModify(ticket, open, newSl, curTp, 0, clrDodgerBlue))
            Print("ScalpEA: OrderModify #", ticket, " fallita, errore ", GetLastError());
        }
      else
        {
         double gainPts = (open - Ask) / g_point;
         if(gainPts < tsPts + g_spreadPoints)
            continue;
         double newSl = NormalizeDouble(Ask + tsPts * g_point, g_digits);
         if(newSl - Ask < minPts * g_point)
            newSl = NormalizeDouble(Ask + minPts * g_point, g_digits);
         if(curSl != 0.0 && newSl >= curSl - stepPts * g_point)
            continue;
         if(!OrderModify(ticket, open, newSl, curTp, 0, clrOrangeRed))
            Print("ScalpEA: OrderModify #", ticket, " fallita, errore ", GetLastError());
        }
     }
  }

//| Limiti di paniere: Total SL, DailyProfit, MaxDD.
void CheckBasketLimits()
  {
   if(CountOurOrders() > 0 && TotalSL > 0)
     {
      double pts = FloatingPoints();
      if(pts <= -(double)TotalSL)
        {
         Print("ScalpEA: Total SL raggiunto (", DoubleToString(pts, 1), " punti). Chiusura del paniere.");
         CloseAllPositions("total SL");
         ArrayResize(g_sarQueue, 0);
         return;
        }
     }

   if(DailyProfit <= 0.0 && MaxDD <= 0.0)
      return;

   double dayPl  = DayProfit();
   double target = DailyProfit;
   double limit  = MaxDD;
   if(DailyLimitsInPercent && g_dayStartBalance > 0.0)
     {
      target = DailyProfit * g_dayStartBalance / 100.0;
      limit  = MaxDD       * g_dayStartBalance / 100.0;
     }

   if(DailyProfit > 0.0 && dayPl >= target)
     {
      Print("ScalpEA: obiettivo giornaliero raggiunto (", DoubleToString(dayPl, 2), "). Stop fino a domani.");
      CloseAllPositions("daily profit");
      ArrayResize(g_sarQueue, 0);
      g_dayBlocked     = true;
      g_dayBlockReason = "obiettivo giornaliero";
      return;
     }

   if(MaxDD > 0.0 && dayPl <= -limit)
     {
      Print("ScalpEA: perdita massima giornaliera raggiunta (", DoubleToString(dayPl, 2), "). Stop fino a domani.");
      CloseAllPositions("max DD");
      ArrayResize(g_sarQueue, 0);
      g_dayBlocked     = true;
      g_dayBlockReason = "perdita massima giornaliera";
     }
  }

//| Azzera i contatori all'inizio di ogni giornata di trading.
void ResetDayState(bool force)
  {
   int stamp = DayStamp(TimeCurrent());
   if(!force && stamp == g_dayStamp)
      return;

   g_dayStamp        = stamp;
   g_dayStartBalance = AccountBalance();
   g_dayBlocked      = false;
   g_dayBlockReason  = "";
   g_tradesToday     = 0;
   g_sarChain        = 0;
   g_realizedCacheTime = 0;

   if(!force && NewsFilter)
      LoadNewsCalendar();
  }

//| Segnale di ingresso: rottura del canale delle ultime SignalBars barre
//| di almeno EntryDistance punti. +1 acquisto, -1 vendita, 0 nessun segnale.
int EntrySignal()
  {
   int hi = iHighest(Symbol(), (ENUM_TIMEFRAMES)Period(), MODE_HIGH, SignalBars, 1);
   int lo = iLowest(Symbol(),  (ENUM_TIMEFRAMES)Period(), MODE_LOW,  SignalBars, 1);
   if(hi < 0 || lo < 0)
      return(0);

   double upper = iHigh(Symbol(), (ENUM_TIMEFRAMES)Period(), hi) + EntryDistance * g_point;
   double lower = iLow(Symbol(),  (ENUM_TIMEFRAMES)Period(), lo) - EntryDistance * g_point;

   if(Ask >= upper)
      return(1);
   if(Bid <= lower)
      return(-1);
   return(0);
  }

//| Esegue i reversal accodati e restituisce quanti ne ha aperti.
int ProcessSarQueue()
  {
   int n = ArraySize(g_sarQueue);
   if(n == 0)
      return(0);

   int opened = 0;
   for(int i = 0; i < n; i++)
      if(TryOpenPosition(g_sarQueue[i], "SAR", true))
         opened++;

   ArrayResize(g_sarQueue, 0);
   return(opened);
  }

//+------------------------------------------------------------------+
//| Pannello                                                         |
//+------------------------------------------------------------------+
#define PANEL_ROWS   16
#define PANEL_WIDTH  296
#define PANEL_X      10
#define PANEL_Y      18
#define PANEL_ROW_H  15

void BuildPanel()
  {
   string bg = PANEL_PREFIX + "bg";
   if(ObjectFind(0, bg) < 0)
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, bg, OBJPROP_CORNER,      PanelCorner);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   PANEL_X);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   PANEL_Y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,       PANEL_WIDTH);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,       PANEL_ROWS * PANEL_ROW_H + 14);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     C'10,10,10');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR,       clrDimGray);
   ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      true);
  }

//| Ordinata della riga: con gli angoli in basso la distanza si misura
//| verso l'alto, quindi le righe vanno numerate al contrario.
int PanelRowY(int index)
  {
   int height = PANEL_ROWS * PANEL_ROW_H + 14;
   if(PanelCorner == 2 || PanelCorner == 3)
      return(PANEL_Y + height - 7 - index * PANEL_ROW_H);
   return(PANEL_Y + 7 + index * PANEL_ROW_H);
  }

//| Scrive la riga index del pannello. Font monospaziato: le colonne
//| restano allineate senza calcolare posizioni separate.
void PanelRow(int index, string text, color clr)
  {
   string name = PANEL_PREFIX + "row" + IntegerToString(index);
   if(ObjectFind(0, name) < 0)
     {
      bool rightSide = (PanelCorner == 1 || PanelCorner == 3);
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     PanelCorner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     rightSide ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  PANEL_X + 8);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  PanelRowY(index));
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

string OnOff(bool v)
  {
   return(v ? "ON" : "OFF");
  }

//| Un livello a zero non e' "0 punti": non esiste.
string LevelText(double points)
  {
   if(points <= 0.0)
      return("off");
   return(StringFormat("%.0f pt", points));
  }

string DirectionName()
  {
   if(TradeDirection == DIR_BUY_ONLY)  return("BuyOnly");
   if(TradeDirection == DIR_SELL_ONLY) return("SellOnly");
   return("BuyAndSell");
  }

void UpdatePanel(bool timeOk, string timeReason, bool newsBlocked, string newsLabel)
  {
   if(!showPanel || IsOptimization())
      return;
   if(TimeCurrent() == g_lastPanelPaint)
      return;
   g_lastPanelPaint = TimeCurrent();

   int    buys   = CountOurOrders(OP_BUY);
   int    sells  = CountOurOrders(OP_SELL);
   double atrPts = AtrPoints();
   double dayPl  = DayProfit();
   double flt    = FloatingProfit();

   color okColor  = clrLimeGreen;
   color badColor = clrTomato;

   PanelRow(0,  "SCALP EA v1.10", PanelAccentColor);
   PanelRow(1,  "----------------------------------", clrDimGray);
   PanelRow(2,  StringFormat("%-11s %s %s", "Simbolo", Symbol(),
                             TimeframeToString((ENUM_TIMEFRAMES)Period())), PanelTextColor);
   PanelRow(3,  StringFormat("%-11s %.1f pt  (stop lv %.0f)", "Spread",
                             g_spreadPoints, g_stopLevel),
                (MaxSpreadPoints > 0.0 && g_spreadPoints > MaxSpreadPoints) ? badColor : PanelTextColor);
   PanelRow(4,  StringFormat("%-11s %.0f pt", "ATR(" + IntegerToString(ATR_Period) + ")", atrPts), PanelTextColor);
   PanelRow(5,  StringFormat("%-11s %s / %s", "TP / SL",
                             LevelText(TakeProfitPoints()),
                             LevelText(StopLossPoints())), PanelTextColor);
   PanelRow(6,  StringFormat("%-11s %s   livelli %s", "Trailing",
                             LevelText(TrailingPoints()),
                             (UseVirtualLevels ? "virtuali" : "broker")), PanelTextColor);
   PanelRow(7,  "----------------------------------", clrDimGray);
   PanelRow(8,  StringFormat("%-11s %s   SAR %s", "Direzione", DirectionName(), OnOff(SAR)), PanelTextColor);
   PanelRow(9,  StringFormat("%-11s %d/%d   buy %d  sell %d   %.2f lot", "Ordini",
                             buys + sells, maxOrders, buys, sells, g_lots), PanelTextColor);
   PanelRow(10, StringFormat("%-11s %.2f", "Flottante", flt), (flt >= 0.0 ? okColor : badColor));
   PanelRow(11, StringFormat("%-11s %.2f   trade %d", "Giorno", dayPl, g_tradesToday),
                (dayPl >= 0.0 ? okColor : badColor));
   PanelRow(12, "----------------------------------", clrDimGray);
   PanelRow(13, StringFormat("%-11s %s", "Sessione", (timeOk ? "attiva" : timeReason)),
                (timeOk ? okColor : badColor));
   PanelRow(14, StringFormat("%-11s %s", "News",
                             (!NewsFilter ? "filtro OFF"
                              : (newsBlocked ? "BLOCCO " + newsLabel
                                 : g_newsStatus + " | " + g_nextNewsLabel))),
                (newsBlocked ? badColor : PanelTextColor));

   string state;
   color  stateColor;
   if(g_dayBlocked)
     {
      state      = "fermo: " + g_dayBlockReason;
      stateColor = badColor;
     }
   else
      if(!timeOk || newsBlocked)
        {
         state      = "in attesa (" + (newsBlocked ? "news" : timeReason) + ")";
         stateColor = clrGold;
        }
      else
        {
         state      = "operativo | ultimo filtro: " + g_lastBlock;
         stateColor = okColor;
        }
   PanelRow(15, StringFormat("%-11s %s", "Stato", state), stateColor);

   if(!IsTesting())
      ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Ciclo principale                                                 |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateSymbolInfo();
   ResetDayState(false);

   if(NewsFilter && !IsTesting() && (int)(TimeCurrent() - g_newsLastLoad) > 4 * 3600)
     {
      UpdateServerGmtOffset();
      LoadNewsCalendar();
     }

   // 1. Chiusure avvenute fuori dal controllo dell'EA (SAR incluso)
   DetectBrokerClosures();
   ArrayResize(g_closedByEa, 0);

   // 2. Livelli virtuali e trailing sulle posizioni aperte
   ManageOpenPositions();

   // 3. Limiti di paniere e limiti giornalieri
   CheckBasketLimits();

   // 4. Filtri
   datetime now        = TimeCurrent();
   string   timeReason = "";
   bool     timeOk     = TimeAllowed(now, timeReason);
   string   newsLabel  = "";
   bool     newsBlk    = NewsBlocked(now, newsLabel);

   if(newsBlk && CloseBeforeNews && CountOurOrders() > 0)
      CloseAllPositions("filtro news");

   // 5. Reversal e nuovi ingressi
   if(g_dayBlocked || !timeOk || newsBlk)
     {
      ArrayResize(g_sarQueue, 0);
      if(g_dayBlocked)
         g_lastBlock = g_dayBlockReason;
      else
         g_lastBlock = (newsBlk ? "news" : timeReason);
     }
   else
     {
      // Un reversal appena eseguito esaurisce il tick: aprire anche il
      // verso opposto significherebbe contraddire lo stop appena preso.
      if(ProcessSarQueue() == 0)
        {
         int signal = EntrySignal();
         if(signal > 0)
            TryOpenPosition(OP_BUY, "breakout rialzista", false);
         else
            if(signal < 0)
               TryOpenPosition(OP_SELL, "breakout ribassista", false);
        }
     }

   // 6. Fotografia dello stato per il tick successivo
   SnapshotOpenTickets();

   UpdatePanel(timeOk, timeReason, newsBlk, newsLabel);
  }
//+------------------------------------------------------------------+
