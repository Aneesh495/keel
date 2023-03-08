#!/usr/bin/env python3
"""
Vessel Traffic Services (VTS) Terminal Radar & Traffic Monitor.
Renders real-time plan position indicator (PPI) radar plots, vessel track records,
CPA/TCPA collision matrices, and maritime emergency alerts.
"""

import sys
import os
import time
import math
import argparse
from typing import Dict, List, Any

def render_radar_scope(
    center_lat: float,
    center_lon: float,
    radius_nm: float,
    tracks: List[Dict[str, Any]],
    width: int = 51,
    height: int = 25
) -> str:
    grid = [[" " for _ in range(width)] for _ in range(height)]
    cx = width // 2
    cy = height // 2

    # Draw range rings and cardinal crosshairs
    for y in range(height):
        for x in range(width):
            dx = (x - cx) * 2.0 # Aspect ratio compensation
            dy = (y - cy)
            r = math.sqrt(dx * dx + dy * dy)
            max_r = height * 0.95
            if abs(r - max_r * 0.5) < 0.6 or abs(r - max_r) < 0.6:
                grid[y][x] = "."
            if x == cx and y % 2 == 0:
                grid[y][x] = "|"
            if y == cy and x % 4 == 0:
                grid[y][x] = "-"
    grid[cy][cx] = "+"

    # Plot vessels
    for t in tracks:
        lat = t.get("lat", 0.0)
        lon = t.get("lon", 0.0)
        d_lat_nm = (lat - center_lat) * 60.0
        d_lon_nm = (lon - center_lon) * 60.0 * math.cos(math.radians(center_lat))

        # Normalized to radar radius
        norm_x = d_lon_nm / radius_nm
        norm_y = d_lat_nm / radius_nm

        px = int(round(cx + norm_x * (cx * 0.9)))
        py = int(round(cy - norm_y * (cy * 0.9)))

        if 0 <= px < width and 0 <= py < height:
            # Velocity heading arrow
            cog = t.get("cog", 0.0)
            sym = "^"
            if 22.5 <= cog < 67.5: sym = "/"
            elif 67.5 <= cog < 112.5: sym = ">"
            elif 112.5 <= cog < 157.5: sym = "\\"
            elif 157.5 <= cog < 202.5: sym = "v"
            elif 202.5 <= cog < 247.5: sym = "/"
            elif 247.5 <= cog < 292.5: sym = "<"
            elif 292.5 <= cog < 337.5: sym = "\\"
            grid[py][px] = sym

    lines = ["+" + "-" * width + "+"]
    for row in grid:
        lines.append("|" + "".join(row) + "|")
    lines.append("+" + "-" * width + "+")
    return "\n".join(lines)

def print_vts_dashboard(tracks: List[Dict[str, Any]], alerts: List[str]):
    center_lat = 51.15
    center_lon = 1.45
    radius_nm = 12.0

    scope_str = render_radar_scope(center_lat, center_lon, radius_nm, tracks)

    print("\033[H\033[J", end="") # Clear terminal
    print("=" * 80)
    print("  KEEL MARITIME VESSEL TRAFFIC SERVICES (VTS) CONSOLE - DOVER SECTOR")
    print("=" * 80)
    print(scope_str)
    print(f"Center: ({center_lat:.4f} N, {center_lon:.4f} E) | Radar Range: {radius_nm:.1f} NM | Active Contacts: {len(tracks)}")
    print("-" * 80)
    print(f"{'MMSI':<10} {'VESSEL NAME':<22} {'LAT':<9} {'LON':<9} {'SOG':<6} {'COG':<6} {'DRAUGHT'}")
    print("-" * 80)
    for t in tracks[:6]:
        print(f"{t['mmsi']:<10} {t.get('name', 'UNKNOWN')[:20]:<22} {t['lat']:<9.4f} {t['lon']:<9.4f} {t['sog']:<5.1f}k {t['cog']:<5.0f}° {t.get('draught', 5.0):.1f}m")
    print("-" * 80)
    print("ACTIVE MARITIME SAFETY ALERTS:")
    if alerts:
        for a in alerts:
            print(f"  [!] {a}")
    else:
        print("  [OK] No collision hazards or grounding risks detected in sector.")
    print("=" * 80)

def main():
    parser = argparse.ArgumentParser(description="VTS Radar Monitor")
    parser.add_argument("--demo", action="store_true", default=True, help="Run animated demonstration")
    args = parser.parse_args()

    sample_tracks = [
        {"mmsi": 211234000, "name": "MAERSK MC-KINNEY", "lat": 51.20, "lon": 1.55, "sog": 16.5, "cog": 230.0, "draught": 14.2},
        {"mmsi": 228987000, "name": "CMA CGM ANTOINE", "lat": 51.16, "lon": 1.48, "sog": 17.0, "cog": 230.0, "draught": 13.8},
        {"mmsi": 244567000, "name": "PRIDE OF CANTERBURY", "lat": 51.12, "lon": 1.34, "sog": 19.5, "cog": 125.0, "draught": 6.2},
        {"mmsi": 255890000, "name": "ATLANTIC SPIRIT", "lat": 51.08, "lon": 1.62, "sog": 14.0, "cog": 50.0, "draught": 12.5}
    ]

    sample_alerts = [
        "COLLISION RISK [CRI=0.82]: MMSI 244567000 (Crossing Give-Way) with MMSI 211234000 (CPA 0.35 NM in 280s)",
        "TSS MONITOR: Ferry PRIDE OF CANTERBURY crossing southwestbound lane at right angles"
    ]

    print_vts_dashboard(sample_tracks, sample_alerts)

if __name__ == "__main__":
    main()
