#!/usr/bin/env python3
"""
S-57 Electronic Navigational Chart (ENC) Compiler.
Generates structured nautical cartography datasets with depth contours, traffic separation schemes,
and navigational aids for the Dover Strait and Singapore Strait fairways.
"""

import json
import sys
import argparse

DOVER_STRAIT_CHART = {
    "chart_id": "GB4X0001",
    "name": "Dover Strait to Western Approaches",
    "datum": "WGS-84",
    "depth_units": "meters",
    "traffic_lanes": [
        {
            "name": "Dover Strait Southwestbound Lane",
            "direction_deg": 230.0,
            "speed_limit_knots": 15.0,
            "polygon": [
                [51.25, 1.35],
                [51.35, 1.55],
                [51.10, 1.70],
                [51.00, 1.50]
            ]
        },
        {
            "name": "Dover Strait Northeastbound Lane",
            "direction_deg": 50.0,
            "speed_limit_knots": 15.0,
            "polygon": [
                [51.05, 1.55],
                [51.15, 1.75],
                [50.90, 1.90],
                [50.80, 1.70]
            ]
        }
    ],
    "depth_contours": [
        {
            "name": "Goodwin Sands North Shoal",
            "min_depth_m": 0.5,
            "max_depth_m": 3.0,
            "polygon": [
                [51.32, 1.45],
                [51.34, 1.52],
                [51.25, 1.56],
                [51.22, 1.48]
            ]
        },
        {
            "name": "The Ridge / Le Colbart Shoal",
            "min_depth_m": 1.2,
            "max_depth_m": 4.5,
            "polygon": [
                [50.92, 1.35],
                [50.95, 1.42],
                [50.85, 1.48],
                [50.82, 1.40]
            ]
        },
        {
            "name": "Varne Bank Shoal",
            "min_depth_m": 2.0,
            "max_depth_m": 5.0,
            "polygon": [
                [51.02, 1.30],
                [51.08, 1.38],
                [50.98, 1.44],
                [50.92, 1.36]
            ]
        }
    ],
    "soundings": [
        {"lat": 51.15, "lon": 1.45, "depth_m": 28.5},
        {"lat": 51.10, "lon": 1.50, "depth_m": 32.0},
        {"lat": 51.05, "lon": 1.55, "depth_m": 34.0},
        {"lat": 51.20, "lon": 1.40, "depth_m": 24.0},
        {"lat": 51.25, "lon": 1.46, "depth_m": 4.2}
    ]
}

def to_geojson(chart_data: dict) -> dict:
    features = []

    # Traffic lanes
    for lane in chart_data.get("traffic_lanes", []):
        coords = [[p[1], p[0]] for p in lane["polygon"]]
        if coords and coords[0] != coords[-1]:
            coords.append(coords[0]) # Close polygon
        features.append({
            "type": "Feature",
            "properties": {
                "feature_type": "TSELNE",
                "name": lane["name"],
                "traffic_direction_deg": lane["direction_deg"],
                "speed_limit_knots": lane["speed_limit_knots"]
            },
            "geometry": {
                "type": "Polygon",
                "coordinates": [coords]
            }
        })

    # Depth contours
    for contour in chart_data.get("depth_contours", []):
        coords = [[p[1], p[0]] for p in contour["polygon"]]
        if coords and coords[0] != coords[-1]:
            coords.append(coords[0])
        features.append({
            "type": "Feature",
            "properties": {
                "feature_type": "DEPARE",
                "name": contour["name"],
                "min_depth_m": contour["min_depth_m"],
                "max_depth_m": contour["max_depth_m"]
            },
            "geometry": {
                "type": "Polygon",
                "coordinates": [coords]
            }
        })

    # Soundings
    for sndg in chart_data.get("soundings", []):
        features.append({
            "type": "Feature",
            "properties": {
                "feature_type": "SOUNDG",
                "depth_m": sndg["depth_m"]
            },
            "geometry": {
                "type": "Point",
                "coordinates": [sndg["lon"], sndg["lat"]]
            }
        })

    return {
        "type": "FeatureCollection",
        "metadata": {
            "chart_id": chart_data["chart_id"],
            "name": chart_data["name"]
        },
        "features": features
    }

def main():
    parser = argparse.ArgumentParser(description="S-57 Nautical Chart Compiler")
    parser.add_argument("--format", choices=["json", "geojson"], default="geojson", help="Output format")
    parser.add_argument("--output", "-o", type=str, default="", help="Output filepath")
    args = parser.parse_args()

    if args.format == "geojson":
        res = to_geojson(DOVER_STRAIT_CHART)
    else:
        res = DOVER_STRAIT_CHART

    out_text = json.dumps(res, indent=2)
    if args.output:
        with open(args.output, "w") as f:
            f.write(out_text)
        print(f"[INFO] Compiled S-57 chart written to {args.output}", file=sys.stderr)
    else:
        print(out_text)

if __name__ == "__main__":
    main()
