using System;
using System.Collections;
using Keel.Core;

namespace Keel.Nautical
{
    // S-57 Depth Area feature object (DEPARE).
    public class S57DepthArea
    {
        public double DepthRangeMinMeters;
        public double DepthRangeMaxMeters;
        public List<GeoCoordinate> PolygonVertices;
        public BoundingBox2D BoundingBox;

        public this(double minDepth, double maxDepth)
        {
            this.DepthRangeMinMeters = minDepth;
            this.DepthRangeMaxMeters = maxDepth;
            this.PolygonVertices = new List<GeoCoordinate>();
            this.BoundingBox = default;
        }

        public ~this()
        {
            delete PolygonVertices;
        }

        public void AddVertex(GeoCoordinate pt)
        {
            PolygonVertices.Add(pt);
            if (PolygonVertices.Count == 1)
            {
                BoundingBox = .(pt.Latitude, pt.Latitude, pt.Longitude, pt.Longitude);
            }
            else
            {
                BoundingBox.MinLat = Math.Min(BoundingBox.MinLat, pt.Latitude);
                BoundingBox.MaxLat = Math.Max(BoundingBox.MaxLat, pt.Latitude);
                BoundingBox.MinLon = Math.Min(BoundingBox.MinLon, pt.Longitude);
                BoundingBox.MaxLon = Math.Max(BoundingBox.MaxLon, pt.Longitude);
            }
        }

        // Ray-casting point-in-polygon containment test.
        public bool Contains(GeoCoordinate pt)
        {
            if (!BoundingBox.Contains(pt))
                return false;

            bool inside = false;
            int n = PolygonVertices.Count;
            for (int i = 0, j = n - 1; i < n; j = i++)
            {
                double xi = PolygonVertices[i].Longitude, yi = PolygonVertices[i].Latitude;
                double xj = PolygonVertices[j].Longitude, yj = PolygonVertices[j].Latitude;

                bool intersect = ((yi > pt.Latitude) != (yj > pt.Latitude)) &&
                    (pt.Longitude < (xj - xi) * (pt.Latitude - yi) / (yj - yi) + xi);
                if (intersect)
                    inside = !inside;
            }
            return inside;
        }
    }

    // S-57 Depth Sounding point object (SOUNDG).
    public struct S57Sounding
    {
        public GeoCoordinate Position;
        public double DepthMeters;

        public this(GeoCoordinate pos, double depth)
        {
            this.Position = pos;
            this.DepthMeters = depth;
        }
    }

    // S-57 Traffic Separation Scheme Lane (TSELNE).
    public class S57TrafficLane
    {
        public String Name = new .() ~ delete _;
        public double TrafficDirectionDeg; // Designated one-way traffic orientation
        public List<GeoCoordinate> BoundaryPolygon = new .() ~ delete _;
        public double SpeedLimitKnots;     // Fairway speed limit

        public bool Contains(GeoCoordinate pt)
        {
            bool inside = false;
            int n = BoundaryPolygon.Count;
            for (int i = 0, j = n - 1; i < n; j = i++)
            {
                double xi = BoundaryPolygon[i].Longitude, yi = BoundaryPolygon[i].Latitude;
                double xj = BoundaryPolygon[j].Longitude, yj = BoundaryPolygon[j].Latitude;

                bool intersect = ((yi > pt.Latitude) != (yj > pt.Latitude)) &&
                    (pt.Longitude < (xj - xi) * (pt.Latitude - yi) / (yj - yi) + xi);
                if (intersect)
                    inside = !inside;
            }
            return inside;
        }
    }
}
