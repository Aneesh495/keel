using System;

namespace Keel.Core
{
    // Fundamental value types and dimensional units for maritime navigation.
    public struct GeoCoordinate
    {
        public double Latitude;
        public double Longitude;

        public this(double lat, double lon)
        {
            this.Latitude = lat;
            this.Longitude = lon;
        }

        public bool IsValid()
        {
            return Latitude >= -90.0 && Latitude <= 90.0 &&
                   Longitude >= -180.0 && Longitude <= 180.0;
        }

        public static readonly GeoCoordinate Zero = .(0.0, 0.0);
    }

    public struct Vector2D
    {
        public double X;
        public double Y;

        public this(double x, double y)
        {
            this.X = x;
            this.Y = y;
        }

        public double LengthSquared => (X * X) + (Y * Y);
        public double Length => Math.Sqrt((X * X) + (Y * Y));

        public Vector2D Normalized()
        {
            double len = Length;
            if (len < 1e-9)
                return .(0.0, 0.0);
            return .(X / len, Y / len);
        }

        public static Vector2D operator+(Vector2D a, Vector2D b) => .(a.X + b.X, a.Y + b.Y);
        public static Vector2D operator-(Vector2D a, Vector2D b) => .(a.X - b.X, a.Y - b.Y);
        public static Vector2D operator*(Vector2D a, double s) => .(a.X * s, a.Y * s);
        public static double Dot(Vector2D a, Vector2D b) => (a.X * b.X) + (a.Y * b.Y);
        public static double Cross(Vector2D a, Vector2D b) => (a.X * b.Y) - (a.Y * b.X);
    }

    public struct BoundingBox2D
    {
        public double MinLat;
        public double MaxLat;
        public double MinLon;
        public double MaxLon;

        public this(double minLat, double maxLat, double minLon, double maxLon)
        {
            this.MinLat = minLat;
            this.MaxLat = maxLat;
            this.MinLon = minLon;
            this.MaxLon = maxLon;
        }

        public bool Contains(GeoCoordinate coord)
        {
            return coord.Latitude >= MinLat && coord.Latitude <= MaxLat &&
                   coord.Longitude >= MinLon && coord.Longitude <= MaxLon;
        }

        public bool Intersects(BoundingBox2D other)
        {
            return !(other.MinLon > MaxLon || other.MaxLon < MinLon ||
                     other.MinLat > MaxLat || other.MaxLat < MinLat);
        }
    }

    public struct VelocityVector
    {
        // Speed over ground in knots
        public double SpeedKnots;
        // Course over ground in degrees (0.0 to 359.99)
        public double CourseDegrees;

        public this(double speedKnots, double courseDegrees)
        {
            this.SpeedKnots = speedKnots;
            this.CourseDegrees = courseDegrees;
        }

        // Returns Cartesian velocity components in knots (East, North)
        public Vector2D ToCartesianKnots()
        {
            double rad = CourseDegrees * (Math.PI_d / 180.0);
            double vx = SpeedKnots * Math.Sin(rad); // Easting
            double vy = SpeedKnots * Math.Cos(rad); // Northing
            return .(vx, vy);
        }
    }

    public enum NavigationalStatus : uint8
    {
        UnderWayUsingEngine = 0,
        AtAnchor = 1,
        NotUnderCommand = 2,
        RestrictedManoeuverability = 3,
        ConstrainedByDraught = 4,
        Moored = 5,
        Aground = 6,
        EngagedInFishing = 7,
        UnderWaySailing = 8,
        ReservedHSC = 9,
        ReservedWIG = 10,
        PowerDrivenTowingAstern = 11,
        PowerDrivenPushingAhead = 12,
        ReservedFuture13 = 13,
        AisSartActive = 14,
        NotDefined = 15
    }

    public enum ShipType : uint8
    {
        NotAvailable = 0,
        WingInGround = 20,
        Fishing = 30,
        Towing = 31,
        TowingLarge = 32,
        DredgingOrUnderwaterOps = 33,
        DivingOps = 34,
        MilitaryOps = 35,
        Sailing = 36,
        PleasureCraft = 37,
        HighSpeedCraft = 40,
        PilotVessel = 50,
        SearchAndRescue = 51,
        Tug = 52,
        PortTender = 53,
        AntiPollutionEquipment = 54,
        LawEnforcement = 55,
        MedicalTransport = 58,
        NonCombatantShip = 59,
        Passenger = 60,
        Cargo = 70,
        Tanker = 80,
        Other = 90
    }
}
