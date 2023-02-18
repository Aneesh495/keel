using System;
using Keel.Core;
using Keel.Vts;
using Keel.Colregs;

namespace Keel.Tests
{
    public static class TestVts
    {
        public static void RunTests()
        {
            Console.WriteLine("[TEST] Running VTS Track Registry and Alert Dispatcher Tests...");

            TrackRegistry registry = scope .();

            // Test 1: Track creation and confirmation
            TrackRecord track1 = registry.GetOrCreateTrack(244670001);
            track1.UpdateDynamicState(.(50.0, 0.0), 12.0, 90.0, 90.0, 0.0, .UnderWayUsingEngine, 1000);
            Debug.Assert(!track1.IsConfirmed, "First report does not confirm track");

            track1.UpdateDynamicState(.(50.0, 0.01), 12.0, 90.0, 90.0, 0.0, .UnderWayUsingEngine, 1010);
            Debug.Assert(track1.IsConfirmed, "Second report confirms track");
            Debug.Assert(registry.TrackCount == 1, "Track count is 1");

            // Test 2: Dead reckoning
            registry.DeadReckonTracks(1070); // 60s elapsed
            Debug.Assert(track1.Position.Longitude > 0.01, "Dead reckoning advances vessel position along course");

            // Test 3: Alert Dispatcher
            AlertDispatcher dispatcher = scope .();
            CpaCalculation cpa = default;
            cpa.CpaDistanceNm = 0.4;
            cpa.TcpaSeconds = 300.0;
            cpa.IsConverging = true;

            dispatcher.DispatchCollisionAlert(244670001, 244670002, .(50.0, 0.0), cpa, .CrossingGiveWay, 0.85, 1070);
            Debug.Assert(dispatcher.AlertCount == 1, "One collision alert dispatched");
            Debug.Assert(dispatcher.ActiveAlerts[0].Severity == .EmergencyAlarm, "High CRI triggers emergency alarm");

            // Test 4: SART Distress Alert
            dispatcher.DispatchSartDistress(970123456, .(50.1, 0.2), 1070);
            Debug.Assert(dispatcher.AlertCount == 2, "SART alert successfully dispatched");

            // Test 5: Track aging and purging
            int purged = registry.PurgeAgedTracks(2000, 500); // 930s elapsed > 500s threshold
            Debug.Assert(purged == 1, "Aged track successfully purged");
            Debug.Assert(registry.TrackCount == 0, "Track count reduced to 0");

            Console.WriteLine("  -> VTS Track Registry and Alert Dispatcher Tests PASSED.");
        }
    }
}
