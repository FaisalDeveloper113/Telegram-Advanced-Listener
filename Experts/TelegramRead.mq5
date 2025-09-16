//+------------------------------------------------------------------+
//|                                    TelegramChannelListener.mq5 |
//+------------------------------------------------------------------+
#property strict
#include <Telegram.mqh>
#include <Trade\Trade.mqh>
#define MaxOrders 100

struct Order_Struct
  {
   ulong             ticket;
   string            symbol;
   ENUM_POSITION_TYPE   order_type;
   double            initial_lot;
   double            stoploss;
   bool              is_Tp1_hit;
   double            Tp1;
                     Order_Struct()
     {
      ticket = -1;
     }
  };
Order_Struct Orders[MaxOrders];

input int   Magic_Number = 113;  // MagicNumber
input string InpToken = "6512679126:AAFSSuBPLl7q-FeSWZoRYnQW7oJHEx58aN8";
input int InpTimerSeconds = 1; // Check every 10 seconds
input string             suffix              = "";                                                      // Add Symbol Suffix
input double  risk = 1; // Risk
input double  tp1closeper = 50;  // Tp1 Close Percentage



CTrade trade;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
class CMyBot: public CCustomBot
  {
public:
   void              ProcessMessages(void)
     {
      for(int i = 0; i < m_chats.Total(); i++)
        {
         CCustomChat *chat = m_chats.GetNodeAtIndex(i);
         if(!chat.m_new_one.done)
           {
            chat.m_new_one.done = true;
            string text = chat.m_new_one.message_text;

            Print("NEW MESSAGE RECEIVED: '", text, "'");
            if(IsValidTradingSignal(text))
              {
               Print("EXECUTING TRADE...");
               ExecuteTrade(text);
              }
            else
              {
               Print("❌ MESSAGE REJECTED: Not a valid trading signal");
              }
           }
        }
     }
  };

CMyBot bot;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
// Initialize bot with token
   if(!bot.Initialize(InpToken))
     {
      Comment("Telegram Bot ERROR: Connection Failed");
      Print("Failed to initialize Telegram bot");
      return INIT_FAILED;
     }

// Get bot name and show in comment
   string botName = bot.GetBotName();
   if(botName != "")
     {
      Comment("Telegram Bot Connected: " + botName);
      Print("Telegram Bot Connected: ", botName);
     }
   else
     {
      Comment("Telegram Bot Connected");
      Print("Telegram Bot Connected");
     }

// Start timer for reading messages
   int deviation = 10;
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetDeviationInPoints(deviation);
   trade.SetTypeFilling(ORDER_FILLING_RETURN);
   trade.LogLevel(1);
   trade.SetAsyncMode(false);
   EventSetTimer(InpTimerSeconds);
   Print("Telegram Message Listener Started - Timer: ", InpTimerSeconds, " seconds");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment(""); // Clear the comment when EA stops
   Print("Telegram Bot Stopped. Reason code: ", reason);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
// Simply call ReadMessages - all WebRequest logic is in Telegram.mqh
   bot.ReadMessages();
   if(isNewBarM1())
      print_orders_information();
   close_orders_partials();
   TakePorfit_Trailing();
   remove_closed_order_from_struct();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
// Nothing needed here for message listening
  }



// Enhanced ExecuteTrade with detailed debugging
void ExecuteTrade(string signal)
  {
   string result[];
   Print("Message : ", signal);

   StringReplace(signal, " ", "");
   StringReplace(signal, "  ", "");
   Print("After removing spaces: ", signal);

// Replace \\n with |
   StringReplace(signal, "\\n", "|");
   Print("After replacement with |: ", signal);

// Get the character code for | separator
   ushort separator = StringGetCharacter("|", 0);

// Now use the character code in StringSplit
   int splitstrings = StringSplit(signal, separator, result);
   Print("Split Result : ", splitstrings);

   ENUM_POSITION_TYPE TYPE;
   StringToUpper(result[0]) ;
   if(result[0] == "BUY")
     {
      TYPE = POSITION_TYPE_BUY;
     }
   if(result[0] == "SELL")
     {
      TYPE = POSITION_TYPE_SELL;
     }
   string SYMBOL = result[1];
   double TP1 = StringToDouble(StringSubstr(result[2], StringFind(result[2], "=") + 1));
   double TP2 = StringToDouble(StringSubstr(result[3], StringFind(result[3], "=") + 1));
   double SL = StringToDouble(StringSubstr(result[4], StringFind(result[4], "=") + 1));

   Print("=== TRADE SIGNAL PARSED ===");
   Print("Type: ", (TYPE == POSITION_TYPE_BUY) ? "BUY" : "SELL",
         " | Symbol: ", SYMBOL,
         " | TP1: ", TP1,
         " | TP2: ", TP2,  // Note: You have a typo here - TP@ should probably be TP1 or TP2
         " | SL: ", SL);

   if(TYPE == POSITION_TYPE_BUY)
     {
      ulong ticket = place_market_buy(SYMBOL,SL,TP1,TP2);
      Print("Buy Trade Tikcet : ", ticket);
     }
   if(TYPE == POSITION_TYPE_SELL)
     {
      ulong ticket = place_market_sell(SYMBOL,SL,TP1,TP2);
      Print("Sell Trade Tikcet : ", ticket);
     }


  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ulong  place_market_buy(string orderSymbol, double sl, double tp1,double tp)
  {
   orderSymbol = orderSymbol + suffix;
   double  Ask = SymbolInfoDouble(orderSymbol,SYMBOL_ASK);
   double  Bid = SymbolInfoDouble(orderSymbol,SYMBOL_BID);
   string trade_comment = "Telegram Trade";
   double lot = getlot(orderSymbol,sl/SymbolInfoDouble(orderSymbol,SYMBOL_POINT));

   if(!trade.Buy(lot,orderSymbol,Ask,Bid - sl,Ask + tp,trade_comment))
     {
      Print("Buy() method failed. Return code=",trade.ResultRetcode(),
            ". Code description: ",trade.ResultRetcodeDescription());
     }

   else
     {
      Print("Buy() method executed successfully. Return code=",trade.ResultRetcode(),
            " (",trade.ResultRetcodeDescription(),")");
      if(store_order_information(trade.ResultOrder(),orderSymbol,POSITION_TYPE_BUY,lot,sl,Ask + tp1))
         Print("Order Stored Successfuly!!");
      return trade.ResultOrder();
     }
   return 0;
  }
//+------------------------------------------------------------------+
ulong  place_market_sell(string orderSymbol, double sl,double tp1, double tp)
  {
   orderSymbol = orderSymbol + suffix;
   double  Ask = SymbolInfoDouble(orderSymbol,SYMBOL_ASK);
   double  Bid = SymbolInfoDouble(orderSymbol,SYMBOL_BID);
   string trade_comment = "Telegram Trade";
   double lot = getlot(orderSymbol,sl/SymbolInfoDouble(orderSymbol,SYMBOL_POINT));

   if(!trade.Sell(lot,orderSymbol,Bid,Ask + sl,Bid - tp,trade_comment))
     {
      Print("Sell() method failed. Return code=",trade.ResultRetcode(),
            ". Code description: ",trade.ResultRetcodeDescription());
     }

   else
     {
      Print("Sell() method executed successfully. Return code=",trade.ResultRetcode(),
            " (",trade.ResultRetcodeDescription(),")");
      if(store_order_information(trade.ResultOrder(),orderSymbol,POSITION_TYPE_SELL,lot,sl,Bid - tp1))
         Print("Order Stored Successfuly!!");
      return trade.ResultOrder();
     }
   return 0;
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool IsValidTradingSignal(string text)
  {
   Print("=== VALIDATING TRADING SIGNAL ===");

// Test 1: Length check
   if(StringLen(text) < 5)
     {
      Print("Test 1: FAILED - Message too short");
      return false;
     }
   Print("Test 1: PASSED - Length check");

// Remove spaces and prepare for splitting
   string temp = text;
   StringReplace(temp, " ", "");
   StringReplace(temp, "  ", "");
   StringReplace(temp, "\\n", "|");
   StringReplace(temp, "\n", "|");


// Split to check components
   string parts[];
   ushort separator = StringGetCharacter("|", 0);
   int count = StringSplit(temp, separator, parts);

// Test 2: Parts count
   if(count < 3)
     {
      Print("Test 2: FAILED - Insufficient parts");
      return false;
     }
   Print("Test 2: PASSED - Parts count");

// Test 3: BUY/SELL check - SIMPLIFIED
   string action = parts[0]; // Don't modify it, use it as-is


// Simple check without StringToUpper - just check both cases
   if(action == "BUY" || action == "SELL" || action == "buy" || action == "sell")
     {
      Print("Test 3: PASSED - Action check");
     }
   else
     {
      Print("Test 3: FAILED - Action is '", action, "'");
      return false;
     }

// Test 4: TP check
   bool hasAnyTP = false;
   for(int i=0; i<count; i++)
     {
      if(StringFind(parts[i], "TP") >= 0 || StringFind(parts[i], "tp") >= 0)
         hasAnyTP = true;
     }

   if(!hasAnyTP)
     {
      Print("Test 4: FAILED - No TP found");
      return false;
     }
   Print("Test 4: PASSED - TP check");

// Test 5: SL check
   bool hasAnySL = false;
   for(int i=0; i<count; i++)
     {
      if(StringFind(parts[i], "SL") >= 0 || StringFind(parts[i], "sl") >= 0)
         hasAnySL = true;
     }

   if(!hasAnySL)
     {
      Print("Test 5: FAILED - No SL found");
      return false;
     }
   Print("Test 5: PASSED - SL check");

   Print("ALL TESTS PASSED - Signal is valid");
   return true;
  }
//+------------------------------------------------------------------+
double getlot(string symbol, double stop_loss)
  {
   Print("Tick Value: ",SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE));
   Print("Tick Size: ",SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE));
   double modeTickV=SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_VALUE)
                    ,modeTickS=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double pipvalue = NormalizeDouble(((SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE)/(SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE)/Point()))*10),2);
   pipvalue = pipvalue / 10;
   double lotSize = 0.1;

   double riskamount=(risk/100) * AccountInfoDouble(ACCOUNT_BALANCE);
   Print("Risk AMount:  ",riskamount);
   double pipvalue_required=riskamount/stop_loss;
   lotSize = pipvalue_required/pipvalue;
//sl=riskamount/pipValuelot
   int roundDigit=0;
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);

   while(step<1)
     {
      roundDigit++;
      step=step*10;
     }
   Print("Round Digits:",roundDigit);
   lotSize = NormalizeDouble(lotSize,roundDigit);
//
   Print("Lot Size: ",lotSize);

   if(lotSize > SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX))
     {
      lotSize=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
     }
   else
      if(lotSize<SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN))
        {
         lotSize=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
        }

//---
   return lotSize;
  }
//+------------------------------------------------------------------+
bool store_order_information(ulong ticket,string symbol, ENUM_POSITION_TYPE type, double lot, double sl, double tp1)
  {
   for(int i=0; i<MaxOrders; i++)
     {
      if(Orders[i].ticket == -1)
        {
         Orders[i].ticket = ticket;
         Orders[i].symbol = symbol;
         Orders[i].order_type = type;
         Orders[i].initial_lot = lot;
         Orders[i].stoploss = sl;
         Orders[i].is_Tp1_hit = false;
         Orders[i].Tp1 = tp1;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void print_orders_information()
  {
   for(int i=0; i<MaxOrders; i++)
     {
      if(Orders[i].ticket != -1)
        {
         Print("[",i,"] --> Ticket: ", Orders[i].ticket," Symbol: ",Orders[i].symbol, " Lot: ", Orders[i].initial_lot, " SL : ", Orders[i].stoploss, " Tp1Hit: ", Orders[i].is_Tp1_hit,
               " Tp1: ", Orders[i].Tp1);
        }
     }
  }
//+------------------------------------------------------------------+
bool isNewBarM1()
  {
   static datetime last_time=0;
   datetime lastbar_time=(datetime)SeriesInfoInteger(Symbol(),PERIOD_M1,SERIES_LASTBAR_DATE);

   if(last_time==0)
     {
      last_time=lastbar_time;
      return(false);
     }

   if(last_time!=lastbar_time)
     {
      last_time=lastbar_time;
      Print("<><><><><>NEW Bar M1 : ",lastbar_time, "<><><><><>");
      return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
void remove_closed_order_from_struct()
  {
   if(PositionsTotal() > 0)
      return;
   bool isOrderRunning;
   for(int x=0; x<MaxOrders; x++)
     {
      if(Orders[x].ticket != -1)
        {
         ulong master_ticket = Orders[x].ticket;
         isOrderRunning = false;
         for(int i=PositionsTotal(); i>0; i--)
           {
            ulong ticket = PositionGetTicket(i);

            if(PositionSelectByTicket(ticket))
              {
               if(PositionGetInteger(POSITION_MAGIC) == Magic_Number)
                 {
                  if((PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) || (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL))
                    {
                     Print("Ticket : ", ticket, " masterTicket : ", master_ticket);
                     if(ticket == master_ticket)
                        isOrderRunning = true;
                    }
                 }
              }
           }
         if(!isOrderRunning)
           {
            Print("Tikcet : ", Orders[x].ticket, " Has been Closed !! Removing from Struct !!");
            Orders[x].ticket = -1;
           }

        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TakePorfit_Trailing()
  {
   for(int i=0; i<MaxOrders; i++)
     {
      if(Orders[i].ticket != -1)
        {
         if(Orders[i].is_Tp1_hit)
           {
            if(PositionSelectByTicket(Orders[i].ticket))
              {
               double stoploss = PositionGetDouble(POSITION_SL);
               double newStopLoss = PositionGetDouble(POSITION_PRICE_OPEN);
               double takeprofit = PositionGetDouble(POSITION_TP);
               stoploss = NormalizeDouble(stoploss,Digits());
               newStopLoss = NormalizeDouble(newStopLoss,Digits());
               if(stoploss != newStopLoss)
                 {
                  if(!trade.PositionModify(Orders[i].ticket,newStopLoss,takeprofit))
                    {
                     if(!trade.PositionModify(Orders[i].ticket,newStopLoss,takeprofit))
                       {
                        Print("Tp2 SL : ", GetLastError());
                        Print("Ticket: ", Orders[i].ticket);
                       }
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void close_orders_partials()
  {
   for(int i=0; i<MaxOrders; i++)
     {
      if(Orders[i].ticket != -1)
        {
         double Ask = SymbolInfoDouble(Orders[i].symbol,SYMBOL_ASK);
         double Bid = SymbolInfoDouble(Orders[i].symbol,SYMBOL_BID);

         if(Orders[i].order_type == POSITION_TYPE_BUY)
           {
            if(Bid >= Orders[i].Tp1 && !Orders[i].is_Tp1_hit &&  Orders[i].Tp1 != 0)
              {
               if(PositionSelectByTicket(Orders[i].ticket))
                 {
                  double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                  double volume = PositionGetDouble(POSITION_VOLUME);
                  double sl = PositionGetDouble(POSITION_SL);
                  double tp = PositionGetDouble(POSITION_TP);
                  double lot_to_close = volume * (tp1closeper/100);
                  lot_to_close = NormalizeDouble(lot_to_close,2);
                  if(trade.PositionClosePartial(Orders[i].ticket,lot_to_close,1))
                    {
                     Print("Ticket : ", Orders[i].ticket, " Tp1 Closed !!");
                     Orders[i].is_Tp1_hit = true;
                     Orders[i].initial_lot = lot_to_close;
                    }
                 }
              }

           }
         if(Orders[i].order_type == POSITION_TYPE_SELL)
           {
            if(Ask <= Orders[i].Tp1 && !Orders[i].is_Tp1_hit && Orders[i].Tp1 != 0)
              {
               if(PositionSelectByTicket(Orders[i].ticket))
                 {
                  double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                  double volume = PositionGetDouble(POSITION_VOLUME);
                  double sl = PositionGetDouble(POSITION_SL);
                  double tp = PositionGetDouble(POSITION_TP);
                  double lot_to_close = volume * (tp1closeper/100);
                  lot_to_close = NormalizeDouble(lot_to_close,2);
                  if(trade.PositionClosePartial(Orders[i].ticket,lot_to_close,1))
                    {
                     Print("Ticket : ", Orders[i].ticket, " Tp1 Closed !!");
                     Orders[i].is_Tp1_hit = true;
                     Orders[i].initial_lot = lot_to_close;
                    }
                 }
              }
           }
        }
     }
  }
//+--------------
//+------------------------------------------------------------------+
