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
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }
   
   ArraySetAsSeries(IndicatorBuffer,true);
   Trade.SetExpertMagicNumber(InpMagic);
   
   // Add indicators to the chart
   if(!AddIndicatorsToChart())
      return INIT_FAILED;
   
   // Display past signals
   DisplayPastSignals(500);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove indicators from the chart
   long chart_id = ChartID();
   int subwindow = 0;
   
   ChartIndicatorDelete(chart_id, subwindow, "Moving Average(" + IntegerToString(InpFastBars) + ")");
   ChartIndicatorDelete(chart_id, subwindow, "Moving Average(" + IntegerToString(InpMidBars) + ")");
   ChartIndicatorDelete(chart_id, subwindow, "Moving Average(" + IntegerToString(InpSlowBars) + ")");
   ChartIndicatorDelete(chart_id, subwindow, "Fractals");

   IndicatorRelease(HandleFast);
   IndicatorRelease(HandleMid);
   IndicatorRelease(HandleSlow);
   IndicatorRelease(HandleFractal);
   
   // Remove all objects created by this EA
   ObjectsDeleteAll(0, "Signal_");
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
   
   int bar = 1;
   ENUM_ORDER_TYPE signal = CheckForSignal(bar);
   
   if(signal != WRONG_VALUE)
   {
      double sl = CalculateStopLoss(signal, bar);
      double entry = (signal == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                                                : SymbolInfoDouble(Symbol(), SYMBOL_BID);
      double tp = entry + ((entry - sl) * InpProfitRatio);
      
      OpenTrade(signal, sl, tp);
      DisplaySignal(signal, entry, sl, tp, bar);
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
      Print("Fast bars must be < Mid bars < Slow bars");
      result = false;
   }
   return (result);
}

void OpenTrade(ENUM_ORDER_TYPE type, double sl, double tp){
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                                           : SymbolInfoDouble(Symbol(), SYMBOL_BID);
                                           
   Trade.PositionOpen(Symbol(), type, InpVolume, price, sl, tp, InpTradeComment);
   
   return;
}

bool AddIndicatorsToChart()
{
   long chart_id = ChartID();
   int subwindow = 0; // 0 means the main chart window

   // Add Fast MA
   if(!ChartIndicatorAdd(chart_id, subwindow, iMA(Symbol(), PERIOD_CURRENT, InpFastBars, 0, InpFastMethod, InpFastAppliedPrice)))
   {
      Print("Failed to add Fast MA indicator to chart");
      return false;
   }

   // Add Mid MA
   if(!ChartIndicatorAdd(chart_id, subwindow, iMA(Symbol(), PERIOD_CURRENT, InpMidBars, 0, InpMidMethod, InpMidAppliedPrice)))
   {
      Print("Failed to add Mid MA indicator to chart");
      return false;
   }

   // Add Slow MA
   if(!ChartIndicatorAdd(chart_id, subwindow, iMA(Symbol(), PERIOD_CURRENT, InpSlowBars, 0, InpSlowMethod, InpSlowAppliedPrice)))
   {
      Print("Failed to add Slow MA indicator to chart");
      return false;
   }

   // Add Fractals
   if(!ChartIndicatorAdd(chart_id, subwindow, iFractals(Symbol(), PERIOD_CURRENT)))
   {
      Print("Failed to add Fractals indicator to chart");
      return false;
   }

   return true;
}

ENUM_ORDER_TYPE CheckForSignal(int bar)
{
   double fast[], mid[], slow[], fractalUp[], fractalDown[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(mid, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(fractalUp, true);
   ArraySetAsSeries(fractalDown, true);
   
   CopyBuffer(HandleFast, 0, 0, 4, fast);
   CopyBuffer(HandleMid, 0, 0, 4, mid);
   CopyBuffer(HandleSlow, 0, 0, 4, slow);
   CopyBuffer(HandleFractal, UPPER_LINE, 0, 4, fractalUp);
   CopyBuffer(HandleFractal, LOWER_LINE, 0, 4, fractalDown);
   
   if (fast[bar] > mid[bar] && mid[bar] > slow[bar])
   {
      if (fast[bar+2] > mid[bar+2] && mid[bar+2] > slow[bar+2])
      {
         if (fractalDown[bar+2] != EMPTY_VALUE && fractalDown[bar+2] > slow[bar+2] && fractalDown[bar+2] < fast[bar+2])
         {
            return ORDER_TYPE_BUY;
         }
      }
   }
   
   if (fast[bar] < mid[bar] && mid[bar] < slow[bar])
   {
      if (fast[bar+2] < mid[bar+2] && mid[bar+2] < slow[bar+2])
      {
         if (fractalUp[bar+2] != EMPTY_VALUE && fractalUp[bar+2] < slow[bar+2] && fractalUp[bar+2] > fast[bar+2])
         {
            return ORDER_TYPE_SELL;
         }
      }
   }
   
   return WRONG_VALUE;
}

double CalculateStopLoss(ENUM_ORDER_TYPE type, int bar)
{
   double fast[], mid[], slow[], fractalUp[], fractalDown[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(mid, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(fractalUp, true);
   ArraySetAsSeries(fractalDown, true);
   
   CopyBuffer(HandleFast, 0, 0, 4, fast);
   CopyBuffer(HandleMid, 0, 0, 4, mid);
   CopyBuffer(HandleSlow, 0, 0, 4, slow);
   CopyBuffer(HandleFractal, UPPER_LINE, 0, 4, fractalUp);
   CopyBuffer(HandleFractal, LOWER_LINE, 0, 4, fractalDown);
   
   if (type == ORDER_TYPE_BUY)
   {
      return (fractalDown[bar+2] < mid[bar+2]) ? slow[bar] : mid[bar];
   }
   else if (type == ORDER_TYPE_SELL)
   {
      return (fractalUp[bar+2] > mid[bar+2]) ? slow[bar] : mid[bar];
   }
   
   return 0;
}

void DisplaySignal(ENUM_ORDER_TYPE type, double entry, double sl, double tp, int bar)
{
   string prefix = "Signal_" + IntegerToString(bar) + "_";
   color signalColor = (type == ORDER_TYPE_BUY) ? clrBlue : clrRed;
   ENUM_OBJECT arrow = (type == ORDER_TYPE_BUY) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL;
   
   datetime time = iTime(Symbol(), PERIOD_CURRENT, bar);
   
   // Entry arrow
   ObjectCreate(0, prefix + "Entry", arrow, 0, time, entry);
   ObjectSetInteger(0, prefix + "Entry", OBJPROP_COLOR, signalColor);
   
   // Stop Loss line
   ObjectCreate(0, prefix + "SL", OBJ_TREND, 0, time, sl, time + PeriodSeconds()*10, sl);
   ObjectSetInteger(0, prefix + "SL", OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, prefix + "SL", OBJPROP_STYLE, STYLE_DOT);
   
   // Take Profit line
   ObjectCreate(0, prefix + "TP", OBJ_TREND, 0, time, tp, time + PeriodSeconds()*10, tp);
   ObjectSetInteger(0, prefix + "TP", OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, prefix + "TP", OBJPROP_STYLE, STYLE_DOT);
}

void DisplayPastSignals(int bars)
{
   for(int i = bars; i > 0; i--)
   {
      ENUM_ORDER_TYPE signal = CheckForSignal(i);
      if(signal != WRONG_VALUE)
      {
         double sl = CalculateStopLoss(signal, i);
         double entry = (signal == ORDER_TYPE_BUY) ? iHigh(Symbol(), PERIOD_CURRENT, i-1)
                                                   : iLow(Symbol(), PERIOD_CURRENT, i-1);
         double tp = entry + ((entry - sl) * InpProfitRatio);
         
         DisplaySignal(signal, entry, sl, tp, i);
      }
   }
}