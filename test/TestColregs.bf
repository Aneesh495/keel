using System;
using Keel.Core;
using Keel.Colregs;

namespace Keel.Tests
{
    public static class TestColregs
    {
        public static void RunTests()
        {
            Console.WriteLine("[TEST] Running COLREGs 72 Collision Avoidance Tests...");

            // Test 1: Head-on situation (Rule 14)
            // Ownship heading 000 deg (North), Target heading 180 deg (South)
            GeoCoordinate p1 = .(50.0, 0.0);
            GeoCoordinate p2 = Geodesy.ProjectGeodesic(p1, 5.0 * 1852.0, 0.0);

            var geomHeadOn = EncounterClassifier.ComputeGeometry(p1, 0.0, 15.0, p2, 180.0, 15.0);
            var encHeadOn = EncounterClassifier.Classify(geomHeadOn, 15.0, 15.0, .UnderWayUsingEngine, .UnderWayUsingEngine);
            Debug.Assert(encHeadOn == .HeadOn, "Rule 14 Head-on correctly classified");

            var cpaHeadOn = CollisionRiskEvaluator.ComputeCpa(p1, 0.0, 15.0, p2, 180.0, 15.0);
            Debug.Assert(cpaHeadOn.IsConverging, "Head-on vessels are converging");
            Debug.Assert(cpaHeadOn.CpaDistanceNm < 0.05, "Head-on collision trajectory has zero CPA");
            Debug.Assert(Math.Abs(cpaHeadOn.TcpaSeconds - 600.0) < 15.0, "TCPA is approx 600 seconds");

            // Test 2: Crossing situation (Rule 15 Give-Way)
            // Ownship heading North, Target 2 NM to starboard heading West
            GeoCoordinate pStarboard = Geodesy.ProjectGeodesic(p1, 2.0 * 1852.0, 90.0);
            var geomCrossing = EncounterClassifier.ComputeGeometry(p1, 0.0, 12.0, pStarboard, 270.0, 12.0);
            var encCrossing = EncounterClassifier.Classify(geomCrossing, 12.0, 12.0, .UnderWayUsingEngine, .UnderWayUsingEngine);
            Debug.Assert(encCrossing == .CrossingGiveWay, "Rule 15 Crossing Give-Way correctly classified");

            var cpaCrossing = CollisionRiskEvaluator.ComputeCpa(p1, 0.0, 12.0, pStarboard, 270.0, 12.0);
            Debug.Assert(cpaCrossing.IsConverging, "Crossing vessels are converging");
            double criCrossing = CollisionRiskEvaluator.CalculateCri(cpaCrossing, 2.0, encCrossing);
            Debug.Assert(criCrossing > 0.5, "Collision Risk Index is elevated for 2 NM crossing situation");

            // Test 3: Overtaking situation (Rule 13)
            // Ownship at 18 kts approaching target at 10 kts from 140 deg abaft beam
            GeoCoordinate pAhead = Geodesy.ProjectGeodesic(p1, 1.5 * 1852.0, 0.0);
            var geomOvertaking = EncounterClassifier.ComputeGeometry(p1, 0.0, 18.0, pAhead, 0.0, 10.0);
            var encOvertaking = EncounterClassifier.Classify(geomOvertaking, 18.0, 10.0, .UnderWayUsingEngine, .UnderWayUsingEngine);
            Debug.Assert(encOvertaking == .Overtaking, "Rule 13 Overtaking correctly classified");

            // Test 4: Autonomous maneuver planning
            ManeuverRecommendation rec = default;
            rec.Init();
            bool planned = ManeuverPlanner.PlanEvasiveManeuver(
                p1, 0.0, 12.0,
                pStarboard, 270.0, 12.0,
                .CrossingGiveWay, 1.5, ref rec
            );
            Debug.Assert(planned, "Maneuver successfully planned");
            Debug.Assert(rec.CourseAlterationDeg > 0.0, "Maneuver recommends starboard turn");
            Debug.Assert(rec.ProjectedCpaNm >= 1.5, "Projected CPA meets safety threshold");
            rec.Dispose();

            Console.WriteLine("  -> COLREGs 72 Collision Avoidance Tests PASSED.");
        }
    }
}
