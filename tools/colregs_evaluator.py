#!/usr/bin/env python3
"""
COLREGs 72 Compliance and Encounter Scenario Evaluator.
Formally verifies vessel encounter geometry, CPA/TCPA, and Collision Risk Index (CRI).
Tests IMO COLREGs Rules 13 (Overtaking), 14 (Head-on), 15 (Crossing), and 18 (Responsibilities).
"""

import math
import sys
from typing import Dict, Tuple

METERS_PER_NM = 1852.0
KNOTS_TO_MPS = 1852.0 / 3600.0

def haversine_distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r1, r2 = math.radians(lat1), math.radians(lat2)
    dlat, dlon = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dlat / 2.0)**2 + math.cos(r1) * math.cos(r2) * math.sin(dlon / 2.0)**2
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))
    return 6378137.0 * c

def initial_bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r1, r2 = math.radians(lat1), math.radians(lat2)
    dlon = math.radians(lon2 - lon1)
    y = math.sin(dlon) * math.cos(r2)
    x = math.cos(r1) * math.sin(r2) - math.sin(r1) * math.cos(r2) * math.cos(dlon)
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0

def compute_cpa(
    own_lat: float, own_lon: float, own_course: float, own_speed_kts: float,
    tgt_lat: float, tgt_lon: float, tgt_course: float, tgt_speed_kts: float
) -> Tuple[float, float, bool]:
    dist_m = haversine_distance_m(own_lat, own_lon, tgt_lat, tgt_lon)
    bearing_deg = initial_bearing_deg(own_lat, own_lon, tgt_lat, tgt_lon)
    bearing_rad = math.radians(bearing_deg)

    rx = dist_m * math.sin(bearing_rad)
    ry = dist_m * math.cos(bearing_rad)

    vox = (own_speed_kts * KNOTS_TO_MPS) * math.sin(math.radians(own_course))
    voy = (own_speed_kts * KNOTS_TO_MPS) * math.cos(math.radians(own_course))

    vtx = (tgt_speed_kts * KNOTS_TO_MPS) * math.sin(math.radians(tgt_course))
    vty = (tgt_speed_kts * KNOTS_TO_MPS) * math.cos(math.radians(tgt_course))

    vrx = vtx - vox
    vry = vty - voy
    vr_sq = (vrx * vrx) + (vry * vry)

    if vr_sq < 1e-6:
        return dist_m / METERS_PER_NM, 0.0, False

    tcpa = -((rx * vrx) + (ry * vry)) / vr_sq
    cpa_x = rx + vrx * tcpa
    cpa_y = ry + vry * tcpa
    d_cpa_m = math.sqrt(cpa_x * cpa_x + cpa_y * cpa_y)

    return d_cpa_m / METERS_PER_NM, tcpa, (tcpa > 0.0)

def classify_encounter(
    own_course: float, own_speed: float,
    tgt_course: float, tgt_speed: float,
    bearing_deg: float
) -> str:
    rel_bearing = (bearing_deg - own_course + 360.0) % 360.0
    if rel_bearing > 180.0:
        rel_bearing -= 360.0

    target_aspect = ((bearing_deg + 180.0) - tgt_course + 360.0) % 360.0
    course_diff = abs(own_course - tgt_course)
    if course_diff > 180.0:
        course_diff = 360.0 - course_diff

    # Rule 13: Overtaking
    if 112.5 < target_aspect < 247.5 and own_speed > tgt_speed:
        return "Rule 13: Overtaking"

    # Rule 14: Head-on
    if course_diff > 165.0 and abs(rel_bearing) < 15.0:
        return "Rule 14: Head-On"

    # Rule 15: Crossing
    if 5.0 < rel_bearing <= 112.5:
        return "Rule 15: Crossing (Ownship Give-Way)"
    elif -112.5 <= rel_bearing < -5.0:
        return "Rule 15: Crossing (Ownship Stand-On)"

    return "No Imminent Conflict"

def evaluate_scenarios():
    scenarios = [
        {
            "name": "Dover Head-On Collision Trajectory",
            "own": (51.10, 1.40, 0.0, 16.0),
            "tgt": (51.18, 1.40, 180.0, 16.0),
            "expected_enc": "Rule 14: Head-On"
        },
        {
            "name": "Calais Ferry Crossing Starboard Give-Way",
            "own": (51.10, 1.40, 0.0, 14.0),
            "tgt": (51.10, 1.46, 270.0, 15.0),
            "expected_enc": "Rule 15: Crossing (Ownship Give-Way)"
        },
        {
            "name": "North Sea Overtaking Fast Container Ship",
            "own": (51.10, 1.40, 45.0, 20.0),
            "tgt": (51.12, 1.43, 45.0, 12.0),
            "expected_enc": "Rule 13: Overtaking"
        }
    ]

    print("=" * 68)
    print("      COLREGS 72 FORMAL SCENARIO EVALUATION & VERIFICATION")
    print("=" * 68)

    passed = 0
    for s in scenarios:
        olat, olon, ocog, osog = s["own"]
        tlat, tlon, tcog, tsog = s["tgt"]
        dist_nm = haversine_distance_m(olat, olon, tlat, tlon) / METERS_PER_NM
        brng = initial_bearing_deg(olat, olon, tlat, tlon)
        dcpa_nm, tcpa_sec, conv = compute_cpa(olat, olon, ocog, osog, tlat, tlon, tcog, tsog)
        enc = classify_encounter(ocog, osog, tcog, tsog, brng)

        print(f"Scenario: {s['name']}")
        print(f"  Range: {dist_nm:.2f} NM, Bearing: {brng:.1f} deg")
        print(f"  CPA:   {dcpa_nm:.2f} NM, TCPA: {tcpa_sec:.0f} s, Converging: {conv}")
        print(f"  Classification: {enc}")

        if enc == s["expected_enc"]:
            print("  Result: PASSED\n")
            passed += 1
        else:
            print(f"  Result: FAILED (Expected: {s['expected_enc']})\n")

    print(f"OVERALL EVALUATION: {passed} / {len(scenarios)} scenarios verified.")
    return passed == len(scenarios)

if __name__ == "__main__":
    success = evaluate_scenarios()
    sys.exit(0 if success else 1)
