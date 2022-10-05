#include "keel_fastpath.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>

#define KEEL_PI 3.14159265358979323846
#define KEEL_DEG_TO_RAD (KEEL_PI / 180.0)
#define KEEL_RAD_TO_DEG (180.0 / KEEL_PI)
#define KEEL_WGS84_A 6378137.0
#define KEEL_WGS84_F (1.0 / 298.257223563)
#define KEEL_WGS84_B 6356752.314245179
#define KEEL_METERS_PER_NM 1852.0

uint8_t keel_decode_ascii_6bit(char c) {
    uint8_t u = (uint8_t)c;
    if (u < 48 || u > 119 || (u > 87 && u < 96)) {
        return 0;
    }
    uint8_t val = (uint8_t)((u - 48) & 0x3F);
    if (val > 40) {
        val = (uint8_t)(val - 8);
    }
    return val;
}

uint8_t keel_nmea_checksum(const char *sentence) {
    if (!sentence) return 0;
    uint8_t cs = 0;
    const char *p = sentence;
    if (*p == '!' || *p == '$') {
        p++;
    }
    while (*p && *p != '*') {
        cs ^= (uint8_t)(*p);
        p++;
    }
    return cs;
}

bool keel_nmea_verify_checksum(const char *sentence) {
    if (!sentence) return false;
    const char *star = strchr(sentence, '*');
    if (!star || strlen(star) < 3) return false;
    
    uint8_t calc_cs = keel_nmea_checksum(sentence);
    char hex[3];
    hex[0] = star[1];
    hex[1] = star[2];
    hex[2] = '\0';
    uint8_t expected_cs = (uint8_t)strtoul(hex, NULL, 16);
    return calc_cs == expected_cs;
}

void keel_bitstream_init(keel_bitstream_t *bs, const uint8_t *payload, size_t len) {
    bs->payload = payload;
    bs->payload_len = len;
    bs->bit_offset = 0;
}

uint32_t keel_bitstream_read_u32(keel_bitstream_t *bs, uint8_t num_bits) {
    if (num_bits == 0 || num_bits > 32) return 0;
    
    uint32_t result = 0;
    for (uint8_t i = 0; i < num_bits; i++) {
        size_t current_bit = bs->bit_offset + i;
        size_t char_idx = current_bit / 6;
        size_t bit_within_char = 5 - (current_bit % 6);
        
        if (char_idx >= bs->payload_len) {
            return result << (num_bits - i);
        }
        
        uint8_t char_val = keel_decode_ascii_6bit((char)bs->payload[char_idx]);
        uint32_t bit = (char_val >> bit_within_char) & 1;
        result = (result << 1) | bit;
    }
    
    bs->bit_offset += num_bits;
    return result;
}

int32_t keel_bitstream_read_i32(keel_bitstream_t *bs, uint8_t num_bits) {
    if (num_bits == 0 || num_bits > 32) return 0;
    uint32_t uval = keel_bitstream_read_u32(bs, num_bits);
    
    // Sign extension for two's complement
    if (uval & (1U << (num_bits - 1))) {
        uint32_t mask = ~0U << num_bits;
        return (int32_t)(uval | mask);
    }
    return (int32_t)uval;
}

static const char kAisCharMap[65] =
    "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_ !\"#$%&'()*+,-./0123456789:;<=>?";

void keel_bitstream_read_string(keel_bitstream_t *bs, uint8_t char_count, char *out_str) {
    for (uint8_t i = 0; i < char_count; i++) {
        uint8_t val = (uint8_t)keel_bitstream_read_u32(bs, 6);
        char c = kAisCharMap[val & 0x3F];
        if (c == '@') {
            c = ' ';
        }
        out_str[i] = c;
    }
    out_str[char_count] = '\0';
    
    // Trim trailing whitespace
    int end = (int)char_count - 1;
    while (end >= 0 && out_str[end] == ' ') {
        out_str[end] = '\0';
        end--;
    }
}

static double normalize_deg(double deg) {
    double res = fmod(deg, 360.0);
    if (res < 0.0) res += 360.0;
    return res;
}

double keel_fast_haversine_m(keel_geo_coord_t p1, keel_geo_coord_t p2) {
    double lat1 = p1.latitude * KEEL_DEG_TO_RAD;
    double lon1 = p1.longitude * KEEL_DEG_TO_RAD;
    double lat2 = p2.latitude * KEEL_DEG_TO_RAD;
    double lon2 = p2.longitude * KEEL_DEG_TO_RAD;
    
    double dlat = lat2 - lat1;
    double dlon = lon2 - lon1;
    
    double s_lat = sin(dlat * 0.5);
    double s_lon = sin(dlon * 0.5);
    
    double a = s_lat * s_lat + cos(lat1) * cos(lat2) * s_lon * s_lon;
    if (a > 1.0) a = 1.0;
    if (a < 0.0) a = 0.0;
    
    double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
    return KEEL_WGS84_A * c;
}

double keel_fast_bearing_deg(keel_geo_coord_t p1, keel_geo_coord_t p2) {
    double lat1 = p1.latitude * KEEL_DEG_TO_RAD;
    double lon1 = p1.longitude * KEEL_DEG_TO_RAD;
    double lat2 = p2.latitude * KEEL_DEG_TO_RAD;
    double lon2 = p2.longitude * KEEL_DEG_TO_RAD;
    
    double dlon = lon2 - lon1;
    double y = sin(dlon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon);
    
    return normalize_deg(atan2(y, x) * KEEL_RAD_TO_DEG);
}

bool keel_vincenty_inverse(
    keel_geo_coord_t p1,
    keel_geo_coord_t p2,
    double *out_dist_m,
    double *out_bearing_deg
) {
    if (fabs(p1.latitude - p2.latitude) < 1e-12 && fabs(p1.longitude - p2.longitude) < 1e-12) {
        if (out_dist_m) *out_dist_m = 0.0;
        if (out_bearing_deg) *out_bearing_deg = 0.0;
        return true;
    }
    
    double phi1 = p1.latitude * KEEL_DEG_TO_RAD;
    double L1 = p1.longitude * KEEL_DEG_TO_RAD;
    double phi2 = p2.latitude * KEEL_DEG_TO_RAD;
    double L2 = p2.longitude * KEEL_DEG_TO_RAD;
    
    double U1 = atan((1.0 - KEEL_WGS84_F) * tan(phi1));
    double U2 = atan((1.0 - KEEL_WGS84_F) * tan(phi2));
    double L = L2 - L1;
    
    double sinU1 = sin(U1), cosU1 = cos(U1);
    double sinU2 = sin(U2), cosU2 = cos(U2);
    
    double lambda = L;
    double lambdaP = 2.0 * KEEL_PI;
    int iterLimit = 100;
    
    double cosSqAlpha = 0.0, sinSigma = 0.0, cos2SigmaM = 0.0, cosSigma = 0.0, sigma = 0.0, sinAlpha = 0.0;
    
    while (fabs(lambda - lambdaP) > 1e-12 && --iterLimit > 0) {
        double sinLambda = sin(lambda);
        double cosLambda = cos(lambda);
        
        sinSigma = sqrt(
            (cosU2 * sinLambda) * (cosU2 * sinLambda) +
            (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda) * (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda)
        );
        
        if (sinSigma == 0.0) {
            if (out_dist_m) *out_dist_m = 0.0;
            if (out_bearing_deg) *out_bearing_deg = 0.0;
            return true;
        }
        
        cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
        sigma = atan2(sinSigma, cosSigma);
        sinAlpha = cosU1 * cosU2 * sinLambda / sinSigma;
        cosSqAlpha = 1.0 - sinAlpha * sinAlpha;
        
        if (cosSqAlpha != 0.0) {
            cos2SigmaM = cosSigma - 2.0 * sinU1 * sinU2 / cosSqAlpha;
        } else {
            cos2SigmaM = 0.0;
        }
        
        double C = (KEEL_WGS84_F / 16.0) * cosSqAlpha * (4.0 + KEEL_WGS84_F * (4.0 - 3.0 * cosSqAlpha));
        lambdaP = lambda;
        lambda = L + (1.0 - C) * KEEL_WGS84_F * sinAlpha *
            (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM)));
    }
    
    if (iterLimit == 0) {
        if (out_dist_m) *out_dist_m = keel_fast_haversine_m(p1, p2);
        if (out_bearing_deg) *out_bearing_deg = keel_fast_bearing_deg(p1, p2);
        return false;
    }
    
    double uSq = cosSqAlpha * (KEEL_WGS84_A * KEEL_WGS84_A - KEEL_WGS84_B * KEEL_WGS84_B) / (KEEL_WGS84_B * KEEL_WGS84_B);
    double A = 1.0 + (uSq / 16384.0) * (4096.0 + uSq * (-768.0 + uSq * (320.0 - 175.0 * uSq)));
    double B = (uSq / 1024.0) * (256.0 + uSq * (-128.0 + uSq * (74.0 - 47.0 * uSq)));
    double deltaSigma = B * sinSigma * (cos2SigmaM + 0.25 * B * (cosSigma * (-1.0 + 2.0 * cos2SigmaM * cos2SigmaM) -
        (B / 6.0) * cos2SigmaM * (-3.0 + 4.0 * sinSigma * sinSigma) * (-3.0 + 4.0 * cos2SigmaM * cos2SigmaM)));
    
    if (out_dist_m) {
        *out_dist_m = KEEL_WGS84_B * A * (sigma - deltaSigma);
    }
    if (out_bearing_deg) {
        double initialBearingRad = atan2(
            cosU2 * sin(lambda),
            cosU1 * sinU2 - sinU1 * cosU2 * cos(lambda)
        );
        *out_bearing_deg = normalize_deg(initialBearingRad * KEEL_RAD_TO_DEG);
    }
    return true;
}

keel_geo_coord_t keel_project_geodesic(
    keel_geo_coord_t origin,
    double dist_m,
    double bearing_deg
) {
    double distRatio = dist_m / KEEL_WGS84_A;
    double brngRad = bearing_deg * KEEL_DEG_TO_RAD;
    
    double lat1 = origin.latitude * KEEL_DEG_TO_RAD;
    double lon1 = origin.longitude * KEEL_DEG_TO_RAD;
    
    double lat2 = asin(
        sin(lat1) * cos(distRatio) +
        cos(lat1) * sin(distRatio) * cos(brngRad)
    );
    
    double lon2 = lon1 + atan2(
        sin(brngRad) * sin(distRatio) * cos(lat1),
        cos(distRatio) - sin(lat1) * sin(lat2)
    );
    
    keel_geo_coord_t res;
    res.latitude = lat2 * KEEL_RAD_TO_DEG;
    res.longitude = normalize_deg(lon2 * KEEL_RAD_TO_DEG);
    if (res.longitude > 180.0) {
        res.longitude -= 360.0;
    }
    return res;
}

void keel_compute_cpa(
    const keel_vessel_state_t *ownship,
    const keel_vessel_state_t *target,
    keel_cpa_result_t *out_result
) {
    if (!ownship || !target || !out_result) return;
    
    // Vector from ownship to target in local Cartesian plane (meters)
    double dist_m = keel_fast_haversine_m(ownship->position, target->position);
    double bearing_deg = keel_fast_bearing_deg(ownship->position, target->position);
    double bearing_rad = bearing_deg * KEEL_DEG_TO_RAD;
    
    // Relative position (target - ownship) in meters: dx = East, dy = North
    double rx = dist_m * sin(bearing_rad);
    double ry = dist_m * cos(bearing_rad);
    
    // Velocities in m/s (1 knot = 1852 m / 3600 s = 0.514444 m/s)
    double k_knots_to_mps = 1852.0 / 3600.0;
    
    double v_own_speed = ownship->speed_knots * k_knots_to_mps;
    double v_own_course = ownship->course_deg * KEEL_DEG_TO_RAD;
    double vox = v_own_speed * sin(v_own_course);
    double voy = v_own_speed * cos(v_own_course);
    
    double v_tgt_speed = target->speed_knots * k_knots_to_mps;
    double v_tgt_course = target->course_deg * KEEL_DEG_TO_RAD;
    double vtx = v_tgt_speed * sin(v_tgt_course);
    double vty = v_tgt_speed * cos(v_tgt_course);
    
    // Relative velocity (target - ownship) in m/s
    double vrx = vtx - vox;
    double vry = vty - voy;
    
    double vr_squared = vrx * vrx + vry * vry;
    double rel_speed_mps = sqrt(vr_squared);
    
    out_result->relative_speed_knots = rel_speed_mps / k_knots_to_mps;
    out_result->relative_bearing_deg = normalize_deg(bearing_deg - ownship->course_deg);
    
    if (vr_squared < 1e-6) {
        // Parallel courses at identical speeds
        out_result->cpa_distance_m = dist_m;
        out_result->cpa_distance_nm = dist_m / KEEL_METERS_PER_NM;
        out_result->tcpa_seconds = 0.0;
        out_result->is_converging = false;
        return;
    }
    
    // Time to CPA: t_cpa = - (r . vr) / |vr|^2
    double r_dot_vr = rx * vrx + ry * vry;
    double tcpa = -r_dot_vr / vr_squared;
    
    out_result->tcpa_seconds = tcpa;
    out_result->is_converging = (tcpa > 0.0);
    
    // Position at CPA
    double cpa_x = rx + vrx * tcpa;
    double cpa_y = ry + vry * tcpa;
    double d_cpa = sqrt(cpa_x * cpa_x + cpa_y * cpa_y);
    
    out_result->cpa_distance_m = d_cpa;
    out_result->cpa_distance_nm = d_cpa / KEEL_METERS_PER_NM;
}

bool keel_point_in_polygon(
    keel_geo_coord_t pt,
    const keel_geo_coord_t *poly,
    size_t n
) {
    if (!poly || n < 3) return false;
    
    bool inside = false;
    for (size_t i = 0, j = n - 1; i < n; j = i++) {
        double xi = poly[i].longitude, yi = poly[i].latitude;
        double xj = poly[j].longitude, yj = poly[j].latitude;
        
        bool intersect = ((yi > pt.latitude) != (yj > pt.latitude)) &&
            (pt.longitude < (xj - xi) * (pt.latitude - yi) / (yj - yi) + xi);
        if (intersect) {
            inside = !inside;
        }
    }
    return inside;
}

// SPSC Ring Buffer Implementation
struct keel_spsc_ring {
    uint8_t *buffer;
    size_t capacity;
    size_t mask;
    size_t item_size;
    _Atomic size_t head;
    _Atomic size_t tail;
};

keel_spsc_ring_t* keel_spsc_create(size_t capacity_pow2, size_t item_size) {
    size_t cap = 1;
    while (cap < capacity_pow2) cap <<= 1;
    
    keel_spsc_ring_t *ring = (keel_spsc_ring_t*)malloc(sizeof(keel_spsc_ring_t));
    if (!ring) return NULL;
    
    ring->buffer = (uint8_t*)malloc(cap * item_size);
    if (!ring->buffer) {
        free(ring);
        return NULL;
    }
    
    ring->capacity = cap;
    ring->mask = cap - 1;
    ring->item_size = item_size;
    atomic_init(&ring->head, 0);
    atomic_init(&ring->tail, 0);
    return ring;
}

void keel_spsc_destroy(keel_spsc_ring_t *ring) {
    if (ring) {
        if (ring->buffer) free(ring->buffer);
        free(ring);
    }
}

bool keel_spsc_push(keel_spsc_ring_t *ring, const void *item) {
    if (!ring || !item) return false;
    size_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
    size_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    
    if ((tail - head) >= ring->capacity) {
        return false; // Full
    }
    
    size_t idx = tail & ring->mask;
    memcpy(ring->buffer + (idx * ring->item_size), item, ring->item_size);
    atomic_store_explicit(&ring->tail, tail + 1, memory_order_release);
    return true;
}

bool keel_spsc_pop(keel_spsc_ring_t *ring, void *out_item) {
    if (!ring || !out_item) return false;
    size_t tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
    size_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    
    if (head >= tail) {
        return false; // Empty
    }
    
    size_t idx = head & ring->mask;
    memcpy(out_item, ring->buffer + (idx * ring->item_size), ring->item_size);
    atomic_store_explicit(&ring->head, head + 1, memory_order_release);
    return true;
}

size_t keel_spsc_count(keel_spsc_ring_t *ring) {
    if (!ring) return 0;
    size_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    size_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    return (tail > head) ? (tail - head) : 0;
}
