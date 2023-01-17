using System;
using System.Collections;
using Keel.Core;
using Keel.Ais;
using Keel.Colregs;
using Keel.Nautical;

namespace Keel.Vts
{
    public class VtsSupervisor
    {
        private TrackRegistry mRegistry = new .() ~ delete _;
        private AlertDispatcher mAlerts = new .() ~ delete _;
        private S57ChartDatabase mChart = new .() ~ delete _;
        private NmeaFragmentReassembler mReassembler = new .() ~ delete _;

        public double WarningCpaNm = 1.5;
        public double WarningTcpaSec = 900.0;
        public double TideElevationMeters = 0.0;
        public int64 CurrentTimeSec = 0;

        public TrackRegistry Registry => mRegistry;
        public AlertDispatcher Alerts => mAlerts;
        public S57ChartDatabase Chart => mChart;

        // Ingests a raw NMEA sentence string and processes it through the entire pipeline.
        public bool IngestNmeaSentence(StringView nmeaLine, int64 timestampSec)
        {
            CurrentTimeSec = timestampSec;

            if (!NmeaSentence.TryParse(nmeaLine, let sentence))
                return false;

            String completePayload = scope .();
            if (!mReassembler.Ingest(sentence, completePayload))
                return true; // Fragment stored, waiting for subsequent parts

            AisBitStream stream = scope .(completePayload);
            if (stream.TotalBits < 38)
                return false;

            uint8 msgType = (uint8)stream.ReadUInt(6);
            stream.SeekBit(0); // Rewind

            switch (msgType)
            {
                case 1, 2, 3:
                    if (AisCodec.DecodePositionReportClassA(stream, let posA))
                    {
                        ProcessClassAPosition(posA, timestampSec);
                        return true;
                    }
                case 4:
                    if (AisCodec.DecodeBaseStationReport(stream, let bs))
                    {
                        // Base station report
                        return true;
                    }
                case 5:
                    if (AisCodec.DecodeStaticVoyageData(stream, let voyage))
                    {
                        ProcessStaticVoyage(voyage);
                        return true;
                    }
                case 18:
                    if (AisCodec.DecodeStandardClassBPosition(stream, let posB))
                    {
                        ProcessClassBPosition(posB, timestampSec);
                        return true;
                    }
                case 21:
                    if (AisCodec.DecodeAidsToNavigation(stream, let aton))
                    {
                        // AtoN
                        return true;
                    }
                default:
                    break;
            }

            return false;
        }

        private void ProcessClassAPosition(in AisPositionReportClassA msg, int64 timestampSec)
        {
            TrackRecord track = mRegistry.GetOrCreateTrack(msg.Header.Mmsi);
            track.UpdateDynamicState(
                msg.Position,
                msg.SpeedOverGround,
                msg.CourseOverGround,
                msg.TrueHeading,
                msg.RateOfTurnDegPerMin,
                msg.NavStatus,
                timestampSec
            );
            mRegistry.UpdateTrackPosition(track.Mmsi, msg.Position);

            // Check SART distress
            if (msg.NavStatus == .AisSartActive || msg.Header.Mmsi >= 970000000 && msg.Header.Mmsi <= 974999999)
            {
                mAlerts.DispatchSartDistress(track.Mmsi, msg.Position, timestampSec);
            }

            // Check anchor dragging
            if (track.NavStatus == .AtAnchor && track.DropAnchorPosition.Latitude != 0.0)
            {
                double distFromDrop = Geodesy.GreatCircleDistanceMeters(track.Position, track.DropAnchorPosition);
                if (distFromDrop > track.AnchorScopeRadiusMeters || track.SpeedOverGroundKnots > 0.8)
                {
                    mAlerts.DispatchAnchorDragging(track.Mmsi, track.Position, distFromDrop, track.SpeedOverGroundKnots, timestampSec);
                }
            }

            // Check TSS compliance
            if (mChart.CheckTssCompliance(track.Position, track.CourseOverGroundDeg, let laneName, let isWrongWay))
            {
                if (isWrongWay && track.SpeedOverGroundKnots > 3.0)
                {
                    mAlerts.DispatchTssViolation(track.Mmsi, track.Position, laneName, track.CourseOverGroundDeg, timestampSec);
                }
            }

            // Check grounding hazard
            if (mChart.CheckGroundingHazard(
                track.Mmsi, track.Position, track.CourseOverGroundDeg,
                track.SpeedOverGroundKnots, track.StaticDraughtMeters,
                TideElevationMeters, 1200.0, let gWarn))
            {
                mAlerts.DispatchGroundingAlert(
                    track.Mmsi, gWarn.HazardLocation,
                    gWarn.DistanceToHazardMeters, gWarn.TimeToHazardSeconds,
                    gWarn.DepthAtHazardMeters, timestampSec
                );
            }

            // Check COLREGs collision risks against adjacent vessels
            EvaluatePairwiseCollisions(track, timestampSec);
        }

        private void ProcessClassBPosition(in AisStandardClassBPosition msg, int64 timestampSec)
        {
            TrackRecord track = mRegistry.GetOrCreateTrack(msg.Header.Mmsi);
            track.UpdateDynamicState(
                msg.Position,
                msg.SpeedOverGround,
                msg.CourseOverGround,
                msg.TrueHeading,
                0.0,
                .UnderWayUsingEngine,
                timestampSec
            );
            mRegistry.UpdateTrackPosition(track.Mmsi, msg.Position);
            EvaluatePairwiseCollisions(track, timestampSec);
        }

        private void ProcessStaticVoyage(in AisStaticVoyageData msg)
        {
            TrackRecord track = mRegistry.GetOrCreateTrack(msg.Header.Mmsi);
            track.ImoNumber = msg.ImoNumber;
            track.ShipCargoType = msg.ShipCargoType;
            track.LengthMeters = msg.OverallLengthMeters;
            track.BeamMeters = msg.OverallBeamMeters;
            track.StaticDraughtMeters = (msg.DraughtMeters > 0.1) ? msg.DraughtMeters : 5.0;

            track.VesselName.Clear();
            for (int i = 0; i < 20 && msg.VesselName[i] != '\0'; i++)
                track.VesselName.Append(msg.VesselName[i]);
            track.VesselName.TrimEnd();

            track.CallSign.Clear();
            for (int i = 0; i < 7 && msg.CallSign[i] != '\0'; i++)
                track.CallSign.Append(msg.CallSign[i]);
            track.CallSign.TrimEnd();
        }

        private void EvaluatePairwiseCollisions(TrackRecord ownship, int64 timestampSec)
        {
            List<uint32> candidateMmsis = scope .();
            // Search within 6 nautical miles (~11,112 meters)
            mRegistry.QueryNearby(ownship.Position, 6.0 * 1852.0, candidateMmsis);

            for (uint32 tgtMmsi in candidateMmsis)
            {
                if (tgtMmsi == ownship.Mmsi)
                    continue;

                if (mRegistry.TryGetTrack(tgtMmsi, let target))
                {
                    var cpa = CollisionRiskEvaluator.ComputeCpa(
                        ownship.Position, ownship.CourseOverGroundDeg, ownship.SpeedOverGroundKnots,
                        target.Position, target.CourseOverGroundDeg, target.SpeedOverGroundKnots
                    );

                    if (cpa.IsConverging && cpa.CpaDistanceNm <= WarningCpaNm && cpa.TcpaSeconds <= WarningTcpaSec)
                    {
                        var geom = EncounterClassifier.ComputeGeometry(
                            ownship.Position, ownship.CourseOverGroundDeg, ownship.SpeedOverGroundKnots,
                            target.Position, target.CourseOverGroundDeg, target.SpeedOverGroundKnots
                        );

                        var enc = EncounterClassifier.Classify(
                            geom, ownship.SpeedOverGroundKnots, target.SpeedOverGroundKnots,
                            ownship.NavStatus, target.NavStatus
                        );

                        double distNm = geom.DistanceMeters / 1852.0;
                        double cri = CollisionRiskEvaluator.CalculateCri(cpa, distNm, enc, WarningCpaNm, WarningTcpaSec);

                        if (cri >= 0.40)
                        {
                            mAlerts.DispatchCollisionAlert(
                                ownship.Mmsi, target.Mmsi,
                                ownship.Position, cpa, enc, cri, timestampSec
                            );
                        }
                    }
                }
            }
        }
    }
}
