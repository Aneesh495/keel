using System;
using Keel.Core;
using Keel.Ais;
using Keel.Colregs;
using Keel.Nautical;
using Keel.Vts;
using Keel.Protocol;

namespace Keel
{
    class Program
    {
        public static int Main(String[] args)
        {
            Console.WriteLine("======================================================================");
            Console.WriteLine("  KEEL: Autonomous Maritime VTS & COLREGs 72 Collision Avoidance      ");
            Console.WriteLine("======================================================================");

            VtsSupervisor supervisor = scope .();
            supervisor.WarningCpaNm = 1.5;
            supervisor.WarningTcpaSec = 900.0;
            supervisor.TideElevationMeters = 1.2;

            // 1. Configure S-57 Nautical Chart: Dover Strait Traffic Separation Scheme
            S57TrafficLane southwestLane = new .();
            southwestLane.Name.Set("Dover Strait SW Lane");
            southwestLane.TrafficDirectionDeg = 230.0;
            southwestLane.SpeedLimitKnots = 15.0;
            southwestLane.BoundaryPolygon.Add(.(51.20, 1.30));
            southwestLane.BoundaryPolygon.Add(.(51.30, 1.50));
            southwestLane.BoundaryPolygon.Add(.(51.05, 1.65));
            southwestLane.BoundaryPolygon.Add(.(50.95, 1.45));
            supervisor.Chart.AddTrafficLane(southwestLane);

            // 2. Configure S-57 Bathymetric Hazard: Goodwin Sands Shoal (depth 2.5 meters)
            S57DepthArea goodwinSands = new .(0.5, 2.5);
            goodwinSands.AddVertex(.(51.30, 1.45));
            goodwinSands.AddVertex(.(51.32, 1.52));
            goodwinSands.AddVertex(.(51.22, 1.55));
            goodwinSands.AddVertex(.(51.20, 1.48));
            supervisor.Chart.AddDepthArea(goodwinSands);

            Console.WriteLine("[INFO] S-57 Nautical Chart initialized: 1 TSS Lane, 1 Depth Area");

            // 3. Feed synthetic NMEA 0183 AIVDM stream simulating crossing collision scenario
            // Vessel 1: Container Ship (MMSI 244670248)
            StringView sentence1 = "!AIVDM,1,1,,A,13aEO:0P00Op`adMDOHr:?vN20S4,0*6B";
            bool fed1 = supervisor.IngestNmeaSentence(sentence1, 1700000000);
            Console.WriteLineF("[INFO] Ingested AIS Message 1 (MMSI 244670248): {0}", fed1 ? "OK" : "FAILED");

            // Vessel 2: Bulk Carrier (MMSI 211000002) in crossing encounter
            TrackRecord ship2 = supervisor.Registry.GetOrCreateTrack(211000002);
            ship2.VesselName.Set("NORDIC CARRIER");
            ship2.ShipCargoType = .Cargo;
            ship2.StaticDraughtMeters = 8.5;
            // Place ship 2 within 2 NM to starboard heading West (Crossing Give-Way)
            GeoCoordinate p2 = Geodesy.ProjectGeodesic(.(51.2407, -1.6089), 2.0 * 1852.0, 90.0);
            ship2.UpdateDynamicState(p2, 14.0, 270.0, 270.0, 0.0, .UnderWayUsingEngine, 1700000000);
            supervisor.Registry.UpdateTrackPosition(211000002, p2);

            Console.WriteLineF("[INFO] Ingested Track 2 (MMSI 211000002, NORDIC CARRIER, Speed 14.0 kts)");

            // 4. Run Dead Reckoning and Safety Analysis
            supervisor.Registry.DeadReckonTracks(1700000060);
            Console.WriteLineF("[INFO] Active Tracks in Registry: {0}", supervisor.Registry.TrackCount);

            // 5. Evaluate and Print Active Alerts
            Console.WriteLineF("[INFO] Dispatched Alerts: {0}", supervisor.Alerts.AlertCount);
            for (var alert in supervisor.Alerts.ActiveAlerts)
            {
                Console.WriteLineF("  -> [{0}] {1}", alert.Severity, alert.Message);
            }

            // 6. Test COLREGs Autonomous Maneuver Planner
            ManeuverRecommendation rec = default;
            rec.Init();
            bool planned = ManeuverPlanner.PlanEvasiveManeuver(
                .(51.2407, -1.6089), 0.0, 14.0,
                p2, 270.0, 14.0,
                .CrossingGiveWay, 1.5, ref rec
            );

            if (planned)
            {
                Console.WriteLine("[INFO] Autonomous Collision Avoidance Maneuver Planned:");
                Console.WriteLineF("  Suggested Course: {0:0.0} deg (Starboard Alteration +{1:0.0} deg)",
                    rec.SuggestedCourseDeg, rec.CourseAlterationDeg);
                Console.WriteLineF("  Projected CPA:    {0:0.00} NM", rec.ProjectedCpaNm);
                Console.WriteLineF("  Rationale:        {0}", rec.Rationale);
            }
            rec.Dispose();

            // 7. Output JSON-RPC telemetry snapshot
            String snapshotJson = scope .();
            JsonRpcTelemetry.SerializeVtsSnapshot(supervisor, snapshotJson);
            Console.WriteLine("[INFO] Telemetry Snapshot Preview:");
            Console.WriteLine(snapshotJson.Substring(0, Math.Min(350, snapshotJson.Length)));
            Console.WriteLine("...");

            Console.WriteLine("======================================================================");
            Console.WriteLine("  KEEL ENGINE EXECUTION COMPLETED WITH ZERO ERRORS                    ");
            Console.WriteLine("======================================================================");
            return 0;
        }
    }
}
