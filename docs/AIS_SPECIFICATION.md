# ITU-R M.1371 & IEC 61162 AIS Protocol Specification

This document provides a technical overview of the Automatic Identification System (AIS) VHF Data Link (VDL) wire formats, 6-bit ASCII armoring, and NMEA 0183 AIVDM encapsulation parsed by Keel.

---

## 1. NMEA 0183 AIVDM Sentence Structure

AIS transmissions captured by marine VHF receivers are framed as ASCII sentences following IEC 61162-1 and NMEA 0183 conventions:

```
!AIVDM,count,num,seq,chan,payload,fill*CS<CR><LF>
```

Field Definitions:
1. `!AIVDM`: Talker identifier indicating an AIS VHF data link message received from another station (`!AIVDO` for ownship transmission).
2. `count`: Total number of sentence fragments composing the message (1 to 9).
3. `num`: Sentence fragment number (1 to count).
4. `seq`: Sequential message identifier (0 to 9) used to group multi-sentence parts.
5. `chan`: VHF radio channel: `A` (161.975 MHz) or `B` (162.025 MHz).
6. `payload`: 6-bit ASCII armored binary payload (up to 60 characters per fragment).
7. `fill`: Number of fill bits (0 to 5) added to pad the final 6-bit word to a byte boundary.
8. `*CS`: Two-character hexadecimal XOR checksum calculated over all characters between `!` and `*`.

---

## 2. 6-Bit Armored ASCII Translation Table

The binary payload is packed into 6-bit words (values 0 to 63) and mapped to ASCII characters:
- Values 0 to 39 map to ASCII 48 (`0`) through 87 (`W`).
- Values 40 to 63 map to ASCII 96 (`` ` ``) through 119 (`w`).

| Value | Char | ASCII | Value | Char | ASCII | Value | Char | ASCII | Value | Char | ASCII |
|-------|------|-------|-------|------|-------|-------|------|-------|-------|------|-------|
| 0 | 0 | 48 | 16 | @ | 64 | 32 | P | 80 | 48 | p | 104 |
| 1 | 1 | 49 | 17 | A | 65 | 33 | Q | 81 | 49 | q | 105 |
| 2 | 2 | 50 | 18 | B | 66 | 34 | R | 82 | 50 | r | 106 |
| 3 | 3 | 51 | 19 | C | 67 | 35 | S | 83 | 51 | s | 107 |
| 4 | 4 | 52 | 20 | D | 68 | 36 | T | 84 | 52 | t | 108 |
| 5 | 5 | 53 | 21 | E | 69 | 37 | U | 85 | 53 | u | 109 |
| 6 | 6 | 54 | 22 | F | 70 | 38 | V | 86 | 54 | v | 110 |
| 7 | 7 | 55 | 23 | G | 71 | 39 | W | 87 | 55 | w | 111 |
| 8 | 8 | 56 | 24 | H | 72 | 40 | ` | 96 | 56 | x | 112 |
| 9 | 9 | 57 | 25 | I | 73 | 41 | a | 97 | 57 | y | 113 |
| 10 | : | 58 | 26 | J | 74 | 42 | b | 98 | 58 | z | 114 |
| 11 | ; | 59 | 27 | K | 75 | 43 | c | 99 | 59 | { | 115 |
| 12 | < | 60 | 28 | L | 76 | 44 | d | 100 | 60 | \| | 116 |
| 13 | = | 61 | 29 | M | 77 | 45 | e | 101 | 61 | } | 117 |
| 14 | > | 62 | 30 | N | 78 | 46 | f | 102 | 62 | ~ | 118 |
| 15 | ? | 63 | 31 | O | 79 | 47 | g | 103 | 63 | w | 119 |

---

## 3. Supported ITU-R M.1371 Message Types

Keel implements full bitstream extraction for all standard operational message types:

### 3.1. Class A Position Reports (Types 1, 2, 3)
- Total length: 168 bits.
- Fields:
  - `MessageType` (6 bits): 1 (Scheduled), 2 (Assigned), or 3 (Interrogated).
  - `RepeatIndicator` (2 bits): Broadcast repeat counter (0 to 3).
  - `Mmsi` (30 bits): Maritime Mobile Service Identity.
  - `NavStatus` (4 bits): Navigational status (0 = Engine, 1 = Anchor, 2 = NUC, 5 = Moored, 14 = SART).
  - `RateOfTurn` (8 bits): Signed two's complement rate of turn.
  - `SpeedOverGround` (10 bits): Speed in units of 0.1 knots (0 to 102.2 knots).
  - `PositionAccuracy` (1 bit): 1 = DGPS (<10m), 0 = Standard (>10m).
  - `Longitude` (28 bits): Signed two's complement in $1/10000$ minute ($\pm 180^\circ$).
  - `Latitude` (27 bits): Signed two's complement in $1/10000$ minute ($\pm 90^\circ$).
  - `CourseOverGround` (12 bits): Units of 0.1 degrees ($0.0^\circ$ to $359.9^\circ$).
  - `TrueHeading` (9 bits): Degrees (0 to 359, 511 = not available).
  - `TimeStamp` (6 bits): UTC second when position was generated (0-59).
  - `RadioStatus` (19 bits): SOTDMA communication state.

### 3.2. Static and Voyage Related Data (Type 5)
- Total length: 424 bits (spans 2 NMEA sentences).
- Fields:
  - `ImoNumber` (30 bits): IMO ship identification number.
  - `CallSign` (42 bits): 7 six-bit ASCII characters.
  - `VesselName` (120 bits): 20 six-bit ASCII characters.
  - `ShipType` (8 bits): Numerical cargo and vessel category identifier.
  - `Dimensions` (30 bits): Bow (9 bits), Stern (9 bits), Port (6 bits), Starboard (6 bits) in meters.
  - `Eta` (20 bits): Month (4), Day (5), Hour (5), Minute (6).
  - `Draught` (8 bits): Static draught in units of 0.1 meters.
  - `Destination` (120 bits): 20 six-bit ASCII characters.

### 3.3. Standard Class B Position Report (Type 18)
- Total length: 168 bits.
- Used by leisure vessels, yachts, and smaller commercial craft operating with carrier-sense (CS) transponders.

### 3.4. Aids to Navigation (AtoN) Report (Type 21)
- Total length: 272 to 360 bits.
- Transmits positions of physical and virtual navigational buoys, cardinal beacons, RACON transponders, and lightships. Includes `OffPositionIndicator` to alert mariners if a buoy has dragged its moorings.
