using System;
using Keel.Core;

namespace Keel.Ais
{
    // Common header for all ITU-R M.1371 AIS messages.
    public struct AisMessageHeader
    {
        public uint8 MessageType;       // bits 0-5 (0-63)
        public uint8 RepeatIndicator;   // bits 6-7 (0-3)
        public uint32 Mmsi;             // bits 8-37 (30 bits)

        public this(uint8 type, uint8 repeat, uint32 mmsi)
        {
            this.MessageType = type;
            this.RepeatIndicator = repeat;
            this.Mmsi = mmsi;
        }
    }

    // Class A Position Report (Message Types 1, 2, and 3).
    public struct AisPositionReportClassA
    {
        public AisMessageHeader Header;
        public NavigationalStatus NavStatus;
        public int16 RateOfTurnRaw;        // Sensor ROT: -128 to 127
        public double SpeedOverGround;     // Knots (0.0 to 102.2)
        public bool PositionAccuracy;      // High (<10m) or Low (>10m)
        public GeoCoordinate Position;     // Longitude and Latitude in decimal degrees
        public double CourseOverGround;    // Degrees (0.0 to 359.9)
        public double TrueHeading;         // Degrees (0 to 359, 511 = not available)
        public uint8 TimeStampSeconds;     // UTC second (0-59, 60-63 = status flags)
        public uint8 ManeuverIndicator;    // 0 = not available, 1 = no special maneuver, 2 = special
        public bool RaimFlag;              // RAIM in use
        public uint32 RadioStatus;         // SOTDMA or ITDMA communication state

        // Evaluates Rate of Turn in degrees per minute using ITU formula: ROT_ais = 4.733 * sqrt(ROT_sensor)
        public double RateOfTurnDegPerMin
        {
            get
            {
                if (RateOfTurnRaw == -128)
                    return 0.0; // Not available
                double sign = (RateOfTurnRaw < 0) ? -1.0 : 1.0;
                double rot = (double)Math.Abs(RateOfTurnRaw) / 4.733;
                return sign * (rot * rot);
            }
        }
    }

    // Base Station Report (Message Type 4).
    public struct AisBaseStationReport
    {
        public AisMessageHeader Header;
        public uint16 UtcYear;
        public uint8 UtcMonth;
        public uint8 UtcDay;
        public uint8 UtcHour;
        public uint8 UtcMinute;
        public uint8 UtcSecond;
        public bool PositionAccuracy;
        public GeoCoordinate Position;
        public uint8 EpfdType;             // Type of electronic position fixing device
        public bool RaimFlag;
        public uint32 RadioStatus;
    }

    // Static and Voyage Related Data (Message Type 5).
    public struct AisStaticVoyageData
    {
        public AisMessageHeader Header;
        public uint8 AisVersion;
        public uint32 ImoNumber;
        public char8[8] CallSign;
        public char8[21] VesselName;
        public ShipType ShipCargoType;
        public uint16 DimensionToBow;       // Distance in meters
        public uint16 DimensionToStern;     // Distance in meters
        public uint8 DimensionToPort;       // Distance in meters
        public uint8 DimensionToStarboard;  // Distance in meters
        public uint8 EpfdType;
        public uint8 EtaMonth;
        public uint8 EtaDay;
        public uint8 EtaHour;
        public uint8 EtaMinute;
        public double DraughtMeters;        // Maximum present static draught in meters
        public char8[21] Destination;

        public double OverallLengthMeters => DimensionToBow + DimensionToStern;
        public double OverallBeamMeters => DimensionToPort + DimensionToStarboard;
    }

    // Binary Broadcast Message (Message Type 8) for meteorological and hydrological sensor data.
    public struct AisBinaryBroadcast
    {
        public AisMessageHeader Header;
        public uint16 DesignatedAreaCode;   // DAC (e.g. 1 = International, 235 = UK, 366 = US)
        public uint8 FunctionalId;          // FI (e.g. 11 = Met/Hydro sensor)
        public double AirTemperatureC;
        public double WindSpeedKnots;
        public double WindDirectionDeg;
        public double WaterLevelMeters;
        public double SurfaceCurrentSpeedKnots;
        public double SurfaceCurrentDirectionDeg;
    }

    // Search and Rescue (SAR) Aircraft Position Report (Message Type 9).
    public struct AisSarAircraftPosition
    {
        public AisMessageHeader Header;
        public uint16 AltitudeMeters;      // Altitude above sea level
        public double SpeedOverGround;     // Knots
        public bool PositionAccuracy;
        public GeoCoordinate Position;
        public double CourseOverGround;
        public uint8 TimeStampSeconds;
        public uint8 AltitudeSensor;
    }

    // Standard Class B Position Report (Message Type 18).
    public struct AisStandardClassBPosition
    {
        public AisMessageHeader Header;
        public double SpeedOverGround;
        public bool PositionAccuracy;
        public GeoCoordinate Position;
        public double CourseOverGround;
        public double TrueHeading;
        public uint8 TimeStampSeconds;
        public bool CsUnitFlag;             // Class B SOTDMA or CS
        public bool DisplayFlag;
        public bool DscFlag;
        public bool BandFlag;
        public bool Message22Flag;
        public bool AssignedMode;
        public bool RaimFlag;
        public uint32 RadioStatus;
    }

    // Extended Class B Equipment Position Report (Message Type 19).
    public struct AisExtendedClassBPosition
    {
        public AisMessageHeader Header;
        public double SpeedOverGround;
        public bool PositionAccuracy;
        public GeoCoordinate Position;
        public double CourseOverGround;
        public double TrueHeading;
        public uint8 TimeStampSeconds;
        public char8[21] VesselName;
        public ShipType ShipCargoType;
        public uint16 DimensionToBow;
        public uint16 DimensionToStern;
        public uint8 DimensionToPort;
        public uint8 DimensionToStarboard;
    }

    // Aids to Navigation Report (Message Type 21: Buoys, Beacons, Lightships).
    public struct AisAidsToNavigation
    {
        public AisMessageHeader Header;
        public uint8 AtoNType;              // 1 = Default, 2 = Reference point, 3 = RACON, 20 = Cardinal N, etc.
        public char8[35] Name;
        public bool PositionAccuracy;
        public GeoCoordinate Position;
        public uint16 DimensionToBow;
        public uint16 DimensionToStern;
        public uint8 DimensionToPort;
        public uint8 DimensionToStarboard;
        public uint8 EpfdType;
        public uint8 TimeStampSeconds;
        public bool OffPositionIndicator;  // True if buoy has drifted from assigned location
        public bool VirtualAtoNFlag;       // True if virtual buoy without physical structure
    }

    // Static Data Report (Message Type 24).
    public struct AisStaticDataReport
    {
        public AisMessageHeader Header;
        public uint8 PartNumber;           // 0 = Part A, 1 = Part B
        public char8[21] VesselName;       // In Part A
        public char8[8] CallSign;          // In Part B
        public ShipType ShipCargoType;     // In Part B
        public uint16 DimensionToBow;
        public uint16 DimensionToStern;
        public uint8 DimensionToPort;
        public uint8 DimensionToStarboard;
    }

    // Long-Range AIS Broadcast (Message Type 27).
    public struct AisLongRangeBroadcast
    {
        public AisMessageHeader Header;
        public bool PositionAccuracy;
        public bool RaimFlag;
        public NavigationalStatus NavStatus;
        public GeoCoordinate Position;
        public double SpeedOverGround;
        public double CourseOverGround;
        public bool GnssPositionStatus;
    }
}
