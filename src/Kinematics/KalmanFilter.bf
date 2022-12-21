using System;
using Keel.Core;

namespace Keel.Kinematics
{
    // Continuous-Discrete Extended Kalman Filter for maritime vessel tracking.
    public class VesselKalmanFilter
    {
        public KinematicState State;
        public double[6, 6] Covariance; // Error covariance matrix P
        public GeoCoordinate ReferenceOrigin;
        public int64 LastTimestampSec;

        public this(GeoCoordinate origin, double initSpeedKnots, double initCourseDeg)
        {
            this.ReferenceOrigin = origin;
            this.State = default;
            double k = 1852.0 / 3600.0;
            double rad = initCourseDeg * Geodesy.DEG_TO_RAD;

            this.State.VelEastMps = (initSpeedKnots * k) * Math.Sin(rad);
            this.State.VelNorthMps = (initSpeedKnots * k) * Math.Cos(rad);
            this.State.HeadingRad = rad;
            this.State.RateOfTurnRadPerSec = 0.0;
            this.LastTimestampSec = 0;

            // Initialize diagonal covariance matrix P
            this.Covariance = default;
            Covariance[0, 0] = 100.0; // Pos East variance (10m std dev)
            Covariance[1, 1] = 100.0; // Pos North variance (10m std dev)
            Covariance[2, 2] = 4.0;   // Vel East variance (2 m/s std dev)
            Covariance[3, 3] = 4.0;   // Vel North variance (2 m/s std dev)
            Covariance[4, 4] = 0.1;   // Heading variance (~18 deg std dev)
            Covariance[5, 5] = 0.01;  // ROT variance
        }

        // Predicts state forward by dt seconds using the coordinated turn motion model.
        public void Predict(double dt)
        {
            if (dt <= 0.0)
                return;

            double r = State.RateOfTurnRadPerSec;

            if (Math.Abs(r) < 1e-5)
            {
                // Constant velocity linear motion model
                State.PosEastMeters += State.VelEastMps * dt;
                State.PosNorthMeters += State.VelNorthMps * dt;
            }
            else
            {
                // Coordinated turn nonlinear motion model
                double sinRdt = Math.Sin(r * dt);
                double cosRdt = Math.Cos(r * dt);

                double vx = State.VelEastMps;
                double vy = State.VelNorthMps;

                State.PosEastMeters += (vx * sinRdt + vy * (cosRdt - 1.0)) / r;
                State.PosNorthMeters += (vx * (1.0 - cosRdt) + vy * sinRdt) / r;

                // Rotate velocity vector by r * dt
                State.VelEastMps = vx * cosRdt - vy * sinRdt;
                State.VelNorthMps = vx * sinRdt + vy * cosRdt;
                State.HeadingRad = Geodesy.NormalizeDegrees((State.HeadingRad + (r * dt)) * Geodesy.RAD_TO_DEG) * Geodesy.DEG_TO_RAD;
            }

            // Add process noise Q to covariance diagonals
            double qPos = 0.5 * dt;
            double qVel = 0.1 * dt;
            double qHdg = 0.01 * dt;
            Covariance[0, 0] += qPos;
            Covariance[1, 1] += qPos;
            Covariance[2, 2] += qVel;
            Covariance[3, 3] += qVel;
            Covariance[4, 4] += qHdg;
        }

        // Corrects filter state using newly received AIS position and velocity observations.
        public void UpdateAisMeasurement(
            GeoCoordinate measuredPos,
            double measuredSogKnots,
            double measuredCogDeg,
            int64 timestampSec)
        {
            if (LastTimestampSec > 0)
            {
                double dt = (double)(timestampSec - LastTimestampSec);
                if (dt > 0.0 && dt < 300.0)
                {
                    Predict(dt);
                }
            }
            LastTimestampSec = timestampSec;

            // Convert observation to local East-North-Up tangent plane
            Vector2D obsPos = LocalCoordinateTransform.GeodeticToLocalTangent(ReferenceOrigin, measuredPos);
            double k = 1852.0 / 3600.0;
            double cogRad = measuredCogDeg * Geodesy.DEG_TO_RAD;
            double obsVx = (measuredSogKnots * k) * Math.Sin(cogRad);
            double obsVy = (measuredSogKnots * k) * Math.Cos(cogRad);

            // Measurement residuals (innovations)
            double resX = obsPos.X - State.PosEastMeters;
            double resY = obsPos.Y - State.PosNorthMeters;
            double resVx = obsVx - State.VelEastMps;
            double resVy = obsVy - State.VelNorthMps;

            // Measurement noise variances R
            double rPos = 25.0; // 5 meters std dev
            double rVel = 1.0;  // 1 m/s std dev

            // Kalman gains for diagonal measurement matrix
            double kx = Covariance[0, 0] / (Covariance[0, 0] + rPos);
            double ky = Covariance[1, 1] / (Covariance[1, 1] + rPos);
            double kvx = Covariance[2, 2] / (Covariance[2, 2] + rVel);
            double kvy = Covariance[3, 3] / (Covariance[3, 3] + rVel);

            // State correction
            State.PosEastMeters += kx * resX;
            State.PosNorthMeters += ky * resY;
            State.VelEastMps += kvx * resVx;
            State.VelNorthMps += kvy * resVy;

            // Covariance reduction
            Covariance[0, 0] *= (1.0 - kx);
            Covariance[1, 1] *= (1.0 - ky);
            Covariance[2, 2] *= (1.0 - kvx);
            Covariance[3, 3] *= (1.0 - kvy);
        }

        // Returns current estimated geodetic coordinate.
        public GeoCoordinate CurrentEstimatedPosition()
        {
            return LocalCoordinateTransform.LocalTangentToGeodetic(ReferenceOrigin, .(State.PosEastMeters, State.PosNorthMeters));
        }
    }
}
