using System;
using System.Collections;
using Keel.Core;

namespace Keel.Nautical
{
    public struct GroundingWarning
    {
        public uint32 Mmsi;
        public double DistanceToHazardMeters;
        public double TimeToHazardSeconds;
        public GeoCoordinate HazardLocation;
        public double DepthAtHazardMeters;
        public double RequiredSafetyDepthMeters;
        public bool IsImminentGrounding;
    }

    public class S57ChartDatabase
    {
        private List<S57DepthArea> mDepthAreas = new .() ~ DeleteContainerAndItems!(_);
        private List<S57Sounding> mSoundings = new .() ~ delete _;
        private List<S57TrafficLane> mTrafficLanes = new .() ~ DeleteContainerAndItems!(_);

        public void AddDepthArea(S57DepthArea area) => mDepthAreas.Add(area);
        public void AddSounding(S57Sounding sndg) => mSoundings.Add(sndg);
        public void AddTrafficLane(S57TrafficLane lane) => mTrafficLanes.Add(lane);

        // Projects vessel along its current course and evaluates grounding hazards against depth areas.
        public bool CheckGroundingHazard(
            uint32 mmsi,
            GeoCoordinate currentPos,
            double courseDeg,
            double speedKnots,
            double staticDraughtMeters,
            double tideElevationMeters,
            double lookaheadSeconds,
            out GroundingWarning outWarning)
        {
            outWarning = default;
            outWarning.Mmsi = mmsi;

            if (speedKnots < 0.5)
                return false;

            double squat = SquatUkcEvaluator.CalculateSquatMeters(speedKnots, 0.75, .ShallowWater);
            double requiredSafetyDepth = staticDraughtMeters + squat + 1.0 - tideElevationMeters;
            outWarning.RequiredSafetyDepthMeters = requiredSafetyDepth;

            double speedMps = speedKnots * (1852.0 / 3600.0);
            double totalProjectionDist = speedMps * lookaheadSeconds;

            // Sample every 100 meters along projected path
            double step = 100.0;
            for (double d = step; d <= totalProjectionDist; d += step)
            {
                GeoCoordinate pt = Geodesy.ProjectGeodesic(currentPos, d, courseDeg);

                for (S57DepthArea area in mDepthAreas)
                {
                    if (area.DepthRangeMaxMeters < requiredSafetyDepth)
                    {
                        if (area.Contains(pt))
                        {
                            outWarning.DistanceToHazardMeters = d;
                            outWarning.TimeToHazardSeconds = d / speedMps;
                            outWarning.HazardLocation = pt;
                            outWarning.DepthAtHazardMeters = area.DepthRangeMaxMeters;
                            outWarning.IsImminentGrounding = (outWarning.TimeToHazardSeconds < 300.0);
                            return true;
                        }
                    }
                }
            }

            return false;
        }

        // Checks whether a vessel in a Traffic Separation Scheme lane is violating the designated flow direction.
        public bool CheckTssCompliance(
            GeoCoordinate pos,
            double courseDeg,
            out String outLaneName,
            out bool outIsWrongWay)
        {
            outLaneName = null;
            outIsWrongWay = false;

            for (S57TrafficLane lane in mTrafficLanes)
            {
                if (lane.Contains(pos))
                {
                    outLaneName = lane.Name;
                    double diff = Math.Abs(courseDeg - lane.TrafficDirectionDeg);
                    if (diff > 180.0) diff = 360.0 - diff;

                    // If heading differs by more than 90 degrees, vessel is traveling against designated flow
                    outIsWrongWay = (diff > 90.0);
                    return true;
                }
            }
            return false;
        }

        public int DepthAreaCount => mDepthAreas.Count;
        public int SoundingCount => mSoundings.Count;
        public int TrafficLaneCount => mTrafficLanes.Count;
    }
}
