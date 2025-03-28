//+------------------------------------------------------------------+
//| Expert Advisor: Bollinger Bands + ATR + ADX Strategy            |
//| Author: LCS                                             |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters
input int BB_Period = 20;                // Bollinger Bands Period
input double BB_Deviation = 2.0;         // Bollinger Bands Deviation
input int ATR_Period = 14;               // ATR Period
input int ADX_Period = 14;               // ADX Period
input double ATR_Threshold = 0.0008;     // ATR Threshold
input double DI_Plus_Min = 30.0;         // Minimum DI+ for trade
input double DI_Minus_Max = 15.0;        // Maximum DI- for trade
input double ATR_SL_Multiplier = 2.0;    // ATR Multiplier for Stop Loss
input double Risk_Reward_Ratio = 1.5;    // Risk-to-Reward Ratio
input double Risk_Percentage = 2.0;      // Risk per trade (% of balance)
input double Lots_Fixed = 0.1;           // Fixed lot size (if risk % is 0)
input bool Use_Risk_Percentage = true;   // Use risk-based lot sizing
input int ACCOUNT_BALANCE = 10000;       // Amount of initial account

//--- Global Variables
int BB_Handle, ATR_Handle, ADX_Handle;
bool tradePlaced = false;

//+------------------------------------------------------------------+
//| Function: Initialize Indicators (OnInit)                        |
//+------------------------------------------------------------------+
int OnInit()
{
    BB_Handle = iBands(Symbol(), PERIOD_CURRENT, BB_Period, BB_Deviation, 0, PRICE_CLOSE);
    ATR_Handle = iATR(Symbol(), PERIOD_CURRENT, ATR_Period);
    ADX_Handle = iADX(Symbol(), PERIOD_CURRENT, ADX_Period);

    if (BB_Handle == INVALID_HANDLE || ATR_Handle == INVALID_HANDLE || ADX_Handle == INVALID_HANDLE)
    {
        Print("Error creating indicator handles!");
        return INIT_FAILED;
    }

    Print("Indicators initialized successfully.");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Function: Deinitialize Indicators (OnDeinit)                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(BB_Handle);
    IndicatorRelease(ATR_Handle);
    IndicatorRelease(ADX_Handle);
    Print("Indicators released successfully.");
}

//+------------------------------------------------------------------+
//| Function: Get Indicator Values                                  |
//+------------------------------------------------------------------+
void GetIndicators()
{
    int shift = 1; // Last closed candle
    double bands[3], atr[], diPlus[], diMinus[], adx[];

    // Copy Bollinger Bands upper value
    CopyBuffer(BB_Handle, 0, shift, 1, bands); // Middle band
    double middleBand = bands[0];

    CopyBuffer(BB_Handle, 1, shift, 1, bands); // Upper band
    double upperBand = bands[0];

    CopyBuffer(BB_Handle, 2, shift, 1, bands); // Lower band
    double lowerBand = bands[0];

    // Copy ATR value
    CopyBuffer(ATR_Handle, 0, shift, 1, atr);
    double atrValue = atr[0];

    // Copy ADX values
    CopyBuffer(ADX_Handle, 0, shift, 1, adx);
    CopyBuffer(ADX_Handle, 1, shift, 1, diPlus);
    CopyBuffer(ADX_Handle, 2, shift, 1, diMinus);

    double adxValue = adx[0];
    double diPlusValue = diPlus[0];
    double diMinusValue = diMinus[0];

    // Store values globally
    tradePlaced = CheckSellCondition(upperBand, atrValue, diPlusValue, diMinusValue);
}

//+------------------------------------------------------------------+
//| Function: Check Sell Condition                                  |
//+------------------------------------------------------------------+
bool CheckSellCondition(double upperBand, double atrValue, double diPlus, double diMinus)
{
    int shift = 1;
    double closePrice = iClose(Symbol(), PERIOD_CURRENT, shift);

    return (
        closePrice > upperBand &&
        diPlus > DI_Plus_Min &&
        diMinus < DI_Minus_Max &&
        atrValue > ATR_Threshold
    );
}

//+------------------------------------------------------------------+
//| Function: Calculate Lot Size Based on Risk                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_pips)
{
    if (!Use_Risk_Percentage) return Lots_Fixed;

    double risk_amount = ACCOUNT_BALANCE * Risk_Percentage / 100.0;
    double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double lot_size = (risk_amount / (sl_pips * tick_value / tick_size));

    lot_size = NormalizeDouble(lot_size, 2);
    return MathMax(lot_size, 0.01); // Ensure minimum lot size
}

//+------------------------------------------------------------------+
//| Function: Place Sell Trade                                       |
//+------------------------------------------------------------------+
void PlaceSellTrade()
{
    if (tradePlaced) return; // Avoid duplicate trades

    int shift = 1;
    double atrValue, atr[];
    CopyBuffer(ATR_Handle, 0, shift, 1, atr);
    atrValue = atr[0];

    double sl_pips = atrValue * ATR_SL_Multiplier;
    double tp_pips = sl_pips * Risk_Reward_Ratio;
    double lotSize = CalculateLotSize(sl_pips);

    double bidPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double slPrice = NormalizeDouble(bidPrice + sl_pips, _Digits);
    double tpPrice = NormalizeDouble(bidPrice - tp_pips, _Digits);

    if (trade.Sell(lotSize, Symbol(), bidPrice, slPrice, tpPrice, "Sell Signal"))
    {
        tradePlaced = true;
    }
}

//+------------------------------------------------------------------+
//| Function: OnTick Execution                                      |
//+------------------------------------------------------------------+
void OnTick()
{
    static datetime lastTradeTime = 0;

    // Fetch indicator values once per tick
    GetIndicators();

    // Check if a trade should be placed
    if (tradePlaced && lastTradeTime != TimeCurrent())
    {
        PlaceSellTrade();
        lastTradeTime = TimeCurrent();
    }

    // Reset trade flag if no open trades
    if (PositionsTotal() == 0)
        tradePlaced = false;
}
