using System;
using Keel.Core;

namespace Keel.Kinematics
{
    public struct OceanCurrent
    {
        public double SetDirectionDeg; // Direction toward which current flows [0, 360)
        public double DriftKnots;       // Current speed in knots

        public this(double setDeg, double driftKnots)
        {
            this.SetDirectionDeg = setDeg;
            this.DriftKnots = driftKnots;
        }

        public Vector2D ToVectorKnots()
        {
            double rad = SetDirectionDeg * Geodesy.DEG_TO_RAD;
            return .(DriftKnots * Math.Sin(rad), DriftKnots * Math.Cos(rad));
        }
    }

    public struct SurfaceWind
    {
        public double DirectionFromDeg; // Direction from which wind blows [0, 360)
        public double SpeedKnots;

        public this(double dirFromDeg, double speedKnots)
        {
            this.DirectionFromDeg = dirFromDeg;
            this.SpeedKnots = speedKnots;
        }
    }

    public static class DriftCurrentCompensator
    {
        // Computes wind leeway angle in degrees (deviation between heading and course through water).
        public static double CalculateLeewayAngleDeg(
            double shipSpeedKnots,
            double shipHeadingDeg,
            in SurfaceWind wind,
            double leewayCoefficient = 0.035)
        {
            if (shipSpeedKnots < 1.0 || wind.SpeedKnots < 1.0)
                return 0.0;

            // Relative wind angle
            double relWind = wind.DirectionFromDeg - shipHeadingDeg;
            while (relWind > 180.0) relWind -= 360.0;
            while (relWind <= -180.0) relWind += 360.0;

            // Leeway is proportional to (WindSpeed / ShipSpeed) * sin(relative wind)
            double ratio = wind.SpeedKnots / shipSpeedKnots;
            double leewayRad = leewayCoefficient * ratio * Math.Sin(relWind * Geodesy.DEG_TO_RAD);

            return leewayRad * Geodesy.RAD_TO_DEG;
        }

        // Resolves Ground Track (SOG, COG) from Speed Through Water (STW), Heading, Leeway, and Ocean Current.
        public static VelocityVector ComputeGroundTrack(
            double speedThroughWaterKnots,
            double headingDeg,
            double leewayAngleDeg,
            in OceanCurrent current)
        {
            // Course through water
            double ctwDeg = Geodesy.NormalizeDegrees(headingDeg + leewayAngleDeg);
            double ctwRad = ctwDeg * Geodesy.DEG_TO_RAD;

            // Water track velocity components in knots
            double v_water_e = speedThroughWaterKnots * Math.Sin(ctwRad);
            double v_water_n = speedThroughWaterKnots * Math.Cos(ctwRad);

            // Current velocity components in knots
            Vector2D v_curr = current.ToVectorKnots();

            // Ground track velocity vector
            double v_ground_e = v_water_e + v_curr.X;
            double v_ground_n = v_water_n + v_curr.Y;

            double sog = Math.Sqrt((v_ground_e * v_ground_e) + (v_ground_n * v_ground_n));
            double cogRad = Math.Atan2(v_ground_e, v_ground_n);
            double cog = Geodesy.NormalizeDegrees(cogRad * Geodesy.RAD_TO_DEG);

            return .(sog, cog);
        }
    }
}
