using System;
using System.Collections;
using Keel.Core;
using Keel.Colregs;

namespace Keel.Vts
{
    public enum AlertSeverity
    {
        Information = 0,
        Caution = 1,
        Warning = 2,
        EmergencyAlarm = 3
    }

    public enum AlertCategory
    {
        CollisionRisk = 0,
        GroundingRisk = 1,
        TssViolation = 2,
        SpeedViolation = 3,
        AnchorDragging = 4,
        SartDistress = 5
    }

    public struct VtsAlert
    {
        public uint64 AlertId;
        public AlertCategory Category;
        public AlertSeverity Severity;
        public uint32 PrimaryMmsi;
        public uint32 SecondaryMmsi;
        public GeoCoordinate Location;
        public int64 TimestampSec;
        public String Message;

        public void Init()
        {
            Message = new String();
        }

        public void Dispose()
        {
            delete Message;
        }
    }

    public class AlertDispatcher
    {
        private List<VtsAlert> mActiveAlerts = new .() ~ delete _;
        private uint64 mNextAlertId = 1;

        public void DispatchCollisionAlert(
            uint32 ownMmsi,
            uint32 tgtMmsi,
            GeoCoordinate loc,
            in CpaCalculation cpa,
            EncounterType enc,
            double cri,
            int64 timestampSec)
        {
            VtsAlert alert = default;
            alert.Init();
            alert.AlertId = mNextAlertId++;
            alert.Category = .CollisionRisk;
            alert.Severity = (cri > 0.8) ? .EmergencyAlarm : .Warning;
            alert.PrimaryMmsi = ownMmsi;
            alert.SecondaryMmsi = tgtMmsi;
            alert.Location = loc;
            alert.TimestampSec = timestampSec;

            alert.Message.AppendF("COLLISION RISK [CRI={0:0.00}]: MMSI {1} and MMSI {2} - CPA {3:0.00} NM in {4:0} sec (Encounter: {5})",
                cri, ownMmsi, tgtMmsi, cpa.CpaDistanceNm, cpa.TcpaSeconds, enc);

            mActiveAlerts.Add(alert);
        }

        public void DispatchGroundingAlert(
            uint32 mmsi,
            GeoCoordinate loc,
            double distMeters,
            double timeSeconds,
            double hazardDepthMeters,
            int64 timestampSec)
        {
            VtsAlert alert = default;
            alert.Init();
            alert.AlertId = mNextAlertId++;
            alert.Category = .GroundingRisk;
            alert.Severity = (timeSeconds < 300.0) ? .EmergencyAlarm : .Warning;
            alert.PrimaryMmsi = mmsi;
            alert.SecondaryMmsi = 0;
            alert.Location = loc;
            alert.TimestampSec = timestampSec;

            alert.Message.AppendF("GROUNDING RISK: Vessel MMSI {0} projected to strike shoal (depth {1:0.0}m) in {2:0} sec ({3:0}m ahead)",
                mmsi, hazardDepthMeters, timeSeconds, distMeters);

            mActiveAlerts.Add(alert);
        }

        public void DispatchTssViolation(
            uint32 mmsi,
            GeoCoordinate loc,
            StringView laneName,
            double courseDeg,
            int64 timestampSec)
        {
            VtsAlert alert = default;
            alert.Init();
            alert.AlertId = mNextAlertId++;
            alert.Category = .TssViolation;
            alert.Severity = .Caution;
            alert.PrimaryMmsi = mmsi;
            alert.SecondaryMmsi = 0;
            alert.Location = loc;
            alert.TimestampSec = timestampSec;

            alert.Message.AppendF("TSS WRONG-WAY TRANSIT: Vessel MMSI {0} heading {1:0} deg against traffic flow in lane '{2}'",
                mmsi, courseDeg, laneName);

            mActiveAlerts.Add(alert);
        }

        public void DispatchAnchorDragging(
            uint32 mmsi,
            GeoCoordinate loc,
            double driftDistanceMeters,
            double speedKnots,
            int64 timestampSec)
        {
            VtsAlert alert = default;
            alert.Init();
            alert.AlertId = mNextAlertId++;
            alert.Category = .AnchorDragging;
            alert.Severity = .Warning;
            alert.PrimaryMmsi = mmsi;
            alert.SecondaryMmsi = 0;
            alert.Location = loc;
            alert.TimestampSec = timestampSec;

            alert.Message.AppendF("ANCHOR DRAGGING: Vessel MMSI {0} drifted {1:0}m from drop position at {2:0.1} knots",
                mmsi, driftDistanceMeters, speedKnots);

            mActiveAlerts.Add(alert);
        }

        public void DispatchSartDistress(
            uint32 mmsi,
            GeoCoordinate loc,
            int64 timestampSec)
        {
            VtsAlert alert = default;
            alert.Init();
            alert.AlertId = mNextAlertId++;
            alert.Category = .SartDistress;
            alert.Severity = .EmergencyAlarm;
            alert.PrimaryMmsi = mmsi;
            alert.SecondaryMmsi = 0;
            alert.Location = loc;
            alert.TimestampSec = timestampSec;

            alert.Message.AppendF("MAYDAY / SART DISTRESS: Emergency locator beacon detected from MMSI {0}", mmsi);

            mActiveAlerts.Add(alert);
        }

        public void ClearAlerts()
        {
            for (var a in mActiveAlerts)
                a.Dispose();
            mActiveAlerts.Clear();
        }

        public int AlertCount => mActiveAlerts.Count;
        public List<VtsAlert> ActiveAlerts => mActiveAlerts;
    }
}
