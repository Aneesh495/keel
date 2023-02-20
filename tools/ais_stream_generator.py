#!/usr/bin/env python3
"""
Synthetic AIS Telemetry Stream Generator for Maritime Waterways.
Implements ITU-R M.1371 6-bit ASCII armoring and NMEA 0183 AIVDM framing.
Simulates realistic commercial vessel traffic in the Dover Strait Traffic Separation Scheme.
"""

import sys
import time
import math
import socket
import argparse
from typing import List, Dict, Any

AIS_CHAR_MAP = "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_ !\"#$%&'()*+,-./0123456789:;<=>?"

def encode_6bit_ascii(val: int) -> str:
    v = val & 0x3F
    if v < 40:
        return chr(v + 48)
    else:
        return chr(v + 56)

def calculate_nmea_checksum(sentence: str) -> str:
    cs = 0
    start = 1 if sentence.startswith('!') or sentence.startswith('$') else 0
    for c in sentence[start:]:
        if c == '*':
            break
        cs ^= ord(c)
    return f"{cs:02X}"

class BitWriter:
    def __init__(self):
        self.bits = ""

    def write_uint(self, val: int, num_bits: int):
        val = int(val) & ((1 << num_bits) - 1)
        self.bits += f"{val:0{num_bits}b}"

    def write_int(self, val: int, num_bits: int):
        val = int(val)
        if val < 0:
            val = (1 << num_bits) + val
        val = val & ((1 << num_bits) - 1)
        self.bits += f"{val:0{num_bits}b}"

    def write_string(self, text: str, char_count: int):
        padded = text.upper()[:char_count].ljust(char_count, '@')
        for c in padded:
            idx = AIS_CHAR_MAP.find(c)
            if idx == -1:
                idx = 0
            self.write_uint(idx, 6)

    def to_armored_ascii(self) -> str:
        # Pad to multiple of 6
        pad = (6 - (len(self.bits) % 6)) % 6
        self.bits += "0" * pad
        chars = []
        for i in range(0, len(self.bits), 6):
            chunk = self.bits[i:i+6]
            val = int(chunk, 2)
            chars.append(encode_6bit_ascii(val))
        return "".join(chars)

def build_type1_msg(
    mmsi: int,
    lat: float,
    lon: float,
    sog_knots: float,
    cog_deg: float,
    heading_deg: float,
    nav_status: int = 0
) -> str:
    bw = BitWriter()
    bw.write_uint(1, 6)           # Message Type 1
    bw.write_uint(0, 2)           # Repeat Indicator
    bw.write_uint(mmsi, 30)       # MMSI
    bw.write_uint(nav_status, 4)  # Navigational Status
    bw.write_int(0, 8)            # ROT sensor (-128 to 127)
    
    # SOG in 0.1 knots
    sog_raw = min(1022, int(round(sog_knots * 10.0)))
    bw.write_uint(sog_raw, 10)
    
    bw.write_uint(1, 1)           # Position accuracy (high)
    
    # Longitude in 1/10000 min = degrees * 600000
    lon_raw = int(round(lon * 600000.0))
    bw.write_int(lon_raw, 28)
    
    # Latitude in 1/10000 min = degrees * 600000
    lat_raw = int(round(lat * 600000.0))
    bw.write_int(lat_raw, 27)
    
    # COG in 0.1 deg
    cog_raw = int(round(cog_deg * 10.0)) % 3600
    bw.write_uint(cog_raw, 12)
    
    # Heading in deg
    hdg_raw = int(round(heading_deg)) % 360
    bw.write_uint(hdg_raw, 9)
    
    # Timestamp (seconds 0-59)
    bw.write_uint(int(time.time()) % 60, 6)
    bw.write_uint(0, 2)           # Maneuver indicator
    bw.write_uint(0, 3)           # Spare
    bw.write_uint(0, 1)           # RAIM
    bw.write_uint(0, 19)          # Radio status
    
    armored = bw.to_armored_ascii()
    sentence = f"AIVDM,1,1,,A,{armored},0"
    cs = calculate_nmea_checksum(sentence)
    return f"!{sentence}*{cs}"

def build_type5_msg(
    mmsi: int,
    imo: int,
    callsign: str,
    name: str,
    ship_type: int,
    bow_m: int,
    stern_m: int,
    port_m: int,
    starboard_m: int,
    draught_m: float,
    destination: str
) -> List[str]:
    bw = BitWriter()
    bw.write_uint(5, 6)           # Message Type 5
    bw.write_uint(0, 2)           # Repeat
    bw.write_uint(mmsi, 30)       # MMSI
    bw.write_uint(0, 2)           # AIS Version
    bw.write_uint(imo, 30)        # IMO
    bw.write_string(callsign, 7)  # Call sign (7 chars)
    bw.write_string(name, 20)     # Name (20 chars)
    bw.write_uint(ship_type, 8)   # Ship type
    bw.write_uint(bow_m, 9)       # Bow
    bw.write_uint(stern_m, 9)     # Stern
    bw.write_uint(port_m, 6)      # Port
    bw.write_uint(starboard_m, 6) # Starboard
    bw.write_uint(1, 4)           # EPFD (GPS)
    bw.write_uint(11, 4)          # ETA Month
    bw.write_uint(20, 5)          # ETA Day
    bw.write_uint(14, 5)          # ETA Hour
    bw.write_uint(30, 6)          # ETA Minute
    bw.write_uint(int(round(draught_m * 10.0)), 8) # Draught
    bw.write_string(destination, 20) # Destination
    bw.write_uint(0, 1)           # DTE
    bw.write_uint(0, 1)           # Spare

    armored = bw.to_armored_ascii()
    
    # Split across two NMEA sentences if > 60 characters
    if len(armored) > 60:
        p1 = armored[:60]
        p2 = armored[60:]
        s1 = f"AIVDM,2,1,1,A,{p1},0"
        s2 = f"AIVDM,2,2,1,A,{p2},2"
        return [f"!{s1}*{calculate_nmea_checksum(s1)}", f"!{s2}*{calculate_nmea_checksum(s2)}"]
    else:
        s = f"AIVDM,1,1,,A,{armored},0"
        return [f"!{s}*{calculate_nmea_checksum(s)}"]

DEFAULT_VESSELS = [
    {
        "mmsi": 211234000,
        "imo": 9481234,
        "name": "MAERSK MC-KINNEY",
        "callsign": "OWZW2",
        "type": 70, # Cargo
        "lat": 51.1500,
        "lon": 1.4500,
        "sog": 16.5,
        "cog": 230.0, # SW Lane Dover TSS
        "heading": 230.0,
        "draught": 14.2,
        "status": 0
    },
    {
        "mmsi": 228987000,
        "imo": 9325678,
        "name": "CMA CGM ANTOINE",
        "callsign": "FMAB",
        "type": 70, # Cargo
        "lat": 51.1350,
        "lon": 1.4200,
        "sog": 17.0,
        "cog": 230.0, # SW Lane Dover TSS
        "heading": 230.0,
        "draught": 13.8,
        "status": 0
    },
    {
        "mmsi": 244567000,
        "imo": 9187654,
        "name": "PRIDE OF CANTERBURY",
        "callsign": "MFRY",
        "type": 60, # Passenger Ferry
        "lat": 51.1200,
        "lon": 1.3400,
        "sog": 19.5,
        "cog": 125.0, # Crossing to Calais
        "heading": 125.0,
        "draught": 6.2,
        "status": 0
    },
    {
        "mmsi": 255890000,
        "imo": 9554321,
        "name": "ATLANTIC SPIRIT",
        "callsign": "CQAB",
        "type": 80, # Tanker
        "lat": 51.0800,
        "lon": 1.6200,
        "sog": 14.0,
        "cog": 50.0, # NE Lane Dover TSS
        "heading": 50.0,
        "draught": 12.5,
        "status": 0
    },
    {
        "mmsi": 232123456,
        "imo": 0,
        "name": "DOVER PILOT NO 1",
        "callsign": "MPLT",
        "type": 50, # Pilot vessel
        "lat": 51.1150,
        "lon": 1.3250,
        "sog": 11.0,
        "cog": 85.0,
        "heading": 85.0,
        "draught": 2.8,
        "status": 0
    }
]

def main():
    parser = argparse.ArgumentParser(description="Synthetic AIS Telemetry Stream Generator")
    parser.add_argument("--udp", type=str, default="", help="UDP destination in host:port format (e.g. 127.0.0.1:10110)")
    parser.add_argument("--count", type=int, default=10, help="Number of telemetry cycles to emit (0 for infinite)")
    parser.add_argument("--interval", type=float, default=1.0, help="Interval in seconds between cycles")
    args = parser.parse_args()

    sock = None
    dest_addr = None
    if args.udp:
        host, port_str = args.udp.split(":")
        dest_addr = (host, int(port_str))
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        print(f"[INFO] Broadcasting synthetic AIS telemetry to UDP {dest_addr[0]}:{dest_addr[1]}", file=sys.stderr)

    cycle = 0
    vessels = DEFAULT_VESSELS

    while True:
        cycle += 1
        for v in vessels:
            # Advance position according to speed and course
            dt_hours = args.interval / 3600.0
            dist_nm = v["sog"] * dt_hours
            dist_deg_lat = (dist_nm * math.cos(math.radians(v["cog"]))) / 60.0
            dist_deg_lon = (dist_nm * math.sin(math.radians(v["cog"]))) / (60.0 * math.cos(math.radians(v["lat"])))

            v["lat"] += dist_deg_lat
            v["lon"] += dist_deg_lon

            line1 = build_type1_msg(
                v["mmsi"], v["lat"], v["lon"], v["sog"], v["cog"], v["heading"], v["status"]
            )
            
            if sock and dest_addr:
                sock.sendto((line1 + "\r\n").encode("ascii"), dest_addr)
            else:
                print(line1)

            # Emit Type 5 static data periodically on cycle 1 or every 10 cycles
            if cycle == 1 or cycle % 10 == 0:
                type5_lines = build_type5_msg(
                    v["mmsi"], v["imo"], v["callsign"], v["name"],
                    v["type"], 150, 50, 15, 15, v["draught"], "ROTTERDAM"
                )
                for t5 in type5_lines:
                    if sock and dest_addr:
                        sock.sendto((t5 + "\r\n").encode("ascii"), dest_addr)
                    else:
                        print(t5)

        if args.count > 0 and cycle >= args.count:
            break

        time.sleep(args.interval)

if __name__ == "__main__":
    main()
