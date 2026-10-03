// Prints FlappedEar Overlays' Corner Analyzer for compared laps as one JSON
// document:
//   cpp_corner_analyzer_dump <output.json> <input.vbo>...
//   cpp_corner_analyzer_dump --day <day.json> <output.json>
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession.
//
// "pairs": the laps of cpp_comparison_dump (for each file with lap traces, a
// start gate and an eligible lap: the first eligible lap against the
// fastest, the swap, and the last eligible lap against the second; a single
// eligible lap against itself; and a few pairs across corpus files of one
// track). For each pair the tool builds the comparison's shared axis from
// lap A's trace and start gate and projects both laps
// (ensureComparisonProgressAxis), and takes three segment sets: the
// proposals of lap A's file's fastest eligible lap on its own axis, approved
// with ids s0, s1, ... (computeSegmentReview and approval), the same shifted
// 37 m (the last one crossing the gate) and every other one. Both laps share
// each set, as when both runs carry the same revision. For each set it
// writes comparisonApprovedSegments, every segment's
// comparisonSegmentMetrics, the per-lap figures it reads (segmentSpeeds and,
// for corners, the geometric phases on the shared axis, computeCornerSpeeds,
// computeBrakingMetrics and computeExitMetrics in full),
// comparisonHeartRate over every segment and comparisonTimeLossObservations.
// These are AnalysisController member functions
// (AnalysisControllerCornerAnalyzer.cpp, AnalysisControllerChannelSummaries.cpp),
// so the tool repeats their lines. The shared axis is written in full under
// "axes" (keyed by file and lap A) so the Dart side measures on exactly the
// same axis.
//
// "cases": comparisonSharedSegmentation and its note on hand-made stored
// segments, and the Corner Analyzer of hand-made sessions (measured,
// inferred, undeclared and mismatched channels, heart rate with
// placeholders, a glitch and a gap) on a 2000 m circular axis with hand-made
// projections, including a range across the start/finish line.
//
// A --day file names a real day's recordings, the pairs to compare and the
// lap whose proposals become the segments:
//   {"runs": [{"runId", "file"}], "pairs": [{"a": {"runId", "lapNumber"},
//    "b": {"runId", "lapNumber"}}], "segmentsFrom": {"runId", "lapNumber"}}
// Use it locally only; never commit its input or output. NaN is written as
// null.

#include "telemetry/BrakingMetrics.h"
#include "telemetry/ChannelSummary.h"
#include "telemetry/CornerPhases.h"
#include "telemetry/CornerSpeeds.h"
#include "telemetry/ExitMetrics.h"
#include "telemetry/LapTiming.h"
#include "telemetry/SectorTiming.h"
#include "telemetry/TimeLoss.h"
#include "telemetry/TrackProgress.h"
#include "telemetry/TrackSegmentProposals.h"
#include "telemetry/TrackSegmentReview.h"
#include "telemetry/TrackSegments.h"
#include "telemetry/VboParser.h"

#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <functional>
#include <memory>
#include <optional>

using namespace FlappedEar;

namespace {

const QString configuration = QStringLiteral("compatibility-v1:") + QString("0123456789abcdef").repeated(4);

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

QJsonValue optional(const std::optional<double> &value)
{
    return value ? number(*value) : QJsonValue(QJsonValue::Null);
}

QJsonArray strings(const QStringList &list)
{
    return QJsonArray::fromStringList(list);
}

// --- AnalysisControllerCornerAnalyzer.cpp, repeated --------------------------

enum class MetricProvenance { Measured, Calculated, Inferred, Unavailable };

QString metricProvenanceName(const MetricProvenance provenance)
{
    switch (provenance) {
    case MetricProvenance::Measured: return QStringLiteral("measured");
    case MetricProvenance::Calculated: return QStringLiteral("calculated");
    case MetricProvenance::Inferred: return QStringLiteral("inferred");
    case MetricProvenance::Unavailable: return QStringLiteral("unavailable");
    }
    return QStringLiteral("unavailable");
}

QVariantMap provenanceValue(
    const std::optional<double> value, const MetricProvenance provenance, const QString &unavailableReason = {})
{
    QVariantMap map{{"provenance", metricProvenanceName(provenance)}};
    if (value) map.insert("value", *value);
    else if (!unavailableReason.isEmpty()) map.insert("unavailableReason", unavailableReason);
    return map;
}

QVariantMap deltaValue(const std::optional<double> value, const QString &unavailableReason = {})
{
    QVariantMap map;
    if (value) map.insert("value", *value);
    else if (!unavailableReason.isEmpty()) map.insert("unavailableReason", unavailableReason);
    return map;
}

MetricProvenance cornerSpeedPhaseProvenance(const CornerSpeeds &speeds, const CornerSpeedValue &phase)
{
    if (!phase.value) return MetricProvenance::Unavailable;
    return speeds.provenance == QLatin1String("measured") ? MetricProvenance::Measured : MetricProvenance::Unavailable;
}

MetricProvenance namedProvenance(const QString &provenance, const bool hasValue)
{
    if (!hasValue) return MetricProvenance::Unavailable;
    if (provenance == QLatin1String("measured")) return MetricProvenance::Measured;
    if (provenance == QLatin1String("inferred")) return MetricProvenance::Inferred;
    return MetricProvenance::Unavailable;
}

struct SegmentSpeeds {
    std::optional<double> entry, exit, maximum, minimum;
    QString unavailableReason;
};

SegmentSpeeds segmentSpeeds(const TelemetrySession &session, const QVector<ProgressSegment> &trace,
    const double axisLengthMeters, const double lapStart, const double lapEnd,
    const double startMeters, const double endMeters)
{
    SegmentSpeeds speeds;
    if (!session.channels.contains(session.aliases.value("speed", "speed"))) {
        speeds.unavailableReason = QString(cornerPhaseSpeedChannelMissing);
        return speeds;
    }
    if (endMeters <= startMeters) {
        speeds.unavailableReason = QString(cornerPhaseCrossesGate);
        return speeds;
    }
    const auto timeAt = [&](const double meters) -> std::optional<double> {
        if (meters <= 1e-6) return lapStart;
        if (meters >= axisLengthMeters - 1e-6) return lapEnd;
        return timeAtProgress(trace, meters);
    };
    const auto start = timeAt(startMeters);
    const auto end = timeAt(endMeters);
    if (start) speeds.entry = session.valueAt("speed", *start);
    if (end) speeds.exit = session.valueAt("speed", *end);
    for (const auto &boundary : {speeds.entry, speeds.exit}) {
        if (!boundary) continue;
        if (!speeds.maximum || *boundary > *speeds.maximum) speeds.maximum = boundary;
        if (!speeds.minimum || *boundary < *speeds.minimum) speeds.minimum = boundary;
    }
    if (start && end && *end > *start) {
        for (const auto &segment : session.sampledSegments("speed", *start, *end, 4000)) {
            for (const auto &point : segment) {
                const double value = point.y();
                if (!speeds.maximum || value > *speeds.maximum) speeds.maximum = value;
                if (!speeds.minimum || value < *speeds.minimum) speeds.minimum = value;
            }
        }
    }
    if (!speeds.entry || !speeds.exit || !speeds.maximum) speeds.unavailableReason = QStringLiteral("incompleteCoverage");
    return speeds;
}

// One comparison slot: the row's bounds and reference, its recording and its
// projection onto the shared axis (m_comparisonProgressTraceCache).
struct Lap {
    const TelemetrySession *session = nullptr;
    QVector<ProgressSegment> trace;
    double start = 0.0;
    double end = 0.0;
    QJsonObject reference;
};

// comparisonSharedSegmentation and the condition of comparisonSegmentationNote:
// `canonical` stands for the canonical run's approved segmentation when the
// comparison was opened from the theoretical best.
std::pair<std::optional<ApprovedSegmentation>, bool> sharedSegmentation(const ApprovedSegmentation &approvedA,
    const ApprovedSegmentation &approvedB, const std::optional<ApprovedSegmentation> &canonical,
    const QString &groupA, const QString &groupB)
{
    const auto shared = [&]() -> std::optional<ApprovedSegmentation> {
        if (approvedA.valid && approvedB.valid && !approvedA.revision.isEmpty()
            && approvedA.revision == approvedB.revision
            && approvedA.trackConfigurationReference == approvedB.trackConfigurationReference)
            return approvedA;
        if (!canonical) return std::nullopt;
        if (groupA.isEmpty() || groupB != groupA) return std::nullopt;
        if (canonical->valid && !canonical->revision.isEmpty() && !canonical->segments.isEmpty()) return *canonical;
        return std::nullopt;
    }();
    bool note = false;
    if (canonical) {
        const bool sameRevision = approvedA.valid && !approvedA.revision.isEmpty() && approvedA.revision == approvedB.revision;
        note = !sameRevision && shared.has_value();
    }
    return {shared, note};
}

QVariantList approvedSegments(const ApprovedSegmentation &shared)
{
    QVariantList rows;
    for (const auto &value : shared.segments) {
        const auto segment = value.toObject();
        rows.append(QVariantMap{{"id", segment.value("id").toString()}, {"name", segment.value("name").toString()},
            {"type", segment.value("type").toString()},
            {"startMeters", segment.value("startProgressMeters").toDouble()},
            {"endMeters", segment.value("endProgressMeters").toDouble()}});
    }
    return rows;
}

// The per-lap results comparisonSegmentMetrics reads, kept for the dump.
struct SegmentDetail {
    SegmentSpeeds speeds[2];
    bool corner = false;
    CornerGeometryPhases phases;
    CornerSpeeds cornerSpeeds[2];
    BrakingMetrics braking[2];
    ExitMetrics exit[2];
};

QVariantMap segmentMetrics(const ProgressAxis &axis, const Lap (&pair)[2], const ApprovedSegmentation &shared,
    const QString &segmentId, SegmentDetail &detail)
{
    if (segmentId.isEmpty() || !axis.valid) return {};
    const auto &approvedA = shared;
    const auto &approvedB = shared;
    QString segmentType;
    for (const auto &value : approvedA.segments) {
        const auto segment = value.toObject();
        if (segment.value("id").toString() == segmentId) { segmentType = segment.value("type").toString(); break; }
    }
    if (segmentType.isEmpty()) return {};
    const auto &slotA = pair[0];
    const auto &slotB = pair[1];

    QVariantMap result{{"segmentId", segmentId}, {"type", segmentType}};
    {
        const auto timesA = computeLapSectorTimes(approvedA, axis.lengthMeters, slotA.trace, slotA.start, slotA.end, slotA.reference);
        const auto timesB = computeLapSectorTimes(approvedB, axis.lengthMeters, slotB.trace, slotB.start, slotB.end, slotB.reference);
        const SectorTime *sectorA = nullptr;
        const SectorTime *sectorB = nullptr;
        for (const auto &sector : timesA.sectors) if (sector.segmentId == segmentId) sectorA = &sector;
        for (const auto &sector : timesB.sectors) if (sector.segmentId == segmentId) sectorB = &sector;
        if (sectorA && sectorB) {
            const auto comparison = compareSectorTimes(timesA, timesB, segmentId);
            result.insert("sectorTime", QVariantMap{
                {"a", provenanceValue(sectorA->seconds,
                     sectorA->seconds ? MetricProvenance::Calculated : MetricProvenance::Unavailable, sectorA->unavailableReason)},
                {"b", provenanceValue(sectorB->seconds,
                     sectorB->seconds ? MetricProvenance::Calculated : MetricProvenance::Unavailable, sectorB->unavailableReason)},
                {"delta", deltaValue(comparison.secondsDelta, comparison.unavailableReason)}});
        }
    }
    {
        double startMeters = 0.0, endMeters = 0.0;
        for (const auto &value : approvedA.segments) {
            const auto segment = value.toObject();
            if (segment.value("id").toString() != segmentId) continue;
            startMeters = segment.value("startProgressMeters").toDouble();
            endMeters = segment.value("endProgressMeters").toDouble();
        }
        const auto length = axis.lengthMeters;
        const auto speedsA = segmentSpeeds(*slotA.session, slotA.trace, length, slotA.start, slotA.end, startMeters, endMeters);
        const auto speedsB = segmentSpeeds(*slotB.session, slotB.trace, length, slotB.start, slotB.end, startMeters, endMeters);
        detail.speeds[0] = speedsA;
        detail.speeds[1] = speedsB;
        const auto entry = [&](const std::optional<double> a, const std::optional<double> b) {
            std::optional<double> delta;
            if (a && b) delta = *a - *b;
            return QVariantMap{
                {"a", provenanceValue(a, a ? MetricProvenance::Measured : MetricProvenance::Unavailable, speedsA.unavailableReason)},
                {"b", provenanceValue(b, b ? MetricProvenance::Measured : MetricProvenance::Unavailable, speedsB.unavailableReason)},
                {"delta", deltaValue(delta)}};
        };
        const auto speedChannel = slotA.session->aliases.value("speed", "speed");
        result.insert("speeds", QVariantMap{{"unit", slotA.session->channels.value(speedChannel).unit},
            {"entry", entry(speedsA.entry, speedsB.entry)},
            {"maximum", entry(speedsA.maximum, speedsB.maximum)}, {"minimum", entry(speedsA.minimum, speedsB.minimum)},
            {"exit", entry(speedsA.exit, speedsB.exit)}});
    }

    if (segmentType != trackSegmentTypeName(TrackSegmentType::Corner)) return result;
    const auto features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
    detail.corner = true;
    for (const auto &value : approvedA.segments) {
        const auto segment = value.toObject();
        if (segment.value("id").toString() == segmentId)
            detail.phases = proposeCornerGeometryPhases(axis, features, cornerFromSegment(axis, features, segment));
    }

    {
        const auto speedsA = computeCornerSpeeds(axis, features, approvedA, segmentId, slotA.trace, *slotA.session);
        const auto speedsB = computeCornerSpeeds(axis, features, approvedB, segmentId, slotB.trace, *slotB.session);
        detail.cornerSpeeds[0] = speedsA;
        detail.cornerSpeeds[1] = speedsB;
        if (speedsA.valid && speedsB.valid) {
            const auto comparison = compareCornerSpeeds(speedsA, speedsB);
            const auto phase = [&](const CornerSpeedValue &a, const CornerSpeedValue &b, const std::optional<double> &delta) {
                return QVariantMap{
                    {"a", provenanceValue(a.value, cornerSpeedPhaseProvenance(speedsA, a), a.unavailableReason)},
                    {"b", provenanceValue(b.value, cornerSpeedPhaseProvenance(speedsB, b), b.unavailableReason)},
                    {"delta", deltaValue(delta, comparison.unavailableReason)}};
            };
            result.insert("corner", QVariantMap{{"channel", speedsA.channel}, {"unit", speedsA.unit},
                {"entry", phase(speedsA.entry, speedsB.entry, comparison.entryDelta)},
                {"apex", phase(speedsA.apex, speedsB.apex, comparison.apexDelta)},
                {"minimum", phase(speedsA.minimum, speedsB.minimum, comparison.minimumDelta)},
                {"exit", phase(speedsA.exit, speedsB.exit, comparison.exitDelta)}});
        }
    }
    {
        const auto brakingA = computeBrakingMetrics(axis.lengthMeters, approvedA, segmentId, slotA.trace, *slotA.session,
            slotA.start, slotA.end);
        const auto brakingB = computeBrakingMetrics(axis.lengthMeters, approvedB, segmentId, slotB.trace, *slotB.session,
            slotB.start, slotB.end);
        detail.braking[0] = brakingA;
        detail.braking[1] = brakingB;
        if (brakingA.valid && brakingB.valid) {
            const auto comparison = compareBrakingMetrics(brakingA, brakingB);
            result.insert("braking", QVariantMap{
                {"point", QVariantMap{
                     {"a", provenanceValue(brakingA.brakingPointMeters,
                          namedProvenance(brakingA.provenance, brakingA.brakingPointMeters.has_value()), brakingA.unavailableReason)},
                     {"b", provenanceValue(brakingB.brakingPointMeters,
                          namedProvenance(brakingB.provenance, brakingB.brakingPointMeters.has_value()), brakingB.unavailableReason)},
                     {"delta", deltaValue(comparison.brakingPointDeltaMeters, comparison.unavailableReason)}}},
                {"seconds", QVariantMap{
                     {"a", provenanceValue(brakingA.brakingSeconds,
                          namedProvenance(brakingA.provenance, brakingA.brakingSeconds.has_value()), brakingA.unavailableReason)},
                     {"b", provenanceValue(brakingB.brakingSeconds,
                          namedProvenance(brakingB.provenance, brakingB.brakingSeconds.has_value()), brakingB.unavailableReason)},
                     {"delta", deltaValue(comparison.brakingSecondsDelta, comparison.unavailableReason)}}},
                {"peakDeceleration", QVariantMap{
                     {"a", provenanceValue(brakingA.peakDeceleration,
                          namedProvenance(brakingA.provenance, brakingA.peakDeceleration.has_value()), brakingA.decelerationUnavailableReason)},
                     {"b", provenanceValue(brakingB.peakDeceleration,
                          namedProvenance(brakingB.provenance, brakingB.peakDeceleration.has_value()), brakingB.decelerationUnavailableReason)},
                     {"delta", deltaValue(comparison.peakDecelerationDelta, comparison.unavailableReason)}}}});
        }
    }
    {
        const auto exitA = computeExitMetrics(axis.lengthMeters, approvedA, segmentId, slotA.trace, *slotA.session, slotA.end);
        const auto exitB = computeExitMetrics(axis.lengthMeters, approvedB, segmentId, slotB.trace, *slotB.session, slotB.end);
        detail.exit[0] = exitA;
        detail.exit[1] = exitB;
        if (exitA.valid && exitB.valid) {
            const auto comparison = compareExitMetrics(exitA, exitB);
            result.insert("exitEffects", QVariantMap{
                {"pickup", QVariantMap{
                     {"a", provenanceValue(exitA.pickup.progressMeters,
                          namedProvenance(exitA.pickup.provenance, exitA.pickup.progressMeters.has_value()), exitA.pickup.unavailableReason)},
                     {"b", provenanceValue(exitB.pickup.progressMeters,
                          namedProvenance(exitB.pickup.provenance, exitB.pickup.progressMeters.has_value()), exitB.pickup.unavailableReason)},
                     {"delta", deltaValue(comparison.pickupDeltaMeters, comparison.pickupUnavailableReason)}}},
                {"exitSpeed", QVariantMap{
                     {"a", provenanceValue(exitA.exitSpeed,
                          exitA.exitSpeed ? MetricProvenance::Measured : MetricProvenance::Unavailable, exitA.downstreamUnavailableReason)},
                     {"b", provenanceValue(exitB.exitSpeed,
                          exitB.exitSpeed ? MetricProvenance::Measured : MetricProvenance::Unavailable, exitB.downstreamUnavailableReason)},
                     {"delta", deltaValue(comparison.exitSpeedDelta)}}}});
        }
    }
    return result;
}

QVariantMap timeLossObservations(const ProgressAxis &axis, const Lap (&pair)[2], const ApprovedSegmentation &shared)
{
    if (!axis.valid) return {{"valid", false}};
    const auto &slotA = pair[0];
    const auto &slotB = pair[1];
    const auto timesA = computeLapSectorTimes(shared, axis.lengthMeters, slotA.trace, slotA.start, slotA.end, slotA.reference);
    const auto timesB = computeLapSectorTimes(shared, axis.lengthMeters, slotB.trace, slotB.start, slotB.end, slotB.reference);
    const auto observations = computeTimeLossObservations(shared, axis.lengthMeters, timesA, slotA.start, timesB, slotB.start);
    if (!observations.valid) return {{"valid", false}, {"unavailableReason", observations.unavailableReason}};
    QVariantList windows;
    for (const auto &window : observations.windows) {
        QVariantMap row{{"segmentId", window.segmentId}, {"name", window.name}, {"type", window.type},
            {"role", window.role}, {"startMeters", window.startProgressMeters}, {"endMeters", window.endProgressMeters}};
        if (!window.cornerSegmentId.isEmpty()) row.insert("cornerSegmentId", window.cornerSegmentId);
        if (window.incrementSeconds) row.insert("incrementSeconds", *window.incrementSeconds);
        else row.insert("unavailableReason", window.unavailableReason);
        if (window.cumulativeAtStartSeconds) row.insert("cumulativeAtStartSeconds", *window.cumulativeAtStartSeconds);
        if (window.cumulativeAtEndSeconds) row.insert("cumulativeAtEndSeconds", *window.cumulativeAtEndSeconds);
        windows.append(row);
    }
    return {{"valid", true}, {"algorithm", QString::fromLatin1(timeLossAlgorithm)},
        {"revision", observations.stamp.revision}, {"windows", windows},
        {"allWindowsTimed", observations.allWindowsTimed},
        {"timedIncrementSumSeconds", observations.timedIncrementSumSeconds},
        {"lapDeltaSeconds", (slotA.end - slotA.start) - (slotB.end - slotB.start)}};
}

// --- AnalysisControllerChannelSummaries.cpp and OutingChannelSummaries.cpp ---

QVariantMap channelSummaryMap(const ChannelSummary &summary)
{
    QVariantMap map{{"valid", summary.valid}, {"sampleCount", summary.sampleCount},
        {"excludedArtifacts", summary.excludedArtifacts}, {"coverage", summary.coverage},
        {"coveredSeconds", summary.coveredSeconds}, {"startTime", summary.startTime}, {"endTime", summary.endTime}};
    if (!summary.valid) { map.insert("unavailableReason", summary.unavailableReason); return map; }
    map.insert("minimum", *summary.minimum); map.insert("maximum", *summary.maximum); map.insert("mean", *summary.mean);
    map.insert("minimumTime", *summary.minimumTime); map.insert("maximumTime", *summary.maximumTime);
    return map;
}

QVariantMap heartRate(const ProgressAxis &axis, const Lap (&pair)[2], const double startMeters, const double endMeters)
{
    if (!axis.valid) return {{"valid", false}};
    const double length = axis.lengthMeters;
    const double from = std::clamp(startMeters, 0.0, length), to = std::clamp(endMeters, 0.0, length);
    QVariantList laps;
    for (int slot = 0; slot < 2; ++slot) {
        const auto &comparisonSlot = pair[slot];
        const double lapStart = comparisonSlot.start;
        const double lapEnd = comparisonSlot.end;
        const auto timeAt = [&](const double meters) -> std::optional<double> {
            if (meters <= 1e-6) return lapStart;
            if (meters >= length - 1e-6) return lapEnd;
            return timeAtProgress(comparisonSlot.trace, meters);
        };
        const QVector<std::pair<double, double>> ranges = from <= to
            ? QVector<std::pair<double, double>>{{from, to}}
            : QVector<std::pair<double, double>>{{from, length}, {0.0, to}};
        QVector<ChannelSummary> parts;
        for (const auto &[rangeStart, rangeEnd] : ranges) {
            const auto t0 = timeAt(rangeStart), t1 = timeAt(rangeEnd);
            if (!t0 || !t1 || *t1 <= *t0) { parts.clear(); break; }
            parts.append(summarizeChannel(*comparisonSlot.session, QStringLiteral("heartRate"), *t0, *t1, heartRateSummaryPolicy()));
        }
        if (parts.isEmpty()) {
            laps.append(QVariantMap{{"valid", false}, {"unavailableReason", QStringLiteral("incompleteCoverage")}});
            continue;
        }
        auto map = channelSummaryMap(combineChannelSummaries(parts));
        map.insert("channel", comparisonSlot.session->aliases.value("heartRate"));
        laps.append(map);
    }
    return {{"valid", true}, {"algorithm", QString::fromLatin1(channelSummaryAlgorithm)}, {"laps", laps},
        {"startMeters", from}, {"endMeters", to}, {"crossesStartFinish", from > to}};
}

// --- JSON of the per-lap results ---------------------------------------------

QJsonObject phaseJson(const CornerPhasePoint &point)
{
    return {{"method", point.method}, {"progress", number(point.progressMeters)},
            {"tolerance", number(point.toleranceMeters)}, {"uncertainty", strings(point.uncertaintyReasons)},
            {"reason", point.unresolvedReason}};
}

QJsonObject speedJson(const CornerSpeedValue &value)
{
    return {{"value", optional(value.value)}, {"progress", number(value.progressMeters)},
            {"time", optional(value.telemetryTime)}, {"reason", value.unavailableReason},
            {"limitations", strings(value.limitations)}};
}

QJsonObject cornerSpeedsJson(const CornerSpeeds &speeds)
{
    return {{"valid", speeds.valid}, {"channel", speeds.channel}, {"unit", speeds.unit},
            {"provenance", speeds.provenance}, {"entry", speedJson(speeds.entry)}, {"apex", speedJson(speeds.apex)},
            {"minimum", speedJson(speeds.minimum)}, {"exit", speedJson(speeds.exit)},
            {"lengthMeters", number(speeds.lengthMeters)}, {"coveredMeters", number(speeds.coveredMeters)},
            {"spacing", number(speeds.meanSampleSpacingMeters)}};
}

QJsonObject brakingJson(const BrakingMetrics &braking)
{
    return {{"valid", braking.valid}, {"intervalStart", number(braking.intervalStartMeters)},
            {"intervalEnd", number(braking.intervalEndMeters)}, {"entry", number(braking.entryMeters)},
            {"reason", braking.unavailableReason}, {"method", braking.method}, {"provenance", braking.provenance},
            {"channel", braking.channel}, {"point", optional(braking.brakingPointMeters)},
            {"pointTime", optional(braking.brakingPointTime)},
            {"beforeEntry", optional(braking.distanceBeforeEntryMeters)},
            {"seconds", optional(braking.brakingSeconds)}, {"distance", optional(braking.brakingDistanceMeters)},
            {"limitations", strings(braking.limitations)}, {"decelerationUnit", braking.decelerationUnit},
            {"peak", optional(braking.peakDeceleration)}, {"mean", optional(braking.meanDeceleration)},
            {"decelerationReason", braking.decelerationUnavailableReason}};
}

QJsonObject exitJson(const ExitMetrics &exit)
{
    const auto &pickup = exit.pickup;
    return {{"valid", exit.valid},
            {"pickup", QJsonObject{{"method", pickup.method}, {"provenance", pickup.provenance},
                                   {"channel", pickup.channel}, {"progress", optional(pickup.progressMeters)},
                                   {"time", optional(pickup.telemetryTime)}, {"reason", pickup.unavailableReason},
                                   {"limitations", strings(pickup.limitations)}}},
            {"source", exit.intervalSource}, {"intervalStart", number(exit.intervalStartMeters)},
            {"intervalEnd", number(exit.intervalEndMeters)}, {"exitSpeed", optional(exit.exitSpeed)},
            {"endSpeed", optional(exit.intervalEndSpeed)}, {"elapsed", optional(exit.elapsedSeconds)},
            {"reason", exit.downstreamUnavailableReason}};
}

QJsonObject segmentSpeedsJson(const SegmentSpeeds &speeds)
{
    return {{"entry", optional(speeds.entry)}, {"exit", optional(speeds.exit)}, {"maximum", optional(speeds.maximum)},
            {"minimum", optional(speeds.minimum)}, {"reason", speeds.unavailableReason}};
}

QJsonObject axisJson(const ProgressAxis &axis)
{
    QJsonArray points, cumulative;
    for (qsizetype i = 0; i < axis.points.size(); ++i) {
        points.append(QJsonArray{axis.points[i].x(), axis.points[i].y()});
        cumulative.append(axis.cumulative[i]);
    }
    return {{"points", points}, {"cumulative", cumulative}, {"lengthMeters", axis.lengthMeters},
            {"spacingMeters", axis.spacingMeters}, {"originLatitude", axis.origin.latitudeDegrees},
            {"originLongitude", axis.origin.longitudeDegrees}, {"valid", axis.valid}};
}

// Everything the Corner Analyzer shows of `shared` for one pair.
QJsonObject analyzerJson(const ProgressAxis &axis, const Lap (&pair)[2], const ApprovedSegmentation &shared)
{
    QJsonArray segments;
    for (const auto &value : approvedSegments(shared)) {
        const auto row = value.toMap();
        const auto id = row.value("id").toString();
        SegmentDetail detail;
        const auto metrics = segmentMetrics(axis, pair, shared, id, detail);
        QJsonObject entry{{"row", QJsonObject::fromVariantMap(row)}, {"metrics", QJsonObject::fromVariantMap(metrics)},
                          {"heartRate", QJsonObject::fromVariantMap(heartRate(axis, pair,
                              row.value("startMeters").toDouble(), row.value("endMeters").toDouble()))}};
        if (!metrics.isEmpty()) {
            entry.insert("segmentSpeeds", QJsonArray{segmentSpeedsJson(detail.speeds[0]), segmentSpeedsJson(detail.speeds[1])});
            if (detail.corner) {
                QJsonArray candidates;
                for (const double candidate : detail.phases.apexCandidatesMeters) candidates.append(number(candidate));
                entry.insert("phases", QJsonObject{{"valid", detail.phases.valid}, {"entry", phaseJson(detail.phases.entry)},
                                                   {"apex", phaseJson(detail.phases.apex)},
                                                   {"exit", phaseJson(detail.phases.exit)}, {"candidates", candidates}});
                entry.insert("cornerSpeeds", QJsonArray{cornerSpeedsJson(detail.cornerSpeeds[0]), cornerSpeedsJson(detail.cornerSpeeds[1])});
                entry.insert("braking", QJsonArray{brakingJson(detail.braking[0]), brakingJson(detail.braking[1])});
                entry.insert("exit", QJsonArray{exitJson(detail.exit[0]), exitJson(detail.exit[1])});
            }
        }
        segments.append(entry);
    }
    SegmentDetail unused;
    return {{"revision", shared.revision}, {"segments", segments},
            {"unknown", QJsonObject::fromVariantMap(segmentMetrics(axis, pair, shared, "not-a-real-id", unused))},
            {"timeLoss", QJsonObject::fromVariantMap(timeLossObservations(axis, pair, shared))}};
}

// --- Recordings and pairs (as cpp_comparison_dump) ---------------------------

struct Recording {
    QString file;
    std::shared_ptr<TelemetrySession> session;
    LapSession laps;
};

std::optional<Recording> load(const QString &path)
{
    Recording recording;
    recording.file = QFileInfo(path).fileName();
    try {
        recording.session = std::make_shared<TelemetrySession>(VboParser::parseFile(path));
        recording.laps = deriveSourceLapSession(*recording.session);
    } catch (const std::exception &) {
        return std::nullopt;
    }
    return recording;
}

GeoCoordinate gateMidpoint(const TimingGate &gate)
{
    return {(gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
            (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0};
}

const LapTrace *traceOf(const Recording &recording, const int lapNumber)
{
    for (const auto &trace : recording.laps.lapTraces)
        if (trace.lapNumber == lapNumber) return &trace;
    return nullptr;
}

const TimedLap *timedLap(const Recording &recording, const int lapNumber)
{
    for (const auto &lap : recording.laps.timedLaps)
        if (lap.number == lapNumber) return &lap;
    return nullptr;
}

QJsonArray withIds(QJsonArray segments)
{
    for (qsizetype i = 0; i < segments.size(); ++i) {
        auto segment = segments[i].toObject();
        segment.insert("id", QString("s%1").arg(i));
        segments[i] = segment;
    }
    return segments;
}

QJsonArray shifted(const QJsonArray &segments, const double length)
{
    QJsonArray result;
    for (const auto &value : segments) {
        auto segment = value.toObject();
        const double start = segment.value("startProgressMeters").toDouble() + 37.0;
        double end = segment.value("endProgressMeters").toDouble() + 37.0;
        if (start >= length) continue;
        if (end > length) end -= length;
        segment.insert("startProgressMeters", start);
        segment.insert("endProgressMeters", end);
        result.append(segment);
    }
    return validTrackSegments(result) ? result : QJsonArray{};
}

QJsonArray everyOther(const QJsonArray &segments)
{
    QJsonArray result;
    for (qsizetype i = 0; i < segments.size(); i += 2) result.append(segments[i]);
    return result;
}

// computeSegmentReview's proposals for one lap, approved with ids s0, s1, ...,
// and the two variants; empty when the lap has no usable axis.
QVector<std::pair<QString, QJsonArray>> segmentSets(const Recording &recording, const int lapNumber)
{
    const auto *trace = traceOf(recording, lapNumber);
    if (!trace || !recording.laps.selectedStartGate) return {};
    const auto &gate = *recording.laps.selectedStartGate;
    const auto axis = buildProgressAxis(*trace, gateMidpoint(gate), gate);
    const auto features = axis.valid ? computeTrackFeatures(axis, segmentReviewSmoothingMeters) : TrackFeatures{};
    if (!features.valid) return {};
    const auto automatic = withIds(proposalsToTrackSegments(proposeTrackSegments(axis, features, {}), configuration));
    if (automatic.isEmpty()) return {};
    QVector<std::pair<QString, QJsonArray>> sets{{"automatic", automatic}};
    const auto moved = shifted(automatic, axis.lengthMeters);
    if (!moved.isEmpty()) sets.append({"shifted", moved});
    sets.append({"everyOther", everyOther(automatic)});
    return sets;
}

int fastestEligible(const Recording &recording)
{
    const TimedLap *best = nullptr;
    for (const auto &lap : recording.laps.timedLaps)
        if (lap.referenceEligible() && (!best || lap.durationSeconds < best->durationSeconds)) best = &lap;
    return best ? best->number : 0;
}

QJsonObject lapReference(const QString &file, const int lapNumber, const double start)
{
    return {{"runId", file}, {"lapNumber", lapNumber}, {"startTime", start}};
}

// One pair: the shared axis and both projections, then every segment set.
std::optional<QJsonObject> pairJson(const QString &runA, const Recording &a, const int lapA, const QString &runB,
    const Recording &b, const int lapB, const QVector<std::pair<QString, QJsonArray>> &sets,
    QHash<QString, QJsonObject> &axes)
{
    const auto *timedA = timedLap(a, lapA);
    const auto *timedB = timedLap(b, lapB);
    if (!timedA || !timedB) return std::nullopt;
    ProgressAxis axis;
    const auto *trace = traceOf(a, lapA);
    if (trace && a.laps.selectedStartGate)
        axis = buildProgressAxis(*trace, gateMidpoint(*a.laps.selectedStartGate), *a.laps.selectedStartGate);
    Lap pair[2];
    pair[0] = {a.session.get(), {}, timedA->startTelemetryTime, timedA->endTelemetryTime,
                lapReference(runA, lapA, timedA->startTelemetryTime)};
    pair[1] = {b.session.get(), {}, timedB->startTelemetryTime, timedB->endTelemetryTime,
                lapReference(runB, lapB, timedB->startTelemetryTime)};
    if (axis.valid) {
        pair[0].trace = projectLapTrace(axis, *pair[0].session, pair[0].start, pair[0].end);
        pair[1].trace = projectLapTrace(axis, *pair[1].session, pair[1].start, pair[1].end);
    }
    const auto axisKey = runA + "#" + QString::number(lapA);
    if (axis.valid && !axes.contains(axisKey)) axes.insert(axisKey, axisJson(axis));
    QJsonArray variants;
    for (const auto &[name, segments] : sets) {
        const auto approved = approvedSegmentation(segments, configuration);
        auto entry = analyzerJson(axis, pair, approved);
        entry.insert("name", name);
        entry.insert("stored", segments);
        variants.append(entry);
    }
    return QJsonObject{{"a", QJsonObject{{"run", runA}, {"lap", lapA}}}, {"b", QJsonObject{{"run", runB}, {"lap", lapB}}},
                       {"axis", axisKey}, {"axisValid", axis.valid},
                       {"axisLength", number(axis.valid ? axis.lengthMeters : 0.0)}, {"variants", variants}};
}

QVector<QPair<int, int>> pairsOf(const Recording &recording)
{
    QVector<QPair<int, int>> pairs;
    if (recording.laps.lapTraces.isEmpty() || !recording.laps.selectedStartGate) return pairs;
    QVector<int> eligible;
    for (const auto &lap : recording.laps.timedLaps)
        if (lap.referenceEligible()) eligible.append(lap.number);
    if (eligible.isEmpty()) return pairs;
    const auto add = [&pairs](const int a, const int b) {
        if (!pairs.contains(qMakePair(a, b))) pairs.append(qMakePair(a, b));
    };
    if (eligible.size() == 1) {
        add(eligible.first(), eligible.first());
        return pairs;
    }
    const int fastest = recording.laps.fastestLapIndex
        ? recording.laps.timedLaps[*recording.laps.fastestLapIndex].number : eligible.first();
    const int other = fastest == eligible.first() ? eligible[1] : eligible.first();
    add(other, fastest);
    add(fastest, other);
    if (eligible.size() >= 3) add(eligible.last(), eligible[1]);
    return pairs;
}

const QVector<QPair<QString, QString>> crossFilePairs{
    {"corners_measured.vbo", "corners_inferred.vbo"},
    {"corners_inferred.vbo", "corners_measured.vbo"},
    {"corners_measured.vbo", "corners_gaps.vbo"},
    {"segments_mixed.vbo", "segments_mixed_gps_gap.vbo"},
    {"segments_mixed_gps_gap.vbo", "segments_mixed.vbo"},
    {"laps_clean.vbo", "laps_gps_gap.vbo"},
};

int firstEligible(const Recording &recording)
{
    for (const auto &lap : recording.laps.timedLaps)
        if (lap.referenceEligible()) return lap.number;
    return recording.laps.timedLaps.isEmpty() ? 0 : recording.laps.timedLaps.first().number;
}

// --- Hand-made cases ---------------------------------------------------------

constexpr double pi = 3.14159265358979323846;

QJsonObject segment(const QString &id, const QString &type, const double start, const double end,
    const QString &reference = configuration)
{
    return {{"id", id}, {"type", type}, {"name", id.toUpper()}, {"startProgressMeters", start},
            {"endProgressMeters", end}, {"trackConfigurationReference", reference}};
}

QJsonObject sharedCases()
{
    const QString other = QStringLiteral("compatibility-v1:") + QString("fedcba9876543210").repeated(4);
    const QJsonArray one{segment("c1", "corner", 100, 200), segment("t1", "straight", 200, 400)};
    const QJsonArray two{segment("c1", "corner", 100, 210), segment("t1", "straight", 210, 400)};
    const QJsonArray canonicalSet{segment("k1", "corner", 90, 190), segment("k2", "straight", 190, 380)};
    const QJsonArray elsewhere{segment("c1", "corner", 100, 200, other), segment("t1", "straight", 200, 400, other)};
    const QJsonArray malformed{QJsonObject{{"id", "x"}}};
    const QVector<std::pair<QString, QJsonValue>> stored{
        {"one", one}, {"two", two}, {"canonical", canonicalSet}, {"elsewhere", elsewhere},
        {"empty", QJsonArray{}}, {"malformed", malformed}, {"missing", QJsonValue()}};
    QJsonObject storedJson;
    for (const auto &[name, value] : stored) storedJson.insert(name, value);
    const auto approved = [&](const QString &name, const QString &reference = configuration) {
        for (const auto &[key, value] : stored)
            if (key == name) return approvedSegmentation(value, reference);
        return ApprovedSegmentation{};
    };
    struct Case { QString a, b, canonical, groupA, groupB, referenceB; };
    const QVector<Case> list{
        {"one", "one", "", "g", "g", ""}, {"one", "two", "", "g", "g", ""}, {"one", "two", "canonical", "g", "g", ""},
        {"one", "two", "canonical", "g", "h", ""}, {"one", "two", "canonical", "", "", ""},
        {"one", "one", "canonical", "g", "g", ""}, {"missing", "missing", "canonical", "g", "g", ""},
        {"malformed", "one", "canonical", "g", "g", ""}, {"one", "two", "empty", "g", "g", ""},
        {"one", "two", "malformed", "g", "g", ""}, {"elsewhere", "one", "", "g", "g", ""},
        {"one", "one", "", "g", "g", "other"}, {"one", "one", "canonical", "g", "g", "other"},
        {"empty", "empty", "", "g", "g", ""}, {"empty", "empty", "canonical", "g", "g", ""}};
    QJsonArray cases;
    for (const auto &item : list) {
        const auto approvedA = approved(item.a);
        const auto approvedB = approved(item.b, item.referenceB == "other" ? other : configuration);
        std::optional<ApprovedSegmentation> canonical;
        if (!item.canonical.isEmpty()) canonical = approved(item.canonical);
        const auto [shared, note] = sharedSegmentation(approvedA, approvedB, canonical, item.groupA, item.groupB);
        QJsonArray rows;
        if (shared)
            for (const auto &row : approvedSegments(*shared)) rows.append(QJsonObject::fromVariantMap(row.toMap()));
        cases.append(QJsonObject{{"a", item.a}, {"b", item.b}, {"canonical", item.canonical}, {"groupA", item.groupA},
                                 {"groupB", item.groupB}, {"referenceB", item.referenceB == "other" ? other : configuration},
                                 {"shared", shared ? QJsonValue(shared->revision) : QJsonValue()},
                                 {"note", note}, {"segments", rows}});
    }
    return {{"stored", storedJson}, {"other", other}, {"cases", cases}};
}

// One hand-made channel at 20 Hz from 0 to 19.95 s, values from `shape`,
// NaN in `nanFrom`..`nanTo`.
struct ChannelSpec {
    QString name;
    QString unit;
    std::function<double(double)> shape;
    double nanFrom = -1.0;
    double nanTo = -1.0;
};

TelemetrySession makeSession(const QVector<ChannelSpec> &specs, const QHash<QString, QString> &aliases, QJsonObject &json)
{
    TelemetrySession session;
    QJsonArray channels;
    for (const auto &spec : specs) {
        TelemetryChannel channel;
        channel.name = spec.name;
        channel.unit = spec.unit;
        QJsonArray times, values;
        for (int i = 0; i < 400; ++i) {
            const double time = i * 0.05;
            float value = static_cast<float>(spec.shape(time));
            if (time >= spec.nanFrom && time < spec.nanTo) value = std::nanf("");
            channel.timestamps.append(time);
            channel.values.append(value);
            times.append(time);
            values.append(number(value));
        }
        session.channels.insert(spec.name, channel);
        channels.append(QJsonObject{{"name", spec.name}, {"unit", spec.unit}, {"times", times}, {"values", values}});
    }
    QJsonObject aliasJson;
    for (auto it = aliases.cbegin(); it != aliases.cend(); ++it) aliasJson.insert(it.key(), it.value());
    session.aliases = aliases;
    session.duration = 19.95;
    json = {{"channels", channels}, {"aliases", aliasJson}};
    return session;
}

double brakeShape(const double t)
{
    const double s = std::max(0.0, std::sin(2.0 * pi * t / 3.1));
    return 50.0 * s * s;
}
double throttleShape(const double t) { return 50.0 + 50.0 * std::sin(2.0 * pi * t / 3.1 + pi); }
double accelerationShape(const double t) { return -0.6 * std::sin(2.0 * pi * t / 3.1); }
double speedShape(const double t) { return 100.0 + 30.0 * std::cos(2.0 * pi * t / 3.1); }
double slowerShape(const double t) { return 95.0 + 28.0 * std::cos(2.0 * pi * (t - 0.2) / 3.1); }
// Heart rate with zero placeholders, then a one-sample glitch.
double heartShape(const double t)
{
    if (t >= 4.0 && t < 4.5) return 0.0;
    if (std::abs(t - 9.0) < 1e-9) return 260.0;
    return 140.0 + 8.0 * std::sin(t / 2.0);
}
double otherHeartShape(const double t) { return 151.0 + 5.0 * std::cos(t / 3.0); }

QVector<std::pair<QString, std::pair<QVector<ChannelSpec>, QHash<QString, QString>>>> sessionSpecs()
{
    const ChannelSpec speed{"velocity", "km/h", speedShape};
    const ChannelSpec brake{"brake", "%", brakeShape, 15.0, 15.3};
    const ChannelSpec throttle{"throttle", "%", throttleShape, 15.0, 15.3};
    const ChannelSpec acceleration{"longacc", "g", accelerationShape};
    const ChannelSpec heart{"heart_rate", "bpm", heartShape, 12.0, 12.6};
    const QHash<QString, QString> all{{"speed", "velocity"}, {"brake", "brake"}, {"throttle", "throttle"},
                                      {"longitudinalAcceleration", "longacc"}, {"heartRate", "heart_rate"}};
    return {
        {"measured", {{speed, brake, throttle, acceleration, heart}, all}},
        {"slower", {{ChannelSpec{"velocity", "km/h", slowerShape}, brake, throttle, acceleration,
                     ChannelSpec{"hr", "bpm", otherHeartShape}},
                    {{"speed", "velocity"}, {"brake", "brake"}, {"throttle", "throttle"},
                     {"longitudinalAcceleration", "longacc"}, {"heartRate", "hr"}}}},
        {"inferred", {{speed, acceleration}, {{"speed", "velocity"}, {"longitudinalAcceleration", "longacc"}}}},
        {"undeclared", {{ChannelSpec{"velocity", "", speedShape}, ChannelSpec{"brake", "", brakeShape},
                         ChannelSpec{"throttle", "", throttleShape}}, {{"speed", "velocity"}, {"brake", "brake"}, {"throttle", "throttle"}}}},
        {"mismatch", {{ChannelSpec{"velocity", "mph", speedShape}, ChannelSpec{"brake", "bar", brakeShape},
                       ChannelSpec{"throttle", "Nm", throttleShape}, ChannelSpec{"longacc", "m/s2", accelerationShape}}, all}},
        {"noSpeed", {{brake, throttle}, {{"brake", "brake"}, {"throttle", "throttle"}}}},
    };
}

// A projection with progress = 100 m/s * (time - from), sampled every 0.05 s,
// split where `gaps` remove samples.
QVector<ProgressSegment> trace(const double from, const double to, const QVector<std::pair<double, double>> &gaps)
{
    QVector<ProgressSegment> result;
    ProgressSegment current;
    for (int i = 0;; ++i) {
        const double time = from + 0.05 * i;
        if (time > to + 1e-9) break;
        const double progress = 100.0 * (time - from);
        const bool removed = std::any_of(gaps.cbegin(), gaps.cend(),
            [progress](const auto &gap) { return progress > gap.first && progress < gap.second; });
        if (removed) {
            if (!current.samples.isEmpty()) result.append(current);
            current = {};
            continue;
        }
        current.samples.append({time, progress, true});
    }
    if (!current.samples.isEmpty()) result.append(current);
    return result;
}

QJsonArray traceJson(const QVector<ProgressSegment> &lap)
{
    QJsonArray result;
    for (const auto &segment : lap) {
        QJsonArray samples;
        for (const auto &sample : segment.samples) samples.append(QJsonArray{sample.telemetryTime, sample.progressMeters});
        result.append(samples);
    }
    return result;
}

// A 2000 m circle, one point a metre, as a closed progress axis.
ProgressAxis circleAxis()
{
    ProgressAxis axis;
    const double radius = 2000.0 / (2.0 * pi);
    for (int i = 0; i < 2000; ++i) {
        const double angle = 2.0 * pi * i / 2000.0;
        axis.points.append(QPointF(radius * std::sin(angle), radius - radius * std::cos(angle)));
        axis.cumulative.append(i);
    }
    axis.lengthMeters = 2000.0;
    axis.spacingMeters = 1.0;
    axis.valid = true;
    return axis;
}

QJsonObject handMadeCases()
{
    QJsonArray sessions;
    QHash<QString, TelemetrySession> made;
    for (const auto &[name, spec] : sessionSpecs()) {
        QJsonObject json;
        made.insert(name, makeSession(spec.first, spec.second, json));
        json.insert("name", name);
        sessions.append(json);
    }
    const QVector<std::pair<QString, QVector<ProgressSegment>>> traces{
        {"full", trace(0.0, 19.95, {})}, {"gapped", trace(0.0, 19.95, {{700.0, 760.0}})},
        {"late", trace(0.0, 19.95, {{1940.0, 2000.0}})}};
    QJsonObject traceInputs;
    for (const auto &[name, value] : traces) traceInputs.insert(name, traceJson(value));
    const QVector<std::pair<QString, QJsonArray>> segmentSets{
        {"partition", QJsonArray{segment("c1", "corner", 300, 500), segment("t1", "straight", 500, 900),
                                 segment("c2", "corner", 900, 1100), segment("c3", "corner", 1150, 1300),
                                 segment("x1", "sector", 1300, 1900), segment("c4", "corner", 1900, 1995)}},
        {"gate", QJsonArray{segment("c1", "corner", 50, 250), segment("t1", "straight", 250, 600),
                            segment("c2", "corner", 1800, 20)}},
    };
    QJsonObject segmentInputs;
    for (const auto &[name, value] : segmentSets) segmentInputs.insert(name, value);
    const auto axis = circleAxis();
    struct PairCase { QString a, traceA, b, traceB; };
    const QVector<PairCase> pairs{
        {"measured", "full", "slower", "full"}, {"measured", "full", "inferred", "gapped"},
        {"inferred", "full", "measured", "late"}, {"undeclared", "full", "mismatch", "full"},
        {"noSpeed", "gapped", "measured", "full"}, {"slower", "late", "slower", "gapped"}};
    const auto traceNamed = [&](const QString &name) {
        for (const auto &[key, value] : traces) if (key == name) return value;
        return QVector<ProgressSegment>{};
    };
    QJsonArray results;
    for (const auto &item : pairs) {
        Lap pair[2];
        pair[0] = {&made[item.a], traceNamed(item.traceA), 0.0, 19.95, lapReference(item.a, 1, 0.0)};
        pair[1] = {&made[item.b], traceNamed(item.traceB), 0.0, 19.95, lapReference(item.b, 2, 0.0)};
        for (const auto &[setName, stored] : segmentSets) {
            auto entry = analyzerJson(axis, pair, approvedSegmentation(stored, configuration));
            QJsonArray ranges;
            for (const auto &[from, to] : QVector<std::pair<double, double>>{
                     {0.0, 1000.0}, {1500.0, 500.0}, {0.0, 2000.0}, {650.0, 800.0}, {-50.0, 2500.0}, {400.0, 400.0}})
                ranges.append(QJsonObject{{"start", from}, {"end", to},
                                          {"result", QJsonObject::fromVariantMap(heartRate(axis, pair, from, to))}});
            entry.insert("ranges", ranges);
            entry.insert("a", item.a);
            entry.insert("traceA", item.traceA);
            entry.insert("b", item.b);
            entry.insert("traceB", item.traceB);
            entry.insert("segmentSet", setName);
            results.append(entry);
        }
    }
    return {{"configuration", configuration}, {"axis", axisJson(axis)}, {"sessions", sessions},
            {"traces", traceInputs}, {"segments", segmentInputs}, {"pairs", results}};
}

QJsonObject cases()
{
    return {{"shared", sharedCases()}, {"handMade", handMadeCases()}};
}

void write(const QString &path, const QJsonObject &document)
{
    QFile output(path);
    if (!output.open(QIODevice::WriteOnly)) std::exit(1);
    output.write(QJsonDocument(document).toJson(QJsonDocument::Compact));
}

QJsonObject axesJson(const QHash<QString, QJsonObject> &axes)
{
    QJsonObject result;
    for (auto it = axes.cbegin(); it != axes.cend(); ++it) result.insert(it.key(), it.value());
    return result;
}

int runDay(const QString &dayPath, const QString &outputPath)
{
    QFile file(dayPath);
    if (!file.open(QIODevice::ReadOnly)) return 1;
    const auto day = QJsonDocument::fromJson(file.readAll()).object();
    QHash<QString, Recording> recordings;
    for (const auto &value : day.value("runs").toArray()) {
        const auto run = value.toObject();
        auto recording = load(run.value("file").toString());
        if (!recording) return 1;
        recordings.insert(run.value("runId").toString(), *recording);
    }
    const auto from = day.value("segmentsFrom").toObject();
    const auto sets = segmentSets(recordings[from.value("runId").toString()], from.value("lapNumber").toInt());
    QHash<QString, QJsonObject> axes;
    QJsonArray pairs;
    for (const auto &value : day.value("pairs").toArray()) {
        const auto pair = value.toObject();
        const auto a = pair.value("a").toObject(), b = pair.value("b").toObject();
        const auto runA = a.value("runId").toString(), runB = b.value("runId").toString();
        if (auto entry = pairJson(runA, recordings[runA], a.value("lapNumber").toInt(), runB, recordings[runB],
                b.value("lapNumber").toInt(), sets, axes))
            pairs.append(*entry);
    }
    QJsonObject files;
    for (auto it = recordings.cbegin(); it != recordings.cend(); ++it) files.insert(it.key(), it.value().file);
    write(outputPath, {{"configuration", configuration}, {"pairs", pairs}, {"axes", axesJson(axes)}, {"files", files}});
    return 0;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc >= 4 && std::strcmp(argv[1], "--day") == 0)
        return runDay(QString::fromLocal8Bit(argv[2]), QString::fromLocal8Bit(argv[3]));
    if (argc < 3) {
        std::fprintf(stderr, "usage: %s <output.json> <input>... | --day <day.json> <output.json>\n", argv[0]);
        return 2;
    }
    QVector<Recording> recordings;
    for (int index = 2; index < argc; ++index)
        if (auto recording = load(QString::fromLocal8Bit(argv[index]))) recordings.append(std::move(*recording));
    QHash<QString, QJsonObject> axes;
    QJsonArray pairs;
    for (const auto &recording : recordings) {
        const auto list = pairsOf(recording);
        if (list.isEmpty()) continue;
        const auto sets = segmentSets(recording, fastestEligible(recording));
        for (const auto &[a, b] : list)
            if (auto entry = pairJson(recording.file, recording, a, recording.file, recording, b, sets, axes))
                pairs.append(*entry);
    }
    for (const auto &[nameA, nameB] : crossFilePairs) {
        const auto a = std::find_if(recordings.cbegin(), recordings.cend(), [&](const Recording &r) { return r.file == nameA; });
        const auto b = std::find_if(recordings.cbegin(), recordings.cend(), [&](const Recording &r) { return r.file == nameB; });
        if (a == recordings.cend() || b == recordings.cend()) continue;
        const auto sets = segmentSets(*a, fastestEligible(*a));
        if (auto entry = pairJson(a->file, *a, firstEligible(*a), b->file, *b, firstEligible(*b), sets, axes))
            pairs.append(*entry);
    }
    write(QString::fromLocal8Bit(argv[1]),
          {{"configuration", configuration}, {"pairs", pairs}, {"axes", axesJson(axes)}, {"cases", cases()}});
    return 0;
}
