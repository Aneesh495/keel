using System;
using Keel.Core;

namespace Keel.Ais
{
    // High-performance encoder and decoder for ITU-R M.1371 maritime AIS payloads.
    public static class AisCodec
    {
        // Decodes a Class A Position Report (Message Types 1, 2, or 3).
        public static bool DecodePositionReportClassA(AisBitStream stream, out AisPositionReportClassA msg)
        {
            msg = default;
            if (stream.RemainingBits < 168)
                return false;

            uint8 type = (uint8)stream.ReadUInt(6);
            uint8 repeat = (uint8)stream.ReadUInt(2);
            uint32 mmsi = stream.ReadUInt(30);
            msg.Header = .(type, repeat, mmsi);

            msg.NavStatus = (NavigationalStatus)stream.ReadUInt(4);
            msg.RateOfTurnRaw = (int16)stream.ReadInt(8);

            uint32 sogRaw = stream.ReadUInt(10);
            msg.SpeedOverGround = (sogRaw < 1023) ? ((double)sogRaw * 0.1) : 0.0;

            msg.PositionAccuracy = stream.ReadBool();

            int32 lonRaw = stream.ReadInt(28);
            int32 latRaw = stream.ReadInt(27);
            double lon = (double)lonRaw / 600000.0;
            double lat = (double)latRaw / 600000.0;
            msg.Position = .(lat, lon);

            uint32 cogRaw = stream.ReadUInt(12);
            msg.CourseOverGround = (cogRaw < 3600) ? ((double)cogRaw * 0.1) : 0.0;

            uint32 hdgRaw = stream.ReadUInt(9);
            msg.TrueHeading = (hdgRaw < 360) ? (double)hdgRaw : msg.CourseOverGround;

            msg.TimeStampSeconds = (uint8)stream.ReadUInt(6);
            msg.ManeuverIndicator = (uint8)stream.ReadUInt(2);
            stream.ReadUInt(3); // spare
            msg.RaimFlag = stream.ReadBool();
            msg.RadioStatus = stream.ReadUInt(19);

            return msg.Position.IsValid();
        }

        // Decodes a Base Station Report (Message Type 4).
        public static bool DecodeBaseStationReport(AisBitStream stream, out AisBaseStationReport msg)
        {
            msg = default;
            if (stream.RemainingBits < 168)
                return false;

            uint8 type = (uint8)stream.ReadUInt(6);
            uint8 repeat = (uint8)stream.ReadUInt(2);
            uint32 mmsi = stream.ReadUInt(30);
            msg.Header = .(type, repeat, mmsi);

            msg.UtcYear = (uint16)stream.ReadUInt(14);
            msg.UtcMonth = (uint8)stream.ReadUInt(4);
            msg.UtcDay = (uint8)stream.ReadUInt(5);
            msg.UtcHour = (uint8)stream.ReadUInt(5);
            msg.UtcMinute = (uint8)stream.ReadUInt(6);
            msg.UtcSecond = (uint8)stream.ReadUInt(6);
            msg.PositionAccuracy = stream.ReadBool();

            int32 lonRaw = stream.ReadInt(28);
            int32 latRaw = stream.ReadInt(27);
            msg.Position = .((double)latRaw / 600000.0, (double)lonRaw / 600000.0);

            msg.EpfdType = (uint8)stream.ReadUInt(4);
            stream.ReadUInt(10); // spare
            msg.RaimFlag = stream.ReadBool();
            msg.RadioStatus = stream.ReadUInt(19);

            return msg.Position.IsValid();
        }

        // Decodes Static and Voyage Related Data (Message Type 5).
        public static bool DecodeStaticVoyageData(AisBitStream stream, out AisStaticVoyageData msg)
        {
            msg = default;
            if (stream.RemainingBits < 420)
                return false;

            uint8 type = (uint8)stream.ReadUInt(6);
            uint8 repeat = (uint8)stream.ReadUInt(2);
            uint32 mmsi = stream.ReadUInt(30);
            msg.Header = .(type, repeat, mmsi);

            msg.AisVersion = (uint8)stream.ReadUInt(2);
            msg.ImoNumber = stream.ReadUInt(30);

            String callSignStr = scope .();
            stream.ReadString(7, callSignStr);
            for (int i = 0; i < Math.Min(7, callSignStr.Length); i++)
                msg.CallSign[i] = callSignStr[i];

            String nameStr = scope .();
            stream.ReadString(20, nameStr);
            for (int i = 0; i < Math.Min(20, nameStr.Length); i++)
                msg.VesselName[i] = nameStr[i];

            msg.ShipCargoType = (ShipType)stream.ReadUInt(8);
            msg.DimensionToBow = (uint16)stream.ReadUInt(9);
            msg.DimensionToStern = (uint16)stream.ReadUInt(9);
            msg.DimensionToPort = (uint8)stream.ReadUInt(6);
            msg.DimensionToStarboard = (uint8)stream.ReadUInt(6);
            msg.EpfdType = (uint8)stream.ReadUInt(4);
            msg.EtaMonth = (uint8)stream.ReadUInt(4);
            msg.EtaDay = (uint8)stream.ReadUInt(5);
            msg.EtaHour = (uint8)stream.ReadUInt(5);
            msg.EtaMinute = (uint8)stream.ReadUInt(6);

            uint32 draughtRaw = stream.ReadUInt(8);
            msg.DraughtMeters = (double)draughtRaw * 0.1;

            String destStr = scope .();
            stream.ReadString(20, destStr);
            for (int i = 0; i < Math.Min(20, destStr.Length); i++)
                msg.Destination[i] = destStr[i];

            return true;
        }

        // Decodes Standard Class B Position Report (Message Type 18).
        public static bool DecodeStandardClassBPosition(AisBitStream stream, out AisStandardClassBPosition msg)
        {
            msg = default;
            if (stream.RemainingBits < 168)
                return false;

            uint8 type = (uint8)stream.ReadUInt(6);
            uint8 repeat = (uint8)stream.ReadUInt(2);
            uint32 mmsi = stream.ReadUInt(30);
            msg.Header = .(type, repeat, mmsi);

            stream.ReadUInt(8); // regional reserved
            uint32 sogRaw = stream.ReadUInt(10);
            msg.SpeedOverGround = (sogRaw < 1023) ? ((double)sogRaw * 0.1) : 0.0;
            msg.PositionAccuracy = stream.ReadBool();

            int32 lonRaw = stream.ReadInt(28);
            int32 latRaw = stream.ReadInt(27);
            msg.Position = .((double)latRaw / 600000.0, (double)lonRaw / 600000.0);

            uint32 cogRaw = stream.ReadUInt(12);
            msg.CourseOverGround = (cogRaw < 3600) ? ((double)cogRaw * 0.1) : 0.0;

            uint32 hdgRaw = stream.ReadUInt(9);
            msg.TrueHeading = (hdgRaw < 360) ? (double)hdgRaw : msg.CourseOverGround;

            msg.TimeStampSeconds = (uint8)stream.ReadUInt(6);
            stream.ReadUInt(2); // regional reserved
            msg.CsUnitFlag = stream.ReadBool();
            msg.DisplayFlag = stream.ReadBool();
            msg.DscFlag = stream.ReadBool();
            msg.BandFlag = stream.ReadBool();
            msg.Message22Flag = stream.ReadBool();
            msg.AssignedMode = stream.ReadBool();
            msg.RaimFlag = stream.ReadBool();
            msg.RadioStatus = stream.ReadUInt(20);

            return msg.Position.IsValid();
        }

        // Decodes Aids to Navigation (AtoN) Report (Message Type 21).
        public static bool DecodeAidsToNavigation(AisBitStream stream, out AisAidsToNavigation msg)
        {
            msg = default;
            if (stream.RemainingBits < 272)
                return false;

            uint8 type = (uint8)stream.ReadUInt(6);
            uint8 repeat = (uint8)stream.ReadUInt(2);
            uint32 mmsi = stream.ReadUInt(30);
            msg.Header = .(type, repeat, mmsi);

            msg.AtoNType = (uint8)stream.ReadUInt(5);

            String nameStr = scope .();
            stream.ReadString(20, nameStr);
            for (int i = 0; i < Math.Min(20, nameStr.Length); i++)
                msg.Name[i] = nameStr[i];

            msg.PositionAccuracy = stream.ReadBool();

            int32 lonRaw = stream.ReadInt(28);
            int32 latRaw = stream.ReadInt(27);
            msg.Position = .((double)latRaw / 600000.0, (double)lonRaw / 600000.0);

            msg.DimensionToBow = (uint16)stream.ReadUInt(9);
            msg.DimensionToStern = (uint16)stream.ReadUInt(9);
            msg.DimensionToPort = (uint8)stream.ReadUInt(6);
            msg.DimensionToStarboard = (uint8)stream.ReadUInt(6);
            msg.EpfdType = (uint8)stream.ReadUInt(4);
            msg.TimeStampSeconds = (uint8)stream.ReadUInt(6);
            msg.OffPositionIndicator = stream.ReadBool();
            stream.ReadUInt(1); // regional reserved
            msg.RaimFlag = stream.ReadBool();
            msg.VirtualAtoNFlag = stream.ReadBool();

            return msg.Position.IsValid();
        }
    }
}
