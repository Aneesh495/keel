# Keel Operator Manual & VTS Deployment Guide

This guide covers operational deployment, configuration parameters, and administrative monitoring for Vessel Traffic Service (VTS) centers utilizing Keel.

---

## 1. System Requirements & Build Instructions

### Prerequisites:
- Clang (11.0 or newer) or GCC (10.0 or newer)
- Make
- Python 3.8 or newer (for operational tooling)
- POSIX-compliant operating system (macOS or Linux)

### Building the Engine:
```bash
# Build native static library and test harness
make all

# Run the 66-point verification test suite
make test

# Execute micro-benchmark performance suite
make bench
```

---

## 2. Configuration Parameters

The VTS supervisor exposes key operational thresholds:

| Parameter | Default | Units | Description |
|-----------|---------|-------|-------------|
| `WarningCpaNm` | 1.50 | Nautical Miles | CPA distance threshold triggering collision warning |
| `WarningTcpaSec` | 900.0 | Seconds | Time to CPA threshold (15 minutes) for active tracking |
| `TideElevationMeters` | 0.0 | Meters | Astronomical tidal height above Chart Datum |
| `SafetyMarginMeters` | 1.0 | Meters | Minimum Under Keel Clearance safety margin |
| `LookaheadSeconds` | 1200.0 | Seconds | Grounding prediction projection window (20 minutes) |
| `TrackMaxAgeSeconds` | 600 | Seconds | Inactivity timeout before track is purged from registry |

---

## 3. Administrative CLI Reference (`keelctl`)

The `keelctl` administrative CLI manages runtime diagnostics, live track tables, and collision matrices:

### 3.1. Engine Status
```bash
./tools/keelctl status
```
Outputs core runtime diagnostics, loaded cartography layers, and fastpath status.

### 3.2. Active Track Inspection
```bash
./tools/keelctl tracks
```
Displays a tabular list of all active vessel contacts in the sector, including MMSI, vessel name, cargo classification, speed over ground, course over ground, static draught, and navigational status.

### 3.3. CPA Collision Matrix
```bash
./tools/keelctl cpa
```
Calculates pairwise range, CPA distance, TCPA, COLREGs encounter classification, and Collision Risk Index (CRI) for all converging vessel pairs.

### 3.4. Scenario Injection & Conformance
```bash
# Inject synthetic AIS traffic stream
./tools/keelctl simulate

# Execute automated protocol conformance suite
./tools/keelctl verify
```

---

## 4. Real-Time Radar Console (`vts_traffic_monitor.py`)

To launch the real-time plan position indicator (PPI) radar console:
```bash
python3 tools/vts_traffic_monitor.py
```

The console renders:
- Range rings and cardinal bearings centered on the monitored fairway.
- Vessel contacts plotted with velocity vector arrows representing course and speed.
- Dynamic tabular contact logs and immediate emergency alerts for collision or grounding risks.
