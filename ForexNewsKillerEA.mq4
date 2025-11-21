//+------------------------------------------------------------------+
//|                   ForexNewsKillerEA.mq4                          |
//|                 Copyright 2025, Ahmad (Ahmed-GoCode)             |
//|                https://github.com/Ahmed-GoCode                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Ahmad (Ahmed-GoCode)"
#property link      "https://github.com/Ahmed-GoCode"
#property strict
#property description "Forex News Killer EA - Protects your trades during news events"

#include <WinUser32.mqh>
#import "user32.dll"
   int GetAncestor(int, int);
   #define MT4_WMCMD_EXPERTS  33020 
#import

enum currencies {type1, type2}; // Auto or Custom

// News Settings
input string                  info1 = "------- NEWS SETTINGS -------";
input string                  news_link = "https://nfs.faireconomy.media/";
input int                     min_before = 5;           // Close trades X minutes before news
input int                     min_before_zero = 60;     // Close at profit X minutes before
input int                     min_after = 45;           // Wait X minutes after news

input bool                    include_high = true;      // High impact news
input bool                    include_medium = false;   // Medium impact news
input bool                    include_low = false;      // Low impact news

input bool                    use_title  = true;        // Filter by title
input string                  title_phrase="Non-Farm,Unemployment,ISM,PMI,CPI,FOMC,Retail Sales,GDP,PCE,JOLTS";

input int                     news_update_hour = 2;     // Update news every X hours

input currencies              symbol_type = type1;      // Auto or Custom
input string                  news_symbols = "USD,EUR,GBP,JPY,CAD,CHF";
input bool                    close_only_news_pair = false;

input bool                    draw_news_lines = true;
input color                   Line_Color = clrRed;
input ENUM_LINE_STYLE         Line_Style = STYLE_DOT;
input int                     Line_Width = 1;

// Order Management
input string                  info2 = "------- ORDER MANAGEMENT -------";
input bool                    stop_algo = true;         // Stop auto trading
input bool                    close_open = true;        // Close open trades
input bool                    close_pending = true;     // Delete pending orders
input bool                    close_zero = true;        // Close at break-even
input double                  close_profit = 1;         // Min profit ($)
input bool                    close_charts = false;     // Close all charts

// Notifications
input string                  info3 = "------- NOTIFICATIONS -------";
input bool                    send_notif = true;
input bool                    send_alert = true;
input int                     delay = 5;

// Global variables
int slippage = 5;
int event_count = 0;
int time_offset = 0;
bool allow_trade = true;
string pairs[];
string sybmols_list;

struct news_event_struct {
   string currency;
   string event_title;
   datetime event_time;
   string event_impact;
};
news_event_struct news_events[500];

int OnInit() {
   if(!IsDllsAllowed()) {
      MessageBox("Please allow DLL imports in Terminal settings.", "Error", MB_ICONERROR);
      return(INIT_FAILED);
   }
   
   if(symbol_type == type2) {
      sybmols_list = news_symbols;
      if(StringGetChar(sybmols_list, 0) == 44)
         sybmols_list = StringSubstr(sybmols_list, 1, StringLen(sybmols_list) - 1);
      if(StringGetChar(sybmols_list, StringLen(sybmols_list) - 1) == 44)
         sybmols_list = StringSubstr(sybmols_list, 0, StringLen(sybmols_list) - 2);
   } else {
      sybmols_list = Symbol();
   }
   
   time_offset = int(TimeCurrent() - TimeGMT());
   NewsUpdate();
   DrawNews();
   EventSetTimer(news_update_hour * 3600);
   
   Print("Forex News Killer EA initialized");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   Comment("");
   ObjectsDeleteAll(0);
   if(reason == 1) EventKillTimer();
}

void OnTick() {
   int main = GetAncestor(WindowHandle(Symbol(), Period()), 2);
   
   // Close at break-even if profitable before news
   if(close_zero) {
      if(BeforeNewsForZeroProfit() != "No News" && allow_trade) {
         if(AccountProfit() >= close_profit) {
            string msg1 = "[NEWS ALERT] ";
            string _pair = close_only_news_pair ? BeforeNewsForZeroProfit() : "all";
            
            if(close_charts) {
               for(long ch = ChartFirst(); ch >= 0; ch = ChartNext(ch)) {
                  bool chart_symbol = true;
                  if(_pair != "all") {
                     chart_symbol = (StringFind(ChartSymbol(ch), _pair) != -1);
                  }
                  if(ch != ChartID() && chart_symbol) ChartClose(ch);
               }
               msg1 += "Charts closed. ";
            }
            
            CloseAll(_pair);
            if(OpenTrades(_pair) > 0) { Sleep(delay * 1000); return; }
            msg1 += "Trades closed. ";
            
            if(close_pending) {
               DeleteAllPendings(_pair);
               if(PlacedPendings(_pair) > 0) { Sleep(delay * 1000); return; }
               msg1 += "Pendings deleted. ";
            }
            
            if(stop_algo && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
               PostMessageA(main, WM_COMMAND, MT4_WMCMD_EXPERTS, 0);
               msg1 += "Auto trading disabled. ";
            }
            
            Print(msg1);
            if(send_notif) SendNotification(msg1);
            if(send_alert) Alert(msg1);
            allow_trade = false;
         }
      }
   }
   
   // Close everything during news
   if(AtNews() != "No News" && allow_trade) {
      string msg1 = "[NEWS EVENT] ";
      string _pair = close_only_news_pair ? AtNews() : "all";
      
      if(close_charts) {
         for(long ch = ChartFirst(); ch >= 0; ch = ChartNext(ch)) {
            bool chart_symbol = true;
            if(_pair != "all") {
               chart_symbol = (StringFind(ChartSymbol(ch), _pair) != -1);
            }
            if(ch != ChartID() && chart_symbol) ChartClose(ch);
         }
         msg1 += "Charts closed. ";
      }
      
      if(close_open) {
         CloseAll(_pair);
         if(OpenTrades(_pair) > 0) { Sleep(delay * 1000); return; }
         msg1 += "Trades closed. ";
      }
      
      if(close_pending) {
         DeleteAllPendings(_pair);
         if(PlacedPendings(_pair) > 0) { Sleep(delay * 1000); return; }
         msg1 += "Pendings deleted. ";
      }
      
      if(stop_algo && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
         PostMessageA(main, WM_COMMAND, MT4_WMCMD_EXPERTS, 0);
         msg1 += "Auto trading disabled. ";
      }
      
      Print(msg1);
      if(send_notif) SendNotification(msg1);
      if(send_alert) Alert(msg1);
      allow_trade = false;
   } else if(AtNews() == "No News" && !allow_trade) {
      if(stop_algo && !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
         PostMessageA(main, WM_COMMAND, MT4_WMCMD_EXPERTS, 0);
      }
      allow_trade = true;
   }
   
   // Display status
   Comment("\n\n     FOREX NEWS KILLER EA"
           +"\n     ===================="
           +"\n     GMT Time: " + (string)TimeGMT()
           +"\n     Open Positions: " + (string)OpenTrades("all")
           +"\n     At News: " + ((AtNews() != "No News") ? ("YES ("+AtNews()+")") : "NO")
           +"\n     Close Soon: " + ((BeforeNewsForZeroProfit() != "No News") ? ("YES ("+BeforeNewsForZeroProfit()+")") : "NO"));
}

void OnTimer() {
   NewsUpdate();
   DrawNews();
}

void NewsUpdate() {
   string cookie=NULL, referer=NULL, headers;
   char post[], result[];
   string sUrl = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml";
   
   ResetLastError();
   int res = WebRequest("GET", sUrl, cookie, referer, 5000, post, sizeof(post), result, headers);
   
   if(res == -1) {
      Print("WebRequest error: ", GetLastError());
      if(ArraySize(result) <= 0) {
         int er = GetLastError();
         ResetLastError();
         if(er == 4060)
            MessageBox("Add https://nfs.faireconomy.media/ to allowed URLs", "Configuration", MB_ICONINFORMATION);
         return;
      }
      Sleep(5000);
   } else {
      string info = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      int start_pos = StringFind(info, "<weeklyevents>", 0);
      int finish_pos = StringFind(info, "</weeklyevents>", 0);
      info = StringSubstr(info, start_pos, finish_pos - start_pos);
      
      // Clear events
      for(int i = 0; i < 500; i++) {
         news_events[i].currency = "";
         news_events[i].event_title = "";
         news_events[i].event_time = 0;
         news_events[i].event_impact = "";
      }
      
      if(StringFind(info, "No Events Scheduled") != -1) {
         event_count = 0;
      } else {
         int c = 0;
         while(StringFind(info, "<event>") != -1) {
            int start_event = StringFind(info, "<event>", 0);
            int finish_event = StringFind(info, "</event>", start_event);
            
            int curr_start = StringFind(info, "<country>", start_event) + 9;
            int curr_finish = StringFind(info, "</country>", start_event);
            int title_start = StringFind(info, "<title>", start_event) + 7;
            int title_finish = StringFind(info, "</title>", start_event);
            int date_start = StringFind(info, "<date><![CDATA[", start_event) + 15;
            int date_finish = StringFind(info, "]]></date>", start_event);
            int time_start = StringFind(info, "<time><![CDATA[", start_event) + 15;
            int time_finish = StringFind(info, "]]></time>", start_event);
            int impact_start = StringFind(info, "<impact><![CDATA[", start_event) + 17;
            int impact_finish = StringFind(info, "]]></impact>", start_event);
            
            string ev_curr = StringSubstr(info, curr_start, curr_finish - curr_start);
            string ev_title = StringSubstr(info, title_start, title_finish - title_start);
            string ev_date = StringSubstr(info, date_start, date_finish - date_start);
            string ev_time = StringSubstr(info, time_start, time_finish - time_start);
            string ev_impact = StringSubstr(info, impact_start, impact_finish - impact_start);
            
            info = StringSubstr(info, finish_event + 8);
            
            if(CurrencySelected(ev_curr) && TitleSelected(ev_title) && ImpactSelected(ev_impact)) {
               news_events[c].currency = ev_curr;
               news_events[c].event_title = ev_title;
               news_events[c].event_time = StringToTime(MakeDateTime(ev_date, ev_time));
               news_events[c].event_impact = ev_impact;
               c++;
            }
         }
         event_count = c;
      }
   }
   Print("News updated. Events: ", event_count);
}

string MakeDateTime(string strDate, string strTime) {
   string strMonth = StringSubstr(strDate, 0, 2);
   string strDay = StringSubstr(strDate, 3, 2);
   string strYear = StringSubstr(strDate, 6, 4);
   int nTimeColonPos = StringFind(strTime, ":");
   string strHour = StringSubstr(strTime, 0, nTimeColonPos);
   string strMinute = StringSubstr(strTime, nTimeColonPos + 1, 2);
   string strAM_PM = StringSubstr(strTime, StringLen(strTime) - 2);
   
   int nHour24 = StrToInteger(strHour);
   if((strAM_PM == "pm" || strAM_PM == "PM") && nHour24 != 12) nHour24 += 12;
   if((strAM_PM == "am" || strAM_PM == "AM") && nHour24 == 12) nHour24 = 0;
   string strHourPad = (nHour24 < 10) ? "0" : "";
   
   return(StringConcatenate(strYear, ".", strMonth, ".", strDay, " ", strHourPad, nHour24, ":", strMinute));
}

void DrawNews() {
   if(draw_news_lines) {
      for(int c = 0; c < 100; c++) {
         if((news_events[c].currency != "") && (news_events[c].event_time != 0)) {
            datetime t1 = news_events[c].event_time + (datetime)time_offset;
            string NAME = news_events[c].currency + " : " + news_events[c].event_title + " - " + news_events[c].event_impact;
            if(ObjectFind(0, NAME) < 0) {
               ObjectCreate(0, NAME, OBJ_VLINE, 0, t1, 0);
               ObjectSetInteger(0, NAME, OBJPROP_SELECTABLE, false);
               ObjectSetInteger(0, NAME, OBJPROP_HIDDEN, true);
               ObjectSetInteger(0, NAME, OBJPROP_COLOR, Line_Color);
               ObjectSetInteger(0, NAME, OBJPROP_STYLE, Line_Style);
               ObjectSetInteger(0, NAME, OBJPROP_WIDTH, Line_Width);
            }
         }
      }
   }
}

bool CurrencySelected(string curr) {
   return (StringFind(sybmols_list, curr) != -1);
}

bool TitleSelected(string title) {
   if(!use_title) return true;
   
   string titles = title_phrase;
   string keywords[];
   if(StringGetChar(titles, 0) == 44) titles = StringSubstr(titles, 1, StringLen(titles) - 1);
   if(StringGetChar(titles, StringLen(titles) - 1) == 44) titles = StringSubstr(titles, 0, StringLen(titles) - 2);
   
   if(StringFind(titles, ",") != -1) {
      ushort u_sep = StringGetCharacter(",", 0);
      int k = StringSplit(titles, u_sep, keywords);
      ArrayResize(keywords, k, k);
      if(k > 0) {
         for(int i = 0; i < k; i++) {
            if(StringFind(title, keywords[i]) != -1) return true;
         }
      }
   }
   return false;
}

bool ImpactSelected(string impact) {
   if(include_high && StringFind(impact, "High") != -1) return true;
   if(include_medium && StringFind(impact, "Medium") != -1) return true;
   if(include_low && StringFind(impact, "Low") != -1) return true;
   return false;
}

string AtNews() {
   for(int c = 0; c < ArraySize(news_events); c++) {
      if((news_events[c].currency != "") && (news_events[c].event_time != 0)) {
         if(StringFind(sybmols_list, news_events[c].currency) != -1) {
            if((TimeGMT() <= (news_events[c].event_time + (min_after * 60))) && 
               (TimeGMT() >= (news_events[c].event_time - (min_before * 60))))
               return news_events[c].currency;
         }
      }
   }
   return "No News";
}

string BeforeNewsForZeroProfit() {
   for(int c = 0; c < ArraySize(news_events); c++) {
      if((news_events[c].currency != "") && (news_events[c].event_time != 0)) {
         if(StringFind(sybmols_list, news_events[c].currency) != -1) {
            if((TimeGMT() <= news_events[c].event_time) && 
               (TimeGMT() >= (news_events[c].event_time - (min_before_zero * 60))))
               return news_events[c].currency;
         }
      }
   }
   return "No News";
}

void CloseAll(string pair) {
   for(int i = OrdersTotal(); i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == pair || pair == "all") {
            if(OrderType() == OP_BUY || OrderType() == OP_SELL) {
               RefreshRates();
               if(!OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), slippage, clrNONE))
                  Print("Close error: ", GetLastError());
            }
         }
      }
   }
}

void DeleteAllPendings(string pair) {
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == pair || pair == "all") {
            if(OrderType() > OP_SELL) {
               RefreshRates();
               if(!OrderDelete(OrderTicket()))
                  Print("Delete error: ", GetLastError());
            }
         }
      }
   }
}

int OpenTrades(string pair) {
   int c = 0;
   for(int i = OrdersTotal(); i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == pair || pair == "all") {
            if(OrderType() == OP_BUY || OrderType() == OP_SELL) c++;
         }
      }
   }
   return c;
}

int PlacedPendings(string pair) {
   int c = 0;
   for(int i = OrdersTotal(); i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if(OrderSymbol() == pair || pair == "all") {
            if(OrderType() > OP_SELL) c++;
         }
      }
   }
   return c;
}
