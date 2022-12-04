using System;
using Keel.Core;

namespace Keel.Colregs
{
    public struct ManeuverRecommendation
    {
        public double SuggestedCourseDeg;
        public double SuggestedSpeedKnots;
        public double ProjectedCpaNm;
        public double CourseAlterationDeg;   // Positive = starboard turn, Negative = port turn
        public bool RequiresImmediateAction;
        public String Rationale;

        public void Init()
        {
            Rationale = new String();
        }

        public void Dispose()
        {
            delete Rationale;
        }
    }

    public static class ManeuverPlanner
    {
        // Plans a COLREGs-compliant maneuver for give-way vessel to achieve target CPA.
        public static bool PlanEvasiveManeuver(
            GeoCoordinate ownPos,
            double ownCourseDeg,
            double ownSpeedKnots,
            GeoCoordinate tgtPos,
            double tgtCourseDeg,
            double tgtSpeedKnots,
            EncounterType encounter,
            double targetSafeCpaNm,
            ref ManeuverRecommendation outRec)
        {
            outRec.SuggestedCourseDeg = ownCourseDeg;
            outRec.SuggestedSpeedKnots = ownSpeedKnots;
            outRec.CourseAlterationDeg = 0.0;
            outRec.RequiresImmediateAction = false;

            if (encounter == .None || encounter == .CrossingStandOn)
            {
                outRec.Rationale.Set("Rule 17: Stand-on vessel; maintain course and speed; monitor target.");
                return false;
            }

            // Test starboard alterations in 5-degree increments up to 60 degrees (COLREGs Rule 8: large and readily apparent)
            for (double delta = 15.0; delta <= 60.0; delta += 5.0)
            {
                double candidateCourse = Geodesy.NormalizeDegrees(ownCourseDeg + delta);
                var cpa = CollisionRiskEvaluator.ComputeCpa(
                    ownPos, candidateCourse, ownSpeedKnots,
                    tgtPos, tgtCourseDeg, tgtSpeedKnots
                );

                if (cpa.CpaDistanceNm >= targetSafeCpaNm || !cpa.IsConverging)
                {
                    outRec.SuggestedCourseDeg = candidateCourse;
                    outRec.CourseAlterationDeg = delta;
                    outRec.ProjectedCpaNm = cpa.CpaDistanceNm;
                    outRec.RequiresImmediateAction = true;

                    if (encounter == .HeadOn)
                    {
                        outRec.Rationale.Set("Rule 14: Alter course to starboard by ");
                        outRec.Rationale.AppendF("{0:0} deg to pass port-to-port.", delta);
                    }
                    else if (encounter == .CrossingGiveWay)
                    {
                        outRec.Rationale.Set("Rule 16: Give-way vessel; alter course to starboard by ");
                        outRec.Rationale.AppendF("{0:0} deg to pass under target stern.", delta);
                    }
                    else if (encounter == .Overtaking)
                    {
                        outRec.Rationale.Set("Rule 13: Overtaking vessel; alter course to starboard by ");
                        outRec.Rationale.AppendF("{0:0} deg to keep well clear.", delta);
                    }
                    return true;
                }
            }

            // If course alteration alone is insufficient, test speed reduction
            double reducedSpeed = ownSpeedKnots * 0.5;
            var speedCpa = CollisionRiskEvaluator.ComputeCpa(
                ownPos, ownCourseDeg, reducedSpeed,
                tgtPos, tgtCourseDeg, tgtSpeedKnots
            );

            outRec.SuggestedSpeedKnots = reducedSpeed;
            outRec.ProjectedCpaNm = speedCpa.CpaDistanceNm;
            outRec.RequiresImmediateAction = true;
            outRec.Rationale.Set("Rule 8: Reduce speed substantially to 50% to allow target vessel to pass ahead.");
            return true;
        }
    }
}
