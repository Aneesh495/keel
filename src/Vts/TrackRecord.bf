using System;
using Keel.Core;

namespace Keel.Vts
{
    public class TrackRecord
    {
        public uint32 Mmsi;
        public uint32 ImoNumber;
        public String CallSign = new .() ~ delete _;
        public String VesselName = new .() ~ delete _;
        public ShipType ShipCargoType;
        public double LengthMeters;
        public double BeamMeters;
        public double StaticDraughtMeters;

        // Dynamic state
        public GeoCoordinate Position;
        public double SpeedOverGroundKnots;
        public double CourseOverGroundDeg;
        public double TrueHeadingDeg;
        public double RateOfTurnDegPerMin;
        public NavigationalStatus NavStatus;
        public int64 LastSeenTimestampSec;

        // Anchor monitoring
        public GeoCoordinate DropAnchorPosition;
        public double AnchorScopeRadiusMeters;

        // Track quality and status
        public bool IsConfirmed;
        public int ReportCount;

        public this(uint32 mmsi)
        {
            this.Mmsi = mmsi;
            this.ImoNumber = 0;
            this.ShipCargoType = .NotAvailable;
            this.LengthMeters = 50.0;
            this.BeamMeters = 10.0;
            this.StaticDraughtMeters = 5.0;
            this.Position = default;
            this.SpeedOverGroundKnots = 0.0;
            this.CourseOverGroundDeg = 0.0;
            this.TrueHeadingDeg = 0.0;
            this.RateOfTurnDegPerMin = 0.0;
            this.NavStatus = .NotDefined;
            this.LastSeenTimestampSec = 0;
            this.DropAnchorPosition = default;
            this.AnchorScopeRadiusMeters = 150.0; // Standard 150m swing circle
            this.IsConfirmed = false;
            this.ReportCount = 0;
        }

        public void UpdateDynamicState(
            GeoCoordinate pos,
            double sogKnots,
            double cogDeg,
            double headingDeg,
            double rotDegPerMin,
            NavigationalStatus status,
            int64 timestampSec)
        {
            this.Position = pos;
            this.SpeedOverGroundKnots = sogKnots;
            this.CourseOverGroundDeg = cogDeg;
            this.TrueHeadingDeg = headingDeg;
            this.RateOfTurnDegPerMin = rotDegPerMin;
            this.NavStatus = status;
            this.LastSeenTimestampSec = timestampSec;
            this.ReportCount++;

            if (this.ReportCount >= 2)
            {
                this.IsConfirmed = true;
            }

            // If transitioning into AtAnchor status for the first time, record drop position
            if (status == .AtAnchor && DropAnchorPosition.Latitude == 0.0 && DropAnchorPosition.Longitude == 0.0)
            {
                DropAnchorPosition = pos;
            }
            else if (status != .AtAnchor)
            {
                DropAnchorPosition = default;
            }
        }
    }
}
