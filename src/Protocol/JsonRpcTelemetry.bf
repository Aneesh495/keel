using System;
using System.Collections;
using Keel.Vts;
using Keel.Colregs;

namespace Keel.Protocol
{
    public static class JsonRpcTelemetry
    {
        // Serializes track record into JSON string.
        public static void SerializeTrack(TrackRecord track, String outJson)
        {
            outJson.Append("{\n");
            outJson.AppendF("  \"mmsi\": {0},\n", track.Mmsi);
            outJson.AppendF("  \"vessel_name\": \"{0}\",\n", track.VesselName);
            outJson.AppendF("  \"call_sign\": \"{0}\",\n", track.CallSign);
            outJson.AppendF("  \"ship_type\": {0},\n", (uint8)track.ShipCargoType);
            outJson.AppendF("  \"latitude\": {0:0.000000},\n", track.Position.Latitude);
            outJson.AppendF("  \"longitude\": {0:0.000000},\n", track.Position.Longitude);
            outJson.AppendF("  \"speed_knots\": {0:0.1},\n", track.SpeedOverGroundKnots);
            outJson.AppendF("  \"course_deg\": {0:0.1},\n", track.CourseOverGroundDeg);
            outJson.AppendF("  \"heading_deg\": {0:0.1},\n", track.TrueHeadingDeg);
            outJson.AppendF("  \"draught_meters\": {0:0.1},\n", track.StaticDraughtMeters);
            outJson.AppendF("  \"nav_status\": {0},\n", (uint8)track.NavStatus);
            outJson.AppendF("  \"last_seen\": {0}\n", track.LastSeenTimestampSec);
            outJson.Append("}");
        }

        // Serializes all active VTS tracks and alerts into a complete status report.
        public static void SerializeVtsSnapshot(VtsSupervisor supervisor, String outJson)
        {
            outJson.Clear();
            outJson.Append("{\n");
            outJson.AppendF("  \"timestamp\": {0},\n", supervisor.CurrentTimeSec);
            outJson.AppendF("  \"track_count\": {0},\n", supervisor.Registry.TrackCount);
            outJson.AppendF("  \"alert_count\": {0},\n", supervisor.Alerts.AlertCount);

            // Active alerts
            outJson.Append("  \"alerts\": [\n");
            bool firstAlert = true;
            for (var alert in supervisor.Alerts.ActiveAlerts)
            {
                if (!firstAlert) outJson.Append(",\n");
                firstAlert = false;
                outJson.Append("    {\n");
                outJson.AppendF("      \"id\": {0},\n", alert.AlertId);
                outJson.AppendF("      \"category\": \"{0}\",\n", alert.Category);
                outJson.AppendF("      \"severity\": \"{0}\",\n", alert.Severity);
                outJson.AppendF("      \"primary_mmsi\": {0},\n", alert.PrimaryMmsi);
                outJson.AppendF("      \"message\": \"{0}\"\n", alert.Message);
                outJson.Append("    }");
            }
            outJson.Append("\n  ],\n");

            // Tracks
            outJson.Append("  \"tracks\": [\n");
            bool firstTrack = true;
            for (TrackRecord track in supervisor.Registry.Tracks)
            {
                if (!firstTrack) outJson.Append(",\n");
                firstTrack = false;
                String trackJson = scope .();
                SerializeTrack(track, trackJson);
                outJson.Append("    ");
                outJson.Append(trackJson);
            }
            outJson.Append("\n  ]\n");
            outJson.Append("}\n");
        }
    }
}
