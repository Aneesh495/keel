#!/usr/bin/env python3
"""
Master Benchmark Orchestrator for Keel Maritime Engine.
Executes C fastpath benchmarks, throughput evaluation, and latency profiling.
"""

import subprocess
import sys
import os

def run_suite():
    script_dir = os.path.dirname(os.path.realpath(__file__))
    root_dir = os.path.dirname(script_dir)
    bench_bin = os.path.join(root_dir, "bin", "fastpath_bench")

    # 1. C Micro-benchmarks
    if os.path.exists(bench_bin):
        subprocess.run([bench_bin])
    else:
        print(f"[WARN] {bench_bin} not found; compiling via make...")
        subprocess.run(["make", "bench"], cwd=root_dir)

    print()
    # 2. Throughput scaling
    throughput_script = os.path.join(script_dir, "throughput_eval.py")
    subprocess.run([sys.executable, throughput_script])

    print()
    # 3. Latency profiling
    latency_script = os.path.join(script_dir, "latency_profiler.py")
    subprocess.run([sys.executable, latency_script])

if __name__ == "__main__":
    run_suite()
