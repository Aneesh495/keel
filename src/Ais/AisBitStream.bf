using System;

namespace Keel.Ais
{
    // Bitstream reader and writer implementing ITU-R M.1371 6-bit ASCII armoring.
    public class AisBitStream
    {
        private uint8* mData;
        private int mLength;
        private int mBitPos;

        private static readonly char[65] sAisCharMap = .(
            '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
            'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_',
            ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '\0'
        );

        public this(StringView payload)
        {
            this.mData = (uint8*)payload.Ptr;
            this.mLength = payload.Length;
            this.mBitPos = 0;
        }

        public this(uint8* data, int length)
        {
            this.mData = data;
            this.mLength = length;
            this.mBitPos = 0;
        }

        // Decodes a single 6-bit ASCII character to integer in range [0, 63].
        public static uint8 Decode6BitAscii(char8 c)
        {
            uint8 u = (uint8)c;
            if (u < 48 || u > 119 || (u > 87 && u < 96))
                return 0;

            uint8 val = (uint8)(u - 48);
            if (val > 40)
                val -= 8;

            return (uint8)(val & 0x3F);
        }

        // Encodes a 6-bit integer [0, 63] to NMEA armored ASCII character.
        public static char8 Encode6BitAscii(uint8 val)
        {
            uint8 v = (uint8)(val & 0x3F);
            if (v < 40)
                return (char8)(v + 48);
            else
                return (char8)(v + 56);
        }

        // Reads up to 32 unsigned bits from current stream position.
        public uint32 ReadUInt(int numBits)
        {
            if (numBits <= 0 || numBits > 32)
                return 0;

            uint32 result = 0;
            for (int i = 0; i < numBits; i++)
            {
                int currentBit = mBitPos + i;
                int charIdx = currentBit / 6;
                int bitWithinChar = 5 - (currentBit % 6);

                if (charIdx >= mLength)
                    return result << (numBits - i);

                uint8 charVal = Decode6BitAscii((char8)mData[charIdx]);
                uint32 bit = (uint32)((charVal >> bitWithinChar) & 1);
                result = (result << 1) | bit;
            }

            mBitPos += numBits;
            return result;
        }

        // Reads up to 32 signed bits with two's complement sign extension.
        public int32 ReadInt(int numBits)
        {
            if (numBits <= 0 || numBits > 32)
                return 0;

            uint32 uval = ReadUInt(numBits);
            if ((uval & (1U << (numBits - 1))) != 0)
            {
                uint32 mask = ~0U << numBits;
                return (int32)(uval | mask);
            }
            return (int32)uval;
        }

        // Reads boolean flag (1 bit).
        public bool ReadBool() => ReadUInt(1) == 1;

        // Reads a 6-bit ASCII encoded string into outString.
        public void ReadString(int charCount, String outString)
        {
            outString.Clear();
            for (int i = 0; i < charCount; i++)
            {
                uint8 val = (uint8)ReadUInt(6);
                char8 c = (char8)sAisCharMap[val & 0x3F];
                if (c == '@')
                    c = ' ';
                outString.Append(c);
            }
            outString.TrimEnd();
        }

        public int BitPosition => mBitPos;
        public int TotalBits => mLength * 6;
        public int RemainingBits => Math.Max(0, (mLength * 6) - mBitPos);

        public void SeekBit(int bitPos)
        {
            mBitPos = Math.Clamp(bitPos, 0, mLength * 6);
        }
    }
}
