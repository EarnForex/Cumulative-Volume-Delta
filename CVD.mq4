//+------------------------------------------------------------------+
//|                                                          CVD.mq4 |
//|                                  Copyright © 2025, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2025, EarnForex.com"
#property link      "https://www.earnforex.com/indicators/CVD/"
#property version   "1.00"
#property strict
#property description "Cumulative Volume Delta (CVD) displays buy/sell volume difference accumulated during some period."
#property description "Supports SMA and EMA smoothing."

#property indicator_separate_window
#property indicator_buffers 5
#property indicator_type1  DRAW_HISTOGRAM
#property indicator_type2  DRAW_HISTOGRAM
#property indicator_type3  DRAW_NONE
#property indicator_type4  DRAW_LINE
#property indicator_type5  DRAW_NONE
#property indicator_color1 clrLimeGreen
#property indicator_color2 clrRed
#property indicator_color4 clrDarkGray
#property indicator_width1 2
#property indicator_width2 2
#property indicator_label1 "CVD Positive"
#property indicator_label2 "CVD Negative"
#property indicator_label3 "CVD Raw"
#property indicator_label4 "CVD Smoothed"
#property indicator_label5 "Delta Volume"

// Enumeration for smoothing type.
enum ENUM_MA_METHOD_CUSTOM
{
    MA_NONE = 0, // No Smoothing
    MA_SMA = 1,  // Simple Moving Average
    MA_EMA = 2   // Exponential Moving Average
};

// Input parameters:
input ENUM_TIMEFRAMES DataTimeframe = PERIOD_CURRENT; // Source timeframe for volume data
input int             CumulativePeriod = 20;          // Period for cumulative delta calculation
input ENUM_MA_METHOD_CUSTOM SmoothMethod = MA_NONE;   // Smoothing method
input int             SmoothPeriod = 1;               // Smoothing period

// Indicator buffers:
double CVDPositive[]; // Buffer for positive CVD values.
double CVDNegative[]; // Buffer for negative CVD values.
double CVDRaw[];      // Raw CVD values for calculation.
double CVDSmooth[];   // Smoothed CVD values.
double DeltaVolume[]; // Non-cumulative delta volume buffer.

// Global variables:
ENUM_TIMEFRAMES varDataTimeframe;
double alpha;

int OnInit()
{
    varDataTimeframe = DataTimeframe;
    // Check if selected timeframe is valid.
    if (PeriodSeconds(varDataTimeframe) > PeriodSeconds())
    {
        varDataTimeframe = (ENUM_TIMEFRAMES)Period();
    }

    // Check if cumulative period is valid.
    if (CumulativePeriod < 1)
    {
        Alert("Cumulative period must be at least 1.");
        return INIT_FAILED;
    }

    // Check if smoothing period is valid.
    if (SmoothPeriod < 1 && SmoothMethod != MA_NONE)
    {
        Alert("Smoothing period must be at least 1.");
        return INIT_FAILED;
    }

    // Set indicator properties.
    string smoothStr = (SmoothMethod == MA_SMA) ? "SMA" : (SmoothMethod == MA_EMA) ? "EMA" : "None";
    IndicatorShortName("CVD (" + GetTimeFrameString(varDataTimeframe) + 
                       " | Period: " + IntegerToString(CumulativePeriod) +
                       " | Smooth: " + smoothStr + ")");
    IndicatorSetInteger(INDICATOR_DIGITS, 0);

    // Map indicator buffers.
    SetIndexBuffer(0, CVDPositive);
    SetIndexBuffer(1, CVDNegative);
    SetIndexBuffer(2, CVDRaw);
    SetIndexBuffer(3, CVDSmooth);
    SetIndexBuffer(4, DeltaVolume);

    // Initialize buffers.
    ArraySetAsSeries(CVDPositive, true);
    ArraySetAsSeries(CVDNegative, true);
    ArraySetAsSeries(CVDRaw, true);
    ArraySetAsSeries(CVDSmooth, true);
    ArraySetAsSeries(DeltaVolume, true);

    alpha = 2.0 / (SmoothPeriod + 1.0);

    return INIT_SUCCEEDED;
}

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
    // Check for sufficient data.
    if (rates_total < CumulativePeriod) return 0;

    // Calculate starting position.
    int limit;
    if (prev_calculated == 0)
    {
        limit = rates_total - 1;
    }
    else
    {
        limit = rates_total - prev_calculated + 1;
    }

    // First pass: Calculate non-cumulative delta volume for each bar.
    for (int i = limit; i >= 0; i--)
    {
        // Calculate and store volume delta for current bar.
        DeltaVolume[i] = CalculateVolumeDelta(i);
    }

    // Second pass: Calculate rolling cumulative delta over fixed period.
    for (int i = limit; i >= 0; i--)
    {
        double rollingSumDelta = 0;
        int periodsToSum = MathMin(CumulativePeriod, rates_total - i);
        
        // Sum delta volume for the last N bars (including current bar).
        for (int j = 0; j < periodsToSum; j++)
        {
            rollingSumDelta += DeltaVolume[i + j];
        }

        CVDRaw[i] = rollingSumDelta;
    }

    // Apply smoothing if required.
    if (SmoothPeriod > 1 && SmoothMethod != MA_NONE)
    {
        if (SmoothMethod == MA_SMA)
        {
            // Apply Simple Moving Average.
            for (int i = limit; i >= 0; i--)
            {
                CVDSmooth[i] = CalculateSMA(i, SmoothPeriod, CVDRaw, rates_total);
            }
        }
        else if (SmoothMethod == MA_EMA)
        {
            // Apply Exponential Moving Average.
            CalculateEMA(CVDRaw, CVDSmooth, SmoothPeriod, rates_total, limit);
        }
    }
    else
    {
        // Copy raw values if no smoothing.
        for (int i = limit; i >= 0; i--)
        {
            CVDSmooth[i] = CVDRaw[i];
        }
    }

    // Split values into positive and negative buffers for histogram display.
    for (int i = limit; i >= 0; i--)
    {
        if (CVDSmooth[i] >= 0)
        {
            CVDPositive[i] = CVDSmooth[i];
            CVDNegative[i] = 0;
        }
        else
        {
            CVDPositive[i] = 0;
            CVDNegative[i] = CVDSmooth[i];
        }
    }

    return rates_total;
}

// Calculate volume delta for a specific bar.
double CalculateVolumeDelta(int barIndex)
{
    // Get data from selected timeframe.
    datetime barTime = iTime(Symbol(), Period(), barIndex);

    // Find corresponding bars in lower timeframe.
    int lowerTFBarIndex = iBarShift(Symbol(), varDataTimeframe, barTime, false);

    // Either an error or the fitting bar is too old.
    if (lowerTFBarIndex == -1 || iTime(Symbol(), varDataTimeframe, lowerTFBarIndex) < barTime) return 0;

    double totalDelta = 0;
    datetime currentBarTime = iTime(Symbol(), Period(), barIndex);
    datetime nextBarTime = (barIndex > 0) ? iTime(Symbol(), Period(), barIndex - 1) : TimeCurrent();

    // Accumulate delta from all lower timeframe bars within current bar.
    int lowerBar = lowerTFBarIndex;
    while (lowerBar >= 0)
    {
        datetime lowerBarTime = iTime(Symbol(), varDataTimeframe, lowerBar);

        // Check if still within current bar timeframe.
        if (lowerBarTime >= nextBarTime) break;

        // Get OHLC and volume for lower timeframe bar.
        double ltfHigh = iHigh(Symbol(), varDataTimeframe, lowerBar);
        double ltfLow = iLow(Symbol(), varDataTimeframe, lowerBar);
        double ltfClose = iClose(Symbol(), varDataTimeframe, lowerBar);
        double ltfVolume = (double)iVolume(Symbol(), varDataTimeframe, lowerBar);

        // Calculate delta using price position within range.
        double range = ltfHigh - ltfLow;
        double buyVolume = 0;
        double sellVolume = 0;

        if (range > 0)
        {
            // Estimate buy/sell volume based on close position in range.
            double closePosition = (ltfClose - ltfLow) / range;
            buyVolume = ltfVolume * closePosition;
            sellVolume = ltfVolume * (1 - closePosition);
            totalDelta += (buyVolume - sellVolume);
        }
        //else return 0;

        // Move to next lower timeframe bar.
        lowerBar--;
    }

    return totalDelta;
}

// Calculate Simple Moving Average.
double CalculateSMA(int position, int period, const double &source[], int totalBars)
{
    // Check for period validity and sufficient data .
    if (period <= 0 || position + period > totalBars) return source[position];

    // Calculate SMA.
    double sum = 0;
    int count = 0;

    for (int i = position; i < position + period && i < totalBars; i++)
    {
        sum += source[i];
        count++;
    }

    if (count > 0)
        return sum / count;
    else
        return source[position];
}

// Calculate Exponential Moving Average based on two buffers.
void CalculateEMA(const double &source[], double &target[], int period, int totalBars, int limit)
{
    if (period <= 0) return;

    // Find starting point for EMA calculation.
    int startPos = totalBars - 1;
    
    // Initialize EMA with SMA for the first value.
    if (target[startPos] == 0.0 || limit == totalBars - 1)
    {
        // Calculate initial SMA.
        double sum = 0;
        int count = 0;
        for (int i = startPos; i >= MathMax(startPos - period + 1, 0); i--)
        {
            sum += source[i];
            count++;
        }
        target[startPos] = (count > 0) ? sum / count : source[startPos];
        startPos--;
    }

    // Calculate EMA for remaining bars.
    for (int i = MathMin(startPos, limit); i >= 0; i--)
    {
        if (i < totalBars - 1)
        {
            // EMA formula: (Close - Previous EMA) * multiplier + Previous EMA.
            target[i] = (source[i] - target[i + 1]) * alpha + target[i + 1];
        }
    }
}

string GetTimeFrameString(ENUM_TIMEFRAMES period)
{
   return StringSubstr(EnumToString((ENUM_TIMEFRAMES)period), 7);
}
//+------------------------------------------------------------------+