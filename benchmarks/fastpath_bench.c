#define _POSIX_C_SOURCE 200809L

#include "keel_fastpath.h"
#include "keel_c_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double get_time_sec(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static void bench_haversine(size_t iterations) {
    keel_geo_coord_t p1 = { 50.1234, -1.2345 };
    keel_geo_coord_t p2 = { 50.5678, -1.8901 };
    
    double t0 = get_time_sec();
    double sum = 0.0;
    for (size_t i = 0; i < iterations; i++) {
        p2.latitude = 50.0 + (double)(i % 1000) * 0.001;
        sum += keel_fast_haversine_m(p1, p2);
    }
    double t1 = get_time_sec();
    double elapsed = t1 - t0;
    double mops = ((double)iterations / elapsed) / 1e6;
    printf("[BENCH] Haversine Distance:       %zu ops in %.3f s (%.2f Mops/s, checksum=%.1f)\n",
           iterations, elapsed, mops, sum);
}

static void bench_vincenty(size_t iterations) {
    keel_geo_coord_t p1 = { 50.1234, -1.2345 };
    keel_geo_coord_t p2 = { 51.5678, 0.8901 };
    
    double t0 = get_time_sec();
    double dist = 0.0;
    double bearing = 0.0;
    double sum = 0.0;
    for (size_t i = 0; i < iterations; i++) {
        p2.latitude = 51.0 + (double)(i % 500) * 0.001;
        keel_vincenty_inverse(p1, p2, &dist, &bearing);
        sum += dist;
    }
    double t1 = get_time_sec();
    double elapsed = t1 - t0;
    double mops = ((double)iterations / elapsed) / 1e6;
    printf("[BENCH] Vincenty WGS-84 Geodesic: %zu ops in %.3f s (%.2f Mops/s, checksum=%.1f)\n",
           iterations, elapsed, mops, sum);
}

static void bench_cpa(size_t iterations) {
    keel_vessel_state_t ownship = {
        .mmsi = 100000001,
        .position = { 50.0, 0.0 },
        .speed_knots = 15.0,
        .course_deg = 45.0,
        .heading_deg = 45.0
    };
    keel_vessel_state_t target = {
        .mmsi = 100000002,
        .position = { 50.1, 0.1 },
        .speed_knots = 12.0,
        .course_deg = 225.0,
        .heading_deg = 225.0
    };
    
    keel_cpa_result_t result;
    double t0 = get_time_sec();
    double sum = 0.0;
    for (size_t i = 0; i < iterations; i++) {
        target.position.latitude = 50.05 + (double)(i % 1000) * 0.0001;
        keel_compute_cpa(&ownship, &target, &result);
        sum += result.cpa_distance_m;
    }
    double t1 = get_time_sec();
    double elapsed = t1 - t0;
    double mops = ((double)iterations / elapsed) / 1e6;
    printf("[BENCH] CPA / TCPA Trajectory:    %zu ops in %.3f s (%.2f Mops/s, checksum=%.1f)\n",
           iterations, elapsed, mops, sum);
}

static void bench_nmea_feed(size_t iterations) {
    keel_engine_t *engine = keel_engine_create();
    const char *sentence = "!AIVDM,1,1,,A,13aEO:0P00Op`adMDOHr:?vN20S4,0*6B";
    
    double t0 = get_time_sec();
    for (size_t i = 0; i < iterations; i++) {
        keel_engine_feed_nmea(engine, sentence);
    }
    double t1 = get_time_sec();
    double elapsed = t1 - t0;
    double mops = ((double)iterations / elapsed) / 1e6;
    printf("[BENCH] NMEA 0183 AIVDM Feed:     %zu ops in %.3f s (%.2f M sentences/s, tracks=%zu)\n",
           iterations, elapsed, mops, keel_engine_track_count(engine));
    
    keel_engine_destroy(engine);
}

static void bench_spsc_ring(size_t iterations) {
    keel_spsc_ring_t *ring = keel_spsc_create(1024, sizeof(uint64_t));
    uint64_t val = 42;
    uint64_t out_val = 0;
    
    double t0 = get_time_sec();
    for (size_t i = 0; i < iterations; i++) {
        keel_spsc_push(ring, &val);
        keel_spsc_pop(ring, &out_val);
    }
    double t1 = get_time_sec();
    double elapsed = t1 - t0;
    double mops = ((double)(iterations * 2) / elapsed) / 1e6; // push + pop
    printf("[BENCH] Lock-Free SPSC Ring:      %zu roundtrips in %.3f s (%.2f Mops/s)\n",
           iterations, elapsed, mops);
    
    keel_spsc_destroy(ring);
}

int main(void) {
    printf("====================================================\n");
    printf("   KEEL C FASTPATH PERFORMANCE MICRO-BENCHMARKS     \n");
    printf("====================================================\n");
    
    bench_haversine(5000000);
    bench_vincenty(1000000);
    bench_cpa(5000000);
    bench_nmea_feed(2000000);
    bench_spsc_ring(5000000);
    
    printf("====================================================\n");
    return 0;
}
