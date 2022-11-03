//+------------------------------------------------------------------+
//|                                                     fx-pivot.mq4 |
//|                                               Yutthasak Wisidsin |
//|                                           yts.ijoe.wss@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Yutthasak Wisidsin"
#property link      "yts.ijoe.wss@gmail.com"
#property version   "1.00"

//-- Algo Settings --//

input string   symbol_prefix  =  "";
input string   symbol_suffix  =  "m#";

input double   starting_lot_size       =  1.00;    // first order volume in MICRO lot size
input int      avg_spread_compensation =  20;      // unit in "point"
input int      hedge_price_spread      =  200;     // spread from first order in "point"

//-- struct --//

struct fibpivot
{
   datetime pivottime;
   
   double r423;
   double r261;
   double r200;
   double r161;
   double r150;
   double r100;
   double r78;
   double r61;
   double r50;
   double r38;
   double pivotpoint;
   double s38;
   double s50;
   double s61;
   double s78;
   double s100;
   double s150;
   double s161;
   double s200;
   double s261;
   double s423;
};

//-- Global Variables --//

fibpivot dayFib;
fibpivot weekFib;

int   i;    // General loop variable
int   MagicNumber;
int   current_symbol_active_orders;
int   current_symbol_pending_orders;

bool  SelectOrder;
bool  SendOrder;
bool  CloseOrder;
bool  DeleteOrder;
bool  ModifyOrder;

double   broker_digits        =  MarketInfo(Symbol(),MODE_DIGITS);
double   broker_stop_level    =  MarketInfo(Symbol(),MODE_STOPLEVEL);
double   broker_contract_size =  MarketInfo(Symbol(),MODE_LOTSIZE);

double   arr_buy[][2];  // [][1] == value ;; [][2] == weight
double   arr_sell[][2];

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // assigning magic number
   MagicNumber =  get_magic_number( Symbol(), symbol_prefix, symbol_suffix );
   Print( Symbol(), " MagicNumber = ", MagicNumber );

   // initialize arrays
   ArrayResize(arr_buy,20);
   ArrayResize(arr_sell,20);
   ArrayInitialize(arr_buy,EMPTY_VALUE);
   ArrayInitialize(arr_sell,EMPTY_VALUE);
   
   // initialize Daily and Weekly Pivot
   update_dayfib();
   update_weekfib();
   update_buy_arr();
   update_sell_arr();

return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{



}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{

//----------//

   // check pivot time then update if not up-to-date
   if( iTime(NULL, PERIOD_D1, 1) != dayFib.pivottime ){ update_dayfib(); update_buy_arr(); update_sell_arr();}   //dayFib
   if( iTime(NULL, PERIOD_W1, 1) != weekFib.pivottime ){ update_weekfib(); update_buy_arr(); update_sell_arr();} //weekFib

//----------//

   // checking for orders by EA on current chart
   double   total_buy_lot        = 0;
   double   buy_sum_weight       = NULL;
   double   buy_breakeven        = NULL;
   int      first_buy_ticket     = NULL;
   int      last_buy_ticket      = NULL;
   
   double   total_sell_lot       = 0;
   double   sell_sum_weight      = NULL;
   double   sell_breakeven       = NULL;
   int      first_sell_ticket    = NULL;
   int      last_sell_ticket     = NULL;
   
   double   total_commission     = 0;
   double   total_swap           = 0;
   
   int      active_buy_orders    = 0;
   int      active_sell_orders   = 0;
      
   if( OrdersTotal() == 0 )
   { 
      current_symbol_active_orders  =  0;
      current_symbol_pending_orders =  0;
   }
   else
   {
      current_symbol_active_orders  = 0;
      current_symbol_pending_orders = 0;
      
      for(i = OrdersTotal() - 1; i >= 0; i--)
      {
         SelectOrder = OrderSelect(i,SELECT_BY_POS,MODE_TRADES);
         if( OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber )
         {
            // active orders
            if( OrderType() == OP_BUY || OrderType() == OP_SELL )
            {
               if( OrderType() == OP_BUY )
               {
                  total_buy_lot     = total_buy_lot + OrderLots();
                  buy_sum_weight    = buy_sum_weight + ( OrderOpenPrice() * OrderLots() );
                  total_commission  = total_commission + OrderCommission();
                  total_swap        = total_swap + OrderSwap();
                  
                  if( first_buy_ticket == NULL || OrderTicket() < first_buy_ticket )
                  {
                     first_buy_ticket = OrderTicket();
                  }
                  if( last_buy_ticket == NULL || OrderTicket() > last_buy_ticket )
                  {
                     last_buy_ticket = OrderTicket();
                  }
                  
                  active_buy_orders++;
               }
               else if( OrderType() == OP_SELL )
               {
                  total_sell_lot    = total_sell_lot + OrderLots();
                  sell_sum_weight   = sell_sum_weight + ( OrderOpenPrice() * OrderLots() );
                  total_commission  = total_commission + OrderCommission();
                  total_swap        = total_swap + OrderSwap();
                  
                  if( first_sell_ticket == NULL || OrderTicket() < first_sell_ticket )
                  {
                     first_sell_ticket = OrderTicket();
                  }
                  if( last_sell_ticket == NULL || OrderTicket() > last_sell_ticket )
                  {
                     last_sell_ticket = OrderTicket();
                  }
                  
                  active_sell_orders++;
               }
               
               current_symbol_active_orders++;               
            }
            
            // pending orders
            else if( OrderType() == OP_BUYLIMIT || OrderType() == OP_BUYSTOP || OrderType() == OP_SELLLIMIT || OrderType() == OP_SELLSTOP )
            {
               current_symbol_pending_orders++;
            }
         }
      }
   }
//----------// orders data

   double   total_fee      =  total_commission + total_swap;
   
   if( buy_sum_weight != 0 && total_buy_lot != 0 )
   {
      buy_breakeven  =  buy_sum_weight / total_buy_lot;
   }
   else{ buy_breakeven = 0; }
   
   if( sell_sum_weight != 0 && total_sell_lot != 0 )
   {
      sell_breakeven =  sell_sum_weight / total_sell_lot;
   }
   else { sell_breakeven = 0; }
   
   double   break_even_price  =  calc_breakeven( buy_breakeven, total_buy_lot, sell_breakeven, total_sell_lot, total_fee );

//---------//

   int      buy_level_index         =  NULL;
   int      sell_level_index        =  NULL;
   double   buy_level_price         =  NULL;     // 2nd dimension --> [0] = Price, [1] = Weight
   int      next_buy_level_index    =  NULL;
   double   next_buy_level_price    =  NULL;
   
   double   sell_level_price        =  NULL;
   double   buy_level_weight        =  NULL;
   double   sell_level_weight       =  NULL;
   int      next_sell_level_index   =  NULL;
   double   next_sell_level_price   =  NULL;
   
   double   buy_order_price   =  NULL;    // account for average spread      
   double   sell_order_price  =  NULL;
   
   double   buy_order_safeguard_price  =  NULL;
   double   sell_order_safeguard_price =  NULL;
   
   double   buy_order_lot  =  NULL;
   double   sell_order_lot =  NULL;

//----------// no position on current symbol

      if( current_symbol_active_orders == 0 ) // NOT in the market
      {
         buy_level_index   =  find_buy(Ask, "lower", 0);
         sell_level_index  =  find_sell(Bid, "higher", 0);
         
         if( (buy_level_index < 0 || buy_level_index == NULL) || (sell_level_index < 0 || sell_level_index == NULL) )
         {
            return;
         }
         else
         {
            buy_level_price   =  arr_buy[buy_level_index][0];     // 2nd dimension --> [0] = Price, [1] = Weight
            sell_level_price  =  arr_sell[sell_level_index][0];
            buy_level_weight  =  arr_buy[buy_level_index][1];
            sell_level_weight =  arr_sell[sell_level_index][1];
         }

         buy_order_price   =  buy_level_price + ( avg_spread_compensation * Point() );    // account for average spread      
         sell_order_price  =  sell_level_price - ( avg_spread_compensation * Point() );
         
         buy_order_safeguard_price  =  buy_level_price - ( hedge_price_spread * Point() );
         sell_order_safeguard_price =  sell_level_price + ( hedge_price_spread * Point() );

   //====================// check for next order
   
         next_buy_level_index    =  find_buy(Ask, "lower", 1);
         next_buy_level_price    =  arr_buy[next_buy_level_index][0];
         next_sell_level_index   =  find_sell(Bid, "higher", 1);
         next_sell_level_price   =  arr_sell[next_sell_level_index][0];
         
         if( next_buy_level_index < 0 || next_buy_level_index == NULL || MathAbs(buy_level_price - next_buy_level_price) / Point() > hedge_price_spread )
         {
            buy_order_lot  =  (starting_lot_size * 1000 / broker_contract_size);
         }
         else
         {
            buy_order_lot  =  (starting_lot_size * 1000 / broker_contract_size) * buy_level_weight;
         }

         if( next_sell_level_index < 0 || next_sell_level_index == NULL || MathAbs(next_sell_level_price - sell_level_price) / Point() > hedge_price_spread )
         {
            sell_order_lot =  (starting_lot_size * 1000 / broker_contract_size);
         }
         else
         {
            sell_order_lot =  (starting_lot_size * 1000 / broker_contract_size) * sell_level_weight;         
         }
   //====================//

         string   first_buy_comment             =  "first_order_buy";
         string   first_buy_safeguard_comment   =  "first_buy_safeguard";
         string   first_sell_comment            =  "first_order_sell";
         string   first_sell_safeguard_comment  =  "first_sell_safeguard";
         
         if( current_symbol_pending_orders == 0 )  // no active, no pending
         {            
            bool allow_trades = check_allow_trades();
            
            //-- send LIMIT ORDER for both BUY and SELL (using Limit Order just in case of connection issues)
            if( allow_trades == true )
            {
               //send BUY
               SendOrder   =  OrderSend(Symbol(), OP_BUYLIMIT, buy_order_lot, buy_order_price, 0, 0, 0, first_buy_comment, MagicNumber, 0, clrNONE);
               SendOrder   =  OrderSend(Symbol(), OP_SELLSTOP, buy_order_lot, buy_order_safeguard_price, 0, 0, 0, first_buy_safeguard_comment, MagicNumber, 0, clrNONE);
               
               //send SELL
               SendOrder   =  OrderSend(Symbol(), OP_SELLLIMIT, sell_order_lot, sell_order_price, 0, 0, 0, first_sell_comment, MagicNumber, 0, clrNONE);
               SendOrder   =  OrderSend(Symbol(), OP_BUYSTOP, sell_order_lot, sell_order_safeguard_price, 0, 0, 0, first_sell_safeguard_comment, MagicNumber, 0, clrNONE);   
            }
         }
         else if( current_symbol_pending_orders > 0 ) // no active, have pending. check for validity
         {
            // select current symbol orders
            for(i = OrdersTotal() - 1; i >= 0; i--)
            {
               SelectOrder = OrderSelect(i,SELECT_BY_POS,MODE_TRADES);
               if( OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber )
               {
                  if( OrderType() == OP_BUYLIMIT )
                  {
                     if( OrderLots() != buy_order_lot || OrderOpenPrice() != buy_order_price || OrderComment() != first_buy_comment )
                     {
                        DeleteOrder = OrderDelete(OrderTicket());
                     }
                  }
                  if( OrderType() == OP_BUYSTOP )
                  {
                     if( OrderLots() != sell_order_lot || OrderOpenPrice() != sell_order_safeguard_price || OrderComment() != first_sell_safeguard_comment )
                     {
                        DeleteOrder = OrderDelete(OrderTicket());
                     }
                  }
                  if( OrderType() == OP_SELLLIMIT )
                  {
                     if( OrderLots() != sell_order_lot || OrderOpenPrice() != sell_order_price || OrderComment() != first_sell_comment )
                     {
                        DeleteOrder = OrderDelete(OrderTicket());
                     }
                  }
                  if( OrderType() == OP_SELLSTOP )
                  {
                     if( OrderLots() != buy_order_lot || OrderOpenPrice() != buy_order_safeguard_price || OrderComment() != first_buy_safeguard_comment )
                     {
                        DeleteOrder = OrderDelete(OrderTicket());
                     }
                  }
               }
            }
         }
   }
   else if( current_symbol_active_orders > 0 ) // IN the market
   {
      double total_lot_size   = total_buy_lot + total_sell_lot;
      double lot_limit        = starting_lot_size * 1.0;
      
      //-- lot size not exceeding lot limit, 
      if( total_lot_size < lot_limit )
      {
         
      }
      else
      {
      
      }
      
   }

} // OnTick

//-------------------------------------------------- GLOBAL FUNCTIONS --------------------------------------------------//

int   get_magic_number(string symbol, string prefix, string suffix)
{
   int   ea_magic_number;
   
      //-- int StringLen = Return the number of symbols in a string.
      
      int   n_prefix    =  StringLen(prefix);   //-- number of Characters before actual SYMBOL
      int   n_suffix    =  StringLen(suffix);   //-- number of Characters after actual SYMBOL
      int   n_symbol    =  StringLen(symbol);   //-- number of Characters in Symbol()
      
      int   n_symbol_char  =  n_symbol - (n_prefix + n_suffix);
      
      //-- string StringSubstr = Extracts a substring from text starting from the specified position.
      
      string   t_prefix    =  StringSubstr(symbol,0,n_prefix);
      string   t_symbol    =  StringSubstr(symbol,n_prefix,n_symbol_char);
      string   t_suffix    =  StringSubstr(symbol,n_prefix + n_symbol_char,n_suffix);
      
      //-- Currency Base/Quote Number --//     
/*    
      AUD   =  1
      CAD   =  2
      CHF   =  3
      EUR   =  4
      GBP   =  5
      JPY   =  6
      NZD   =  7
      USD   =  8
      ETC.  =  9
*/
      string   c_base   =  StringSubstr(t_symbol,0,3);
      string   c_quote  =  StringSubstr(t_symbol,3,3);

      string   n_base;
      string   n_quote;
      
            if( c_base  == "AUD" ){ n_base   =  "1"; }
      else  if( c_base  == "CAD" ){ n_base   =  "2"; }
      else  if( c_base  == "CHF" ){ n_base   =  "3"; }
      else  if( c_base  == "EUR" ){ n_base   =  "4"; }
      else  if( c_base  == "GBP" ){ n_base   =  "5"; }
      else  if( c_base  == "JPY" ){ n_base   =  "6"; }
      else  if( c_base  == "NZD" ){ n_base   =  "7"; }
      else  if( c_base  == "USD" ){ n_base   =  "8"; }
      else  { n_base = "9"; }
      
      //-----//
      
            if( c_quote  == "AUD" ){ n_quote   =  "1"; }
      else  if( c_quote  == "CAD" ){ n_quote   =  "2"; }
      else  if( c_quote  == "CHF" ){ n_quote   =  "3"; }
      else  if( c_quote  == "EUR" ){ n_quote   =  "4"; }
      else  if( c_quote  == "GBP" ){ n_quote   =  "5"; }
      else  if( c_quote  == "JPY" ){ n_quote   =  "6"; }
      else  if( c_quote  == "NZD" ){ n_quote   =  "7"; }
      else  if( c_quote  == "USD" ){ n_quote   =  "8"; }
      else  { n_quote = "9"; }
      
      //-----//
      
      string   t_magic_number =  n_base + n_quote;             //-- combine base and quote string
      
      ea_magic_number   =  StringToInteger(t_magic_number);    //-- convert MagicNumber from STRING to INT

return(ea_magic_number);
}

////////////////////////////////////////////////// FUNCTIONS //////////////////////////////////////////////////

bool check_allow_trades()
{
   bool isAllowed = false;
   
   return(isAllowed);
}

//////////////////////////////////////////////////

void update_dayfib()
{
   datetime d_time   =  iTime(NULL, PERIOD_D1, 1);
   double   d_high   =  iHigh(NULL, PERIOD_D1, 1);
   double   d_low    =  iLow(NULL, PERIOD_D1, 1);
   double   d_close  =  iClose(NULL, PERIOD_D1, 1);
   double   d_range  =  d_high - d_low;
   double   d_pivot  =  NormalizeDouble((d_high + d_low + d_close)/3, Digits());

   dayFib.pivottime  =  d_time;
   dayFib.pivotpoint =  d_pivot;
   dayFib.r423       =  NormalizeDouble(d_pivot + (d_range*4.236), Digits());
   dayFib.r261       =  NormalizeDouble(d_pivot + (d_range*2.618), Digits());
   dayFib.r200       =  NormalizeDouble(d_pivot + (d_range*2.000), Digits());
   dayFib.r161       =  NormalizeDouble(d_pivot + (d_range*1.618), Digits());
   dayFib.r150       =  NormalizeDouble(d_pivot + (d_range*1.500), Digits());
   dayFib.r100       =  NormalizeDouble(d_pivot + (d_range*1.000), Digits());
   dayFib.r61        =  NormalizeDouble(d_pivot + (d_range*0.618), Digits());
   dayFib.r50        =  NormalizeDouble(d_pivot + (d_range*0.500), Digits());
   dayFib.r38        =  NormalizeDouble(d_pivot + (d_range*0.382), Digits());
   dayFib.s38        =  NormalizeDouble(d_pivot - (d_range*0.382), Digits());
   dayFib.s50        =  NormalizeDouble(d_pivot - (d_range*0.500), Digits());
   dayFib.s61        =  NormalizeDouble(d_pivot - (d_range*0.618), Digits());
   dayFib.s100       =  NormalizeDouble(d_pivot - (d_range*1.000), Digits());
   dayFib.s150       =  NormalizeDouble(d_pivot - (d_range*1.500), Digits());
   dayFib.s161       =  NormalizeDouble(d_pivot - (d_range*1.618), Digits());
   dayFib.s200       =  NormalizeDouble(d_pivot - (d_range*2.000), Digits());
   dayFib.s261       =  NormalizeDouble(d_pivot - (d_range*2.618), Digits());
   dayFib.s423       =  NormalizeDouble(d_pivot - (d_range*4.236), Digits());
}

void update_weekfib()
{
   datetime w_time   =  iTime(NULL, PERIOD_W1, 1);
   double   w_high   =  iHigh(NULL, PERIOD_W1, 1);
   double   w_low    =  iLow(NULL, PERIOD_W1, 1);
   double   w_close  =  iClose(NULL, PERIOD_W1, 1);
   double   w_range  =  w_high - w_low;
   double   w_pivot  =  NormalizeDouble((w_high + w_low + w_close)/3, Digits());
     
   weekFib.pivottime  =  w_time;
   weekFib.pivotpoint =  w_pivot;
   weekFib.r423       =  NormalizeDouble(w_pivot + (w_range*4.236), Digits());
   weekFib.r261       =  NormalizeDouble(w_pivot + (w_range*2.618), Digits());
   weekFib.r200       =  NormalizeDouble(w_pivot + (w_range*2.000), Digits());
   weekFib.r161       =  NormalizeDouble(w_pivot + (w_range*1.618), Digits());
   weekFib.r150       =  NormalizeDouble(w_pivot + (w_range*1.500), Digits()); 
   weekFib.r100       =  NormalizeDouble(w_pivot + (w_range*1.000), Digits());
   weekFib.r61        =  NormalizeDouble(w_pivot + (w_range*0.618), Digits());
   weekFib.r50        =  NormalizeDouble(w_pivot + (w_range*0.500), Digits());
   weekFib.r38        =  NormalizeDouble(w_pivot + (w_range*0.382), Digits());
   weekFib.s38        =  NormalizeDouble(w_pivot - (w_range*0.382), Digits());
   weekFib.s50        =  NormalizeDouble(w_pivot - (w_range*0.500), Digits());
   weekFib.s61        =  NormalizeDouble(w_pivot - (w_range*0.618), Digits());
   weekFib.s100       =  NormalizeDouble(w_pivot - (w_range*1.000), Digits());
   weekFib.s150       =  NormalizeDouble(w_pivot - (w_range*1.500), Digits());
   weekFib.s161       =  NormalizeDouble(w_pivot - (w_range*1.618), Digits());
   weekFib.s200       =  NormalizeDouble(w_pivot - (w_range*2.000), Digits());
   weekFib.s261       =  NormalizeDouble(w_pivot - (w_range*2.618), Digits());
   weekFib.s423       =  NormalizeDouble(w_pivot - (w_range*4.236), Digits());
}

//////////////////////////////////////////////////

void update_buy_arr()
{
   arr_buy[0][0]  =  weekFib.s423;
   arr_buy[0][1]  =  0.5;
   
   arr_buy[1][0]  =  weekFib.s261;
   arr_buy[1][1]  =  0.5;
    
   arr_buy[2][0]  =  weekFib.s200;
   arr_buy[2][1]  =  1.0;
   
   arr_buy[3][0]  =  weekFib.s161;
   arr_buy[3][1]  =  0.5;
   
   arr_buy[4][0]  =  weekFib.s150;
   arr_buy[4][1]  =  0.5;
   
   arr_buy[5][0]  =  weekFib.s100;
   arr_buy[5][1]  =  1.0;
   
   arr_buy[6][0]  =  weekFib.s61;
   arr_buy[6][1]  =  0.5;
   
   arr_buy[7][0]  =  weekFib.s50;
   arr_buy[7][1]  =  0.5;
   
   arr_buy[8][0]  =  weekFib.s38;
   arr_buy[8][1]  =  0.5;
   
   arr_buy[9][0]  =  weekFib.pivotpoint;
   arr_buy[9][1]  =  1.0;
   
   arr_buy[10][0] =  dayFib.s423;
   arr_buy[10][1] =  0.3;
   
   arr_buy[11][0] =  dayFib.s261;
   arr_buy[11][1] =  0.3;
   
   arr_buy[12][0] =  dayFib.s200;
   arr_buy[12][1] =  1.0;
   
   arr_buy[13][0] =  dayFib.s161;
   arr_buy[13][1] =  0.5;
   
   arr_buy[14][0] =  dayFib.s150;
   arr_buy[14][1] =  0.5;
   
   arr_buy[15][0] =  dayFib.s100;
   arr_buy[15][1] =  1.0;
   
   arr_buy[16][0] =  dayFib.s61;
   arr_buy[16][1] =  0.3;
   
   arr_buy[17][0] =  dayFib.s50;
   arr_buy[17][1] =  0.5;
   
   arr_buy[18][0] =  dayFib.s38;
   arr_buy[18][1] =  0.3;
   
   arr_buy[19][0] =  dayFib.pivotpoint;
   arr_buy[19][1] =  1.0;
   
   ArraySort(arr_buy,WHOLE_ARRAY,0,MODE_ASCEND);   // sorting from Lowest[0] --> Highest[19]
}

void update_sell_arr()
{
   arr_sell[0][0]  =  weekFib.r423;
   arr_sell[0][1]  =  0.5;
   
   arr_sell[1][0]  =  weekFib.r261;
   arr_sell[1][1]  =  0.5;
   
   arr_sell[2][0]  =  weekFib.r200;
   arr_sell[2][1]  =  1.0;
   
   arr_sell[3][0]  =  weekFib.r161;
   arr_sell[3][1]  =  0.5;
   
   arr_sell[4][0]  =  weekFib.r150;
   arr_sell[4][1]  =  0.5;
   
   arr_sell[5][0]  =  weekFib.r100;
   arr_sell[5][1]  =  1.0;
   
   arr_sell[6][0]  =  weekFib.r61;
   arr_sell[6][1]  =  0.5;
   
   arr_sell[7][0]  =  weekFib.r50;
   arr_sell[7][1]  =  0.5;
   
   arr_sell[8][0]  =  weekFib.r38;
   arr_sell[8][1]  =  0.5;
   
   arr_sell[9][0]  =  weekFib.pivotpoint;
   arr_sell[9][1]  =  1.0;
   
   arr_sell[10][0] =  dayFib.r423;
   arr_sell[10][1] =  0.3;
   
   arr_sell[11][0] =  dayFib.r261;
   arr_sell[11][1] =  0.3;
   
   arr_sell[12][0] =  dayFib.r200;
   arr_sell[12][1] =  1.0;
   
   arr_sell[13][0] =  dayFib.r161;
   arr_sell[13][1] =  0.5;
   
   arr_sell[14][0] =  dayFib.r150;
   arr_sell[14][1] =  0.5;
   
   arr_sell[15][0] =  dayFib.r100;
   arr_sell[15][1] =  1.0;
   
   arr_sell[16][0] =  dayFib.r61;
   arr_sell[16][1] =  0.3;
   
   arr_sell[17][0] =  dayFib.r50;
   arr_sell[17][1] =  0.5;
   
   arr_sell[18][0] =  dayFib.r38;
   arr_sell[18][1] =  0.3;
   
   arr_sell[19][0] =  dayFib.pivotpoint;
   arr_sell[19][1] =  1.0;
   
   ArraySort(arr_sell,WHOLE_ARRAY,0,MODE_ASCEND);   // sorting from Lowest[0] --> Highest[19]
}

//////////////////////////////////////////////////

int find_buy(double price_ask, string mode, int offset_index)
{
   int      total_buy_level         =  ArraySize(arr_buy) / 2;
   int      buy_level_index         =  NULL;
   
   if( mode == "lower" )
   {
      double   current_highest_lower_price   = NULL;
      
      for( i = 0; i < total_buy_level; i++ )
      {
         if( arr_buy[i][0] < price_ask ) // lower than price
         {
            if( current_highest_lower_price == NULL || arr_buy[i][0] > current_highest_lower_price )
            {
               current_highest_lower_price = arr_buy[i][0];
               buy_level_index = i;
            }
         }
      }
      
      buy_level_index = buy_level_index - offset_index;
   }
   else if( mode == "higher" )
   {
      double   current_lowest_higher_price   = NULL;
      
      for( i = 0; i < total_buy_level; i++ )
      {
         if( arr_buy[i][0] > price_ask ) // higher than price
         {
            if( current_lowest_higher_price == NULL || arr_buy[i][0] < current_lowest_higher_price )
            {
               current_lowest_higher_price = arr_buy[i][0];
               buy_level_index = i;
            }
         }
      }
      
      buy_level_index = buy_level_index + offset_index;
   }
   
return(buy_level_index);
}

int find_sell(double price_bid, string mode, int offset_index)
{
   int   total_sell_level  = ArraySize(arr_sell) / 2;
   int   sell_level_index  = NULL;
   
   if( mode == "higher" )
   {
      double current_lowest_higher_price = NULL;
      
      for( i = 0; i < total_sell_level; i++ )
      {
         if( arr_sell[i][0] > price_bid ) // higher than price
         {
            if( current_lowest_higher_price == NULL || arr_sell[i][0] < current_lowest_higher_price )
            {
               current_lowest_higher_price = arr_sell[i][0];
               sell_level_index = i;
            }
         }
      }
      
      sell_level_index = sell_level_index + offset_index;
   }
   else if( mode == "lower" )
   {
      double current_highest_lower_price = NULL;
      
      for( i = 0; i < total_sell_level; i++ )
      {
         if( arr_sell[i][0] < price_bid )
         {
            if( current_highest_lower_price == NULL || arr_sell[i][0] > current_highest_lower_price )
            {
               current_highest_lower_price = arr_sell[i][0];
               sell_level_index = i;
            }
         }
      }
      
      sell_level_index = sell_level_index - offset_index;
   }
   
return(sell_level_index);
}

//////////////////////////////////////////////////

double calc_breakeven( double buy_be, double buy_lot, double sell_be, double sell_lot, double trade_fee )
{
   double be_price            = NULL;
   double lot_diff            = NULL;
   double be_spread           = NULL;
   double loss_in_point       = NULL;
   double profit_point_to_be  = NULL;
   double trade_fee_point     = NULL;
   
   if( buy_lot + sell_lot == 0 )
   {
      trade_fee_point = 0;
   }
   else
   {
      trade_fee_point = calc_trades_fee(trade_fee, lot_diff) * Point();
   }
   
   if( buy_lot > sell_lot )
   {
      if( sell_be == 0 )
      {
         be_price = buy_be + trade_fee_point;
      }
      else
      {
         lot_diff             = buy_lot - sell_lot;
         be_spread            = NormalizeDouble(MathAbs(buy_be - sell_be), Digits());
         loss_in_point        = be_spread * sell_lot;
         profit_point_to_be   = NormalizeDouble(loss_in_point / lot_diff, Digits()) + 1;
         be_price             = buy_be + profit_point_to_be + trade_fee_point;
      }
   }
   else if( sell_lot > buy_lot )
   {
      if( buy_be == 0 )
      {
         be_price = sell_be - trade_fee_point;
      }
      else
      {
         lot_diff             = sell_lot - buy_lot;
         be_spread            = NormalizeDouble(MathAbs(buy_be - sell_be), Digits());
         loss_in_point        = be_spread * buy_lot;
         profit_point_to_be   = NormalizeDouble(loss_in_point / lot_diff, Digits()) + 1;
         be_price             = sell_be - profit_point_to_be - trade_fee_point;
      }
   }
   
   return(be_price);
}

double calc_trades_fee( double fee_dollar, double lot_difference )
{
   double fee_in_point;
   
      //-- get Symbol() string start position
      int   prefix_length  =  StringLen(symbol_prefix);
      int   suffix_length  =  StringLen(symbol_suffix);
      int   symbol_length  =  StringLen(Symbol());
      int   symbol_char_length   =  symbol_length - (prefix_length + suffix_length);
      
      //-- string StringSubstr = Extracts a substring from a text string starting from the specified position.
      string   str_prefix  =  StringSubstr(Symbol(),0,prefix_length);
      string   str_symbol  =  StringSubstr(Symbol(),prefix_length, suffix_length);
      string   str_suffix  =  StringSubstr(Symbol(),prefix_length + symbol_length, suffix_length);
      
   /*    
         AUD   =  1
         CAD   =  2
         CHF   =  3
         EUR   =  4
         GBP   =  5
         JPY   =  6
         NZD   =  7
         USD   =  8
         ETC.  =  9
   */
   
      //-- ONLY USD for now
      
      string   base_currency  =  StringSubstr(Symbol(),0,3);
      string   quote_currency =  StringSubstr(Symbol(),3,3);
      
      double   value_per_point   =  NULL;
      
      if( quote_currency == "USD" )
      {
         value_per_point   =  Point() * broker_contract_size * lot_difference;
      }
      else
      {
         string cross_exchange_symbol  = str_prefix + "USD" + quote_currency + str_suffix;
         value_per_point   =  ( Point() * broker_contract_size ) / iClose(cross_exchange_symbol,0,0) * lot_difference;
      }
      Print(value_per_point);
      fee_in_point = NormalizeDouble(fee_dollar / value_per_point,0) + 1;
   
   return(fee_in_point);
}