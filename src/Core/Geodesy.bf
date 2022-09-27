using System;

namespace Keel.Core
{
    // High-precision WGS-84 geodesic calculations and navigational trigonometry.
    public static class Geodesy
    {
        // WGS-84 ellipsoid constants
        public const double WGS84_A = 6378137.0; // semi-major axis in meters
        public const double WGS84_F = 1.0 / 298.257223563; // flattening
        public const double WGS84_B = 6356752.314245179; // semi-minor axis in meters

        public const double METERS_PER_NAUTICAL_MILE = 1852.0;
        public const double DEG_TO_RAD = Math.PI_d / 180.0;
        public const double RAD_TO_DEG = 180.0 / Math.PI_d;

        // Converts nautical miles to meters.
        public static double NauticalMilesToMeters(double nm) => nm * METERS_PER_NAUTICAL_MILE;

        // Converts meters to nautical miles.
        public static double MetersToNauticalMiles(double m) => m / METERS_PER_NAUTICAL_MILE;

        // Normalizes an angle to [0.0, 360.0) degrees.
        public static double NormalizeDegrees(double deg)
        {
            double res = deg % 360.0;
            if (res < 0.0)
                res += 360.0;
            return res;
        }

        // Fast Great Circle distance using the haversine formula in meters.
        public static double GreatCircleDistanceMeters(GeoCoordinate p1, GeoCoordinate p2)
        {
            double lat1 = p1.Latitude * DEG_TO_RAD;
            double lon1 = p1.Longitude * DEG_TO_RAD;
            double lat2 = p2.Latitude * DEG_TO_RAD;
            double lon2 = p2.Longitude * DEG_TO_RAD;

            double dLat = lat2 - lat1;
            double dLon = lon2 - lon1;

            double sinDLat = Math.Sin(dLat * 0.5);
            double sinDLon = Math.Sin(dLon * 0.5);

            double a = (sinDLat * sinDLat) +
                       Math.Cos(lat1) * Math.Cos(lat2) * (sinDLon * sinDLon);
            double c = 2.0 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(Math.Max(0.0, 1.0 - a)));

            return WGS84_A * c;
        }

        // Initial forward bearing (azimuth) from p1 to p2 in degrees [0, 360).
        public static double InitialBearingDegrees(GeoCoordinate p1, GeoCoordinate p2)
        {
            double lat1 = p1.Latitude * DEG_TO_RAD;
            double lon1 = p1.Longitude * DEG_TO_RAD;
            double lat2 = p2.Latitude * DEG_TO_RAD;
            double lon2 = p2.Longitude * DEG_TO_RAD;

            double dLon = lon2 - lon1;

            double y = Math.Sin(dLon) * Math.Cos(lat2);
            double x = Math.Cos(lat1) * Math.Sin(lat2) -
                       Math.Sin(lat1) * Math.Cos(lat2) * Math.Cos(dLon);

            double initialBearingRad = Math.Atan2(y, x);
            return NormalizeDegrees(initialBearingRad * RAD_TO_DEG);
        }

        // Exact WGS-84 inverse geodesic calculation using Vincenty formulae.
        // Returns true if convergence succeeded; outDistanceMeters and outInitialBearingDeg are populated.
        public static bool VincentyInverse(
            GeoCoordinate p1,
            GeoCoordinate p2,
            out double outDistanceMeters,
            out double outInitialBearingDeg)
        {
            outDistanceMeters = 0.0;
            outInitialBearingDeg = 0.0;

            if (Math.Abs(p1.Latitude - p2.Latitude) < 1e-12 && Math.Abs(p1.Longitude - p2.Longitude) < 1e-12)
            {
                return true;
            }

            double phi1 = p1.Latitude * DEG_TO_RAD;
            double L1 = p1.Longitude * DEG_TO_RAD;
            double phi2 = p2.Latitude * DEG_TO_RAD;
            double L2 = p2.Longitude * DEG_TO_RAD;

            double U1 = Math.Atan((1.0 - WGS84_F) * Math.Tan(phi1));
            double U2 = Math.Atan((1.0 - WGS84_F) * Math.Tan(phi2));
            double L = L2 - L1;

            double sinU1 = Math.Sin(U1), cosU1 = Math.Cos(U1);
            double sinU2 = Math.Sin(U2), cosU2 = Math.Cos(U2);

            double lambda = L;
            double lambdaP = 2.0 * Math.PI_d;
            int iterLimit = 100;

            double cosSqAlpha = 0.0;
            double sinSigma = 0.0;
            double cos2SigmaM = 0.0;
            double cosSigma = 0.0;
            double sigma = 0.0;
            double sinAlpha = 0.0;

            while (Math.Abs(lambda - lambdaP) > 1e-12 && --iterLimit > 0)
            {
                double sinLambda = Math.Sin(lambda);
                double cosLambda = Math.Cos(lambda);

                sinSigma = Math.Sqrt(
                    (cosU2 * sinLambda) * (cosU2 * sinLambda) +
                    (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda) * (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
                );

                if (sinSigma == 0.0)
                {
                    outDistanceMeters = 0.0;
                    return true;
                }

                cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
                sigma = Math.Atan2(sinSigma, cosSigma);
                sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma;
                cosSqAlpha = 1.0 - sinAlpha * sinAlpha;

                if (cosSqAlpha != 0.0)
                {
                    cos2SigmaM = cosSigma - 2.0 * sinU1 * sinU2 / cosSqAlpha;
                }
                else
                {
                    cos2SigmaM = 0.0;
                }

                double C = (WGS84_F / 16.0) * cosSqAlpha * (4.0 + WGS84_F * (4.0 - 3.0 * cosSqAlpha));
                lambdaP = lambda;
                lambda = L + (1.0 - C) * WGS84_F * sinAlpha *
                    (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM)));
            }

            if (iterLimit == 0)
            {
                // Fall back to Haversine if convergence failed (antipodal points)
                outDistanceMeters = GreatCircleDistanceMeters(p1, p2);
                outInitialBearingDeg = InitialBearingDegrees(p1, p2);
                return false;
            }

            double uSq = cosSqAlpha * (WGS84_A * WGS84_A - WGS84_B * WGS84_B) / (WGS84_B * WGS84_B);
            double A = 1.0 + (uSq / 16384.0) * (4096.0 + uSq * (-768.0 + uSq * (320.0 - 175.0 * uSq)));
            double B = (uSq / 1024.0) * (256.0 + uSq * (-128.0 + uSq * (74.0 - 47.0 * uSq)));
            double deltaSigma = B * sinSigma * (cos2SigmaM + 0.25 * B * (cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM) -
                (B / 6.0) * cos2SigmaM * (-3.0 + 4.0 * sinSigma * sinSigma) * (-3.0 + 4.0 * cos2SigmaM * cos2SigmaM)));

            outDistanceMeters = WGS84_B * A * (sigma - deltaSigma);

            double initialBearingRad = Math.Atan2(
                cosU2 * Math.Sin(lambda),
                cosU1 * sinU2 - sinU1 * cosU2 * Math.Cos(lambda)
            );
            outInitialBearingDeg = NormalizeDegrees(initialBearingRad * RAD_TO_DEG);
            return true;
        }

        // Projects a new coordinate along a geodesic path given starting point, distance in meters, and bearing in degrees.
        public static GeoCoordinate ProjectGeodesic(GeoCoordinate origin, double distanceMeters, double bearingDegrees)
        {
            double distRatio = distanceMeters / WGS84_A;
            double brngRad = bearingDegrees * DEG_TO_RAD;

            double lat1 = origin.Latitude * DEG_TO_RAD;
            double lon1 = origin.Longitude * DEG_TO_RAD;

            double lat2 = Math.Asin(
                Math.Sin(lat1) * Math.Cos(distRatio) +
                Math.Cos(lat1) * Math.Sin(distRatio) * Math.Cos(brngRad)
            );

            double lon2 = lon1 + Math.Atan2(
                Math.Sin(brngRad) * Math.Sin(distRatio) * Math.Cos(lat1),
                Math.Cos(distRatio) - Math.Sin(lat1) * Math.Sin(lat2)
            );

            double finalLat = lat2 * RAD_TO_DEG;
            double finalLon = NormalizeDegrees(lon2 * RAD_TO_DEG);
            if (finalLon > 180.0)
                finalLon -= 360.0;

            return .(finalLat, finalLon);
        }

        // Calculates cross-track distance in meters from point P to great circle path from start to end.
        // Positive distance indicates right of path; negative indicates left.
        public static double CrossTrackDistanceMeters(GeoCoordinate start, GeoCoordinate end, GeoCoordinate point)
        {
            double d13 = GreatCircleDistanceMeters(start, point) / WGS84_A;
            double brng13 = InitialBearingDegrees(start, point) * DEG_TO_RAD;
            double brng12 = InitialBearingDegrees(start, end) * DEG_TO_RAD;

            double xtd = Math.Asin(Math.Sin(d13) * Math.Sin(brng13 - brng12));
            return xtd * WGS84_A;
        }
    }
}
