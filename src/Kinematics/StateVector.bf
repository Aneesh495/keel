using System;
using Keel.Core;

namespace Keel.Kinematics
{
    // Kinematic vessel state vector in local East-North-Up tangent plane.
    public struct KinematicState
    {
        public double PosEastMeters;       // x
        public double PosNorthMeters;      // y
        public double VelEastMps;          // vx
        public double VelNorthMps;         // vy
        public double HeadingRad;          // psi
        public double RateOfTurnRadPerSec; // r = d(psi)/dt

        public double SpeedOverGroundKnots
        {
            get
            {
                double vMps = Math.Sqrt((VelEastMps * VelEastMps) + (VelNorthMps * VelNorthMps));
                return vMps * (3600.0 / 1852.0);
            }
        }

        public double CourseOverGroundDeg
        {
            get
            {
                double cogRad = Math.Atan2(VelEastMps, VelNorthMps);
                double deg = cogRad * Geodesy.RAD_TO_DEG;
                return Geodesy.NormalizeDegrees(deg);
            }
        }

        public double HeadingDeg => Geodesy.NormalizeDegrees(HeadingRad * Geodesy.RAD_TO_DEG);
        public double RateOfTurnDegPerMin => RateOfTurnRadPerSec * Geodesy.RAD_TO_DEG * 60.0;
    }

    public static class LocalCoordinateTransform
    {
        // Converts geodetic coordinate to local tangent plane (East, North) meters relative to origin.
        public static Vector2D GeodeticToLocalTangent(GeoCoordinate origin, GeoCoordinate target)
        {
            double distMeters = Geodesy.GreatCircleDistanceMeters(origin, target);
            double bearingDeg = Geodesy.InitialBearingDegrees(origin, target);
            double bearingRad = bearingDeg * Geodesy.DEG_TO_RAD;

            double east = distMeters * Math.Sin(bearingRad);
            double north = distMeters * Math.Cos(bearingRad);
            return .(east, north);
        }

        // Converts local tangent plane (East, North) meters back to geodetic coordinate.
        public static GeoCoordinate LocalTangentToGeodetic(GeoCoordinate origin, Vector2D localEnu)
        {
            double distMeters = localEnu.Length;
            if (distMeters < 1e-4)
                return origin;

            double bearingRad = Math.Atan2(localEnu.X, localEnu.Y);
            double bearingDeg = Geodesy.NormalizeDegrees(bearingRad * Geodesy.RAD_TO_DEG);

            return Geodesy.ProjectGeodesic(origin, distMeters, bearingDeg);
        }
    }
}
