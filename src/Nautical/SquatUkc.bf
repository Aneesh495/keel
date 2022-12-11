using System;
using Keel.Core;

namespace Keel.Nautical
{
    public enum WaterwayType
    {
        OpenWater = 0,      // Unrestricted deep water (depth / draught > 2.0)
        ShallowWater = 1,   // Shallow water (1.2 < depth / draught <= 2.0)
        ConfinedChannel = 2 // Narrow fairway / canal with banks
    }

    public static class SquatUkcEvaluator
    {
        // Approximates vessel block coefficient C_b based on ship type.
        public static double EstimateBlockCoefficient(ShipType type)
        {
            switch (type)
            {
                case .Tanker: return 0.85;
                case .Cargo: return 0.75;
                case .Passenger: return 0.60;
                case .HighSpeedCraft: return 0.45;
                case .Tug: return 0.55;
                default: return 0.70;
            }
        }

        // Calculates hydrodynamic squat sinkage in meters using the Barrass formula.
        public static double CalculateSquatMeters(
            double speedKnots,
            double blockCoefficient,
            WaterwayType waterway)
        {
            if (speedKnots <= 0.5)
                return 0.0;

            double vSq = speedKnots * speedKnots;

            switch (waterway)
            {
                case .OpenWater:
                    // Open water squat: Delta_T = C_b * V^2 / 100
                    return (blockCoefficient * vSq) / 100.0;

                case .ShallowWater:
                    // Shallow open water squat: Delta_T = C_b * V^2 / 75
                    return (blockCoefficient * vSq) / 75.0;

                case .ConfinedChannel:
                    // Confined channel / canal squat: Delta_T = C_b * V^2 / 50
                    return (blockCoefficient * vSq) / 50.0;

                default:
                    return (blockCoefficient * vSq) / 100.0;
            }
        }

        // Calculates additional draught increase due to vessel heel angle (e.g. during tight rudder turn or wind heeling).
        public static double CalculateHeelingAllowanceMeters(double beamMeters, double heelAngleDeg)
        {
            if (heelAngleDeg <= 0.0)
                return 0.0;
            double rad = heelAngleDeg * Geodesy.DEG_TO_RAD;
            return (beamMeters * 0.5) * Math.Sin(rad);
        }

        // Evaluates Under Keel Clearance (UKC) in meters.
        // Returns negative UKC if vessel is predicted to strike seabed (grounding).
        public static double CalculateUkc(
            double chartSoundingDepthMeters,
            double tideElevationMeters,
            double staticDraughtMeters,
            double squatMeters,
            double heelingAllowanceMeters,
            double wavePitchMarginMeters = 0.5)
        {
            double availableWaterDepth = chartSoundingDepthMeters + tideElevationMeters;
            double totalDynamicDraught = staticDraughtMeters + squatMeters + heelingAllowanceMeters + wavePitchMarginMeters;
            return availableWaterDepth - totalDynamicDraught;
        }

        // Verifies whether UKC complies with port safety policy (e.g. minimum 10% of draught or 1.5m).
        public static bool IsUkcSafe(
            double ukcMeters,
            double staticDraughtMeters,
            double policySafetyMarginRatio = 0.10,
            double minAbsoluteMarginMeters = 1.0)
        {
            double requiredMargin = Math.Max(minAbsoluteMarginMeters, staticDraughtMeters * policySafetyMarginRatio);
            return ukcMeters >= requiredMargin;
        }
    }
}
