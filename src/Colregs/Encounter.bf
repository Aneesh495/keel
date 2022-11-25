using System;
using Keel.Core;

namespace Keel.Colregs
{
    // Encounter types according to IMO COLREGs 1972 Rules 13-18.
    public enum EncounterType
    {
        None = 0,
        Overtaking = 1,              // Rule 13: Overtaking (Give-way)
        HeadOn = 2,                  // Rule 14: Head-on situation (Both alter to starboard)
        CrossingGiveWay = 3,         // Rule 15: Crossing give-way (Target on starboard)
        CrossingStandOn = 4,         // Rule 15: Crossing stand-on (Target on port)
        PriorityResponsibility = 5   // Rule 18: Priority hierarchy (NUC, RAM, CBD, Fishing, Sailing)
    }

    public struct EncounterGeometry
    {
        public double TargetBearingDeg;       // True bearing from ownship to target [0, 360)
        public double TargetRelativeBearing;  // Bearing relative to ownship heading [-180, +180)
        public double TargetAspectDeg;        // Ownship bearing relative to target heading [0, 360)
        public double CourseDifferenceDeg;    // Angular difference between courses [0, 180]
        public double DistanceMeters;
        public double RelativeSpeedKnots;

        public bool IsTargetOnStarboard => TargetRelativeBearing > 0.0 && TargetRelativeBearing < 180.0;
        public bool IsTargetOnPort => TargetRelativeBearing < 0.0 && TargetRelativeBearing > -180.0;
        public bool IsTargetAbaftBeam => Math.Abs(TargetRelativeBearing) > 112.5;
    }

    public static class EncounterClassifier
    {
        // Computes relative geometry between ownship and target.
        public static EncounterGeometry ComputeGeometry(
            GeoCoordinate ownPos,
            double ownCourseDeg,
            double ownSpeedKnots,
            GeoCoordinate tgtPos,
            double tgtCourseDeg,
            double tgtSpeedKnots)
        {
            EncounterGeometry geom = default;
            geom.DistanceMeters = Geodesy.GreatCircleDistanceMeters(ownPos, tgtPos);
            geom.TargetBearingDeg = Geodesy.InitialBearingDegrees(ownPos, tgtPos);

            // Relative bearing [-180, +180)
            double relBrng = geom.TargetBearingDeg - ownCourseDeg;
            while (relBrng > 180.0) relBrng -= 360.0;
            while (relBrng <= -180.0) relBrng += 360.0;
            geom.TargetRelativeBearing = relBrng;

            // Target aspect angle
            double reciprocalBrng = Geodesy.NormalizeDegrees(geom.TargetBearingDeg + 180.0);
            double aspect = reciprocalBrng - tgtCourseDeg;
            while (aspect < 0.0) aspect += 360.0;
            while (aspect >= 360.0) aspect -= 360.0;
            geom.TargetAspectDeg = aspect;

            // Course difference
            double diff = Math.Abs(ownCourseDeg - tgtCourseDeg);
            if (diff > 180.0) diff = 360.0 - diff;
            geom.CourseDifferenceDeg = diff;

            // Relative speed
            double v_own_x = ownSpeedKnots * Math.Sin(ownCourseDeg * Geodesy.DEG_TO_RAD);
            double v_own_y = ownSpeedKnots * Math.Cos(ownCourseDeg * Geodesy.DEG_TO_RAD);
            double v_tgt_x = tgtSpeedKnots * Math.Sin(tgtCourseDeg * Geodesy.DEG_TO_RAD);
            double v_tgt_y = tgtSpeedKnots * Math.Cos(tgtCourseDeg * Geodesy.DEG_TO_RAD);
            double vrx = v_tgt_x - v_own_x;
            double vry = v_tgt_y - v_own_y;
            geom.RelativeSpeedKnots = Math.Sqrt((vrx * vrx) + (vry * vry));

            return geom;
        }

        // Evaluates Rule 18 vessel priority hierarchy.
        // Returns true if rule 18 applies (one vessel has higher priority).
        public static bool CheckRule18Priority(
            NavigationalStatus ownStatus,
            NavigationalStatus tgtStatus,
            out bool ownshipIsGiveWay)
        {
            ownshipIsGiveWay = false;

            int PriorityScore(NavigationalStatus s)
            {
                switch (s)
                {
                    case .NotUnderCommand: return 6;
                    case .RestrictedManoeuverability: return 5;
                    case .ConstrainedByDraught: return 4;
                    case .EngagedInFishing: return 3;
                    case .UnderWaySailing: return 2;
                    default: return 1; // Power-driven vessel
                }
            }

            int ownScore = PriorityScore(ownStatus);
            int tgtScore = PriorityScore(tgtStatus);

            if (ownScore != tgtScore)
            {
                ownshipIsGiveWay = (ownScore < tgtScore);
                return true;
            }
            return false;
        }

        // Classifies encounter situation according to COLREGs Rules 13, 14, 15, and 18.
        public static EncounterType Classify(
            in EncounterGeometry geom,
            double ownSpeedKnots,
            double tgtSpeedKnots,
            NavigationalStatus ownStatus,
            NavigationalStatus tgtStatus)
        {
            // Rule 18 takes precedence if one vessel has restricted maneuverability
            if (CheckRule18Priority(ownStatus, tgtStatus, let ownGiveWay))
            {
                return ownGiveWay ? .CrossingGiveWay : .CrossingStandOn;
            }

            // Rule 13: Overtaking
            // Any vessel coming up with another vessel from a direction more than 22.5 deg abaft her beam
            // That is, target aspect angle is between 112.5 deg and 247.5 deg
            if (geom.TargetAspectDeg > 112.5 && geom.TargetAspectDeg < 247.5)
            {
                if (ownSpeedKnots > tgtSpeedKnots)
                {
                    return .Overtaking; // Ownship is overtaking target
                }
            }
            else if (Math.Abs(geom.TargetRelativeBearing) > 112.5 && tgtSpeedKnots > ownSpeedKnots)
            {
                return .None; // Target is overtaking ownship; target is give-way
            }

            // Rule 14: Head-on situation
            // When two power-driven vessels are meeting on reciprocal or nearly reciprocal courses so as to involve risk of collision
            if (geom.CourseDifferenceDeg > 165.0 && Math.Abs(geom.TargetRelativeBearing) < 15.0)
            {
                return .HeadOn;
            }

            // Rule 15: Crossing situation
            // When two power-driven vessels are crossing so as to involve risk of collision
            if (geom.IsTargetOnStarboard && !geom.IsTargetAbaftBeam)
            {
                // Target is on starboard side: ownship shall keep out of the way
                return .CrossingGiveWay;
            }
            else if (geom.IsTargetOnPort && !geom.IsTargetAbaftBeam)
            {
                // Target is on port side: ownship shall keep course and speed
                return .CrossingStandOn;
            }

            return .None;
        }
    }
}
