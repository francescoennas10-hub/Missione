//+------------------------------------------------------------------+
//|                                    EMABounceOB_Dashboard.mq4      |
//|        Dashboard ESTERNA per EMABounceOrderBlockEA v1.00          |
//|                                                                   |
//|  COS'E'                                                           |
//|   Un indicatore autonomo che NON calcola nulla sul grafico su cui |
//|   viene applicato: legge lo stato pubblicato dall'Expert Advisor  |
//|   sulle GlobalVariables del terminale e lo mostra.                |
//|                                                                   |
//|  PERCHE' ESTERNA                                                  |
//|   1. Il pannello si puo' tenere su un grafico dedicato (anche di  |
//|      un altro simbolo o su un secondo monitor) senza coprire il   |
//|      grafico operativo.                                           |
//|   2. Un solo pannello vede TUTTE le istanze dell'EA in esecuzione |
//|      sul terminale: si passa dall'una all'altra con un clic.      |
//|   3. Il disegno del pannello non pesa sul thread dell'EA: se la   |
//|      dashboard viene rimossa, l'EA continua a operare identico.   |
//|                                                                   |
//|  INSTALLAZIONE                                                    |
//|   MQL4/Indicators/EMABounceOB_Dashboard.mq4 -> F7 -> trascinare   |
//|   su un grafico qualsiasi. Nessun parametro obbligatorio: le      |
//|   istanze vengono rilevate da sole.                               |
//|                                                                   |
//|  PROTOCOLLO                                                       |
//|   Chiavi GlobalVariable:  EBOB_<SIMBOLO>_<MAGIC>_<chiave>         |
//|   L'istanza e' considerata viva se la chiave "hb" (heartbeat) e'  |
//|   piu' recente di StaleSeconds. Se l'EA viene fermato il pannello |
//|   resta con l'ultimo stato noto e lo marca OFFLINE: distinguere   |
//|   "fermo" da "non ci sono dati" e' meta' del valore di un         |
//|   pannello di monitoraggio.                                       |
//+------------------------------------------------------------------+
#property copyright "EMA Bounce & Order Block Dashboard"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0
#property description "Dashboard esterna per EMABounceOrderBlockEA: legge lo stato via GlobalVariables."
#property description "Applicabile a qualsiasi grafico, rileva tutte le istanze dell'EA sul terminale."

#define GV_PREFIX   "EBOB_"
#define MAX_INST    16

//--- Codici di stato dell'EA (devono restare allineati all'Expert)
#define ST_INIT      0
#define ST_NOBIAS    1
#define ST_WAITPB    2
#define ST_INZONE    3
#define ST_ARMED     4
#define ST_INPOS     5
#define ST_BLOCKED   6
#define ST_FILTER    7

//+------------------------------------------------------------------+
//| INPUT: selezione dell'istanza                                    |
//+------------------------------------------------------------------+
input string s_sel        = "===== ISTANZA =====";
input string FilterSymbol = "";      // Simbolo da mostrare ("" = tutti, "CURRENT" = questo grafico)
input int    FilterMagic  = 0;       // Magic da mostrare (0 = qualsiasi)
input int    StaleSeconds = 30;      // Secondi oltre i quali l'istanza e' OFFLINE
input int    RefreshSecs  = 1;       // Intervallo di aggiornamento (secondi)

//+------------------------------------------------------------------+
//| INPUT: aspetto                                                   |
//+------------------------------------------------------------------+
input string s_look       = "===== ASPETTO =====";
input int    PanelX       = 10;      // Distanza dal bordo sinistro (px)
input int    PanelY       = 20;      // Distanza dal bordo superiore (px)
input int    ColumnWidth  = 250;     // Larghezza di una colonna (px)
input string PanelFont    = "Tahoma";// Font
input int    FontSize     = 8;       // Dimensione del font
input color  BgColor      = C'12,12,14';    // Sfondo del pannello
input color  BorderColor  = C'60,60,66';    // Bordo
input color  HeaderBg     = C'26,26,32';    // Sfondo dell'intestazione
input color  SectionBg    = C'22,22,26';    // Sfondo dei titoli di sezione
input color  TitleColor   = clrWhite;       // Titolo
input color  SectionColor = clrDeepSkyBlue; // Titoli di sezione
input color  CaptionColor = C'145,145,152'; // Etichette
input color  ValueColor   = clrWhiteSmoke;  // Valori
input color  BullColor    = C'0,215,120';   // Rialzista / positivo
input color  BearColor    = C'255,85,85';   // Ribassista / negativo
input color  WarnColor    = clrGoldenrod;   // Attenzione
input color  MutedColor   = C'95,95,102';   // Valori spenti / offline

//+------------------------------------------------------------------+
//| Istanza rilevata                                                 |
//+------------------------------------------------------------------+
struct InstanceInfo
  {
   bool     used;
   string   symbol;
   long     magic;
   string   prefix;
   datetime heartbeat;
  };

InstanceInfo g_inst[MAX_INST];
int      g_instCount = 0;
int      g_sel       = 0;
string   g_pfx       = "";     // Prefisso dell'istanza selezionata
string   g_obj       = "";     // Prefisso degli oggetti grafici
int      g_rowH      = 16;
int      g_pad       = 8;
int      g_panelW    = 520;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_obj    = "EBOBDASH" + IntegerToString((int)ChartID()) + "_";
   g_rowH   = FontSize + 8;
   g_panelW = ColumnWidth * 2 + g_pad * 3;

   IndicatorShortName("EBOB Dashboard");

   EventSetTimer((int)MathMax(1, RefreshSecs));
   ScanInstances();
   Render();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteObjects();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| OnCalculate - la dashboard non calcola serie, disegna soltanto   |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| OnTimer - unico motore di aggiornamento                          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ScanInstances();
   Render();
  }

//+------------------------------------------------------------------+
//| Clic sui pulsanti delle istanze                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   string tag = g_obj + "inst";
   if(StringFind(sparam, tag, 0) != 0)
      return;

   int idx = (int)StringToInteger(StringSubstr(sparam, StringLen(tag)));
   if(idx >= 0 && idx < g_instCount)
     {
      g_sel = idx;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      Render();
     }
  }

//+------------------------------------------------------------------+
//| Posizione dell'ultima occorrenza di un carattere                 |
//+------------------------------------------------------------------+
int LastIndexOf(string text, string ch)
  {
   int idx = -1, pos = 0;

   while(true)
     {
      int found = StringFind(text, ch, pos);
      if(found < 0)
         break;
      idx = found;
      pos = found + 1;
     }

   return(idx);
  }

//+------------------------------------------------------------------+
//| SCOPERTA DELLE ISTANZE                                           |
//| Si cercano le sole chiavi "hb": una per istanza. Il nome viene   |
//| analizzato da destra, cosi' i simboli con underscore nel nome    |
//| (XAUUSD_i, XAUUSD.raw...) restano leggibili.                     |
//+------------------------------------------------------------------+
void ScanInstances()
  {
   InstanceInfo previous[MAX_INST];
   int prevCount = g_instCount;
   for(int i = 0; i < MAX_INST; i++)
      previous[i] = g_inst[i];

   //--- Simbolo dell'istanza attualmente selezionata, per ritrovarla dopo
   string selSymbol = "";
   long   selMagic  = 0;
   if(g_sel >= 0 && g_sel < prevCount && previous[g_sel].used)
     {
      selSymbol = previous[g_sel].symbol;
      selMagic  = previous[g_sel].magic;
     }

   for(int i = 0; i < MAX_INST; i++)
      g_inst[i].used = false;

   g_instCount = 0;

   int total = GlobalVariablesTotal();

   for(int i = 0; i < total && g_instCount < MAX_INST; i++)
     {
      string name = GlobalVariableName(i);

      if(StringFind(name, GV_PREFIX, 0) != 0)
         continue;

      int cut = LastIndexOf(name, "_");
      if(cut < 0)
         continue;

      if(StringSubstr(name, cut + 1) != "hb")
         continue;

      string rest = StringSubstr(name, 0, cut);          // EBOB_<SIM>_<MAGIC>
      int    cut2 = LastIndexOf(rest, "_");
      if(cut2 <= 4)
         continue;

      string magicStr = StringSubstr(rest, cut2 + 1);
      string symbol   = StringSubstr(rest, StringLen(GV_PREFIX), cut2 - StringLen(GV_PREFIX));

      if(StringLen(symbol) == 0 || StringLen(magicStr) == 0)
         continue;

      long magic = StringToInteger(magicStr);

      //--- Filtri
      if(FilterMagic != 0 && magic != FilterMagic)
         continue;

      if(StringLen(FilterSymbol) > 0)
        {
         string want = (FilterSymbol == "CURRENT") ? Symbol() : FilterSymbol;
         if(symbol != want)
            continue;
        }

      g_inst[g_instCount].used      = true;
      g_inst[g_instCount].symbol    = symbol;
      g_inst[g_instCount].magic     = magic;
      g_inst[g_instCount].prefix    = rest + "_";
      g_inst[g_instCount].heartbeat = (datetime)GlobalVariableGet(name);
      g_instCount++;
     }

   //--- Mantieni selezionata la stessa istanza anche se l'ordine cambia
   if(StringLen(selSymbol) > 0)
     {
      for(int i = 0; i < g_instCount; i++)
         if(g_inst[i].symbol == selSymbol && g_inst[i].magic == selMagic)
           { g_sel = i; return; }
     }

   if(g_sel >= g_instCount)
      g_sel = 0;
  }

//+------------------------------------------------------------------+
//| Lettura di una chiave dell'istanza selezionata                   |
//+------------------------------------------------------------------+
double GV(string key)
  {
   if(StringLen(g_pfx) == 0)
      return(0.0);

   string name = g_pfx + key;
   if(!GlobalVariableCheck(name))
      return(0.0);

   return(GlobalVariableGet(name));
  }

//+------------------------------------------------------------------+
//|                     PRIMITIVE DI DISEGNO                         |
//+------------------------------------------------------------------+
void Rect(string id, int x, int y, int w, int h, color bg, color border, int zorder)
  {
   string name = g_obj + id;

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

void Text(string id, int x, int y, string text, color clr, int size, int anchor)
  {
   string name = g_obj + id;

   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;

   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     anchor);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   size);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     5);
   ObjectSetString (0, name, OBJPROP_FONT,       PanelFont);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
  }

void Button(string id, int x, int y, int w, int h, string text, color bg, color fg, bool selected)
  {
   string name = g_obj + id;

   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
         return;

   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      fg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, selected ? SectionColor : BorderColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   FontSize);
   ObjectSetInteger(0, name, OBJPROP_STATE,      false);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     6);
   ObjectSetString (0, name, OBJPROP_FONT,       PanelFont);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
  }

//--- Barra di riempimento: un numero si legge, una barra si coglie
void Bar(string id, int x, int y, int w, int h, double ratio, color fill, color back)
  {
   if(ratio < 0.0) ratio = 0.0;
   if(ratio > 1.0) ratio = 1.0;

   Rect(id + "bg", x, y, w, h, back, back, 3);

   int fw = (int)MathRound(w * ratio);
   if(fw < 1) fw = 1;

   Rect(id + "fg", x, y, fw, h, fill, fill, 4);
  }

//+------------------------------------------------------------------+
//| Sezione e riga, con colonna (0 = sinistra, 1 = destra)           |
//+------------------------------------------------------------------+
int ColX(int col)
  {
   return(PanelX + g_pad + col * (ColumnWidth + g_pad));
  }

void Section(int col, int &y, string id, string title)
  {
   Rect("sec" + id, ColX(col) - 3, y - 2, ColumnWidth + 6, g_rowH + 2, SectionBg, SectionBg, 2);
   Text("sect" + id, ColX(col), y + 1, title, SectionColor, FontSize, ANCHOR_LEFT_UPPER);
   y += g_rowH + 5;
  }

void Row(int col, int &y, string id, string caption, string value, color valueColor)
  {
   Text("cap" + id, ColX(col), y, caption, CaptionColor, FontSize, ANCHOR_LEFT_UPPER);
   Text("val" + id, ColX(col) + ColumnWidth, y, value, valueColor, FontSize, ANCHOR_RIGHT_UPPER);
   y += g_rowH;
  }

//--- Riga con barra di riempimento sotto l'etichetta
void RowBar(int col, int &y, string id, string caption, string value,
            color valueColor, double ratio, color fill)
  {
   Row(col, y, id, caption, value, valueColor);
   Bar("bar" + id, ColX(col), y - 2, ColumnWidth, 3, ratio, fill, C'45,45,50');
   y += 6;
  }

void DeleteObjects()
  {
   if(StringLen(g_obj) == 0)
      return;

   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_obj, 0) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//|                        FORMATTAZIONE                             |
//+------------------------------------------------------------------+
string PriceStr(double price, int digits)
  {
   if(price == 0.0)
      return("-");
   return(DoubleToString(price, digits));
  }

string MoneyStr(double value)
  {
   string sign = (value > 0.0 ? "+" : "");
   return(sign + DoubleToString(value, 2));
  }

string PipsStr(double priceDistance, double pip)
  {
   if(priceDistance <= 0.0 || pip <= 0.0)
      return("-");
   return(DoubleToString(priceDistance / pip, 1) + " p");
  }

string AgeStr(int seconds)
  {
   if(seconds < 60)
      return(IntegerToString(seconds) + "s fa");
   if(seconds < 3600)
      return(IntegerToString(seconds / 60) + "m fa");
   return(IntegerToString(seconds / 3600) + "h fa");
  }

string ClockStr(int seconds)
  {
   if(seconds < 0) seconds = 0;
   int m = seconds / 60;
   int s = seconds % 60;
   return(StringFormat("%d:%02d", m, s));
  }

string TfStr(int minutes)
  {
   switch(minutes)
     {
      case 1:     return("M1");
      case 5:     return("M5");
      case 15:    return("M15");
      case 30:    return("M30");
      case 60:    return("H1");
      case 240:   return("H4");
      case 1440:  return("D1");
      case 10080: return("W1");
      case 43200: return("MN1");
     }
   return(IntegerToString(minutes) + "m");
  }

string DirStr(int dir)
  {
   if(dir > 0) return("RIALZISTA");
   if(dir < 0) return("RIBASSISTA");
   return("NEUTRO");
  }

color DirColor(int dir)
  {
   if(dir > 0) return(BullColor);
   if(dir < 0) return(BearColor);
   return(MutedColor);
  }

string YesNo(double flag)
  {
   return(flag > 0.5 ? "SI" : "no");
  }

color FlagColor(double flag)
  {
   return(flag > 0.5 ? BullColor : MutedColor);
  }

//+------------------------------------------------------------------+
//| Stato operativo dell'EA                                          |
//+------------------------------------------------------------------+
string StateStr(int code)
  {
   switch(code)
     {
      case ST_INIT:    return("avvio");
      case ST_NOBIAS:  return("nessun trend");
      case ST_WAITPB:  return("attesa ritracciamento");
      case ST_INZONE:  return("prezzo nella banda");
      case ST_ARMED:   return("ordine armato");
      case ST_INPOS:   return("in posizione");
      case ST_BLOCKED: return("operativita' sospesa");
      case ST_FILTER:  return("fuori sessione");
     }
   return("-");
  }

color StateColor(int code)
  {
   switch(code)
     {
      case ST_INPOS:   return(BullColor);
      case ST_INZONE:
      case ST_ARMED:   return(WarnColor);
      case ST_BLOCKED: return(BearColor);
     }
   return(ValueColor);
  }

//+------------------------------------------------------------------+
//| Motivo dell'ultimo ingresso non eseguito                         |
//| Il campo piu' utile del pannello: dice perche' l'EA non opera.   |
//+------------------------------------------------------------------+
string RejectStr(int code)
  {
   switch(code)
     {
      case 0:  return("-");
      case 1:  return("spread oltre il massimo");
      case 2:  return("spread troppo alto sull'ATR");
      case 3:  return("fuori sessione");
      case 4:  return("limite trade giornalieri");
      case 5:  return("stop giornaliero raggiunto");
      case 6:  return("target giornaliero raggiunto");
      case 7:  return("cooldown dopo l'ultimo trade");
      case 8:  return("posizioni gia' al limite");
      case 9:  return("stop level del broker");
      case 10: return("stop tecnico troppo ampio");
      case 11: return("stop tecnico troppo stretto");
      case 12: return("rapporto R:R insufficiente");
      case 13: return("volume non calcolabile");
      case 14: return("invio ordine fallito");
      case 15: return("storico insufficiente");
      case 16: return("nessun order block valido");
      case 17: return("nessun rimbalzo sulla banda");
      case 18: return("confluenza sotto la soglia");
      case 19: return("pausa per perdite consecutive");
      case 20: return("nessun bias di trend");
     }
   return("codice " + IntegerToString(code));
  }

color RejectColor(int code)
  {
   if(code == 0)
      return(MutedColor);

   //--- Blocchi di rischio in rosso, condizioni di mercato in ambra
   if(code == 5 || code == 6 || code == 4 || code == 19)
      return(BearColor);

   return(WarnColor);
  }

//+------------------------------------------------------------------+
//|                         RENDERING                                |
//+------------------------------------------------------------------+
int g_lastHeight = 420;
int g_lastMode   = -1;   // 0 = nessuna istanza, 1 = pannello completo

void Render()
  {
   int mode = (g_instCount == 0) ? 0 : 1;

   //--- Il cambio di modalita' lascerebbe oggetti orfani
   if(mode != g_lastMode)
     {
      DeleteObjects();
      g_lastMode = mode;
     }

   if(mode == 0)
     {
      RenderEmpty();
      ChartRedraw();
      return;
     }

   g_pfx = g_inst[g_sel].prefix;

   //--- Sfondo: creato per primo, quindi disegnato sotto a tutto il resto
   Rect("bg", PanelX, PanelY, g_panelW, g_lastHeight, BgColor, BorderColor, 0);

   int y = PanelY + 1;
   RenderHeader(y);

   int yL = y;
   int yR = y;

   RenderBias(yL);
   RenderZone(yL);
   RenderOrderBlock(yL);
   RenderSignal(yL);

   RenderPosition(yR);
   RenderRisk(yR);
   RenderMarket(yR);
   RenderAccount(yR);

   int bottom = (int)MathMax(yL, yR);
   RenderInstances(bottom);

   //--- Altezza definitiva del pannello
   g_lastHeight = bottom - PanelY + g_pad;
   ObjectSetInteger(0, g_obj + "bg", OBJPROP_YSIZE, g_lastHeight);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Nessuna istanza rilevata                                         |
//+------------------------------------------------------------------+
void RenderEmpty()
  {
   int h = g_rowH * 5 + g_pad * 2;

   Rect("bg", PanelX, PanelY, g_panelW, h, BgColor, BorderColor, 0);
   Rect("hdr", PanelX + 1, PanelY + 1, g_panelW - 2, g_rowH + 6, HeaderBg, HeaderBg, 1);

   Text("title", PanelX + g_pad, PanelY + 5, "EMA BOUNCE & ORDER BLOCK",
        TitleColor, FontSize, ANCHOR_LEFT_UPPER);
   Text("live", PanelX + g_panelW - g_pad, PanelY + 5, "NESSUN DATO",
        BearColor, FontSize, ANCHOR_RIGHT_UPPER);

   int y = PanelY + g_rowH + 14;

   Text("e1", PanelX + g_pad, y, "Nessuna istanza di EMABounceOrderBlockEA rilevata.",
        ValueColor, FontSize, ANCHOR_LEFT_UPPER);
   y += g_rowH;
   Text("e2", PanelX + g_pad, y, "Verificare che l'EA sia attivo e PublishTelemetry = true.",
        CaptionColor, FontSize, ANCHOR_LEFT_UPPER);
   y += g_rowH;

   string filt = "Filtri: simbolo=" + (StringLen(FilterSymbol) > 0 ? FilterSymbol : "tutti") +
                 "  magic=" + (FilterMagic != 0 ? IntegerToString(FilterMagic) : "qualsiasi");
   Text("e3", PanelX + g_pad, y, filt, MutedColor, FontSize, ANCHOR_LEFT_UPPER);
  }

//+------------------------------------------------------------------+
//| Intestazione: identita' dell'istanza e stato del collegamento    |
//+------------------------------------------------------------------+
void RenderHeader(int &y)
  {
   int    age    = (int)(TimeCurrent() - g_inst[g_sel].heartbeat);
   bool   online = (age <= MathMax(3, StaleSeconds));

   Rect("hdr", PanelX + 1, y, g_panelW - 2, g_rowH * 2 + 8, HeaderBg, HeaderBg, 1);

   Text("title", PanelX + g_pad, y + 4, "EMA BOUNCE & ORDER BLOCK",
        TitleColor, FontSize, ANCHOR_LEFT_UPPER);

   Text("live", PanelX + g_panelW - g_pad, y + 4,
        (online ? "[+] ONLINE" : "[!] OFFLINE " + AgeStr(age)),
        (online ? BullColor : BearColor), FontSize, ANCHOR_RIGHT_UPPER);

   string ident = g_inst[g_sel].symbol + "  #" + IntegerToString((int)g_inst[g_sel].magic) +
                  "   " + TfStr((int)GV("tfm")) + " / " + TfStr((int)GV("btf")) + " (bias)";

   Text("ident", PanelX + g_pad, y + 4 + g_rowH, ident, SectionColor, FontSize, ANCHOR_LEFT_UPPER);

   Text("upd", PanelX + g_panelW - g_pad, y + 4 + g_rowH,
        "agg. " + AgeStr(age), MutedColor, FontSize, ANCHOR_RIGHT_UPPER);

   y += g_rowH * 2 + 14;
  }

//+------------------------------------------------------------------+
//| Colonna sinistra                                                 |
//+------------------------------------------------------------------+
void RenderBias(int &y)
  {
   Section(0, y, "bias", "TREND BIAS");

   int    bias = (int)GV("bias");
   double str  = GV("bstr");

   Row(0, y, "b1", "Direzione ammessa", DirStr(bias), DirColor(bias));
   RowBar(0, y, "b2", "Forza del bias", DoubleToString(str, 0) + " / 100",
          (str >= 60.0 ? BullColor : (str > 0.0 ? WarnColor : MutedColor)),
          str / 100.0, (bias >= 0 ? BullColor : BearColor));
   Row(0, y, "b3", "Timeframe di lettura", TfStr((int)GV("btf")), ValueColor);

   y += 4;
  }

void RenderZone(int &y)
  {
   Section(0, y, "zone", "BANDA EMA DINAMICA");

   int    dig = (int)GV("dig");
   double lo  = GV("zlo"), hi = GV("zhi");

   Row(0, y, "z1", "Banda", (hi > 0.0 ? PriceStr(lo, dig) + " - " + PriceStr(hi, dig) : "-"), ValueColor);
   Row(0, y, "z2", "Prezzo", (GV("zin") > 0.5 ? "DENTRO la banda" : "fuori banda"),
       (GV("zin") > 0.5 ? WarnColor : MutedColor));
   Row(0, y, "z3", "Rimbalzo confermato", YesNo(GV("bounce")), FlagColor(GV("bounce")));
   Row(0, y, "z4", "Rottura struttura", YesNo(GV("bos")), FlagColor(GV("bos")));
   Row(0, y, "z5", "Momentum", YesNo(GV("mom")), FlagColor(GV("mom")));

   y += 4;
  }

void RenderOrderBlock(int &y)
  {
   Section(0, y, "ob", "ORDER BLOCK");

   int    dig  = (int)GV("dig");
   int    dir  = (int)GV("obdir");
   double lo   = GV("oblo"), hi = GV("obhi");
   int    tch  = (int)GV("obtch");

   Row(0, y, "o1", "Zone valide in memoria", IntegerToString((int)GV("obn")), ValueColor);
   Row(0, y, "o2", "Zona attiva", (dir != 0 ? DirStr(dir) : "nessuna"), DirColor(dir));
   Row(0, y, "o3", "Estremi", (hi > 0.0 ? PriceStr(lo, dig) + " - " + PriceStr(hi, dig) : "-"), ValueColor);
   Row(0, y, "o4", "Eta'", (dir != 0 ? IntegerToString((int)GV("obage")) + " barre" : "-"), ValueColor);
   Row(0, y, "o5", "Tocchi ricevuti", (dir != 0 ? IntegerToString(tch) : "-"),
       (tch >= 2 ? WarnColor : ValueColor));
   Row(0, y, "o6", "Impulso di origine",
       (dir != 0 ? DoubleToString(GV("obimp"), 2) + " ATR" : "-"), ValueColor);

   y += 4;
  }

void RenderSignal(int &y)
  {
   Section(0, y, "sig", "SEGNALE");

   int state = (int)GV("state");
   int score = (int)GV("score");
   int rej   = (int)GV("rej");

   Row(0, y, "s1", "Stato operativo", StateStr(state), StateColor(state));
   RowBar(0, y, "s2", "Confluenza", IntegerToString(score) + " / 100",
          (score >= 60 ? BullColor : (score > 0 ? WarnColor : MutedColor)),
          score / 100.0, (score >= 60 ? BullColor : WarnColor));
   Row(0, y, "s3", "Ultimo segnale", DirStr((int)GV("sig")), DirColor((int)GV("sig")));
   Row(0, y, "s4", "Ultimo blocco", RejectStr(rej), RejectColor(rej));
   Row(0, y, "s5", "Cooldown residuo",
       ((int)GV("cool") > 0 ? IntegerToString((int)GV("cool")) + " barre" : "-"),
       ((int)GV("cool") > 0 ? WarnColor : MutedColor));

   y += 4;
  }

//+------------------------------------------------------------------+
//| Colonna destra                                                   |
//+------------------------------------------------------------------+
void RenderPosition(int &y)
  {
   Section(1, y, "pos", "POSIZIONE");

   int    dig  = (int)GV("dig");
   int    pos  = (int)GV("pos");
   int    dir  = (int)GV("pdir");
   double pl   = GV("ppl");
   double r    = GV("pr");

   int    pend = (int)GV("pend");
   bool   flat = (pos == 0);

   //--- Le righe si disegnano sempre tutte: lasciarne alcune indietro
   //    significherebbe mostrare i dati dell'ultima posizione chiusa.
   Row(1, y, "p1", "Direzione",
       (flat ? (pend > 0 ? "ordine armato" : "flat") : (dir > 0 ? "LONG" : "SHORT")),
       (flat ? (pend > 0 ? WarnColor : MutedColor) : DirColor(dir)));

   Row(1, y, "p2", "Volume",
       (flat ? "-" : DoubleToString(GV("plots"), 2) + " lotti"),
       (flat ? MutedColor : ValueColor));

   Row(1, y, "p3", "Ingresso", (flat ? "-" : PriceStr(GV("popen"), dig)),
       (flat ? MutedColor : ValueColor));

   Row(1, y, "p4", "Stop loss", (flat ? "-" : PriceStr(GV("psl"), dig)),
       (flat ? MutedColor : (GV("psl") > 0.0 ? ValueColor : BearColor)));

   Row(1, y, "p5", "Take profit", (flat ? "-" : PriceStr(GV("ptp"), dig)),
       (flat ? MutedColor : ValueColor));

   Row(1, y, "p6", "P/L flottante",
       (flat ? "-" : MoneyStr(pl) + " " + AccountCurrency()),
       (flat ? MutedColor : (pl >= 0.0 ? BullColor : BearColor)));

   RowBar(1, y, "p7", "Multiplo di rischio", (flat ? "-" : DoubleToString(r, 2) + " R"),
          (flat ? MutedColor : (r >= 0.0 ? BullColor : BearColor)),
          (flat ? 0.0 : MathAbs(r) / 3.0),
          (r >= 0.0 ? BullColor : BearColor));

   Row(1, y, "p8", (flat ? "Ordini pendenti" : "Barre in posizione"),
       (flat ? (pend > 0 ? IntegerToString(pend) : "-") : IntegerToString((int)GV("pbars"))),
       (flat ? (pend > 0 ? WarnColor : MutedColor) : ValueColor));

   y += 4;
  }

void RenderRisk(int &y)
  {
   Section(1, y, "risk", "PROSSIMO TRADE");

   double pip  = GV("pip");
   double sl   = GV("psl0");
   double tp   = GV("ptp0");
   int    trd  = (int)GV("trd");
   int    maxt = (int)GV("maxtrd");

   Row(1, y, "r1", "Volume stimato", DoubleToString(GV("nlots"), 2) + " lotti", ValueColor);
   Row(1, y, "r2", "Rischio per trade",
       DoubleToString(GV("nrisk"), 2) + " " + AccountCurrency(), ValueColor);
   Row(1, y, "r3", "Ultimo SL calcolato", PipsStr(sl, pip), ValueColor);
   Row(1, y, "r4", "Ultimo TP calcolato", PipsStr(tp, pip), ValueColor);
   Row(1, y, "r5", "R:R dell'ultimo calcolo",
       (sl > 0.0 && tp > 0.0 ? "1:" + DoubleToString(tp / sl, 2) : "-"), ValueColor);
   Row(1, y, "r6", "Trade oggi",
       IntegerToString(trd) + (maxt > 0 ? " / " + IntegerToString(maxt) : ""),
       (maxt > 0 && trd >= maxt ? BearColor : ValueColor));

   y += 4;
  }

void RenderMarket(int &y)
  {
   Section(1, y, "mkt", "MERCATO");

   double pip  = GV("pip");
   double atr  = GV("atr");
   double spr  = GV("spr");
   double sprr = GV("sprr");

   color sprColor = BullColor;
   if(sprr > 0.10) sprColor = WarnColor;
   if(sprr > 0.20) sprColor = BearColor;

   Row(1, y, "m1", "ATR", PipsStr(atr, pip), ValueColor);
   Row(1, y, "m2", "Spread", PipsStr(spr, pip), sprColor);
   RowBar(1, y, "m3", "Spread / ATR", DoubleToString(sprr * 100.0, 1) + " %",
          sprColor, sprr / 0.30, sprColor);
   Row(1, y, "m4", "Stop level broker", PipsStr(GV("stoplv"), pip), ValueColor);
   Row(1, y, "m5", "Sessione", (GV("sess") > 0.5 ? "aperta" : "chiusa"),
       (GV("sess") > 0.5 ? BullColor : MutedColor));
   Row(1, y, "m6", "Prossima barra", ClockStr((int)GV("nbar")), MutedColor);

   y += 4;
  }

void RenderAccount(int &y)
  {
   Section(1, y, "acc", "CONTO & PERFORMANCE");

   double dpl  = GV("dpl");
   double dplp = GV("dplp");
   double dlim = GV("dlim");
   double net  = GV("net");
   double pf   = GV("pf");
   int    wins = (int)GV("wins");
   int    loss = (int)GV("los");
   int    strk = (int)GV("strk");

   Row(1, y, "a1", "Equity", DoubleToString(GV("eq"), 2), ValueColor);
   Row(1, y, "a2", "Saldo",  DoubleToString(GV("bal"), 2), ValueColor);

   //--- Barra del consumo dello stop giornaliero
   double used = (dlim > 0.0 && dplp < 0.0) ? MathAbs(dplp) / dlim : 0.0;
   RowBar(1, y, "a3", "P/L di giornata",
          MoneyStr(dpl) + "  (" + DoubleToString(dplp, 2) + "%)",
          (dpl >= 0.0 ? BullColor : BearColor),
          (dpl >= 0.0 ? 0.0 : used), BearColor);

   Row(1, y, "a4", "Profitto totale EA", MoneyStr(net), (net >= 0.0 ? BullColor : BearColor));

   int trades = wins + loss;
   Row(1, y, "a5", "Vinti / Persi",
       IntegerToString(wins) + " / " + IntegerToString(loss) +
       (trades > 0 ? "  (" + DoubleToString(100.0 * wins / trades, 0) + "%)" : ""),
       ValueColor);

   Row(1, y, "a6", "Profit factor",
       (pf > 0.0 ? DoubleToString(pf, 2) : "-"),
       (pf >= 1.0 ? BullColor : (pf > 0.0 ? BearColor : MutedColor)));

   Row(1, y, "a7", "Perdite consecutive", IntegerToString(strk),
       (strk >= 3 ? BearColor : (strk > 0 ? WarnColor : MutedColor)));

   if(GV("block") > 0.5)
      Row(1, y, "a8", "OPERATIVITA'", "SOSPESA", BearColor);
   else
      Row(1, y, "a8", "Operativita'", "attiva", BullColor);

   y += 4;
  }

//+------------------------------------------------------------------+
//| Elenco delle istanze: un pulsante per ciascuna                   |
//+------------------------------------------------------------------+
void RenderInstances(int &y)
  {
   y += 2;

   //--- Con una sola istanza l'elenco e' rumore
   if(g_instCount <= 1)
     {
      for(int i = 0; i < MAX_INST; i++)
        {
         string n = g_obj + "inst" + IntegerToString(i);
         if(ObjectFind(0, n) >= 0)
            ObjectDelete(0, n);
        }
      if(ObjectFind(0, g_obj + "seclist") >= 0)
        {
         ObjectDelete(0, g_obj + "seclist");
         ObjectDelete(0, g_obj + "sectlist");
        }
      return;
     }

   Section(0, y, "list", "ISTANZE ATTIVE (clic per selezionare)");

   int bw = (g_panelW - g_pad * 2 - 6) / 3;
   int bh = g_rowH + 2;

   for(int i = 0; i < MAX_INST; i++)
     {
      string id = "inst" + IntegerToString(i);

      if(i >= g_instCount)
        {
         string n = g_obj + id;
         if(ObjectFind(0, n) >= 0)
            ObjectDelete(0, n);
         continue;
        }

      int col = i % 3;
      int row = i / 3;

      int age  = (int)(TimeCurrent() - g_inst[i].heartbeat);
      bool on  = (age <= MathMax(3, StaleSeconds));
      bool sel = (i == g_sel);

      string label = g_inst[i].symbol + " #" + IntegerToString((int)g_inst[i].magic);

      Button(id,
             PanelX + g_pad + col * (bw + 3),
             y + row * (bh + 3),
             bw, bh, label,
             sel ? SectionBg : BgColor,
             on ? (sel ? TitleColor : ValueColor) : MutedColor,
             sel);
     }

   int rows = (g_instCount + 2) / 3;
   y += rows * (bh + 3) + 2;
  }
//+------------------------------------------------------------------+
