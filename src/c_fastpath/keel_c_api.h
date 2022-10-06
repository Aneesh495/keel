#ifndef KEEL_C_API_H
#define KEEL_C_API_H

#include "keel_fastpath.h"

#ifdef __cplusplus
extern "C" {
#endif

// Opaque Keel Vessel Traffic Management Engine instance
typedef struct keel_engine keel_engine_t;

// COLREGs encounter classification
typedef enum {
    KEEL_ENCOUNTER_NONE = 0,
    KEEL_ENCOUNTER_OVERTAKING = 1,       // Rule 13: Overtaking
    KEEL_ENCOUNTER_HEAD_ON = 2,          // Rule 14: Head-on situation
    KEEL_ENCOUNTER_CROSSING_GIVE_WAY = 3,// Rule 15: Crossing give-way vessel (target on starboard)
    KEEL_ENCOUNTER_CROSSING_STAND_ON = 4 // Rule 15: Crossing stand-on vessel (target on port)
} keel_colregs_encounter_t;

// COLREGs Collision Risk Record
typedef struct {
    uint32_t ownship_mmsi;
    uint32_t target_mmsi;
    keel_cpa_result_t cpa;
    keel_colregs_encounter_t encounter_type;
    double collision_risk_index; // 0.0 (safe) to 1.0 (imminent collision)
    char recommended_action[64]; // Textual recommended evasive maneuver
} keel_colregs_risk_t;

// Creates a new Keel VTS engine instance
keel_engine_t* keel_engine_create(void);

// Destroys a Keel VTS engine instance and releases all associated resources
void keel_engine_destroy(keel_engine_t *engine);

// Ingests a raw NMEA 0183 AIVDM/AIVDO sentence into the engine. Returns true on success.
bool keel_engine_feed_nmea(keel_engine_t *engine, const char *nmea_sentence);

// Ingests raw binary telemetry or direct position update into track registry
bool keel_engine_update_vessel(
    keel_engine_t *engine,
    uint32_t mmsi,
    double lat,
    double lon,
    double speed_knots,
    double course_deg,
    double heading_deg,
    double rot,
    uint8_t nav_status
);

// Returns the total number of actively tracked vessels
size_t keel_engine_track_count(keel_engine_t *engine);

// Retrieves vessel state for a specific MMSI. Returns true if found.
bool keel_engine_get_track(keel_engine_t *engine, uint32_t mmsi, keel_vessel_state_t *out_state);

// Retrieves all active vessel tracks into an array. Returns number of tracks copied.
size_t keel_engine_get_all_tracks(
    keel_engine_t *engine,
    keel_vessel_state_t *out_states,
    size_t max_count
);

// Evaluates pairwise CPA/TCPA between ownship and all targets within range
size_t keel_engine_evaluate_all_cpa(
    keel_engine_t *engine,
    uint32_t ownship_mmsi,
    keel_cpa_result_t *out_cpas,
    uint32_t *out_target_mmsis,
    size_t max_count
);

// Evaluates COLREGs collision risks across all tracked vessels
size_t keel_engine_evaluate_colregs_risks(
    keel_engine_t *engine,
    double warning_cpa_nm,
    double warning_tcpa_sec,
    keel_colregs_risk_t *out_risks,
    size_t max_risks
);

// Adds an S-57 bathymetric depth polygon contour to the spatial chart database
bool keel_engine_add_s57_depth_contour(
    keel_engine_t *engine,
    double depth_meters,
    const keel_geo_coord_t *vertices,
    size_t num_vertices
);

// Evaluates whether a vessel's projected trajectory poses a grounding hazard
bool keel_engine_check_grounding_hazard(
    keel_engine_t *engine,
    uint32_t mmsi,
    double safety_depth_m,
    double lookahead_sec,
    double *out_hazard_distance_m
);

// Removes inactive tracks older than max_age_seconds
size_t keel_engine_purge_aged_tracks(keel_engine_t *engine, uint32_t max_age_seconds);

#ifdef __cplusplus
}
#endif

#endif // KEEL_C_API_H
