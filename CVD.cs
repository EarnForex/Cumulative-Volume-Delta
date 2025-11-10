// -------------------------------------------------------------------------------
//   Cumulative Volume Delta (CVD) displays buy/sell volume difference accumulated during some period.
//   Supports SMA and EMA smoothing.
//   
//   Version 1.00
//   Copyright 2025, EarnForex.com
//   https://www.earnforex.com/indicators/CVD/
// -------------------------------------------------------------------------------

using System;
using cAlgo.API;

namespace cAlgo
{
    [Indicator(IsOverlay = false, AccessRights = AccessRights.None)]
    public class CVD : Indicator
    {
        // Enumeration for smoothing type.
        public enum SmoothingMethod
        {
            None, // No Smoothing
            SMA,  // Simple Moving Average
            EMA   // Exponential Moving Average
        }

        // Input parameters.
        [Parameter("Source Timeframe", DefaultValue = "Current")]
        public TimeFrame DataTimeframe { get; set; }

        [Parameter("Cumulative Period", DefaultValue = 20, MinValue = 1)]
        public int CumulativePeriod { get; set; }

        [Parameter("Smoothing Method", DefaultValue = SmoothingMethod.None)]
        public SmoothingMethod SmoothMethod { get; set; }

        [Parameter("Smoothing Period", DefaultValue = 1, MinValue = 1)]
        public int SmoothPeriod { get; set; }

        // Output buffers.
        [Output("CVD Positive", LineColor = "LimeGreen", PlotType = PlotType.Histogram, Thickness = 2)]
        public IndicatorDataSeries CVDPositive { get; set; }

        [Output("CVD Negative", LineColor = "Red", PlotType = PlotType.Histogram, Thickness = 2)]
        public IndicatorDataSeries CVDNegative { get; set; }

        [Output("CVD Smoothed", LineColor = "DarkGray", PlotType = PlotType.Line, LineStyle = LineStyle.Dots)]
        public IndicatorDataSeries CVDSmooth { get; set; }

        // Internal data series.
        private IndicatorDataSeries CVDRaw;
        private IndicatorDataSeries DeltaVolume;
        
        // Multi-timeframe bars.
        private Bars lowerTFBars;
        
        // EMA multiplier.
        private double alpha;

        protected override void Initialize()
        {
            // Initialize internal data series.
            CVDRaw = CreateDataSeries();
            DeltaVolume = CreateDataSeries();

            // Get lower timeframe bars.
            if (DataTimeframe.Name == "Current")
            {
                lowerTFBars = Bars;
            }
            else
            {
                lowerTFBars = MarketData.GetBars(DataTimeframe);
            }

            // Check if selected timeframe is valid.
            if (lowerTFBars.TimeFrame > Bars.TimeFrame)
            {
                Print("Warning: Data timeframe should be equal to or lower than the current chart timeframe. Using current timeframe.");
                lowerTFBars = Bars;
            }

            // Calculate EMA multiplier.
            alpha = 2.0 / (SmoothPeriod + 1.0);
        }

        public override void Calculate(int index)
        {
            // Check for sufficient data.
            if (index < CumulativePeriod)
            {
                CVDPositive[index] = 0;
                CVDNegative[index] = 0;
                CVDSmooth[index] = 0;
                return;
            }

            // Calculate non-cumulative delta volume for current bar.
            DeltaVolume[index] = CalculateVolumeDelta(index);

            // Calculate rolling cumulative delta over fixed period.
            double rollingSumDelta = 0;
            int periodsToSum = Math.Min(CumulativePeriod, index + 1);
            
            // Sum delta volume for the last N bars (including current bar).
            for (int j = 0; j < periodsToSum; j++)
            {
                rollingSumDelta += DeltaVolume[index - j];
            }
            
            CVDRaw[index] = rollingSumDelta;

            // Apply smoothing.
            ApplySmoothing(index);

            // Split values into positive and negative buffers for histogram display.
            if (CVDSmooth[index] >= 0)
            {
                CVDPositive[index] = CVDSmooth[index];
                CVDNegative[index] = 0;
            }
            else
            {
                CVDPositive[index] = 0;
                CVDNegative[index] = CVDSmooth[index];
            }
        }

        private double CalculateVolumeDelta(int barIndex)
        {
            // Get current bar time.
            DateTime barTime = Bars.OpenTimes[barIndex];
            DateTime nextBarTime = Bars.OpenTimes[barIndex + 1]; // A newer bar.
            if (IsLastBar) nextBarTime = DateTime.Now; // No newer bar.

            // Find corresponding bars in lower timeframe.
            int lowerTFStartIndex = lowerTFBars.OpenTimes.GetIndexByTime(barTime);
            if (lowerTFStartIndex < 0 || lowerTFBars.OpenTimes[lowerTFStartIndex] < barTime)
                return 0;

            double totalDelta = 0;
            // Accumulate delta from all lower timeframe bars within current bar.
            for (int i = lowerTFStartIndex; i < lowerTFBars.Count; i++)
            {
                // Check if still within current bar timeframe.
                if (lowerTFBars.OpenTimes[i] >= nextBarTime)
                    break;

                // Get OHLC and volume for lower timeframe bar.
                double ltfHigh = lowerTFBars.HighPrices[i];
                double ltfLow = lowerTFBars.LowPrices[i];
                double ltfClose = lowerTFBars.ClosePrices[i];
                double ltfVolume = lowerTFBars.TickVolumes[i];

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
            }

            return totalDelta;
        }

        private void ApplySmoothing(int index)
        {
            if (SmoothPeriod <= 1 || SmoothMethod == SmoothingMethod.None)
            {
                CVDSmooth[index] = CVDRaw[index];
            }
            else if (SmoothMethod == SmoothingMethod.SMA)
            {
                CVDSmooth[index] = CalculateSMA(index, SmoothPeriod, CVDRaw);
            }
            else if (SmoothMethod == SmoothingMethod.EMA)
            {
                CVDSmooth[index] = CalculateEMA(index, SmoothPeriod, CVDRaw);
            }
        }

        private double CalculateSMA(int index, int period, IndicatorDataSeries source)
        {
            if (period <= 0 || index < period - 1)
            {
                return source[index];
            }
            double sum = 0;
            int count = 0;

            for (int i = 0; i < period && index - i >= 0; i++)
            {
                sum += source[index - i];
                count++;
            }

            return count > 0 ? sum / count : source[index];
        }

        private double CalculateEMA(int index, int period, IndicatorDataSeries source)
        {
            if (period <= 0)
            {
                return source[index];
            }
            // Initialize with SMA for the first value.
            if (index < period)
            {
                return CalculateSMA(index, index + 1, source);
            }
            
            // For the first complete period, use SMA.
            if (index == period - 1 || double.IsNaN(CVDSmooth[index - 1]))
            {
                return CalculateSMA(index, period, source);
            }

            // EMA formula: (Current - Previous EMA) * multiplier + Previous EMA.
            return (source[index] - CVDSmooth[index - 1]) * alpha + CVDSmooth[index - 1];
        }
    }
}