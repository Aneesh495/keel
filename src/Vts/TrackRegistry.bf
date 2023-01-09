using System;
using System.Collections;
using Keel.Core;

namespace Keel.Vts
{
    public class TrackRegistry
    {
        private Dictionary<uint32, TrackRecord> mTracks = new .() ~ DeleteContainerAndValues!(_);
        private SpatialGrid2D mSpatialGrid = new .() ~ delete _;

        public TrackRecord GetOrCreateTrack(uint32 mmsi)
        {
            if (mTracks.TryGetValue(mmsi, var track))
            {
                return track;
            }

            track = new TrackRecord(mmsi);
            mTracks[mmsi] = track;
            return track;
        }

        public bool TryGetTrack(uint32 mmsi, out TrackRecord outTrack)
        {
            return mTracks.TryGetValue(mmsi, out outTrack);
        }

        public void UpdateTrackPosition(uint32 mmsi, GeoCoordinate pos)
        {
            mSpatialGrid.InsertOrUpdate(mmsi, pos);
        }

        public void RemoveTrack(uint32 mmsi)
        {
            if (mTracks.TryGetValue(mmsi, var track))
            {
                mSpatialGrid.Remove(mmsi);
                mTracks.Remove(mmsi);
                delete track;
            }
        }

        // Dead reckons active tracks forward to currentTimestampSec.
        public void DeadReckonTracks(int64 currentTimestampSec)
        {
            for (var kv in mTracks)
            {
                TrackRecord track = kv.value;
                if (!track.IsConfirmed || track.SpeedOverGroundKnots < 0.5)
                    continue;

                double dt = (double)(currentTimestampSec - track.LastSeenTimestampSec);
                if (dt > 2.0 && dt < 600.0) // Dead reckon between 2s and 10 minutes
                {
                    double speedMps = track.SpeedOverGroundKnots * (1852.0 / 3600.0);
                    double distMeters = speedMps * dt;
                    GeoCoordinate projected = Geodesy.ProjectGeodesic(track.Position, distMeters, track.CourseOverGroundDeg);
                    track.Position = projected;
                    track.LastSeenTimestampSec = currentTimestampSec;
                    mSpatialGrid.InsertOrUpdate(track.Mmsi, projected);
                }
            }
        }

        // Purges tracks that haven't transmitted within maxAgeSeconds.
        public int PurgeAgedTracks(int64 currentTimestampSec, int64 maxAgeSeconds)
        {
            List<uint32> toRemove = scope .();
            for (var kv in mTracks)
            {
                if ((currentTimestampSec - kv.value.LastSeenTimestampSec) > maxAgeSeconds)
                {
                    toRemove.Add(kv.key);
                }
            }

            for (uint32 mmsi in toRemove)
            {
                RemoveTrack(mmsi);
            }
            return toRemove.Count;
        }

        public void QueryNearby(GeoCoordinate center, double radiusMeters, List<uint32> outMmsis)
        {
            mSpatialGrid.QueryNearby(center, radiusMeters, outMmsis);
        }

        public int TrackCount => mTracks.Count;

        public Dictionary<uint32, TrackRecord>.ValueEnumerator Tracks => mTracks.Values;
    }
}
