using System;
using Keel.Core;
using Keel.Nautical;

namespace Keel.Tests
{
    public static class TestNautical
    {
        public static void RunTests()
        {
            Console.WriteLine("[TEST] Running S-57 Nautical Chart and Bathymetry Tests...");

            // Test 1: S-57 Depth Area polygon containment
            S57DepthArea shoal = scope .(0.5, 3.0);
            shoal.AddVertex(.(50.10, -1.10));
            shoal.AddVertex(.(50.10, -1.00));
            shoal.AddVertex(.(50.00, -1.00));
            shoal.AddVertex(.(50.00, -1.10));

            Debug.Assert(shoal.Contains(.(50.05, -1.05)), "Point inside depth area correctly identified");
            Debug.Assert(!shoal.Contains(.(50.20, -1.20)), "Point outside depth area correctly identified");

            // Test 2: Hydrodynamic Squat calculation (Barrass formula)
            double squatOpen = SquatUkcEvaluator.CalculateSquatMeters(16.0, 0.75, .OpenWater);
            // 0.75 * 256 / 100 = 1.92 meters
            Debug.Assert(Math.Abs(squatOpen - 1.92) < 0.05, "Open water squat accurately computed (~1.92m)");

            double squatConfined = SquatUkcEvaluator.CalculateSquatMeters(10.0, 0.80, .ConfinedChannel);
            // 0.80 * 100 / 50 = 1.60 meters
            Debug.Assert(Math.Abs(squatConfined - 1.60) < 0.05, "Confined channel squat accurately computed (~1.60m)");

            // Test 3: Dynamic Under Keel Clearance (UKC)
            double ukc = SquatUkcEvaluator.CalculateUkc(
                12.0, // chart depth
                1.5,  // tide
                9.0,  // static draught
                1.2,  // squat
                0.3,  // heeling
                0.5   // wave margin
            );
            // 13.5 - 11.0 = 2.5 meters
            Debug.Assert(Math.Abs(ukc - 2.5) < 0.05, "UKC calculated accurately (~2.5m)");
            Debug.Assert(SquatUkcEvaluator.IsUkcSafe(ukc, 9.0), "UKC meets 10% safety policy");

            // Test 4: Negative UKC (grounding condition)
            double shallowUkc = SquatUkcEvaluator.CalculateUkc(6.0, 0.0, 7.5, 0.5, 0.0, 0.0);
            Debug.Assert(shallowUkc < 0.0, "Negative UKC correctly identifies seabed collision");

            Console.WriteLine("  -> S-57 Nautical Chart and Bathymetry Tests PASSED.");
        }
    }
}
