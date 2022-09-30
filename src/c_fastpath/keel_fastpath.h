#ifndef KEEL_FASTPATH_H
#define KEEL_FASTPATH_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Geodesic coordinate in decimal degrees WGS-84
typedef struct {
    double latitude;
    double longitude;
} keel_geo_coord_t;

// 2D Cartesian vector
typedef struct {
    double x;
    double y;
} keel_vec2_t;

// Dynamic kinematic vessel state
typedef struct {
    uint32_t mmsi;
    keel_geo_coord_t position;
    double speed_knots;
    double course_deg;
    double heading_deg;
    double rate_of_turn;
    uint32_t timestamp_sec;
    uint8_t nav_status;
} keel_vessel_state_t;

// Closest Point of Approach (CPA) result
typedef struct {
    double cpa_distance_m;      // Distance at closest point of approach in meters
    double cpa_distance_nm;     // Distance in nautical miles
    double tcpa_seconds;        // Time to CPA in seconds (negative if diverging)
    bool is_converging;         // True if vessels are closing
    double relative_speed_knots;// Relative closure speed
    double relative_bearing_deg;// Relative bearing from ownship to target
} keel_cpa_result_t;

// 6-bit ASCII Bitstream reader context
typedef struct {
    const uint8_t *payload;
    size_t payload_len;
    size_t bit_offset;
} keel_bitstream_t;

// Initialize bitstream reader
void keel_bitstream_init(keel_bitstream_t *bs, const uint8_t *payload, size_t len);

// Read unsigned bits (up to 32 bits)
uint32_t keel_bitstream_read_u32(keel_bitstream_t *bs, uint8_t num_bits);

// Read signed two's complement bits (up to 32 bits)
int32_t keel_bitstream_read_i32(keel_bitstream_t *bs, uint8_t num_bits);

// Read string from 6-bit ASCII payload into out_str (null-terminated)
void keel_bitstream_read_string(keel_bitstream_t *bs, uint8_t char_count, char *out_str);

// Armored ASCII decoding: decodes NMEA 6-bit ASCII character to 6-bit value (0-63)
uint8_t keel_decode_ascii_6bit(char c);

// NMEA 0183 XOR checksum calculation
uint8_t keel_nmea_checksum(const char *sentence);

// Validates NMEA checksum of format *HH
bool keel_nmea_verify_checksum(const char *sentence);

// Fast haversine great circle distance in meters
double keel_fast_haversine_m(keel_geo_coord_t p1, keel_geo_coord_t p2);

// Fast initial forward bearing in degrees [0, 360)
double keel_fast_bearing_deg(keel_geo_coord_t p1, keel_geo_coord_t p2);

// High-precision WGS-84 Vincenty inverse formula
bool keel_vincenty_inverse(
    keel_geo_coord_t p1,
    keel_geo_coord_t p2,
    double *out_dist_m,
    double *out_bearing_deg
);

// High-precision WGS-84 geodesic direct projection
keel_geo_coord_t keel_project_geodesic(
    keel_geo_coord_t origin,
    double dist_m,
    double bearing_deg
);

// High-performance CPA and TCPA calculation
void keel_compute_cpa(
    const keel_vessel_state_t *ownship,
    const keel_vessel_state_t *target,
    keel_cpa_result_t *out_result
);

// Point in polygon test (Ray-Casting) for S-57 depth areas
bool keel_point_in_polygon(
    keel_geo_coord_t pt,
    const keel_geo_coord_t *poly_vertices,
    size_t num_vertices
);

// SPSC lock-free ring buffer for C fastpath
typedef struct keel_spsc_ring keel_spsc_ring_t;

keel_spsc_ring_t* keel_spsc_create(size_t capacity_pow2, size_t item_size);
void keel_spsc_destroy(keel_spsc_ring_t *ring);
bool keel_spsc_push(keel_spsc_ring_t *ring, const void *item);
bool keel_spsc_pop(keel_spsc_ring_t *ring, void *out_item);
size_t keel_spsc_count(keel_spsc_ring_t *ring);

#ifdef __cplusplus
}
#endif

#endif // KEEL_FASTPATH_H
