using System;
using Keel.Core;
using Keel.Ais;

namespace Keel.Tests
{
    public static class TestAis
    {
        public static void RunTests()
        {
            Console.WriteLine("[TEST] Running AIS Codec and Protocol Tests...");

            // Test 1: Checksum verification
            StringView validSentence = "!AIVDM,1,1,,A,13aEO:0P00Op`adMDOHr:?vN20S4,0*6B";
            Debug.Assert(NmeaSentence.VerifyChecksum(validSentence), "Valid checksum must verify");

            StringView corruptedSentence = "!AIVDM,1,1,,A,13aEO:0P00Op`adMDOHr:?vN20S4,0*65";
            Debug.Assert(!NmeaSentence.VerifyChecksum(corruptedSentence), "Corrupted checksum must be rejected");

            // Test 2: NMEA Sentence Parsing
            bool parsed = NmeaSentence.TryParse(validSentence, let sentence);
            Debug.Assert(parsed, "NMEA sentence parsed successfully");
            Debug.Assert(sentence.TotalParts == 1, "Total parts is 1");
            Debug.Assert(sentence.PartNumber == 1, "Part number is 1");
            Debug.Assert(sentence.Channel == 'A', "Channel is A");
            Debug.Assert(sentence.Payload == "13aEO:0P00Op`adMDOHr:?vN20S4", "Payload matches");

            // Test 3: Bitstream 6-bit ASCII decoding
            Debug.Assert(AisBitStream.Decode6BitAscii('0') == 0, "'0' decodes to 0");
            Debug.Assert(AisBitStream.Decode6BitAscii('W') == 39, "'W' decodes to 39");
            Debug.Assert(AisBitStream.Decode6BitAscii('`') == 40, "'`' decodes to 40");
            Debug.Assert(AisBitStream.Decode6BitAscii('w') == 63, "'w' decodes to 63");

            // Test 4: Message Type 1 Position Report Decoding
            AisBitStream stream = scope .(sentence.Payload);
            bool decoded = AisCodec.DecodePositionReportClassA(stream, let msg);
            Debug.Assert(decoded, "Class A position report decoded");
            Debug.Assert(msg.Header.MessageType == 1, "Message type is 1");
            Debug.Assert(msg.Header.Mmsi == 244670248, "MMSI is 244670248");
            Debug.Assert(msg.Position.Latitude > 50.0 && msg.Position.Latitude < 55.0, "Latitude in expected range");
            Debug.Assert(msg.Position.Longitude > -3.0 && msg.Position.Longitude < 0.0, "Longitude in expected range");

            // Test 5: Multi-sentence reassembler
            NmeaFragmentReassembler reassembler = scope .();
            StringView part1 = "!AIVDM,2,1,3,B,55?73902>80010@F00000000000000000000000000000000000000000000,0*34";
            StringView part2 = "!AIVDM,2,2,3,B,00000000000,2*23";

            String complete = scope .();
            if (NmeaSentence.TryParse(part1, let s1))
            {
                bool done1 = reassembler.Ingest(s1, complete);
                Debug.Assert(!done1, "First part alone should not finish reassembly");
            }
            if (NmeaSentence.TryParse(part2, let s2))
            {
                bool done2 = reassembler.Ingest(s2, complete);
                Debug.Assert(done2, "Second part completes multi-sentence reassembly");
                Debug.Assert(complete.Length > 60, "Combined payload has expected length");
            }

            Console.WriteLine("  -> AIS Codec and Protocol Tests PASSED.");
        }
    }
}
