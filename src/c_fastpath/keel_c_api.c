#include "keel_c_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

#define MAX_TRACKS 1024
#define MAX_CONTOURS 128
#define MAX_CONTOUR_VERTICES 256

typedef struct {
    double depth_meters;
    keel_geo_coord_t vertices[MAX_CONTOUR_VERTICES];
    size_t num_vertices;
} s57_contour_t;

// Internal reassembly buffer for multi-part NMEA sentences
typedef struct {
    int seq_id;
    int total_parts;
    int received_mask;
    char payload_parts[4][80];
    time_t last_updated;
} nmea_reassembly_entry_t;

struct keel_engine {
    keel_vessel_state_t tracks[MAX_TRACKS];
    bool track_active[MAX_TRACKS];
    size_t track_count;
    
    s57_contour_t contours[MAX_CONTOURS];
    size_t contour_count;
    
    nmea_reassembly_entry_t reassembly[16];
};

static uint32_t get_current_time_sec(void) {
    return (uint32_t)time(NULL);
}

keel_engine_t* keel_engine_create(void) {
    keel_engine_t *engine = (keel_engine_t*)calloc(1, sizeof(keel_engine_t));
    return engine;
}

void keel_engine_destroy(keel_engine_t *engine) {
    if (engine) {
        free(engine);
    }
}

static int find_or_alloc_track_slot(keel_engine_t *engine, uint32_t mmsi) {
    int free_idx = -1;
    for (int i = 0; i < MAX_TRACKS; i++) {
        if (engine->track_active[i] && engine->tracks[i].mmsi == mmsi) {
            return i;
        }
        if (!engine->track_active[i] && free_idx == -1) {
            free_idx = i;
        }
    }
    return free_idx;
}

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
) {
    if (!engine || mmsi == 0) return false;
    
    int slot = find_or_alloc_track_slot(engine, mmsi);
    if (slot == -1) {
        return false; // Table full
    }
    
    if (!engine->track_active[slot]) {
        engine->track_active[slot] = true;
        engine->track_count++;
    }
    
    keel_vessel_state_t *st = &engine->tracks[slot];
    st->mmsi = mmsi;
    st->position.latitude = lat;
    st->position.longitude = lon;
    st->speed_knots = speed_knots;
    st->course_deg = course_deg;
    st->heading_deg = heading_deg;
    st->rate_of_turn = rot;
    st->nav_status = nav_status;
    st->timestamp_sec = get_current_time_sec();
    return true;
}

static bool parse_ais_position_report(keel_engine_t *engine, const char *payload) {
    size_t payload_len = strlen(payload);
    if (payload_len < 28) return false; // Minimum length for 168 bits
    
    keel_bitstream_t bs;
    keel_bitstream_init(&bs, (const uint8_t*)payload, payload_len);
    
    uint32_t msg_type = keel_bitstream_read_u32(&bs, 6);
    if (msg_type != 1 && msg_type != 2 && msg_type != 3 && msg_type != 18) {
        // We handle Class A (1,2,3) and Class B (18) position reports
        return false;
    }
    
    uint32_t repeat = keel_bitstream_read_u32(&bs, 2);
    (void)repeat;
    uint32_t mmsi = keel_bitstream_read_u32(&bs, 30);
    
    uint8_t nav_status = 15;
    double rot = 0.0;
    double sog = 0.0;
    double lon = 0.0;
    double lat = 0.0;
    double cog = 0.0;
    double heading = 511.0;
    
    if (msg_type <= 3) {
        // Class A
        nav_status = (uint8_t)keel_bitstream_read_u32(&bs, 4);
        int32_t rot_raw = keel_bitstream_read_i32(&bs, 8);
        rot = (double)rot_raw;
        uint32_t sog_raw = keel_bitstream_read_u32(&bs, 10);
        sog = (sog_raw < 1023) ? (sog_raw * 0.1) : 0.0;
        
        keel_bitstream_read_u32(&bs, 1); // pos accuracy
        int32_t lon_raw = keel_bitstream_read_i32(&bs, 28);
        int32_t lat_raw = keel_bitstream_read_i32(&bs, 27);
        lon = (double)lon_raw / 600000.0;
        lat = (double)lat_raw / 600000.0;
        
        uint32_t cog_raw = keel_bitstream_read_u32(&bs, 12);
        cog = (cog_raw < 3600) ? (cog_raw * 0.1) : 0.0;
        
        uint32_t hdg_raw = keel_bitstream_read_u32(&bs, 9);
        heading = (hdg_raw < 360) ? (double)hdg_raw : cog;
    } else {
        // Class B (Type 18)
        keel_bitstream_read_u32(&bs, 8); // regional reserved
        uint32_t sog_raw = keel_bitstream_read_u32(&bs, 10);
        sog = (sog_raw < 1023) ? (sog_raw * 0.1) : 0.0;
        
        keel_bitstream_read_u32(&bs, 1); // pos accuracy
        int32_t lon_raw = keel_bitstream_read_i32(&bs, 28);
        int32_t lat_raw = keel_bitstream_read_i32(&bs, 27);
        lon = (double)lon_raw / 600000.0;
        lat = (double)lat_raw / 600000.0;
        
        uint32_t cog_raw = keel_bitstream_read_u32(&bs, 12);
        cog = (cog_raw < 3600) ? (cog_raw * 0.1) : 0.0;
        
        uint32_t hdg_raw = keel_bitstream_read_u32(&bs, 9);
        heading = (hdg_raw < 360) ? (double)hdg_raw : cog;
    }
    
    if (lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0) {
        return keel_engine_update_vessel(engine, mmsi, lat, lon, sog, cog, heading, rot, nav_status);
    }
    return false;
}

bool keel_engine_feed_nmea(keel_engine_t *engine, const char *nmea) {
    if (!engine || !nmea) return false;
    if (!keel_nmea_verify_checksum(nmea)) return false;
    
    // Parse tokens: !AIVDM,total,num,seq,chan,payload,fill*CS
    char buf[256];
    strncpy(buf, nmea, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    
    char *star = strchr(buf, '*');
    if (star) *star = '\0';
    
    char *tokens[10];
    int token_count = 0;
    char *cursor = buf;
    while (cursor && token_count < 10) {
        // Empty fields keep their positions, including the optional sequence ID.
        tokens[token_count++] = cursor;
        char *comma = strchr(cursor, ',');
        if (!comma) break;
        *comma = '\0';
        cursor = comma + 1;
    }
    
    if (token_count < 6) return false;
    
    int total_parts = atoi(tokens[1]);
    int part_num = atoi(tokens[2]);
    const char *payload = tokens[5];
    
    if (total_parts == 1 && part_num == 1) {
        return parse_ais_position_report(engine, payload);
    }
    
    // Multi-part reassembly logic
    if (total_parts > 1 && total_parts <= 4 && part_num >= 1 && part_num <= total_parts) {
        int seq_id = (tokens[3][0] != '\0') ? atoi(tokens[3]) : 0;
        
        // Find or create reassembly slot
        int slot = -1;
        time_t now = time(NULL);
        for (int i = 0; i < 16; i++) {
            if (engine->reassembly[i].seq_id == seq_id && engine->reassembly[i].total_parts == total_parts) {
                if (now - engine->reassembly[i].last_updated < 10) {
                    slot = i;
                    break;
                }
            }
        }
        if (slot == -1) {
            for (int i = 0; i < 16; i++) {
                if (engine->reassembly[i].received_mask == 0 || (now - engine->reassembly[i].last_updated >= 10)) {
                    slot = i;
                    memset(&engine->reassembly[slot], 0, sizeof(nmea_reassembly_entry_t));
                    engine->reassembly[slot].seq_id = seq_id;
                    engine->reassembly[slot].total_parts = total_parts;
                    break;
                }
            }
        }
        if (slot == -1) return false;
        
        nmea_reassembly_entry_t *entry = &engine->reassembly[slot];
        entry->last_updated = now;
        strncpy(entry->payload_parts[part_num - 1], payload, sizeof(entry->payload_parts[0]) - 1);
        entry->received_mask |= (1 << (part_num - 1));
        
        int full_mask = (1 << total_parts) - 1;
        if ((entry->received_mask & full_mask) == full_mask) {
            // Reassembled complete payload
            char combined_payload[320];
            combined_payload[0] = '\0';
            for (int p = 0; p < total_parts; p++) {
                strncat(combined_payload, entry->payload_parts[p], sizeof(combined_payload) - strlen(combined_payload) - 1);
            }
            entry->received_mask = 0; // reset
            return parse_ais_position_report(engine, combined_payload);
        }
        return true;
    }
    
    return false;
}

size_t keel_engine_track_count(keel_engine_t *engine) {
    return engine ? engine->track_count : 0;
}

bool keel_engine_get_track(keel_engine_t *engine, uint32_t mmsi, keel_vessel_state_t *out_state) {
    if (!engine || !out_state || mmsi == 0) return false;
    for (int i = 0; i < MAX_TRACKS; i++) {
        if (engine->track_active[i] && engine->tracks[i].mmsi == mmsi) {
            *out_state = engine->tracks[i];
            return true;
        }
    }
    return false;
}

size_t keel_engine_get_all_tracks(
    keel_engine_t *engine,
    keel_vessel_state_t *out_states,
    size_t max_count
) {
    if (!engine || !out_states || max_count == 0) return 0;
    size_t count = 0;
    for (int i = 0; i < MAX_TRACKS && count < max_count; i++) {
        if (engine->track_active[i]) {
            out_states[count++] = engine->tracks[i];
        }
    }
    return count;
}

size_t keel_engine_evaluate_all_cpa(
    keel_engine_t *engine,
    uint32_t ownship_mmsi,
    keel_cpa_result_t *out_cpas,
    uint32_t *out_target_mmsis,
    size_t max_count
) {
    if (!engine || !out_cpas || !out_target_mmsis || max_count == 0) return 0;
    
    keel_vessel_state_t ownship;
    if (!keel_engine_get_track(engine, ownship_mmsi, &ownship)) {
        return 0;
    }
    
    size_t count = 0;
    for (int i = 0; i < MAX_TRACKS && count < max_count; i++) {
        if (engine->track_active[i] && engine->tracks[i].mmsi != ownship_mmsi) {
            out_target_mmsis[count] = engine->tracks[i].mmsi;
            keel_compute_cpa(&ownship, &engine->tracks[i], &out_cpas[count]);
            count++;
        }
    }
    return count;
}

static keel_colregs_encounter_t classify_encounter(
    const keel_vessel_state_t *own,
    const keel_vessel_state_t *tgt,
    const keel_cpa_result_t *cpa
) {
    double rel_brng = cpa->relative_bearing_deg; // Bearing of target relative to ownship heading
    
    // Target heading relative to ownship heading
    double diff_course = fabs(own->course_deg - tgt->course_deg);
    if (diff_course > 180.0) diff_course = 360.0 - diff_course;
    
    // Rule 13: Overtaking (approaching from more than 22.5 deg abaft the beam, i.e. 112.5 deg to 247.5 deg)
    if (rel_brng > 112.5 && rel_brng < 247.5 && own->speed_knots > tgt->speed_knots) {
        return KEEL_ENCOUNTER_OVERTAKING;
    }
    
    // Rule 14: Head-on (reciprocal or nearly reciprocal courses within 15 deg, meeting ahead within 10 deg)
    if (diff_course > 165.0 && (rel_brng < 15.0 || rel_brng > 345.0)) {
        return KEEL_ENCOUNTER_HEAD_ON;
    }
    
    // Rule 15: Crossing
    if (rel_brng > 5.0 && rel_brng <= 112.5) {
        // Target is to starboard: ownship is GIVE-WAY
        return KEEL_ENCOUNTER_CROSSING_GIVE_WAY;
    } else if (rel_brng >= 247.5 && rel_brng < 355.0) {
        // Target is to port: ownship is STAND-ON
        return KEEL_ENCOUNTER_CROSSING_STAND_ON;
    }
    
    return KEEL_ENCOUNTER_NONE;
}

static double calculate_cri(
    double d_cpa_nm,
    double t_cpa_sec,
    double dist_nm,
    keel_colregs_encounter_t encounter
) {
    if (t_cpa_sec < 0.0) return 0.0; // Diverging
    
    // Weight parameters
    double w_dcpa = 0.40;
    double w_tcpa = 0.35;
    double w_dist = 0.15;
    double w_enc  = 0.10;
    
    // DCPA risk factor: 1.0 when d_cpa <= 0.5 nm, decays to 0.0 at 2.0 nm
    double u_dcpa = 0.0;
    if (d_cpa_nm <= 0.5) u_dcpa = 1.0;
    else if (d_cpa_nm < 2.0) u_dcpa = (2.0 - d_cpa_nm) / 1.5;
    
    // TCPA risk factor: 1.0 when t_cpa <= 300s (5 min), decays to 0.0 at 1200s (20 min)
    double u_tcpa = 0.0;
    if (t_cpa_sec <= 300.0) u_tcpa = 1.0;
    else if (t_cpa_sec < 1200.0) u_tcpa = (1200.0 - t_cpa_sec) / 900.0;
    
    // Distance risk factor: 1.0 when dist <= 1.0 nm, decays to 0.0 at 5.0 nm
    double u_dist = 0.0;
    if (dist_nm <= 1.0) u_dist = 1.0;
    else if (dist_nm < 5.0) u_dist = (5.0 - dist_nm) / 4.0;
    
    // Encounter factor: Crossing give-way and head-on carry higher immediate risk
    double u_enc = 0.5;
    if (encounter == KEEL_ENCOUNTER_CROSSING_GIVE_WAY) u_enc = 1.0;
    else if (encounter == KEEL_ENCOUNTER_HEAD_ON) u_enc = 0.9;
    else if (encounter == KEEL_ENCOUNTER_CROSSING_STAND_ON) u_enc = 0.7;
    else if (encounter == KEEL_ENCOUNTER_OVERTAKING) u_enc = 0.6;
    
    double cri = (w_dcpa * u_dcpa) + (w_tcpa * u_tcpa) + (w_dist * u_dist) + (w_enc * u_enc);
    if (cri > 1.0) cri = 1.0;
    return cri;
}

size_t keel_engine_evaluate_colregs_risks(
    keel_engine_t *engine,
    double warning_cpa_nm,
    double warning_tcpa_sec,
    keel_colregs_risk_t *out_risks,
    size_t max_risks
) {
    if (!engine || !out_risks || max_risks == 0) return 0;
    
    size_t risk_count = 0;
    
    for (int i = 0; i < MAX_TRACKS && risk_count < max_risks; i++) {
        if (!engine->track_active[i]) continue;
        const keel_vessel_state_t *own = &engine->tracks[i];
        
        for (int j = i + 1; j < MAX_TRACKS && risk_count < max_risks; j++) {
            if (!engine->track_active[j]) continue;
            const keel_vessel_state_t *tgt = &engine->tracks[j];
            
            keel_cpa_result_t cpa;
            keel_compute_cpa(own, tgt, &cpa);
            
            if (cpa.is_converging && cpa.cpa_distance_nm <= warning_cpa_nm && cpa.tcpa_seconds <= warning_tcpa_sec) {
                double dist_m = keel_fast_haversine_m(own->position, tgt->position);
                double dist_nm = dist_m / 1852.0;
                keel_colregs_encounter_t enc = classify_encounter(own, tgt, &cpa);
                double cri = calculate_cri(cpa.cpa_distance_nm, cpa.tcpa_seconds, dist_nm, enc);
                
                keel_colregs_risk_t *r = &out_risks[risk_count++];
                r->ownship_mmsi = own->mmsi;
                r->target_mmsi = tgt->mmsi;
                r->cpa = cpa;
                r->encounter_type = enc;
                r->collision_risk_index = cri;
                
                switch (enc) {
                    case KEEL_ENCOUNTER_HEAD_ON:
                        snprintf(r->recommended_action, sizeof(r->recommended_action),
                                 "Rule 14: Alter course to starboard; pass port-to-port");
                        break;
                    case KEEL_ENCOUNTER_CROSSING_GIVE_WAY:
                        snprintf(r->recommended_action, sizeof(r->recommended_action),
                                 "Rule 16: Give-way vessel; alter course to starboard early");
                        break;
                    case KEEL_ENCOUNTER_CROSSING_STAND_ON:
                        snprintf(r->recommended_action, sizeof(r->recommended_action),
                                 "Rule 17: Stand-on vessel; maintain course and speed; monitor");
                        break;
                    case KEEL_ENCOUNTER_OVERTAKING:
                        snprintf(r->recommended_action, sizeof(r->recommended_action),
                                 "Rule 13: Overtaking vessel; keep well clear of overtaken ship");
                        break;
                    default:
                        snprintf(r->recommended_action, sizeof(r->recommended_action),
                                 "Rule 8: Action to avoid collision; maintain radar watch");
                        break;
                }
            }
        }
    }
    return risk_count;
}

bool keel_engine_add_s57_depth_contour(
    keel_engine_t *engine,
    double depth_meters,
    const keel_geo_coord_t *vertices,
    size_t num_vertices
) {
    if (!engine || !vertices || num_vertices < 3 || num_vertices > MAX_CONTOUR_VERTICES) {
        return false;
    }
    if (engine->contour_count >= MAX_CONTOURS) {
        return false;
    }
    
    s57_contour_t *c = &engine->contours[engine->contour_count++];
    c->depth_meters = depth_meters;
    c->num_vertices = num_vertices;
    memcpy(c->vertices, vertices, num_vertices * sizeof(keel_geo_coord_t));
    return true;
}

bool keel_engine_check_grounding_hazard(
    keel_engine_t *engine,
    uint32_t mmsi,
    double safety_depth_m,
    double lookahead_sec,
    double *out_hazard_distance_m
) {
    if (!engine || mmsi == 0) return false;
    
    keel_vessel_state_t st;
    if (!keel_engine_get_track(engine, mmsi, &st)) {
        return false;
    }
    
    double speed_mps = st.speed_knots * (1852.0 / 3600.0);
    double total_dist = speed_mps * lookahead_sec;
    if (total_dist < 10.0) {
        return false; // Stationary or negligible movement
    }
    
    // Sample points every 100 meters along projected path
    double step = 100.0;
    for (double d = step; d <= total_dist; d += step) {
        keel_geo_coord_t proj = keel_project_geodesic(st.position, d, st.course_deg);
        
        for (size_t i = 0; i < engine->contour_count; i++) {
            const s57_contour_t *c = &engine->contours[i];
            if (c->depth_meters < safety_depth_m) {
                if (keel_point_in_polygon(proj, c->vertices, c->num_vertices)) {
                    if (out_hazard_distance_m) {
                        *out_hazard_distance_m = d;
                    }
                    return true;
                }
            }
        }
    }
    return false;
}

size_t keel_engine_purge_aged_tracks(keel_engine_t *engine, uint32_t max_age_seconds) {
    if (!engine) return 0;
    uint32_t now = get_current_time_sec();
    size_t purged = 0;
    
    for (int i = 0; i < MAX_TRACKS; i++) {
        if (engine->track_active[i]) {
            if ((now - engine->tracks[i].timestamp_sec) > max_age_seconds) {
                engine->track_active[i] = false;
                engine->track_count--;
                purged++;
            }
        }
    }
    return purged;
}
