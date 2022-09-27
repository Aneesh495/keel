using System;
using System.Collections;

namespace Keel.Core
{
    // High-performance 2D uniform grid spatial index for fast maritime proximity queries.
    public class SpatialGrid2D
    {
        public struct CellCoord
        {
            public int32 X;
            public int32 Y;

            public this(int32 x, int32 y)
            {
                this.X = x;
                this.Y = y;
            }

            public int GetHashCode() => (X * 73856093) ^ (Y * 19349663);
        }

        public struct Entry
        {
            public uint32 Mmsi;
            public GeoCoordinate Position;
            public int32 CellX;
            public int32 CellY;
        }

        private double mCellSizeDegrees;
        private Dictionary<CellCoord, List<uint32>> mBuckets;
        private Dictionary<uint32, Entry> mEntries;

        public this(double cellSizeNauticalMiles = 2.0)
        {
            // Convert nautical miles to approximate degrees latitude
            this.mCellSizeDegrees = cellSizeNauticalMiles / 60.0;
            this.mBuckets = new Dictionary<CellCoord, List<uint32>>();
            this.mEntries = new Dictionary<uint32, Entry>();
        }

        public ~this()
        {
            for (var kv in mBuckets)
            {
                delete kv.value;
            }
            delete mBuckets;
            delete mEntries;
        }

        private CellCoord GetCell(GeoCoordinate coord)
        {
            int32 cx = (int32)Math.Floor(coord.Longitude / mCellSizeDegrees);
            int32 cy = (int32)Math.Floor(coord.Latitude / mCellSizeDegrees);
            return .(cx, cy);
        }

        public void InsertOrUpdate(uint32 mmsi, GeoCoordinate coord)
        {
            CellCoord targetCell = GetCell(coord);

            if (mEntries.TryGetValue(mmsi, var oldEntry))
            {
                if (oldEntry.CellX == targetCell.X && oldEntry.CellY == targetCell.Y)
                {
                    // Position moved within the same cell
                    Entry updated = oldEntry;
                    updated.Position = coord;
                    mEntries[mmsi] = updated;
                    return;
                }

                // Remove from previous cell
                CellCoord oldCell = .(oldEntry.CellX, oldEntry.CellY);
                if (mBuckets.TryGetValue(oldCell, var oldList))
                {
                    oldList.Remove(mmsi);
                }
            }

            // Insert into new cell
            if (!mBuckets.TryGetValue(targetCell, var list))
            {
                list = new List<uint32>();
                mBuckets[targetCell] = list;
            }
            list.Add(mmsi);

            mEntries[mmsi] = Entry()
            {
                Mmsi = mmsi,
                Position = coord,
                CellX = targetCell.X,
                CellY = targetCell.Y
            };
        }

        public void Remove(uint32 mmsi)
        {
            if (mEntries.TryGetValue(mmsi, var entry))
            {
                CellCoord cell = .(entry.CellX, entry.CellY);
                if (mBuckets.TryGetValue(cell, var list))
                {
                    list.Remove(mmsi);
                }
                mEntries.Remove(mmsi);
            }
        }

        // Queries all vessel MMSIs within radiusMeters of queryCoord.
        public void QueryNearby(GeoCoordinate queryCoord, double radiusMeters, List<uint32> results)
        {
            results.Clear();
            double radiusDegrees = (radiusMeters / Geodesy.METERS_PER_NAUTICAL_MILE) / 60.0;
            int cellRadius = (int)Math.Ceiling(radiusDegrees / mCellSizeDegrees);

            CellCoord centerCell = GetCell(queryCoord);

            for (int dy = -cellRadius; dy <= cellRadius; dy++)
            {
                for (int dx = -cellRadius; dx <= cellRadius; dx++)
                {
                    CellCoord c = .(centerCell.X + (int32)dx, centerCell.Y + (int32)dy);
                    if (mBuckets.TryGetValue(c, var list))
                    {
                        for (uint32 mmsi in list)
                        {
                            if (mEntries.TryGetValue(mmsi, var entry))
                            {
                                double distMeters = Geodesy.GreatCircleDistanceMeters(queryCoord, entry.Position);
                                if (distMeters <= radiusMeters)
                                {
                                    results.Add(mmsi);
                                }
                            }
                        }
                    }
                }
            }
        }

        public int TrackedCount => mEntries.Count;
    }
}
