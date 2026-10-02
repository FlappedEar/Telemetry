// Prints FlappedEar Overlays' sector timing and theoretical-best results as
// one JSON document:
//   cpp_theoretical_best_dump <output.json> <input.vbo>...
//   cpp_theoretical_best_dump --day <day.json> <output.json>
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession; files without lap traces, a start gate or an
// eligible lap are skipped. A file becomes a day of two runs ("run-a" with
// its odd laps, "run-b" with its even laps). The fastest eligible lap's
// segment proposals (steps of AnalysisController::computeSegmentReview) are
// approved into its run with ids s0, s1, ..., then shifted 37 m (the last one
// crossing the gate) and thinned to every other segment, as three segment
// sets. For each set it follows requestOutingTheoreticalBest (canonical run:
// the first run id, sorted, with approved segments) and the loop of
// calculateOutingTheoreticalBest without the corner metrics (one axis from
// the canonical run's fastest lap, every lap projected and timed), and writes
// every lap's sector times, the theoretical best, Overlays' published
// theoretical best and time-loss rankings (maps thinned), and sector
// comparisons. A --day file names recordings, the eligible laps, each run's
// stored segments and the best lap, for a local check of a real day. The
// cases section times hand-made projections. NaN is written as null.

#include "telemetry/LapTiming.h"
#include "telemetry/OutingTheoreticalBest.h"
#include "telemetry/OutingTheoreticalBestResults.h"
#include "telemetry/SectorTiming.h"
#include "telemetry/TheoreticalBest.h"
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
#include <optional>
#include <stdexcept>

using namespace FlappedEar;

namespace {

constexpr int outlineStride = 50;
const QString configuration = QStringLiteral("compatibility-v1:") + QString("0123456789abcdef").repeated(4);
const QString otherConfiguration = QStringLiteral("compatibility-v1:") + QString("fedcba9876543210").repeated(4);

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

QJsonValue optional(const std::optional<double> &value)
{
    return value ? number(*value) : QJsonValue(QJsonValue::Null);
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

// The loop of calculateOutingTheoreticalBest, with sessions in memory and
// without the corner metrics (KAN-63). Overlays sorts with std::sort; a
// stable sort keeps laps of a run in their order, as the Dart port does.
OutingTheoreticalBest calculate(QVector<Row> population, const QHash<QString, Run> &runs,
    const ApprovedSegmentation &approved, const QString &canonicalRunId, const QJsonObject &actualBestReference)
{
    OutingTheoreticalBest result;
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
        QVector<LapSectorTimes> populationTimes;
        for (const auto &row : population) {
            if (!runs.contains(row.runId)) continue;
            const auto projected = projectLapTrace(axis, *runs.value(row.runId).session, row.start, row.end);
            populationTimes.append(computeLapSectorTimes(approved, axis.lengthMeters, projected, row.start, row.end, row.reference));
            result.population.append({populationTimes.last(), row.start});
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
    return result;
}

QJsonObject sectorTimesJson(const LapSectorTimes &times)
{
    QJsonArray sectors;
    for (const auto &sector : times.sectors) {
        sectors.append(QJsonObject{{"segmentId", sector.segmentId}, {"name", sector.name}, {"type", sector.type},
                                   {"start", number(sector.startProgressMeters)}, {"end", number(sector.endProgressMeters)},
                                   {"lengthMeters", number(sector.lengthMeters)},
                                   {"coveredMeters", number(sector.coveredMeters)},
                                   {"startTime", optional(sector.startTime)}, {"endTime", optional(sector.endTime)},
                                   {"seconds", optional(sector.seconds)}, {"reason", sector.unavailableReason}});
    }
    return {{"lap", lapKey(times.lapReference)}, {"valid", times.valid}, {"revision", times.stamp.revision},
            {"algorithm", times.stamp.calculationAlgorithm},
            {"completePartition", times.completePartition}, {"lapSeconds", number(times.lapSeconds)},
            {"sumSeconds", optional(times.sumSeconds)}, {"partitionErrorSeconds", optional(times.partitionErrorSeconds)},
            {"sectors", sectors}};
}

QJsonObject bestJson(const TheoreticalBestLap &best)
{
    QJsonArray sectors;
    for (const auto &sector : best.sectors) {
        sectors.append(QJsonObject{{"segmentId", sector.segmentId}, {"seconds", optional(sector.seconds)},
                                   {"source", lapKey(sector.sourceLapReference)}, {"reason", sector.unavailableReason}});
    }
    return {{"valid", best.valid}, {"revision", best.stamp.revision}, {"algorithm", best.stamp.calculationAlgorithm},
            {"totalSeconds", optional(best.totalSeconds)}, {"reason", best.unavailableReason}, {"sectors", sectors}};
}

QJsonObject pointJson(const QVariant &point)
{
    const auto map = point.toMap();
    return {{"x", map.value("x").toDouble()}, {"y", map.value("y").toDouble()}};
}

// The published theoretical best with the map thinned: each part's size and
// end points, and every 50th outline point.
QJsonObject publishedJson(QVariantMap published)
{
    auto map = published.take("map").toMap();
    QJsonObject result = QJsonObject::fromVariantMap(published);
    if (map.isEmpty()) return result;
    QJsonArray segments;
    for (const auto &value : map.value("segments").toList()) {
        QJsonArray parts;
        for (const auto &partValue : value.toMap().value("parts").toList()) {
            const auto part = partValue.toList();
            QJsonObject item{{"size", part.size()}};
            if (!part.isEmpty()) {
                item.insert("first", pointJson(part.first()));
                item.insert("last", pointJson(part.last()));
            }
            parts.append(item);
        }
        segments.append(QJsonObject{{"segmentId", value.toMap().value("segmentId").toString()}, {"parts", parts}});
    }
    const auto outline = map.value("outline").toList();
    QJsonArray outlinePoints;
    for (qsizetype i = 0; i < outline.size(); i += outlineStride) outlinePoints.append(pointJson(outline[i]));
    result.insert("map", QJsonObject{{"segments", segments}, {"outlineSize", outline.size()}, {"outline", outlinePoints}});
    return result;
}

QString label(const QJsonObject &reference)
{
    return QStringLiteral("%1 · LAP %2").arg(reference.value("runId").toString()).arg(reference.value("lapNumber").toInt());
}

QJsonObject observationsJson(const TimeLossObservations &observations)
{
    QJsonArray windows;
    for (const auto &window : observations.windows) {
        windows.append(QJsonObject{{"segmentId", window.segmentId}, {"role", window.role},
                                   {"cornerSegmentId", window.cornerSegmentId},
                                   {"increment", optional(window.incrementSeconds)},
                                   {"atStart", optional(window.cumulativeAtStartSeconds)},
                                   {"atEnd", optional(window.cumulativeAtEndSeconds)},
                                   {"reason", window.unavailableReason}});
    }
    return {{"valid", observations.valid}, {"reason", observations.unavailableReason},
            {"allWindowsTimed", observations.allWindowsTimed},
            {"timedIncrementSumSeconds", number(observations.timedIncrementSumSeconds)}, {"windows", windows}};
}

// Canonical run as requestOutingTheoreticalBest picks it, the calculation
// and everything written for it.
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
    const auto computed = calculate(population, runs, approved, canonicalRunId, actualBestReference);
    entry.insert("error", computed.error);
    if (!computed.error.isEmpty()) return entry;
    entry.insert("axis", QJsonObject{{"pointCount", computed.axis.points.size()},
                                     {"lengthMeters", number(computed.axisLengthMeters)}});
    QJsonArray laps;
    for (const auto &lap : computed.population) laps.append(sectorTimesJson(lap.times));
    entry.insert("laps", laps);
    entry.insert("best", bestJson(computed.best));
    entry.insert("actualBest", computed.actualBest ? QJsonValue(lapKey(computed.actualBest->lapReference)) : QJsonValue());
    entry.insert("published", publishedJson(publishTheoreticalBest(computed, "ready", {}, label)));
    entry.insert("timeLossRunBests", QJsonObject::fromVariantMap(publishTimeLossRanking(computed, "ready", {}, false, label)));
    entry.insert("timeLossAllLaps", QJsonObject::fromVariantMap(publishTimeLossRanking(computed, "ready", {}, true, label)));
    if (computed.actualBest && !computed.population.isEmpty()) {
        const auto &first = computed.population.first();
        entry.insert("observations", observationsJson(computeTimeLossObservations(computed.approved,
            computed.axisLengthMeters, first.times, first.startTime, *computed.actualBest,
            computed.actualBest->lapReference.value("startTime").toDouble())));
    }
    if (computed.population.size() >= 2) {
        const auto &a = computed.population[0].times;
        const auto &b = computed.population[1].times;
        QJsonArray comparisons;
        QStringList ids;
        for (const auto &sector : a.sectors) ids.append(sector.segmentId);
        ids.append("missing");
        for (const auto &id : ids) {
            const auto comparison = compareSectorTimes(a, b, id);
            comparisons.append(QJsonObject{{"segmentId", id}, {"valid", comparison.valid},
                                           {"delta", optional(comparison.secondsDelta)},
                                           {"reason", comparison.unavailableReason}});
        }
        entry.insert("comparisons", comparisons);
    }
    return entry;
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

// The segments 37 m further on; the last one may cross the gate.
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
    // computeSegmentReview's coverage gaps are left out: the parity of the
    // proposals themselves is checked by cpp_segments_dump.
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
                       {"actualBest", lapKey(actualBest)}, {"variants", variants}};
}

// --day: recordings, eligible laps, stored segments and the best lap, from a file.
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
    output.write(QJsonDocument(dayJson(population, runs, stored, actualBest)).toJson(QJsonDocument::Indented));
    return 0;
}

QJsonObject segment(const QString &id, const QString &type, const double start, const double end,
    const QString &reference = configuration)
{
    return {{"id", id}, {"type", type}, {"name", id.toUpper()}, {"startProgressMeters", start},
            {"endProgressMeters", end}, {"trackConfigurationReference", reference}};
}

// A projection with progress = speed * (time - start) + offset, sampled every
// 0.05 s, as runs of [time, progress] split where `gaps` remove samples.
QVector<ProgressSegment> trace(const double from, const double to, const double offset,
    const QVector<std::pair<double, double>> &gaps)
{
    QVector<ProgressSegment> result;
    ProgressSegment current;
    for (int i = 0;; ++i) {
        const double time = from + 0.05 * i;
        if (time > to + 1e-9) break;
        const double progress = offset + 100.0 * (time - from);
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

QJsonArray sectorCases()
{
    const auto partition = QJsonArray{segment("c1", "corner", 0, 300), segment("t1", "straight", 300, 700),
                                      segment("x1", "sector", 700, 1000)};
    const auto wrapped = QJsonArray{segment("c1", "corner", 100, 400), segment("t1", "straight", 400, 800),
                                    segment("x1", "sector", 800, 100)};
    const auto gapped = QJsonArray{segment("c1", "corner", 0, 300), segment("t1", "straight", 400, 1000)};
    const auto mixed = QJsonArray{segment("c1", "corner", 0, 300),
                                  segment("o1", "corner", 300, 700, otherConfiguration)};
    struct Case {
        QJsonValue stored;
        double length;
        QVector<ProgressSegment> lap;
        double start;
        double end;
    };
    const QVector<Case> inputs{
        {partition, 1000, trace(10.0, 19.95, 3.0, {}), 10.0, 20.0},
        {partition, 1000, trace(10.0, 19.95, 3.0, {{450.0, 520.0}}), 10.0, 20.0},
        {partition, 1000, trace(10.0, 19.95, 3.0, {{290.0, 310.0}}), 10.0, 20.0},
        {partition, 1000, trace(10.0, 19.7, 20.0, {}), 10.0, 20.0},
        {partition, 1000, trace(10.0, 19.8, 14.0, {}), 10.0, 20.0},
        {wrapped, 1000, trace(10.0, 19.95, 3.0, {}), 10.0, 20.0},
        {wrapped, 1000, trace(10.0, 19.95, 3.0, {{40.0, 60.0}}), 10.0, 20.0},
        {wrapped, 1000, trace(10.0, 19.95, 3.0, {{850.0, 870.0}}), 10.0, 20.0},
        {gapped, 1000, trace(10.0, 19.95, 3.0, {}), 10.0, 20.0},
        {mixed, 1000, trace(10.0, 19.95, 3.0, {}), 10.0, 20.0},
        {QJsonArray{}, 1000, trace(10.0, 19.95, 3.0, {}), 10.0, 20.0},
        {partition, 1000, {}, 10.0, 20.0},
        {partition, 1000, trace(10.0, 19.95, 3.0, {}), 20.0, 20.0},
        {partition, 0, trace(10.0, 19.95, 3.0, {}), 10.0, 20.0},
        {QJsonValue("x"), 1000, trace(10.0, 19.95, 3.0, {}), 10.0, 20.0},
        {partition, 1200, trace(10.0, 19.95, 3.0, {}), 10.0, 20.0},
    };
    QJsonArray cases;
    QVector<LapSectorTimes> population;
    for (qsizetype i = 0; i < inputs.size(); ++i) {
        const auto &input = inputs[i];
        const auto approved = approvedSegmentation(input.stored, configuration);
        const auto times = computeLapSectorTimes(approved, input.length, input.lap, input.start, input.end,
            lapReference("case", static_cast<int>(i), input.start));
        QJsonObject item{{"stored", input.stored}, {"lengthMeters", input.length}, {"trace", traceJson(input.lap)},
                         {"start", input.start}, {"end", input.end}, {"result", sectorTimesJson(times)},
                         {"coverage", number(projectedCoverageMeters(input.lap, 250.0, 520.0, input.length))}};
        cases.append(item);
    }
    return cases;
}

// Theoretical best and time loss over the hand-made partition laps, one of
// them timed against other segments.
QJsonObject populationCase()
{
    const auto partition = QJsonArray{segment("c1", "corner", 0, 300), segment("t1", "straight", 300, 700),
                                      segment("x1", "sector", 700, 1000)};
    const auto other = QJsonArray{segment("c1", "corner", 0, 350), segment("t1", "straight", 350, 700),
                                  segment("x1", "sector", 700, 1000)};
    const auto approved = approvedSegmentation(partition, configuration);
    const auto otherApproved = approvedSegmentation(other, configuration);
    // Laps differ by an offset (their speed through each part is the same
    // except where a gap removes coverage).
    const QVector<std::tuple<QVector<ProgressSegment>, double, bool>> laps{
        {trace(10.0, 19.95, 3.0, {}), 10.0, false},
        {trace(30.0, 39.95, 3.0, {{450.0, 520.0}}), 30.0, false},
        {trace(50.0, 59.95, 3.0, {}), 50.0, true},
        {trace(70.0, 79.95, 3.0, {{100.0, 130.0}}), 70.0, false},
    };
    QVector<LapSectorTimes> population;
    QVector<TimedLapSectors> timed;
    QJsonArray inputs;
    for (qsizetype i = 0; i < laps.size(); ++i) {
        const auto &[lap, start, useOther] = laps[i];
        // Stretch lap i's time a little, so the sectors differ.
        auto stretched = lap;
        for (auto &part : stretched)
            for (auto &sample : part.samples) sample.telemetryTime = start + (sample.telemetryTime - start) * (1.0 + 0.01 * i * (sample.progressMeters > 500 ? 1 : -0.5));
        const double end = start + 10.0 * (1.0 + 0.01 * i);
        population.append(computeLapSectorTimes(useOther ? otherApproved : approved, 1000, stretched, start, end,
            lapReference(i % 2 ? "b" : "a", static_cast<int>(i), start)));
        timed.append({population.last(), start});
        inputs.append(QJsonObject{{"trace", traceJson(stretched)}, {"start", start}, {"end", end}, {"other", useOther}});
    }
    QJsonArray observations;
    for (const auto &lap : timed)
        observations.append(observationsJson(computeTimeLossObservations(approved, 1000, lap.times, lap.startTime, timed[0].times, timed[0].startTime)));
    const auto ranking = rankTimeLosses(approved, 1000, timed, timed[0], 3);
    QJsonArray losses;
    for (const auto &loss : ranking.losses)
        losses.append(QJsonObject{{"lap", lapKey(loss.lapReference)}, {"segmentId", loss.window.segmentId},
                                  {"loss", loss.lossSeconds}, {"coverageLap", loss.coverageLap},
                                  {"coverageReference", loss.coverageReference}});
    return {{"stored", partition}, {"otherStored", other}, {"laps", inputs},
            {"best", bestJson(computeTheoreticalBest(approved, population))},
            {"bestNone", bestJson(computeTheoreticalBest(approvedSegmentation(QJsonArray{}, configuration), population))},
            {"observations", observations},
            {"ranking", QJsonObject{{"valid", ranking.valid}, {"observationCount", ranking.observationCount},
                                    {"comparedLapCount", ranking.comparedLapCount},
                                    {"untimedWindowCount", ranking.untimedWindowCount}, {"losses", losses}}}};
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
    const QJsonObject cases{{"configuration", configuration}, {"sectorTimes", sectorCases()},
                            {"population", populationCase()}};
    QFile output(QString::fromLocal8Bit(argv[1]));
    if (!output.open(QIODevice::WriteOnly)) return 1;
    output.write(QJsonDocument(QJsonObject{{"files", results}, {"cases", cases}}).toJson(QJsonDocument::Compact));
    return 0;
}
