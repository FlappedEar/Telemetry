// Prints FlappedEar Overlays' Corner Analyzer results as one JSON document:
//   cpp_corner_metrics_dump <output.json> <input.vbo>...
//   cpp_corner_metrics_dump --day <day.json> <output.json>
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession; files without lap traces, a start gate or an
// eligible lap are skipped. As in cpp_theoretical_best_dump, a file becomes a
// day of two runs ("run-a" with its odd laps, "run-b" with its even laps) and
// the fastest eligible lap's segment proposals are approved into its run with
// ids s0, s1, ..., also shifted 37 m (the last one crossing the gate) and
// thinned to every other segment. For each set it follows the loop of
// calculateOutingTheoreticalBest with the sessions in memory (one axis from
// the canonical run's fastest lap, 6 m features, every lap projected) and
// writes, for every lap and corner segment, computeCornerSpeeds,
// computeBrakingMetrics and computeExitMetrics in full and the KAN-63
// observation; the geometric phases of every segment; the published
// variability (publishTheoreticalBest); and each lap compared with the best
// lap. The shared axis is written in full. A --day file (see cpp_theoretical_best_dump) does the same for a real
// day. The cases section runs detectBrakingOnsets, computeBrakingMetrics and
// computeExitMetrics on hand-made sessions and projections, and
// lateralOffsetMeters and summarizeCornerVariability on fixed inputs. NaN is
// written as null.

#include "telemetry/BrakingMetrics.h"
#include "telemetry/BrakingOnset.h"
#include "telemetry/CornerPhases.h"
#include "telemetry/CornerSpeeds.h"
#include "telemetry/DrivingVariability.h"
#include "telemetry/ExitMetrics.h"
#include "telemetry/LapTiming.h"
#include "telemetry/OutingTheoreticalBest.h"
#include "telemetry/OutingTheoreticalBestResults.h"
#include "telemetry/SectorTiming.h"
#include "telemetry/TelemetryGeometry.h"
#include "telemetry/TheoreticalBest.h"
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
#include <optional>
#include <stdexcept>

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

struct Run {
    QString id;
    const TelemetrySession *session = nullptr;
    const LapSession *laps = nullptr;
};

struct Row {
    QString runId;
    int lapNumber = 0;
    double start = 0.0;
    double end = 0.0;
    QJsonObject reference;
};

QJsonObject lapReference(const QString &runId, const int lapNumber, const double start)
{
    return {{"runId", runId}, {"lapNumber", lapNumber}, {"startTime", start}};
}

QString lapKey(const QJsonObject &reference)
{
    if (reference.isEmpty()) return {};
    return reference.value("runId").toString() + "#" + QString::number(reference.value("lapNumber").toInt());
}

GeoCoordinate gateMidpoint(const TimingGate &gate)
{
    return {(gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
            (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0};
}

QJsonObject phaseJson(const CornerPhasePoint &point)
{
    return {{"method", point.method}, {"progress", number(point.progressMeters)},
            {"tolerance", number(point.toleranceMeters)}, {"uncertainty", strings(point.uncertaintyReasons)},
            {"reason", point.unresolvedReason}, {"evidence", point.evidence}};
}

QJsonObject speedJson(const CornerSpeedValue &value)
{
    return {{"value", optional(value.value)}, {"progress", number(value.progressMeters)},
            {"time", optional(value.telemetryTime)}, {"reason", value.unavailableReason},
            {"limitations", strings(value.limitations)}};
}

QJsonObject speedsJson(const CornerSpeeds &speeds)
{
    return {{"valid", speeds.valid}, {"segmentId", speeds.segmentId}, {"name", speeds.name}, {"type", speeds.type},
            {"channel", speeds.channel}, {"unit", speeds.unit}, {"provenance", speeds.provenance},
            {"entry", speedJson(speeds.entry)}, {"apex", speedJson(speeds.apex)},
            {"minimum", speedJson(speeds.minimum)}, {"exit", speedJson(speeds.exit)},
            {"lengthMeters", number(speeds.lengthMeters)}, {"coveredMeters", number(speeds.coveredMeters)},
            {"spacing", number(speeds.meanSampleSpacingMeters)}, {"revision", speeds.stamp.revision},
            {"algorithm", speeds.stamp.calculationAlgorithm}};
}

QJsonObject brakingJson(const BrakingMetrics &braking)
{
    return {{"valid", braking.valid}, {"segmentId", braking.segmentId},
            {"intervalStart", number(braking.intervalStartMeters)}, {"intervalEnd", number(braking.intervalEndMeters)},
            {"entry", number(braking.entryMeters)}, {"reason", braking.unavailableReason},
            {"method", braking.method}, {"provenance", braking.provenance}, {"channel", braking.channel},
            {"thresholdUnit", braking.thresholdUnit}, {"onThreshold", number(braking.onThreshold)},
            {"point", optional(braking.brakingPointMeters)}, {"pointTime", optional(braking.brakingPointTime)},
            {"beforeEntry", optional(braking.distanceBeforeEntryMeters)},
            {"seconds", optional(braking.brakingSeconds)}, {"distance", optional(braking.brakingDistanceMeters)},
            {"limitations", strings(braking.limitations)},
            {"decelerationChannel", braking.decelerationChannel}, {"decelerationUnit", braking.decelerationUnit},
            {"peak", optional(braking.peakDeceleration)}, {"mean", optional(braking.meanDeceleration)},
            {"decelerationReason", braking.decelerationUnavailableReason}, {"revision", braking.stamp.revision},
            {"algorithm", braking.stamp.calculationAlgorithm}};
}

QJsonObject exitJson(const ExitMetrics &exit)
{
    const auto &pickup = exit.pickup;
    return {{"valid", exit.valid}, {"segmentId", exit.segmentId},
            {"pickup", QJsonObject{{"method", pickup.method}, {"provenance", pickup.provenance},
                                   {"channel", pickup.channel}, {"unit", pickup.unit},
                                   {"on", number(pickup.threshold.on)}, {"off", number(pickup.threshold.off)},
                                   {"thresholdUnit", pickup.threshold.unit},
                                   {"progress", optional(pickup.progressMeters)},
                                   {"time", optional(pickup.telemetryTime)}, {"reason", pickup.unavailableReason},
                                   {"limitations", strings(pickup.limitations)}}},
            {"source", exit.intervalSource}, {"intervalStart", number(exit.intervalStartMeters)},
            {"intervalEnd", number(exit.intervalEndMeters)}, {"speedChannel", exit.speedChannel},
            {"speedUnit", exit.speedUnit}, {"exitSpeed", optional(exit.exitSpeed)},
            {"endSpeed", optional(exit.intervalEndSpeed)}, {"elapsed", optional(exit.elapsedSeconds)},
            {"reason", exit.downstreamUnavailableReason}, {"revision", exit.stamp.revision},
            {"algorithm", exit.stamp.calculationAlgorithm}};
}

QJsonObject observationJson(const CornerLapObservation &observation)
{
    return {{"braking", optional(observation.brakingPointMeters)}, {"brakingProvenance", observation.brakingProvenance},
            {"apex", optional(observation.apexSpeed)}, {"minimum", optional(observation.minimumSpeed)},
            {"exit", optional(observation.exitSpeed)}, {"pickup", optional(observation.pickupMeters)},
            {"pickupProvenance", observation.pickupProvenance}, {"line", optional(observation.lineOffsetMeters)},
            {"accuracy", optional(observation.gpsAccuracyMeters)}};
}

QJsonObject summaryJson(const ConsistencySummary &summary)
{
    return QJsonObject::fromVariantMap(consistencySummaryMap(summary));
}

QJsonObject variabilityJson(const CornerVariability &variability)
{
    return {{"segmentId", variability.segmentId}, {"name", variability.name},
            {"brakingPointMeasured", summaryJson(variability.brakingPointMeasured)},
            {"brakingPointInferred", summaryJson(variability.brakingPointInferred)},
            {"apexSpeed", summaryJson(variability.apexSpeed)}, {"minimumSpeed", summaryJson(variability.minimumSpeed)},
            {"exitSpeed", summaryJson(variability.exitSpeed)}, {"pickupMeasured", summaryJson(variability.pickupMeasured)},
            {"pickupInferred", summaryJson(variability.pickupInferred)}, {"lineOffset", summaryJson(variability.lineOffset)},
            {"typicalGpsAccuracyMeters", optional(variability.typicalGpsAccuracyMeters)},
            {"lineSpreadResolvable", variability.lineSpreadResolvable}};
}

struct CornerLap {
    QJsonObject reference;
    QString segmentId;
    CornerSpeeds speeds;
    BrakingMetrics braking;
    ExitMetrics exit;
};

struct Calculated {
    OutingTheoreticalBest computed;
    TrackFeatures features;
    QVector<CornerLap> corners; // lap by lap, corner by corner
};

// The loop of calculateOutingTheoreticalBest with the sessions in memory,
// keeping each corner's metrics in full. Overlays sorts with std::sort; a
// stable sort keeps laps of a run in their order, as the Dart port does.
Calculated calculate(QVector<Row> population, const QHash<QString, Run> &runs,
    const ApprovedSegmentation &approved, const QString &canonicalRunId, const QJsonObject &actualBestReference)
{
    Calculated calculated;
    auto &result = calculated.computed;
    result.canonicalRunId = canonicalRunId;
    try {
        std::stable_sort(population.begin(), population.end(),
            [](const Row &a, const Row &b) { return a.runId < b.runId; });
        auto canonical = population.cend();
        for (auto it = population.cbegin(); it != population.cend(); ++it) {
            if (it->runId != canonicalRunId) continue;
            if (canonical == population.cend() || it->end - it->start < canonical->end - canonical->start) canonical = it;
        }
        if (canonical == population.cend()) throw std::runtime_error("The canonical run has no eligible lap in this population.");
        const auto &axisRun = runs.value(canonicalRunId);
        const auto trace = std::find_if(axisRun.laps->lapTraces.cbegin(), axisRun.laps->lapTraces.cend(),
            [&](const LapTrace &candidate) { return candidate.lapNumber == canonical->lapNumber; });
        if (!axisRun.laps->selectedStartGate || trace == axisRun.laps->lapTraces.cend())
            throw std::runtime_error("Could not build a shared track axis from the canonical run.");
        const auto &gate = *axisRun.laps->selectedStartGate;
        const auto axis = buildProgressAxis(*trace, gateMidpoint(gate), gate);
        if (!axis.valid) throw std::runtime_error("The shared track axis could not be built from the canonical run's GPS trace.");
        const auto features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
        calculated.features = features;
        QVector<std::pair<QString, std::pair<double, double>>> corners;
        for (const auto &value : approved.segments) {
            const auto segment = value.toObject();
            if (segment.value("type").toString() == trackSegmentTypeName(TrackSegmentType::Corner))
                corners.append({segment.value("id").toString(),
                    {segment.value("startProgressMeters").toDouble(), segment.value("endProgressMeters").toDouble()}});
        }
        QVector<LapSectorTimes> populationTimes;
        for (const auto &row : population) {
            if (!runs.contains(row.runId)) continue;
            const auto &session = *runs.value(row.runId).session;
            const auto projected = projectLapTrace(axis, session, row.start, row.end);
            populationTimes.append(computeLapSectorTimes(approved, axis.lengthMeters, projected, row.start, row.end, row.reference));
            result.population.append({populationTimes.last(), row.start});
            for (const auto &[segmentId, bounds] : corners) {
                CornerLapObservation observation;
                observation.lapReference = row.reference;
                const auto speeds = computeCornerSpeeds(axis, features, approved, segmentId, projected, session);
                if (speeds.valid) {
                    observation.apexSpeed = speeds.apex.value;
                    observation.minimumSpeed = speeds.minimum.value;
                    observation.exitSpeed = speeds.exit.value;
                }
                const auto braking = computeBrakingMetrics(axis.lengthMeters, approved, segmentId, projected, session,
                    row.start, row.end);
                if (braking.valid && braking.brakingPointMeters) {
                    observation.brakingPointMeters = braking.brakingPointMeters;
                    observation.brakingProvenance = braking.provenance;
                }
                const auto exit = computeExitMetrics(axis.lengthMeters, approved, segmentId, projected, session, row.end);
                if (exit.valid && exit.pickup.progressMeters) {
                    observation.pickupMeters = exit.pickup.progressMeters;
                    observation.pickupProvenance = exit.pickup.provenance;
                }
                const auto [start, end] = bounds;
                const double middle = end >= start ? (start + end) / 2.0
                    : std::fmod(start + (end + axis.lengthMeters - start) / 2.0, axis.lengthMeters);
                const double at = speeds.valid && speeds.apex.value ? speeds.apex.progressMeters : middle;
                if (const auto time = timeAtProgress(projected, at)) {
                    const auto latitude = session.valueAt("latitude", *time);
                    const auto longitude = session.valueAt("longitude", *time);
                    if (latitude && longitude) {
                        const auto local = projectCoordinate({*latitude, *longitude}, axis.origin);
                        observation.lineOffsetMeters = lateralOffsetMeters(axis, at, QPointF(local.eastMeters, local.northMeters));
                    }
                    observation.gpsAccuracyMeters = session.valueAt("accuracy", *time);
                }
                result.cornerObservations[segmentId].append(observation);
                calculated.corners.append({row.reference, segmentId, speeds, braking, exit});
            }
            if (!actualBestReference.isEmpty() && row.reference == actualBestReference)
                result.actualBest = populationTimes.last();
        }
        result.best = computeTheoreticalBest(approved, populationTimes);
        result.approved = approved;
        result.axisLengthMeters = axis.lengthMeters;
        result.axis = axis;
    } catch (const std::exception &error) {
        result.error = QString::fromUtf8(error.what());
    }
    return calculated;
}

QString label(const QJsonObject &reference)
{
    return QStringLiteral("%1 · LAP %2").arg(reference.value("runId").toString()).arg(reference.value("lapNumber").toInt());
}

QJsonObject dayJson(const QVector<Row> &population, const QHash<QString, Run> &runs,
    const QHash<QString, QJsonValue> &storedSegments, const QJsonObject &actualBestReference)
{
    QStringList runOrder;
    for (const auto &row : population) if (!runOrder.contains(row.runId)) runOrder.append(row.runId);
    std::sort(runOrder.begin(), runOrder.end());
    QString canonicalRunId;
    ApprovedSegmentation approved;
    for (const auto &runId : runOrder) {
        auto candidate = approvedSegmentation(storedSegments.value(runId), configuration);
        if (candidate.valid && !candidate.revision.isEmpty() && !candidate.segments.isEmpty()) {
            canonicalRunId = runId;
            approved = candidate;
            break;
        }
    }
    QJsonObject entry{{"canonicalRunId", canonicalRunId}};
    if (canonicalRunId.isEmpty()) return entry;
    entry.insert("revision", approved.revision);
    const auto calculated = calculate(population, runs, approved, canonicalRunId, actualBestReference);
    const auto &computed = calculated.computed;
    entry.insert("error", computed.error);
    if (!computed.error.isEmpty()) return entry;
    entry.insert("axis", QJsonObject{{"pointCount", computed.axis.points.size()},
                                     {"lengthMeters", number(computed.axisLengthMeters)}});

    // The geometric phases of every segment on the shared axis.
    QJsonArray phases;
    for (const auto &value : approved.segments) {
        const auto segment = value.toObject();
        const auto corner = cornerFromSegment(computed.axis, calculated.features, segment);
        const auto geometry = proposeCornerGeometryPhases(computed.axis, calculated.features, corner);
        QJsonArray candidates;
        for (const double candidate : geometry.apexCandidatesMeters) candidates.append(number(candidate));
        phases.append(QJsonObject{{"segmentId", segment.value("id").toString()},
                                  {"cornerType", trackSegmentTypeName(corner.type)},
                                  {"turn", number(corner.turnRadians)}, {"peak", number(corner.peakCurvaturePerMeter)},
                                  {"lengthMeters", number(corner.lengthMeters)}, {"valid", geometry.valid},
                                  {"entry", phaseJson(geometry.entry)}, {"apex", phaseJson(geometry.apex)},
                                  {"exit", phaseJson(geometry.exit)}, {"candidates", candidates}});
    }
    entry.insert("phases", phases);

    QJsonArray laps;
    QHash<QString, const CornerLap *> bestCorners;
    for (const auto &corner : calculated.corners) {
        if (corner.reference == actualBestReference) bestCorners.insert(corner.segmentId, &corner);
    }
    QJsonArray comparisons;
    for (const auto &corner : calculated.corners) {
        laps.append(QJsonObject{{"lap", lapKey(corner.reference)}, {"segmentId", corner.segmentId},
                                {"speeds", speedsJson(corner.speeds)}, {"braking", brakingJson(corner.braking)},
                                {"exit", exitJson(corner.exit)}});
        const auto *best = bestCorners.value(corner.segmentId);
        if (!best) continue;
        const auto speeds = compareCornerSpeeds(corner.speeds, best->speeds);
        const auto braking = compareBrakingMetrics(corner.braking, best->braking);
        const auto exit = compareExitMetrics(corner.exit, best->exit);
        comparisons.append(QJsonObject{
            {"lap", lapKey(corner.reference)}, {"segmentId", corner.segmentId},
            {"speeds", QJsonObject{{"valid", speeds.valid}, {"reason", speeds.unavailableReason},
                                   {"entry", optional(speeds.entryDelta)}, {"apex", optional(speeds.apexDelta)},
                                   {"minimum", optional(speeds.minimumDelta)}, {"exit", optional(speeds.exitDelta)}}},
            {"braking", QJsonObject{{"valid", braking.valid}, {"reason", braking.unavailableReason},
                                    {"point", optional(braking.brakingPointDeltaMeters)},
                                    {"seconds", optional(braking.brakingSecondsDelta)},
                                    {"distance", optional(braking.brakingDistanceDeltaMeters)},
                                    {"peak", optional(braking.peakDecelerationDelta)},
                                    {"mean", optional(braking.meanDecelerationDelta)}}},
            {"exit", QJsonObject{{"valid", exit.valid}, {"pickupReason", exit.pickupUnavailableReason},
                                 {"pickup", optional(exit.pickupDeltaMeters)}, {"exitSpeed", optional(exit.exitSpeedDelta)},
                                 {"endSpeed", optional(exit.intervalEndSpeedDelta)},
                                 {"elapsed", optional(exit.elapsedSecondsDelta)}}}});
    }
    entry.insert("corners", laps);
    entry.insert("comparisons", comparisons);
    // In segment order: cornerObservations is a QHash, whose order changes
    // from run to run.
    QJsonArray observations;
    for (const auto &value : approved.segments) {
        const auto segmentId = value.toObject().value("id").toString();
        for (const auto &observation : computed.cornerObservations.value(segmentId)) {
            auto item = observationJson(observation);
            item.insert("lap", lapKey(observation.lapReference));
            item.insert("segmentId", segmentId);
            observations.append(item);
        }
    }
    entry.insert("observations", observations);

    // The published variability, as the theoretical-best dialog reads it.
    const auto published = publishTheoreticalBest(computed, "ready", {}, label);
    QJsonArray variability;
    for (const auto &value : published.value("sectors").toList()) {
        const auto row = value.toMap();
        if (!row.contains("variability")) continue;
        auto item = QJsonObject::fromVariantMap(row.value("variability").toMap());
        item.insert("segmentId", row.value("segmentId").toString());
        variability.append(item);
    }
    entry.insert("variability", variability);
    entry.insert("variabilityAlgorithm", published.value("variabilityAlgorithm").toString());
    return entry;
}

// The shared axis in full: the Dart port runs the metrics on it, so a
// segment bound on an axis sample is inside on both sides.
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

std::optional<QJsonObject> runFile(const QString &path)
{
    TelemetrySession session;
    LapSession laps;
    try {
        session = VboParser::parseFile(path);
        laps = deriveSourceLapSession(session);
    } catch (const std::exception &) {
        return std::nullopt;
    }
    if (laps.lapTraces.isEmpty() || !laps.selectedStartGate) return std::nullopt;
    QVector<Row> population;
    const TimedLap *best = nullptr;
    for (const auto &lap : laps.timedLaps) {
        if (!lap.referenceEligible()) continue;
        const QString runId = lap.number % 2 == 1 ? "run-a" : "run-b";
        population.append({runId, lap.number, lap.startTelemetryTime, lap.endTelemetryTime,
                           lapReference(runId, lap.number, lap.startTelemetryTime)});
        if (!best || lap.durationSeconds < best->durationSeconds) best = &lap;
    }
    if (!best) return std::nullopt;
    const auto trace = std::find_if(laps.lapTraces.cbegin(), laps.lapTraces.cend(),
        [best](const LapTrace &candidate) { return candidate.lapNumber == best->number; });
    if (trace == laps.lapTraces.cend()) return std::nullopt;
    const auto &gate = *laps.selectedStartGate;
    const auto axis = buildProgressAxis(*trace, gateMidpoint(gate), gate);
    const auto features = axis.valid ? computeTrackFeatures(axis, segmentReviewSmoothingMeters) : TrackFeatures{};
    if (!features.valid) return std::nullopt;
    const auto proposals = proposeTrackSegments(axis, features, {});
    const auto automatic = withIds(proposalsToTrackSegments(proposals, configuration));
    if (automatic.isEmpty()) return std::nullopt;

    QHash<QString, Run> runs{{"run-a", {"run-a", &session, &laps}}, {"run-b", {"run-b", &session, &laps}}};
    const QString bestRun = best->number % 2 == 1 ? "run-a" : "run-b";
    const auto actualBest = lapReference(bestRun, best->number, best->startTelemetryTime);
    QJsonArray variants;
    const QVector<std::pair<QString, QJsonArray>> sets{
        {"automatic", automatic}, {"shifted", shifted(automatic, axis.lengthMeters)}, {"everyOther", everyOther(automatic)}};
    for (const auto &[name, segments] : sets) {
        if (segments.isEmpty()) continue;
        auto entry = dayJson(population, runs, {{bestRun, segments}}, actualBest);
        entry.insert("name", name);
        entry.insert("segments", QJsonObject{{bestRun, segments}});
        variants.append(entry);
    }
    QJsonArray populationJson;
    for (const auto &row : population)
        populationJson.append(QJsonObject{{"runId", row.runId}, {"lapNumber", row.lapNumber}});
    return QJsonObject{{"file", QFileInfo(path).fileName()}, {"population", populationJson},
                       {"actualBest", lapKey(actualBest)}, {"variants", variants}, {"axis", axisJson(axis)}};
}

int runDay(const QString &input, const QString &outputPath)
{
    QFile file(input);
    if (!file.open(QIODevice::ReadOnly)) return 1;
    const auto day = QJsonDocument::fromJson(file.readAll()).object();
    QVector<TelemetrySession> sessions;
    QVector<LapSession> lapSessions;
    const auto runList = day.value("runs").toArray();
    sessions.reserve(runList.size());
    lapSessions.reserve(runList.size());
    QHash<QString, Run> runs;
    for (const auto &value : runList) {
        const auto run = value.toObject();
        sessions.append(VboParser::parseFile(run.value("file").toString()));
        lapSessions.append(deriveSourceLapSession(sessions.last()));
        runs.insert(run.value("runId").toString(), {run.value("runId").toString(), &sessions.last(), &lapSessions.last()});
    }
    QVector<Row> population;
    for (const auto &value : day.value("population").toArray()) {
        const auto row = value.toObject();
        population.append({row.value("runId").toString(), row.value("lapNumber").toInt(), row.value("start").toDouble(),
                           row.value("end").toDouble(),
                           lapReference(row.value("runId").toString(), row.value("lapNumber").toInt(), row.value("start").toDouble())});
    }
    QHash<QString, QJsonValue> stored;
    const auto segments = day.value("segments").toObject();
    for (auto it = segments.begin(); it != segments.end(); ++it) stored.insert(it.key(), it.value());
    const auto best = day.value("actualBest").toObject();
    QJsonObject actualBest;
    for (const auto &row : population)
        if (row.runId == best.value("runId").toString() && row.lapNumber == best.value("lapNumber").toInt()) actualBest = row.reference;
    if (day.contains("configuration") && day.value("configuration").toString() != configuration) {
        std::fprintf(stderr, "segments must use the tool's configuration reference\n");
        return 2;
    }
    QFile output(outputPath);
    if (!output.open(QIODevice::WriteOnly)) return 1;
    auto entry = dayJson(population, runs, stored, actualBest);
    QString canonicalRunId = entry.value("canonicalRunId").toString();
    const Row *canonical = nullptr;
    for (const auto &row : population)
        if (row.runId == canonicalRunId && (!canonical || row.end - row.start < canonical->end - canonical->start)) canonical = &row;
    if (canonical) {
        const auto &laps = *runs.value(canonicalRunId).laps;
        for (const auto &trace : laps.lapTraces) {
            if (trace.lapNumber != canonical->lapNumber || !laps.selectedStartGate) continue;
            entry.insert("axisFull", axisJson(buildProgressAxis(trace, gateMidpoint(*laps.selectedStartGate), *laps.selectedStartGate)));
        }
    }
    output.write(QJsonDocument(entry).toJson(QJsonDocument::Compact));
    return 0;
}

// --- Hand-made sessions ----------------------------------------------------

constexpr double pi = 3.14159265358979323846;

// One hand-made channel: 20 Hz from 0 to 19.95 s, values from `shape`, with
// every sample in (12.0, 12.6) removed (a gap) and NaN in `nanFrom`..`nanTo`.
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
            if (time > 12.0 && time < 12.6) continue;
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
    return std::abs(t - 7.0) < 1e-9 ? 25.0 : 50.0 * s * s;
}
double throttleShape(const double t) { return 50.0 + 50.0 * std::sin(2.0 * pi * t / 3.1 + pi); }
double accelerationShape(const double t) { return -0.6 * std::sin(2.0 * pi * t / 3.1); }
double speedShape(const double t) { return 100.0 + 30.0 * std::cos(2.0 * pi * t / 3.1); }

QVector<std::pair<QString, std::pair<QVector<ChannelSpec>, QHash<QString, QString>>>> sessionSpecs()
{
    const ChannelSpec speed{"velocity", "km/h", speedShape};
    const ChannelSpec brake{"brake", "%", brakeShape, 15.0, 15.3};
    const ChannelSpec throttle{"throttle", "%", throttleShape, 15.0, 15.3};
    const ChannelSpec acceleration{"longacc", "g", accelerationShape};
    const QHash<QString, QString> all{{"speed", "velocity"}, {"brake", "brake"}, {"throttle", "throttle"},
                                      {"longitudinalAcceleration", "longacc"}};
    return {
        {"measured", {{speed, brake, throttle, acceleration}, all}},
        {"inferred", {{speed, acceleration}, {{"speed", "velocity"}, {"longitudinalAcceleration", "longacc"}}}},
        {"undeclared", {{ChannelSpec{"velocity", "", speedShape}, ChannelSpec{"brake", "", brakeShape},
                         ChannelSpec{"throttle", "", throttleShape}}, {{"speed", "velocity"}, {"brake", "brake"}, {"throttle", "throttle"}}}},
        {"mismatch", {{speed, ChannelSpec{"brake", "bar", brakeShape}, ChannelSpec{"throttle", "Nm", throttleShape},
                       ChannelSpec{"longacc", "m/s2", accelerationShape}}, all}},
        {"none", {{speed}, {{"speed", "velocity"}}}},
        {"noSpeed", {{brake, throttle}, {{"brake", "brake"}, {"throttle", "throttle"}}}},
        {"upperCase", {{speed, ChannelSpec{"brake", " % ", brakeShape}, ChannelSpec{"longacc", "G", accelerationShape}},
                       {{"speed", "velocity"}, {"brake", "brake"}, {"longitudinalAcceleration", "longacc"}}}},
    };
}

// A projection with progress = 100 m/s * time, sampled every 0.05 s, split
// where `gaps` remove samples.
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

QJsonObject segment(const QString &id, const QString &type, const double start, const double end)
{
    return {{"id", id}, {"type", type}, {"name", id.toUpper()}, {"startProgressMeters", start},
            {"endProgressMeters", end}, {"trackConfigurationReference", configuration}};
}

QJsonObject detectionJson(const BrakingOnsetDetection &detection)
{
    QJsonArray candidates;
    for (const auto &candidate : detection.candidates) {
        candidates.append(QJsonObject{{"time", number(candidate.telemetryTime)},
                                      {"tolerance", number(candidate.toleranceSeconds)},
                                      {"duration", number(candidate.durationSeconds)}, {"peak", number(candidate.peakValue)},
                                      {"progress", optional(candidate.progressMeters)},
                                      {"uncertainty", strings(candidate.uncertaintyReasons)}});
    }
    return {{"valid", detection.valid}, {"method", detection.method}, {"provenance", detection.provenance},
            {"channel", detection.channel}, {"channelUnit", detection.channelUnit},
            {"on", number(detection.threshold.on)}, {"off", number(detection.threshold.off)},
            {"thresholdUnit", detection.threshold.unit}, {"minimumDuration", number(detection.minimumDurationSeconds)},
            {"candidates", candidates}, {"rejectedSpikes", detection.rejectedSpikes}, {"gaps", detection.gaps},
            {"reason", detection.unresolvedReason}};
}

QJsonObject cases()
{
    QJsonArray sessions, onsets, metrics;
    const auto lap = trace(0.0, 19.95, {});
    const auto gapped = trace(0.0, 19.95, {{700.0, 760.0}});
    const QVector<std::pair<QString, QVector<ProgressSegment>>> traces{{"full", lap}, {"gapped", gapped}};
    QJsonObject traceInputs;
    for (const auto &[name, value] : traces) traceInputs.insert(name, traceJson(value));
    const QVector<std::pair<QString, QJsonArray>> segmentSets{
        {"partition", QJsonArray{segment("c1", "corner", 300, 500), segment("t1", "straight", 500, 900),
                                 segment("c2", "corner", 900, 1100), segment("c3", "corner", 1150, 1300),
                                 segment("x1", "sector", 1300, 1900), segment("c4", "corner", 1900, 1995)}},
        {"gate", QJsonArray{segment("c1", "corner", 50, 250), segment("t1", "straight", 250, 600),
                            segment("c2", "corner", 1800, 20)}},
        {"end", QJsonArray{segment("t0", "straight", 1400, 1700), segment("c1", "corner", 1700, 2000)}},
    };
    QJsonObject segmentInputs;
    for (const auto &[name, value] : segmentSets) segmentInputs.insert(name, value);

    for (const auto &[name, spec] : sessionSpecs()) {
        QJsonObject json;
        const auto session = makeSession(spec.first, spec.second, json);
        json.insert("name", name);
        sessions.append(json);

        const QVector<std::tuple<double, double, BrakingOnsetOptions, bool>> windows{
            {0.5, 19.5, {}, true}, {1.0, 1.4, {}, false}, {12.2, 13.5, {}, true}, {3.0, 3.0, {}, false},
            {6.9, 8.0, {}, true}, {14.0, 16.0, {}, false}, {19.0, 30.0, {}, true}, {25.0, 30.0, {}, false},
            {0.0, 20.0, {{10.0, 5.0, "%"}, {0.3, 0.15, "g"}, 0.2, false}, true},
            {0.0, 20.0, {{30.0, 20.0, "%"}, {0.5, 0.2, "g"}, 0.05, true}, false},
            {0.0, 20.0, {{10.0, 10.0, "%"}, {0.3, 0.15, "g"}, 0.2, true}, false},
            {0.0, 20.0, {{10.0, 5.0, "%"}, {0.3, 0.15, "g"}, 0.0, true}, false},
        };
        for (qsizetype i = 0; i < windows.size(); ++i) {
            const auto &[from, to, options, withTrace] = windows[i];
            const auto detection = detectBrakingOnsets(session, from, to, options, withTrace ? &lap : nullptr);
            onsets.append(QJsonObject{{"session", name}, {"start", from}, {"end", to},
                                      {"options", QJsonObject{{"measuredOn", options.measuredBrake.on},
                                                              {"measuredOff", options.measuredBrake.off},
                                                              {"inferredOn", options.inferredDeceleration.on},
                                                              {"inferredOff", options.inferredDeceleration.off},
                                                              {"minimumDuration", options.minimumDurationSeconds},
                                                              {"allowInferred", options.allowInferred}}},
                                      {"trace", withTrace}, {"result", detectionJson(detection)}});
        }

        for (const auto &[setName, stored] : segmentSets) {
            const auto approved = approvedSegmentation(stored, configuration);
            for (const auto &[traceName, projected] : traces) {
                QStringList ids;
                for (const auto &value : stored) ids.append(value.toObject().value("id").toString());
                ids.append("missing");
                for (const auto &id : ids) {
                    const QVector<std::tuple<double, double>> optionSets{{200.0, 200.0}, {50.0, 120.0}, {0.0, 1000.0}};
                    for (const auto &[approach, follow] : optionSets) {
                        BrakingMetricsOptions brakingOptions;
                        brakingOptions.approachMeters = approach;
                        ExitMetricsOptions exitOptions;
                        exitOptions.followMeters = follow;
                        const auto braking = computeBrakingMetrics(2000.0, approved, id, projected, session, 0.0, 20.0, brakingOptions);
                        const auto exit = computeExitMetrics(2000.0, approved, id, projected, session, 20.0, exitOptions);
                        const auto exitNoEnd = computeExitMetrics(2000.0, approved, id, projected, session, std::nullopt, exitOptions);
                        metrics.append(QJsonObject{{"session", name}, {"segments", setName}, {"trace", traceName},
                                                   {"segmentId", id}, {"approach", approach}, {"follow", follow},
                                                   {"braking", brakingJson(braking)}, {"exit", exitJson(exit)},
                                                   {"exitNoEnd", exitJson(exitNoEnd)}});
                    }
                }
            }
        }
    }

    // Lateral offsets on a small square axis and a summary of fixed observations.
    ProgressAxis axis;
    axis.points = {{0, 0}, {10, 0}, {10, 10}, {0, 10}, {0, 0}};
    axis.cumulative = {0, 10, 20, 30, 40};
    axis.lengthMeters = 40;
    axis.spacingMeters = 10;
    axis.valid = true;
    QJsonArray offsets;
    const QVector<std::tuple<double, double, double>> points{{5, 5, 2}, {5, 5, -3}, {15, 12, 5}, {0, -1, -1},
        {40, 1, 1}, {41, 0, 0}, {-1, 0, 0}, {20, 10, 10}, {35, -2, 5}};
    for (const auto &[progress, east, north] : points)
        offsets.append(QJsonObject{{"progress", progress}, {"east", east}, {"north", north},
                                   {"offset", optional(lateralOffsetMeters(axis, progress, QPointF(east, north)))}});
    QVector<CornerLapObservation> observations;
    QJsonArray observationInputs;
    for (int i = 0; i < 7; ++i) {
        CornerLapObservation observation;
        observation.lapReference = lapReference("case", i, i);
        if (i != 3) { observation.brakingPointMeters = 100.0 + 3.0 * i * (i % 2 ? -1 : 1); observation.brakingProvenance = i < 5 ? "measured" : "inferred"; }
        if (i != 1) observation.apexSpeed = 80.0 + i;
        observation.minimumSpeed = 70.0 + 0.5 * i * i;
        if (i > 2) observation.exitSpeed = 90.0 - i;
        if (i % 3 != 0) { observation.pickupMeters = 150.0 + i; observation.pickupProvenance = i == 2 ? "inferred" : i == 4 ? "other" : "measured"; }
        observation.lineOffsetMeters = std::sin(i) * 2.0;
        if (i != 6) observation.gpsAccuracyMeters = i == 5 ? -1.0 : 0.4 + 0.1 * i;
        observations.append(observation);
        auto item = observationJson(observation);
        item.insert("lap", lapKey(observation.lapReference));
        observationInputs.append(item);
    }
    return {{"configuration", configuration}, {"sessions", sessions}, {"traces", traceInputs},
            {"segments", segmentInputs}, {"onsets", onsets}, {"metrics", metrics},
            {"offsets", offsets}, {"observations", observationInputs},
            {"variability", variabilityJson(summarizeCornerVariability("c1", "C1", observations))},
            {"variabilityTwo", variabilityJson(summarizeCornerVariability("c1", "C1", observations, 2))}};
}

} // namespace

int main(int argc, char **argv)
{
    if (argc >= 4 && std::strcmp(argv[1], "--day") == 0)
        return runDay(QString::fromLocal8Bit(argv[2]), QString::fromLocal8Bit(argv[3]));
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s <output.json> <input>... | --day <day.json> <output.json>\n", argv[0]);
        return 2;
    }
    QJsonArray results;
    for (int index = 2; index < argc; ++index) {
        if (const auto entry = runFile(QString::fromLocal8Bit(argv[index]))) results.append(*entry);
    }
    QFile output(QString::fromLocal8Bit(argv[1]));
    if (!output.open(QIODevice::WriteOnly)) return 1;
    output.write(QJsonDocument(QJsonObject{{"files", results}, {"cases", cases()}}).toJson(QJsonDocument::Compact));
    return 0;
}
