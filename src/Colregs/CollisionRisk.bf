using System;
using Keel.Core;

namespace Keel.Colregs
{
    public struct CpaCalculation
    {
        public double CpaDistanceMeters;
        public double CpaDistanceNm;
        public double TcpaSeconds;
        public bool IsConverging;
        public double RelativeSpeedKnots;
        public double BowCrossingRangeNm;
        public double BowCrossingTimeSeconds;
    }

    public struct CollisionRiskAssessment
    {
        public uint32 OwnshipMmsi;
        public uint32 TargetMmsi;
        public EncounterType Encounter;
        public CpaCalculation Cpa;
        public double CollisionRiskIndex; // Range 0.0 (safe) to 1.0 (imminent collision)
        public bool IsRiskOfCollision;
        public String RecommendedAction;

        public void Init()
        {
            RecommendedAction = new String();
        }

        public void Dispose()
        {
            delete RecommendedAction;
        }
    }

    public static class CollisionRiskEvaluator
    {
        // Computes Closest Point of Approach (CPA) and Time to CPA (TCPA).
        public static CpaCalculation ComputeCpa(
            GeoCoordinate ownPos,
            double ownCourseDeg,
            double ownSpeedKnots,
            GeoCoordinate tgtPos,
            double tgtCourseDeg,
            double tgtSpeedKnots)
        {
            CpaCalculation res = default;

            double distMeters = Geodesy.GreatCircleDistanceMeters(ownPos, tgtPos);
            double bearingDeg = Geodesy.InitialBearingDegrees(ownPos, tgtPos);
            double bearingRad = bearingDeg * Geodesy.DEG_TO_RAD;

            // Cartesian relative position (target - ownship) in meters
            double rx = distMeters * Math.Sin(bearingRad);
            double ry = distMeters * Math.Cos(bearingRad);

            // Knots to m/s conversion factor: 1852 / 3600 = 0.514444
            double k = 1852.0 / 3600.0;

            double vox = (ownSpeedKnots * k) * Math.Sin(ownCourseDeg * Geodesy.DEG_TO_RAD);
            double voy = (ownSpeedKnots * k) * Math.Cos(ownCourseDeg * Geodesy.DEG_TO_RAD);

            double vtx = (tgtSpeedKnots * k) * Math.Sin(tgtCourseDeg * Geodesy.DEG_TO_RAD);
            double vty = (tgtSpeedKnots * k) * Math.Cos(tgtCourseDeg * Geodesy.DEG_TO_RAD);

            // Relative velocity (target - ownship) in m/s
            double vrx = vtx - vox;
            double vry = vty - voy;

            double vrSq = (vrx * vrx) + (vry * vry);
            double relSpeedMps = Math.Sqrt(vrSq);
            res.RelativeSpeedKnots = relSpeedMps / k;

            if (vrSq < 1e-6)
            {
                // Parallel courses at identical speeds
                res.CpaDistanceMeters = distMeters;
                res.CpaDistanceNm = distMeters / Geodesy.METERS_PER_NAUTICAL_MILE;
                res.TcpaSeconds = 0.0;
                res.IsConverging = false;
                return res;
            }

            // Time to CPA: tcpa = - (r . vr) / |vr|^2
            double rDotVr = (rx * vrx) + (ry * vry);
            double tcpa = -rDotVr / vrSq;

            res.TcpaSeconds = tcpa;
            res.IsConverging = (tcpa > 0.0);

            // Distance at CPA
            double cpaX = rx + (vrx * tcpa);
            double cpaY = ry + (vry * tcpa);
            double dCpa = Math.Sqrt((cpaX * cpaX) + (cpaY * cpaY));

            res.CpaDistanceMeters = dCpa;
            res.CpaDistanceNm = dCpa / Geodesy.METERS_PER_NAUTICAL_MILE;

            // Bow Crossing Range (BCR) and Bow Crossing Time (BCT)
            // When relative position crosses ownship heading line
            double ownHeadingRad = ownCourseDeg * Geodesy.DEG_TO_RAD;
            double n_x = -Math.Cos(ownHeadingRad);
            double n_y = Math.Sin(ownHeadingRad);

            double vr_dot_n = (vrx * n_x) + (vry * n_y);
            if (Math.Abs(vr_dot_n) > 1e-4)
            {
                double r_dot_n = (rx * n_x) + (ry * n_y);
                double t_bcr = -r_dot_n / vr_dot_n;
                res.BowCrossingTimeSeconds = t_bcr;

                if (t_bcr > 0.0)
                {
                    double bx = rx + (vrx * t_bcr);
                    double by = ry + (vry * t_bcr);
                    // Distance along heading line
                    double bcrMeters = (bx * Math.Sin(ownHeadingRad)) + (by * Math.Cos(ownHeadingRad));
                    res.BowCrossingRangeNm = bcrMeters / Geodesy.METERS_PER_NAUTICAL_MILE;
                }
            }

            return res;
        }

        // Calculates quantitative Collision Risk Index (CRI) in range [0.0, 1.0].
        public static double CalculateCri(
            in CpaCalculation cpa,
            double distanceNm,
            EncounterType encounter,
            double warningCpaNm = 1.5,
            double warningTcpaSec = 900.0)
        {
            if (!cpa.IsConverging || cpa.TcpaSeconds <= 0.0)
                return 0.0;

            // 1. Distance at CPA risk membership
            double u_dcpa = 0.0;
            if (cpa.CpaDistanceNm <= (warningCpaNm * 0.33))
                u_dcpa = 1.0;
            else if (cpa.CpaDistanceNm <= warningCpaNm)
                u_dcpa = 0.5 * (1.0 + Math.Cos(Math.PI_d * (cpa.CpaDistanceNm - (warningCpaNm * 0.33)) / (warningCpaNm * 0.67)));

            // 2. Time to CPA risk membership
            double u_tcpa = 0.0;
            if (cpa.TcpaSeconds <= (warningTcpaSec * 0.33))
                u_tcpa = 1.0;
            else if (cpa.TcpaSeconds <= warningTcpaSec)
                u_tcpa = 0.5 * (1.0 + Math.Cos(Math.PI_d * (cpa.TcpaSeconds - (warningTcpaSec * 0.33)) / (warningTcpaSec * 0.67)));

            // 3. Distance risk membership
            double maxDistNm = 6.0;
            double u_dist = Math.Clamp((maxDistNm - distanceNm) / maxDistNm, 0.0, 1.0);

            // 4. Encounter risk weighting
            double u_enc = 0.5;
            switch (encounter)
            {
                case .CrossingGiveWay: u_enc = 1.0; break;
                case .HeadOn: u_enc = 0.9; break;
                case .CrossingStandOn: u_enc = 0.7; break;
                case .Overtaking: u_enc = 0.6; break;
                default: u_enc = 0.4; break;
            }

            // Weighted multi-attribute synthesis
            double cri = (0.40 * u_dcpa) + (0.35 * u_tcpa) + (0.15 * u_dist) + (0.10 * u_enc);
            return Math.Clamp(cri, 0.0, 1.0);
        }
    }
}
