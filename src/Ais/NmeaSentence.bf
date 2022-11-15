using System;
using System.Collections;

namespace Keel.Ais
{
    // Representation of a single parsed NMEA 0183 AIVDM/AIVDO sentence.
    public struct NmeaSentence
    {
        public StringView TalkerType; // "!AIVDM" or "!AIVDO"
        public int TotalParts;
        public int PartNumber;
        public int SequentialId;
        public char8 Channel; // 'A' or 'B'
        public StringView Payload;
        public int FillBits;
        public uint8 Checksum;
        public bool IsValid;

        // Computes NMEA 0183 XOR checksum over string between '!' and '*'.
        public static uint8 CalculateChecksum(StringView sentence)
        {
            uint8 cs = 0;
            int start = 0;
            if (sentence.Length > 0 && (sentence[0] == '!' || sentence[0] == '$'))
                start = 1;

            for (int i = start; i < sentence.Length; i++)
            {
                char8 c = sentence[i];
                if (c == '*')
                    break;
                cs ^= (uint8)c;
            }
            return cs;
        }

        // Verifies the NMEA checksum at the end of sentence (*HH).
        public static bool VerifyChecksum(StringView sentence)
        {
            int starIdx = sentence.IndexOf('*');
            if (starIdx == -1 || (sentence.Length - starIdx) < 3)
                return false;

            uint8 calc = CalculateChecksum(sentence);
            StringView hexStr = sentence.Substring(starIdx + 1, 2);
            if (uint8.Parse(hexStr, .Hex) case .Ok(let expected))
            {
                return calc == expected;
            }
            return false;
        }

        // Parses a raw NMEA sentence.
        public static bool TryParse(StringView rawLine, out NmeaSentence outSentence)
        {
            outSentence = default;
            if (!VerifyChecksum(rawLine))
                return false;

            int starIdx = rawLine.IndexOf('*');
            StringView content = rawLine.Substring(0, starIdx);

            StringView[8] tokens = default;
            int tokenCount = 0;

            int cursor = 0;
            while (cursor <= content.Length && tokenCount < 8)
            {
                int nextComma = content.IndexOf(',', cursor);
                if (nextComma == -1)
                {
                    tokens[tokenCount++] = content.Substring(cursor);
                    break;
                }
                tokens[tokenCount++] = content.Substring(cursor, nextComma - cursor);
                cursor = nextComma + 1;
            }

            if (tokenCount < 7)
                return false;

            outSentence.TalkerType = tokens[0];
            if (int.Parse(tokens[1]) case .Ok(let tp)) outSentence.TotalParts = tp; else return false;
            if (int.Parse(tokens[2]) case .Ok(let pn)) outSentence.PartNumber = pn; else return false;
            if (tokens[3].Length > 0)
            {
                if (int.Parse(tokens[3]) case .Ok(let seq)) outSentence.SequentialId = seq;
            }
            outSentence.Channel = tokens[4].Length > 0 ? tokens[4][0] : 'A';
            outSentence.Payload = tokens[5];
            if (int.Parse(tokens[6]) case .Ok(let fb)) outSentence.FillBits = fb;

            outSentence.IsValid = true;
            return true;
        }
    }

    // Cache entry for reconstructing multi-part NMEA sentences.
    public class NmeaFragmentReassembler
    {
        private class FragmentEntry
        {
            public int SequentialId;
            public int TotalParts;
            public int ReceivedMask;
            public String[4] PartPayloads = .(new .(), new .(), new .(), new .());
            public int64 LastTimestamp;

            public ~this()
            {
                for (var p in PartPayloads)
                    delete p;
            }
        }

        private Dictionary<int, FragmentEntry> mEntries;

        public this()
        {
            mEntries = new Dictionary<int, FragmentEntry>();
        }

        public ~this()
        {
            for (var kv in mEntries)
                delete kv.value;
            delete mEntries;
        }

        // Ingests an NMEA sentence. If it completes a multi-part payload, returns true and populates outCompletePayload.
        public bool Ingest(in NmeaSentence sentence, String outCompletePayload)
        {
            if (sentence.TotalParts <= 1)
            {
                outCompletePayload.Set(sentence.Payload);
                return true;
            }

            if (sentence.TotalParts > 4 || sentence.PartNumber < 1 || sentence.PartNumber > sentence.TotalParts)
                return false;

            int key = (sentence.SequentialId << 4) | sentence.TotalParts;
            if (!mEntries.TryGetValue(key, var entry))
            {
                entry = new FragmentEntry();
                entry.SequentialId = sentence.SequentialId;
                entry.TotalParts = sentence.TotalParts;
                mEntries[key] = entry;
            }

            entry.PartPayloads[sentence.PartNumber - 1].Set(sentence.Payload);
            entry.ReceivedMask |= (1 << (sentence.PartNumber - 1));

            int fullMask = (1 << sentence.TotalParts) - 1;
            if ((entry.ReceivedMask & fullMask) == fullMask)
            {
                outCompletePayload.Clear();
                for (int i = 0; i < sentence.TotalParts; i++)
                {
                    outCompletePayload.Append(entry.PartPayloads[i]);
                }
                mEntries.Remove(key);
                delete entry;
                return true;
            }

            return false;
        }
    }
}
