using System;
using Keel.Core;

namespace Keel.Tests
{
    public static class TestGeodesy
    {
        public static void RunTests()
        {
            Console.WriteLine("[TEST] Running Geodesy and WGS-84 Tests...");

            // Test 1: Lands End to John o Groats baseline
            GeoCoordinate landsEnd = .(50.064650, -5.714902);
            GeoCoordinate johnOGroats = .(58.643889, -3.070000);

            bool vincentyOk = Geodesy.VincentyInverse(landsEnd, johnOGroats, let distMeters, let forwardBearing);
            Debug.Assert(vincentyOk, "Vincenty inverse must converge for UK baseline");
            Debug.Assert(distMeters > 960000.0 && distMeters < 980000.0, "Vincenty distance approx 970 km");
            Debug.Assert(forwardBearing > 5.0 && forwardBearing < 15.0, "Forward bearing approx 9.1 deg");

            // Test 2: Haversine distance
            double havDist = Geodesy.GreatCircleDistanceMeters(landsEnd, johnOGroats);
            Debug.Assert(Math.Abs(havDist - distMeters) < 5000.0, "Haversine agrees with Vincenty within 0.5%");

            // Test 3: Geodesic direct projection
            GeoCoordinate origin = .(50.0, 0.0);
            GeoCoordinate projected = Geodesy.ProjectGeodesic(origin, 10000.0, 90.0); // 10 km East
            Debug.Assert(projected.Longitude > origin.Longitude, "Projecting East increases longitude");
            Debug.Assert(Math.Abs(projected.Latitude - origin.Latitude) < 0.001, "Projecting due East preserves latitude");

            // Test 4: Cross-track distance
            GeoCoordinate p1 = .(50.0, 0.0);
            GeoCoordinate p2 = .(52.0, 0.0); // Track runs due North along meridian 0.0
            GeoCoordinate offTrackPt = .(51.0, 0.1); // Displaced East of track

            double xtd = Geodesy.CrossTrackDistanceMeters(p1, p2, offTrackPt);
            Debug.Assert(xtd > 5000.0 && xtd < 10000.0, "Cross-track distance correctly computed (~7 km)");

            Console.WriteLine("  -> Geodesy and WGS-84 Tests PASSED.");
        }
    }
}
