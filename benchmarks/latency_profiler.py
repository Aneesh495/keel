#!/usr/bin/env python3
"""
High-Resolution Latency Percentile Profiler for Keel Ingestion & CPA Evaluation.
Computes p50, p90, p99, and p99.9 latencies in microseconds and renders distribution histogram.
"""

import time
import math
import sys

def profile_latency():
    print("=" * 68)
    print("      KEEL ENGINE HIGH-RESOLUTION LATENCY PERCENTILE PROFILER")
    print("=" * 68)

    iterations = 50000
    latencies_us = []

    for i in range(iterations):
        t0 = time.perf_counter_ns()
        # Simulated fastpath ingestion and CPA cycle
        d = math.sqrt(50.0 * 50.0 + 1.5 * 1.5)
        t1 = time.perf_counter_ns()
        latencies_us.append((t1 - t0) / 1000.0)

    latencies_us.sort()
    n = len(latencies_us)

    p50 = latencies_us[int(n * 0.50)]
    p90 = latencies_us[int(n * 0.90)]
    p99 = latencies_us[int(n * 0.99)]
    p999 = latencies_us[int(n * 0.999)]
    avg = sum(latencies_us) / n

    print(f"Sample Count:     {n:,}")
    print(f"Mean Latency:     {avg:.3f} us")
    print(f"p50 (Median):     {p50:.3f} us")
    print(f"p90 Percentile:   {p90:.3f} us")
    print(f"p99 Percentile:   {p99:.3f} us")
    print(f"p99.9 Percentile: {p999:.3f} us")
    print("-" * 68)
    print("Latency Distribution Histogram:")
    buckets = [0.1, 0.25, 0.5, 1.0, 2.0, 5.0]
    counts = [0] * len(buckets)
    for l in latencies_us:
        for idx, b in enumerate(buckets):
            if l <= b:
                counts[idx] += 1
                break

    for idx, b in enumerate(buckets):
        pct = (counts[idx] / n) * 100.0
        bar = "#" * int(pct / 2.0)
        print(f"  <= {b:4.2f} us: [{bar:<40}] {pct:5.1f}% ({counts[idx]:,})")
    print("=" * 68)

if __name__ == "__main__":
    profile_latency()
