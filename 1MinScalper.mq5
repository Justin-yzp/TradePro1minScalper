//+------------------------------------------------------------------+
//|                                                  1MinScalper.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//MA Inputs
input int InpFastBars = 20;                                  //Fast Bars
input ENUM_MA_METHOD InpFastMethod = MODE_EMA;               //Fast Method
input ENUM_APPLIED_PRICE InpFastAppliedPrice = PRICE_CLOSE;  //Fast Price

input int InpMidBars = 50;                                  //Mid Bars
input ENUM_MA_METHOD InpMidMethod = MODE_EMA;               //Mid Method
input ENUM_APPLIED_PRICE InpMidAppliedPrice = PRICE_CLOSE;  //Mid Price

input int InpSlowBars = 100;                                //Slow Bars
input ENUM_MA_METHOD InpSlowMethod = MODE_EMA;               //Slow Method
input ENUM_APPLIED_PRICE InpSlowAppliedPrice = PRICE_CLOSE;  //Slow Price

input double InpProfitRatio = 1.5;                          //TP:SL Ratio

input double InpVolume = 0.01;                              //Trade Lots
input string InpTradeComment = "M1 Scalper";                //Comments
input int InpMagic = 2198;                                  //Magic Number

int SkipTrade = -1;

//Indicator Handles 
int HandleFast;
int HandleMid;
int HandleSlow;
int HandleFractal;

//Buffer Array
double IndicatorBuffer[];

#include <Trade/Trade.mqh>
CTrade Trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if (!CheckInputs()) return (INIT_PARAMETERS_INCORRECT);
   
   HandleFast = iMA(Symbol(), PERIOD_CURRENT, InpFastBars,0,InpFastMethod,InpFastAppliedPrice);
   HandleMid = iMA(Symbol(), PERIOD_CURRENT, InpMidBars,0,InpMidMethod,InpMidAppliedPrice);
   HandleSlow = iMA(Symbol(), PERIOD_CURRENT, InpSlowBars,0,InpSlowMethod,InpSlowAppliedPrice);
   HandleFractal = iFractals(Symbol(),PERIOD_CURRENT);
   
   if(HandleFast == INVALID_HANDLE 
   || HandleMid == INVALID_HANDLE 
   || HandleSlow == INVALID_HANDLE
   || HandleFractal == INVALID_HANDLE){
      printf("Faild to create indicator handles");
      return(INIT_FAILED);
   }
   
   ArraySetAsSeries(IndicatorBuffer,true);
   Trade.SetExpertMagicNumber(InpMagic);
   
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(HandleFast);
   IndicatorRelease(HandleMid);
   IndicatorRelease(HandleSlow);
   IndicatorRelease(HandleFractal);
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   
   if (!NewBar()) return;
   
   for (int i = PositionsTotal()-1; i>=0; i--){
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      
      return;
   
   }
   
   //Get values 
   
   int fractalBar = 3;
   int bar = 1;
   
   int copyBars = fractalBar + 1;
   
   if (CopyBuffer(HandleFast,0,0,copyBars,IndicatorBuffer) < copyBars) return;
   double fast = IndicatorBuffer[bar];
   double fastF = IndicatorBuffer[fractalBar];
   
   if (CopyBuffer(HandleMid,0,0,copyBars,IndicatorBuffer) < copyBars) return;
   double mid = IndicatorBuffer[bar];
   double midF = IndicatorBuffer[fractalBar];
   
   if (CopyBuffer(HandleSlow,0,0,copyBars,IndicatorBuffer) < copyBars) return;
   double slow = IndicatorBuffer[bar];
   double slowF = IndicatorBuffer[fractalBar];
   
   if (CopyBuffer(HandleFractal,UPPER_LINE,0,copyBars,IndicatorBuffer) < copyBars) return;
   double fractalHi = IndicatorBuffer[fractalBar];
   
   if (CopyBuffer(HandleFractal,LOWER_LINE,0,copyBars,IndicatorBuffer) < copyBars) return;
   double fractalLo = IndicatorBuffer[fractalBar];
   
   double close = iClose(Symbol(), PERIOD_CURRENT, bar);
   
   double sl = 0;
   
   //Buy
   if (fast > mid && mid > slow){
      if (close < slow){
         SkipTrade = ORDER_TYPE_BUY;
      }
      else if (fastF > midF && midF > slowF){
         if (fractalLo != EMPTY_VALUE && fractalLo > slowF && fractalLo < fastF){
            if (SkipTrade != ORDER_TYPE_BUY){
               sl = (fractalLo < midF) ? slow : mid;
               OpenTrade(ORDER_TYPE_BUY, sl);
            }
            SkipTrade = -1;
            return;
         }
      
      }
   
   }
   
   // Sell
   if (fast < mid && mid < slow){
      if (close > slow){
         SkipTrade = ORDER_TYPE_SELL;
      }
      else if (fastF < midF && midF < slowF){
         if (fractalHi != EMPTY_VALUE && fractalHi < slowF && fractalLo > fastF){
            if (SkipTrade != ORDER_TYPE_SELL){
               sl = (fractalLo > midF) ? slow : mid;
               OpenTrade(ORDER_TYPE_SELL, sl);
            }
            SkipTrade = -1;
            return;
         }
      
      }
   
   }
   
   
   
   
   
  }
//+------------------------------------------------------------------+

bool NewBar(){

   datetime currentTime = iTime(Symbol(), PERIOD_CURRENT, 0);
   static datetime previousTime = 0;
   if (currentTime == previousTime) return(false);
   previousTime = currentTime;
   return(true);
}

bool CheckInputs(){

   bool result = true;
   if (InpFastBars >= InpMidBars || InpMidBars >= InpSlowBars){
      printf("Fast bars must be < Mid bars < Slow bars");
      result = false;
   }
   return (result);
}

void OpenTrade(ENUM_ORDER_TYPE type, double sl){
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                                           : SymbolInfoDouble(Symbol(), SYMBOL_BID);
                                           
   double tp = price + ((price - sl) * InpProfitRatio);
   Trade.PositionOpen(Symbol(), type, InpVolume, price, sl, tp, InpTradeComment);
   
   return;


}