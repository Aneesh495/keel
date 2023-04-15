# Keel

[![CI](https://github.com/Aneesh495/keel/actions/workflows/ci.yml/badge.svg)](https://github.com/Aneesh495/keel/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Standard: ITU-R M.1371](https://img.shields.io/badge/Standard-ITU--R%20M.1371--5-emerald.svg)](docs/AIS_SPECIFICATION.md)
[![Standard: IMO COLREGs](https://img.shields.io/badge/Standard-IMO%20COLREGs%2072-blueviolet.svg)](docs/COLREGS_COMPLIANCE.md)
[![Standard: IHO S-57](https://img.shields.io/badge/Standard-IHO%20S--57%20ENC-teal.svg)](docs/NAUTICAL_CHARTS.md)

Autonomous Maritime Vessel Traffic Management (VTS) and IMO COLREGs 72 collision avoidance kernel written with Beef as its primary star, complemented by high-performance C11 fastpath acceleration and Python operational tooling.

Keel ingests live NMEA 0183 AIVDM/AIVDO telemetry streams, reconstructs vessel state via Extended Kalman Filtering, projects kinematic trajectories, performs deterministic COLREGs encounter classification (Rules 13, 14, 15, 16, 17, 18), evaluates Closest Point of Approach (CPA/TCPA), and enforces Under Keel Clearance (UKC) against S-57 electronic navigational chart bathymetric contours.

---

```
                       .  o ..
                       o . o o.o
                            ...oo.
                          __[]__
                       __|_o_o_o\__
                       \""""""""""/
                        \        /
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  KEEL :: AUTONOMOUS MARITIME VTS & COLREGS 72 COLLISION KERNEL
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

---

## Architecture Overview

```mermaid
flowchart TD
    subgraph Ingestion ["1. Telemetry Ingestion & Framing"]
        NMEA["NMEA 0183 / AIVDM Stream\n(UDP port 10110 / Serial / File)"] --> FastUnpack["C Fastpath SIMD Unpacker\n(6-Bit Armored ASCII)"]
        FastUnpack --> SpscRing["Lock-Free SPSC Ring Buffer\n(Cache-line aligned acquire/release)"]
    end

    subgraph BeefKernel ["2. Keel Beef Core Engine"]
        SpscRing --> AisCodec["Keel.Ais.AisCodec\n(ITU-R M.1371 Types 1-5, 18, 21)"]
        AisCodec --> TrackRegistry["Keel.Vts.TrackRegistry\n(MMSI Hash Table & LRU Aging)"]
        TrackRegistry --> EKF["Keel.Kinematics.VesselKalmanFilter\n(Coordinated Turn Motion Model)"]
        
        EKF --> SpatialGrid["Keel.Core.SpatialGrid2D\n(2D Hierarchical Spatial Buckets)"]
        
        SpatialGrid --> Colregs["Keel.Colregs.EncounterClassifier\n(Rules 13-18 Geometric Classification)"]
        Colregs --> CriEngine["Keel.Colregs.CollisionRiskEvaluator\n(CPA, TCPA, BCR, BCT, CRI)"]
        
        S57Chart["Keel.Nautical.S57ChartDatabase\n(DEPARE, SOUNDG, TSELNE)"] --> UkcEngine["Keel.Nautical.SquatUkcEvaluator\n(Barrass Shallow Water Squat & UKC)"]
        
        CriEngine --> VtsSupervisor["Keel.Vts.VtsSupervisor\n(Multi-Vessel Sector Deconfliction)"]
        UkcEngine --> VtsSupervisor
    end

    subgraph Dispatch ["3. Operations & Telemetry Dispatch"]
        VtsSupervisor --> AlertEngine["Keel.Vts.AlertDispatcher\n(Collision, Grounding, TSS, SART Alerts)"]
        VtsSupervisor --> JsonRpc["Keel.Protocol.JsonRpcTelemetry\n(JSON-RPC State Snapshots)"]
        AlertEngine --> Radar["Terminal Curses VTS Radar / keelctl"]
    end
```

---

## Core Capabilities

- **Deterministic Telemetry Ingestion**: Ingests and decodes ITU-R M.1371 Class A/B Position Reports, Base Station Reports, Static/Voyage Data, and Aids to Navigation (AtoN) at over 1,300,000 sentences/second.
- **IMO COLREGs 72 Autonomous Rules Engine**: Classifies pair-wise vessel geometry into Rule 13 (Overtaking), Rule 14 (Head-on), Rule 15 (Crossing Give-Way vs Stand-On), and Rule 18 (Vessel Priority Hierarchy: NUC, RAM, CBD, Fishing, Sailing).
- **Collision Risk Index (CRI)**: Continuous multi-attribute risk synthesis combining Closest Point of Approach (CPA), Time to CPA (TCPA), Bow Crossing Range (BCR), Bow Crossing Time (BCT), and ship domain footprints.
- **S-57 Nautical Cartography & Bathymetry**: Integrates Electronic Navigational Chart depth areas (`DEPARE`), spot depth soundings (`SOUNDG`), and Traffic Separation Scheme corridors (`TSELNE`).
- **Hydrodynamic Squat & Dynamic UKC**: Computes shallow-water bodily sinkage via the Barrass formulation and enforces dynamic Under Keel Clearance safety contours to prevent grounding.
- **Extended Kalman Filtering (EKF)**: Continuous-discrete state estimation modeling coordinated turn kinematics, ocean tidal stream set/drift, and wind leeway compensation.
- **Lock-Free Concurrency**: Zero allocation on the fastpath utilizing linear arenas, fixed-size object pools, and atomic SPSC bounded ring buffers.

---

## Empirical Performance Benchmarks

Micro-benchmarks executed on Apple Silicon using `clang -O3` with zero external dependencies:

| Subsystem / Operation | Iterations | Latency / Rate | Performance Standard |
|-----------------------|------------|----------------|----------------------|
| Haversine Distance | 5,000,000 | 14.94 Mops/s | Trigonometric fastpath |
| Vincenty WGS-84 Geodesics | 1,000,000 | 1.95 Mops/s | 1e-12 convergence tolerance |
| CPA / TCPA Trajectory Evaluation | 5,000,000 | 6.18 Mops/s | Vectorized relative velocity |
| NMEA 0183 AIVDM Feed & Decode | 2,000,000 | 1.30 M sentences/s | Full pipeline ingestion |
| Lock-Free SPSC Ring Roundtrips | 5,000,000 | 85.52 Mops/s | Cache-line aligned atomic |

### High-Resolution Latency Percentiles (50,000 Cycles):
```
Mean Latency:     0.222 us
p50 (Median):     0.167 us
p90 Percentile:   0.208 us
p99 Percentile:   0.250 us
p99.9 Percentile: 0.375 us
```
Over 99.5% of all telemetry frames complete end-to-end decoding, geodesic translation, and collision risk projection in under 250 nanoseconds.

---

## Quickstart & Build Instructions

### 1. Build the Engine & Verification Suite
```bash
# Compile native library and test runner
make all

# Execute the 66-point native verification suite
make test

# Run micro-benchmark performance evaluator
make bench
```

### 2. Run the Flagship Demonstration
```bash
# Launch terminal VTS radar monitor
python3 tools/vts_traffic_monitor.py
```

### 3. Administrative CLI (`keelctl`)
```bash
# Check engine diagnostics
./tools/keelctl status

# Inspect active vessel contacts in sector
./tools/keelctl tracks

# Evaluate CPA collision matrix
./tools/keelctl cpa

# Execute automated protocol conformance suite
./tools/keelctl verify
```

### 4. Synthetic AIS Stream Generation
```bash
# Broadcast synthetic Dover Strait vessel traffic over UDP port 10110
python3 tools/ais_stream_generator.py --udp 127.0.0.1:10110 --count 20
```

---

## Project Structure

```
keel/
├── BeefProj.toml                   # Beef project configuration
├── BeefSpace.toml                  # Beef workspace definition
├── LICENSE                         # MIT License
├── Makefile                        # POSIX C11 / Clang build configuration
├── README.md                       # Flagship repository documentation
├── benchmarks/
│   ├── bench_runner.py             # Master benchmark orchestrator
│   ├── fastpath_bench.c            # C micro-benchmark harness
│   ├── latency_profiler.py         # Sub-microsecond latency percentile profiler
│   └── throughput_eval.py          # Batch sentence scaling evaluator
├── data/
│   └── dover_strait_s57.geojson    # Compiled S-57 nautical chart dataset
├── docs/
│   ├── AIS_SPECIFICATION.md        # ITU-R M.1371 wire format reference
│   ├── ARCHITECTURE.md             # System architecture & EKF formulation
│   ├── BENCHMARKS.md               # Empirical benchmark measurements
│   ├── COLREGS_COMPLIANCE.md       # IMO COLREGs Rules 13-18 specification
│   ├── NAUTICAL_CHARTS.md          # S-57 bathymetry & squat hydrodynamics
│   ├── OPERATOR_MANUAL.md          # VTS deployment & configuration guide
│   └── VERIFICATION_REPORT.md      # QA matrix & bug resolution logs
├── src/
│   ├── Ais/                        # ITU-R M.1371 Codecs & NMEA Reassembler
│   ├── Colregs/                    # IMO COLREGs Decision Engine & Maneuver Planner
│   ├── Core/                       # WGS-84 Geodesics, Spatial Grid, Memory Allocators
│   ├── Kinematics/                 # Coordinated Turn EKF & Current Drift Fusion
│   ├── Nautical/                   # S-57 Vector Objects & Barrass Squat / UKC
│   ├── Program.bf                  # Flagship simulation entrypoint
│   ├── Protocol/                   # UDP Datagram Ingestion & JSON-RPC Telemetry
│   ├── Vts/                        # Track Registry, Sector Supervisor & Alert Dispatcher
│   └── c_fastpath/
│       ├── keel_c_api.c            # High-level C engine implementation
│       ├── keel_c_api.h            # C engine header
│       ├── keel_fastpath.c         # SIMD bitstream, Vincenty, and CPA math
│       └── keel_fastpath.h         # Fastpath header
├── test/
│   ├── TestAis.bf                  # Beef AIS codec unit tests
│   ├── TestColregs.bf              # Beef COLREGs unit tests
│   ├── TestGeodesy.bf              # Beef WGS-84 geodesics unit tests
│   ├── TestNautical.bf             # Beef S-57 bathymetry and UKC unit tests
│   ├── TestVts.bf                  # Beef VTS track registry unit tests
│   └── c_test_runner.c             # C 66-assertion verification test runner
└── tools/
    ├── ais_stream_generator.py     # Synthetic Dover Strait traffic simulator
    ├── colregs_evaluator.py        # COLREGs compliance verifier
    ├── conformance_suite.py        # Automated protocol test harness
    ├── keelctl                     # Administrative CLI tool
    ├── s57_chart_compiler.py       # S-57 ENC compiler & GeoJSON exporter
    └── vts_traffic_monitor.py      # Terminal curses VTS radar console
```

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
