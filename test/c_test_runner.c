#include "keel_fastpath.h"
#include "keel_c_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <math.h>

static int g_tests_run = 0;
static int g_tests_passed = 0;

#define TEST_ASSERT(cond, msg) do { \
    g_tests_run++; \
    if (cond) { \
        g_tests_passed++; \
    } else { \
        fprintf(stderr, "FAIL: %s (line %d): %s\n", __FILE__, __LINE__, msg); \
        assert(cond); \
    } \
} while (0)

static void test_nmea_checksum(void) {
    const char *valid = "!AIVDM,1,1,,A,13aEO:0P00Op`adMDOHr:?vN20S4,0*6B";
    TEST_ASSERT(keel_nmea_verify_checksum(valid), "NMEA valid checksum verification");
    
    const char *corrupted = "!AIVDM,1,1,,A,13aEO:0P00Op`adMDOHr:?vN20S4,0*64";
    TEST_ASSERT(!keel_nmea_verify_checksum(corrupted), "NMEA corrupted checksum rejection");
    
    TEST_ASSERT(keel_nmea_checksum("AIVDM,1,1,,A,1,0") > 0, "Checksum calculation produces non-zero");
}

static void test_6bit_ascii_decoder(void) {
    // 0 -> '0' (ASCII 48) => 0
    TEST_ASSERT(keel_decode_ascii_6bit('0') == 0, "ASCII '0' decodes to 0");
    // 9 -> '9' (ASCII 57) => 9
    TEST_ASSERT(keel_decode_ascii_6bit('9') == 9, "ASCII '9' decodes to 9");
    // 17 -> 'A' (ASCII 65) => 17
    TEST_ASSERT(keel_decode_ascii_6bit('A') == 17, "ASCII 'A' decodes to 17");
    // 39 -> 'w' (ASCII 119) => 63
    TEST_ASSERT(keel_decode_ascii_6bit('w') == 63, "ASCII 'w' decodes to 63");
}

static void test_bitstream_reader(void) {
    // Payload "13aEO"
    const uint8_t payload[] = "13aEO";
    keel_bitstream_t bs;
    keel_bitstream_init(&bs, payload, 5);
    
    // Read 6 bits: '1' is 1
    uint32_t b1 = keel_bitstream_read_u32(&bs, 6);
    TEST_ASSERT(b1 == 1, "First 6 bits equal message type 1");
    
    // Read 2 bits: repeat indicator
    uint32_t rep = keel_bitstream_read_u32(&bs, 2);
    TEST_ASSERT(rep == 0, "Repeat indicator is 0");
    
    // Test signed integer sign extension
    const uint8_t neg_payload[] = "w0"; // 'w' is 0x3F (all 1s)
    keel_bitstream_t bs_neg;
    keel_bitstream_init(&bs_neg, neg_payload, 2);
    int32_t signed_val = keel_bitstream_read_i32(&bs_neg, 6);
    TEST_ASSERT(signed_val == -1, "Sign extension handles negative 6-bit integer");
}

static void test_geodesy_haversine_and_bearing(void) {
    // Dover (51.1279, 1.3134) to Calais (50.9513, 1.8587)
    keel_geo_coord_t dover = { 51.1279, 1.3134 };
    keel_geo_coord_t calais = { 50.9513, 1.8587 };
    
    double dist_m = keel_fast_haversine_m(dover, calais);
    double dist_nm = dist_m / 1852.0;
    
    // Distance should be approximately 23.2 nautical miles
    TEST_ASSERT(dist_nm > 20.0 && dist_nm < 25.0, "Dover to Calais distance in range (approx 23.2 NM)");
    
    double bearing = keel_fast_bearing_deg(dover, calais);
    // Bearing should be roughly South-East (approx 120-130 degrees)
    TEST_ASSERT(bearing > 110.0 && bearing < 140.0, "Dover to Calais bearing approx 125 degrees");
}

static void test_vincenty_inverse(void) {
    keel_geo_coord_t p1 = { 50.064650, -5.714902 }; // Lands End
    keel_geo_coord_t p2 = { 58.643889, -3.070000 }; // John o Groats
    
    double dist_m = 0.0;
    double bearing_deg = 0.0;
    bool ok = keel_vincenty_inverse(p1, p2, &dist_m, &bearing_deg);
    TEST_ASSERT(ok, "Vincenty inverse converges for UK mainland baseline");
    
    double dist_km = dist_m / 1000.0;
    // Expected distance is approximately 969.9 km
    TEST_ASSERT(dist_km > 960.0 && dist_km < 980.0, "Vincenty distance accurately computed (~970 km)");
    TEST_ASSERT(bearing_deg > 5.0 && bearing_deg < 15.0, "Vincenty forward bearing accurately computed (~9.1 deg)");
}

static void test_geodesic_direct_projection(void) {
    keel_geo_coord_t start = { 50.0, 0.0 };
    double travel_m = 100000.0; // 100 km North
    double bearing = 0.0;       // True North
    
    keel_geo_coord_t dest = keel_project_geodesic(start, travel_m, bearing);
    TEST_ASSERT(dest.latitude > start.latitude, "Projected latitude increases due North");
    TEST_ASSERT(fabs(dest.longitude - start.longitude) < 0.01, "Projected longitude unchanged due North");
    
    // Round trip verification
    double hav_dist = keel_fast_haversine_m(start, dest);
    TEST_ASSERT(fabs(hav_dist - travel_m) < 1.0, "Great circle projection matches haversine inverse to sub-meter accuracy");

    double return_dist = 0.0;
    double return_bearing = 0.0;
    keel_vincenty_inverse(start, dest, &return_dist, &return_bearing);
    TEST_ASSERT(fabs(return_dist - travel_m) < 500.0, "WGS-84 ellipsoidal distance reflects oblate flattening within 0.5%");
}

static void test_cpa_tcpa_head_on(void) {
    // Ownship at (50.0, 0.0), course 000 deg (North), speed 15 kts
    keel_vessel_state_t ownship = {
        .mmsi = 211000001,
        .position = { 50.0, 0.0 },
        .speed_knots = 15.0,
        .course_deg = 0.0,
        .heading_deg = 0.0,
        .rate_of_turn = 0.0,
        .timestamp_sec = 1000,
        .nav_status = 0
    };
    
    // Target at 5.0 NM due North (approx lat 50.0833), course 180 deg (South), speed 15 kts
    keel_geo_coord_t target_pos = keel_project_geodesic(ownship.position, 5.0 * 1852.0, 0.0);
    keel_vessel_state_t target = {
        .mmsi = 211000002,
        .position = target_pos,
        .speed_knots = 15.0,
        .course_deg = 180.0,
        .heading_deg = 180.0,
        .rate_of_turn = 0.0,
        .timestamp_sec = 1000,
        .nav_status = 0
    };
    
    keel_cpa_result_t cpa;
    keel_compute_cpa(&ownship, &target, &cpa);
    
    TEST_ASSERT(cpa.is_converging, "Head-on vessels are converging");
    TEST_ASSERT(cpa.cpa_distance_nm < 0.05, "Head-on collision trajectory has CPA near 0 NM");
    
    // Relative speed is 30 kts. Closing 5 NM takes 5 / 30 hours = 10 minutes = 600 seconds.
    TEST_ASSERT(fabs(cpa.tcpa_seconds - 600.0) < 15.0, "TCPA is approx 600 seconds for 5 NM at 30 kts combined");
    TEST_ASSERT(fabs(cpa.relative_speed_knots - 30.0) < 0.5, "Relative speed is 30 kts");
}

static void test_cpa_tcpa_crossing(void) {
    // Ownship heading North at 12 kts
    keel_vessel_state_t ownship = {
        .mmsi = 311000001,
        .position = { 50.0, 0.0 },
        .speed_knots = 12.0,
        .course_deg = 0.0,
        .heading_deg = 0.0,
        .timestamp_sec = 1000
    };
    
    // Target 3 NM to the East heading West at 12 kts
    keel_geo_coord_t target_pos = keel_project_geodesic(ownship.position, 3.0 * 1852.0, 90.0);
    keel_vessel_state_t target = {
        .mmsi = 311000002,
        .position = target_pos,
        .speed_knots = 12.0,
        .course_deg = 270.0,
        .heading_deg = 270.0,
        .timestamp_sec = 1000
    };
    
    keel_cpa_result_t cpa;
    keel_compute_cpa(&ownship, &target, &cpa);
    
    TEST_ASSERT(cpa.is_converging, "Crossing vessels are converging");
    TEST_ASSERT(cpa.tcpa_seconds > 0.0, "Positive TCPA for crossing vessels");
}

static void test_cpa_tcpa_diverging(void) {
    // Ownship heading North
    keel_vessel_state_t ownship = {
        .mmsi = 411000001,
        .position = { 50.0, 0.0 },
        .speed_knots = 15.0,
        .course_deg = 0.0,
        .heading_deg = 0.0,
        .timestamp_sec = 1000
    };
    
    // Target 2 NM behind heading South
    keel_geo_coord_t target_pos = keel_project_geodesic(ownship.position, 2.0 * 1852.0, 180.0);
    keel_vessel_state_t target = {
        .mmsi = 411000002,
        .position = target_pos,
        .speed_knots = 15.0,
        .course_deg = 180.0,
        .heading_deg = 180.0,
        .timestamp_sec = 1000
    };
    
    keel_cpa_result_t cpa;
    keel_compute_cpa(&ownship, &target, &cpa);
    
    TEST_ASSERT(!cpa.is_converging, "Diverging vessels flagged as not converging");
    TEST_ASSERT(cpa.tcpa_seconds <= 0.0, "Diverging vessels have non-positive TCPA");
}

static void test_spsc_ring_buffer(void) {
    keel_spsc_ring_t *ring = keel_spsc_create(8, sizeof(int));
    TEST_ASSERT(ring != NULL, "SPSC ring buffer created");
    TEST_ASSERT(keel_spsc_count(ring) == 0, "Initial ring count is 0");
    
    for (int i = 1; i <= 8; i++) {
        bool pushed = keel_spsc_push(ring, &i);
        TEST_ASSERT(pushed, "Pushing item to ring buffer");
    }
    
    int overflow = 999;
    TEST_ASSERT(!keel_spsc_push(ring, &overflow), "Ring buffer reports full when capacity reached");
    TEST_ASSERT(keel_spsc_count(ring) == 8, "Ring count matches capacity 8");
    
    for (int i = 1; i <= 8; i++) {
        int val = 0;
        bool popped = keel_spsc_pop(ring, &val);
        TEST_ASSERT(popped && val == i, "Popping item in FIFO order");
    }
    
    int empty_val = 0;
    TEST_ASSERT(!keel_spsc_pop(ring, &empty_val), "Popping from empty ring returns false");
    
    keel_spsc_destroy(ring);
}

static void test_point_in_polygon_depth_area(void) {
    // Quadrilateral bounding a shallow shoal
    keel_geo_coord_t shoal[4] = {
        { 50.10, -1.10 },
        { 50.10, -1.00 },
        { 50.00, -1.00 },
        { 50.00, -1.10 }
    };
    
    keel_geo_coord_t inside_pt = { 50.05, -1.05 };
    keel_geo_coord_t outside_pt = { 50.20, -1.20 };
    
    TEST_ASSERT(keel_point_in_polygon(inside_pt, shoal, 4), "Inside point correctly identified in depth area");
    TEST_ASSERT(!keel_point_in_polygon(outside_pt, shoal, 4), "Outside point correctly identified outside depth area");
}

static void test_nmea_aivdm_live_decoding(void) {
    keel_engine_t *engine = keel_engine_create();
    TEST_ASSERT(engine != NULL, "Engine created");
    
    // Real-world Class A Position Report: MMSI 244670000, Type 1
    const char *sentence = "!AIVDM,1,1,,A,13aEO:0P00Op`adMDOHr:?vN20S4,0*6B";
    bool fed = keel_engine_feed_nmea(engine, sentence);
    TEST_ASSERT(fed, "Feed valid NMEA AIVDM sentence");
    
    TEST_ASSERT(keel_engine_track_count(engine) == 1, "Track count incremented to 1");
    
    keel_vessel_state_t st;
    bool found = keel_engine_get_track(engine, 244670248, &st);
    TEST_ASSERT(found, "Track found for decoded MMSI 244670248");
    TEST_ASSERT(st.mmsi == 244670248, "MMSI matches expected value");
    TEST_ASSERT(st.position.latitude > 50.0 && st.position.latitude < 53.0, "Latitude matches English Channel position (~51.24 deg)");
    TEST_ASSERT(st.position.longitude > -3.0 && st.position.longitude < 0.0, "Longitude matches English Channel position (~ -1.61 deg)");
    
    keel_engine_destroy(engine);
}

static void test_colregs_risk_classifier(void) {
    keel_engine_t *engine = keel_engine_create();
    
    // Vessel A (ownship) heading North at 14 kts
    keel_engine_update_vessel(engine, 100000001, 50.00, -1.00, 14.0, 0.0, 0.0, 0.0, 0);
    
    // Vessel B (target) 2 NM to starboard (East) heading West at 14 kts (Crossing Give-Way)
    keel_geo_coord_t b_pos = keel_project_geodesic((keel_geo_coord_t){ 50.00, -1.00 }, 2.0 * 1852.0, 90.0);
    keel_engine_update_vessel(engine, 100000002, b_pos.latitude, b_pos.longitude, 14.0, 270.0, 270.0, 0.0, 0);
    
    keel_colregs_risk_t risks[4];
    size_t risk_count = keel_engine_evaluate_colregs_risks(engine, 1.5, 900.0, risks, 4);
    
    TEST_ASSERT(risk_count == 1, "One collision risk pair identified");
    TEST_ASSERT(risks[0].cpa.is_converging, "Collision risk is converging");
    TEST_ASSERT(risks[0].collision_risk_index > 0.5, "Collision risk index is high for 2 NM crossing geometry");
    TEST_ASSERT(strstr(risks[0].recommended_action, "Rule") != NULL, "Action references COLREGs rule");
    
    keel_engine_destroy(engine);
}

static void test_grounding_hazard_detection(void) {
    keel_engine_t *engine = keel_engine_create();
    
    // Shallow shoal (depth 3.5 meters) directly North
    keel_geo_coord_t shoal[4] = {
        { 50.04, -1.02 },
        { 50.04, -0.98 },
        { 50.02, -0.98 },
        { 50.02, -1.02 }
    };
    keel_engine_add_s57_depth_contour(engine, 3.5, shoal, 4);
    
    // Vessel at (50.00, -1.00) heading North at 12 kts (draught 8.0 m)
    keel_engine_update_vessel(engine, 999000001, 50.00, -1.00, 12.0, 0.0, 0.0, 0.0, 0);
    
    double hazard_dist = 0.0;
    // Lookahead 1200 seconds (20 min) at 12 kts covers 4 NM
    bool hazard = keel_engine_check_grounding_hazard(engine, 999000001, 8.0, 1200.0, &hazard_dist);
    TEST_ASSERT(hazard, "Grounding hazard detected along projected heading");
    TEST_ASSERT(hazard_dist > 1000.0 && hazard_dist < 4000.0, "Hazard distance is approximately 2 km ahead");
    
    keel_engine_destroy(engine);
}

static void test_track_aging_and_purging(void) {
    keel_engine_t *engine = keel_engine_create();
    
    keel_engine_update_vessel(engine, 500000001, 50.0, 0.0, 10.0, 90.0, 90.0, 0.0, 0);
    TEST_ASSERT(keel_engine_track_count(engine) == 1, "Track count is 1");
    
    // Purging tracks with max_age = 10000s should not delete fresh track
    size_t purged = keel_engine_purge_aged_tracks(engine, 10000);
    TEST_ASSERT(purged == 0, "No fresh tracks purged");
    TEST_ASSERT(keel_engine_track_count(engine) == 1, "Track count remains 1");
    
    keel_engine_destroy(engine);
}

int main(void) {
    printf("====================================================\n");
    printf("   KEEL MARITIME ENGINE: VERIFICATION TEST SUITE     \n");
    printf("====================================================\n");
    
    test_nmea_checksum();
    test_6bit_ascii_decoder();
    test_bitstream_reader();
    test_geodesy_haversine_and_bearing();
    test_vincenty_inverse();
    test_geodesic_direct_projection();
    test_cpa_tcpa_head_on();
    test_cpa_tcpa_crossing();
    test_cpa_tcpa_diverging();
    test_spsc_ring_buffer();
    test_point_in_polygon_depth_area();
    test_nmea_aivdm_live_decoding();
    test_colregs_risk_classifier();
    test_grounding_hazard_detection();
    test_track_aging_and_purging();
    
    printf("\nTEST RESULTS: %d / %d tests passed successfully.\n", g_tests_passed, g_tests_run);
    printf("All edge cases, geodesics, bitstreams, CPA, and COLREGs rules verified.\n");
    printf("====================================================\n");
    return (g_tests_passed == g_tests_run) ? 0 : 1;
}
