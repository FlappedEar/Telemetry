// Prints FlappedEar Overlays' lap ranking, run progression, lap consistency,
// section progression and published time losses as one JSON document:
//   cpp_progression_dump <output.json> <input.vbo>...
//   cpp_progression_dump --day <day.json> <output.json>
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession.
//
// "files": each file with lap traces, a start gate and an eligible lap
// becomes the day of two runs of cpp_theoretical_best_dump ("run-a" with its
// odd laps, "run-b" with its even laps), timed against the fastest lap's
// proposals approved with ids s0, s1, ... and against the same shifted 37 m.
// For each set it writes publishSectorProgression with the runs listed as
// run-b, run-a and a run without laps, and publishTimeLossRanking of the run
// bests and of every lap (with corner names).
//
// "day": every input that parses is one run ("r00", "r01", ... named
// "Session 1", ...) whose sections come from outingLapRows and are sorted
// with sortOutingLaps, as OutingLapDerivation does. Runs get one of two
// track configurations, or an unresolved one; one lap is excluded by the
// user and one run is stale (both in runs with three timed laps), and the run metadata (in reverse import order)
// carries notes, conditions and setup changes for some runs and one run
// without recordings. For each configuration it writes rankOutingLaps,
// summarizeOutingProgression and the lap consistency of
// AnalysisController::outingLapConsistency (the day and each run over
// eligibleOutingLaps, in row order).
//
// "cases": summarizeConsistency over fixed values, and the section
// progression and time losses of hand-made laps (three runs, up to five laps
// each, so the statistics are available).
//
// A --day file names a real day's recordings (runs: runId, name, file), the
// eligible laps (population), each run's stored segments and the best lap,
// as for cpp_theoretical_best_dump; every run gets the same configuration,
// a detected route, so laps off it are left out as Overlays does.
// It writes the same as a file and a day. NaN is written as null.

#include "telemetry/Consistency.h"
#include "telemetry/LapTiming.h"
#include "telemetry/OutingLaps.h"
#include "telemetry/OutingTheoreticalBest.h"
#include "telemetry/OutingTheoreticalBestResults.h"
#include "telemetry/SectorTiming.h"
#include "telemetry/TheoreticalBest.h"
#include "telemetry/TimeLoss.h"
#include "telemetry/TrackProgress.h"
#include "telemetry/TrackSegmentProposals.h"
#include "telemetry/TrackSegmentReview.h"
#include "telemetry/TrackInference.h"
#include "telemetry/TrackSegments.h"
#include "telemetry/VboParser.h"

#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <limits>
#include <optional>
#include <stdexcept>

using namespace FlappedEar;

namespace {

const QString configuration = QStringLiteral("compatibility-v1:") + QString("0123456789abcdef").repeated(4);
const QString gates = QStringLiteral("gates-v1:") + QString("a").repeated(64);
const QJsonObject configurationA{{"layoutId", "Test circuit"}, {"direction", "clockwise"}, {"gateRevision", gates}};
const QJsonObject configurationB{{"layoutId", "Test circuit reversed"}, {"direction", "counterclockwise"},
                                 {"gateRevision", gates}};
const QJsonObject unresolved{{"layoutId", "Test circuit"}, {"gateRevision", gates}};
const QString eventId = QStringLiteral("event-1");
const QByteArray derivationKey = QByteArray("d").repeated(64);

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

QString label(const QJsonObject &reference)
{
    return QStringLiteral("%1 · LAP %2").arg(reference.value("runId").toString()).arg(reference.value("lapNumber").toInt());
}

GeoCoordinate gateMidpoint(const TimingGate &gate)
{
    return {(gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
            (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0};
}

// The loop of calculateOutingTheoreticalBest, as in cpp_theoretical_best_dump.
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

// The published section progression and time losses of one population.
QJsonObject resultsJson(const QVector<Row> &population, const QHash<QString, Run> &runs,
    const QHash<QString, QJsonValue> &storedSegments, const QJsonObject &actualBestReference,
    const QVariantMap &progression)
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
    const auto computed = calculate(population, runs, approved, canonicalRunId, actualBestReference);
    entry.insert("error", computed.error);
    if (!computed.error.isEmpty()) return entry;
    entry.insert("sectorProgression",
        QJsonObject::fromVariantMap(publishSectorProgression(computed, "ready", {}, progression, label)));
    entry.insert("timeLossRunBests", QJsonObject::fromVariantMap(publishTimeLossRanking(computed, "ready", {}, false, label)));
    entry.insert("timeLossAllLaps", QJsonObject::fromVariantMap(publishTimeLossRanking(computed, "ready", {}, true, label)));
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
    // The progression's order, with a run without laps and its context.
    const QVariantMap progression{{"runs", QVariantList{
        QVariantMap{{"runId", "run-b"}, {"runName", "Run B"}, {"clock", "Time unavailable · import order"},
                    {"notes", "New tyres"}, {"conditions", QVariant()}, {"setupChanges", "Front wing +1"}},
        QVariantMap{{"runId", "run-x"}, {"runName", "Run X"}},
        QVariantMap{{"runId", "run-a"}, {"runName", "Run A"}, {"conditions", "Dry"}}}}};
    QJsonArray variants;
    const QVector<std::pair<QString, QJsonArray>> sets{
        {"automatic", automatic}, {"shifted", shifted(automatic, axis.lengthMeters)}};
    for (const auto &[name, segments] : sets) {
        if (segments.isEmpty()) continue;
        auto entry = resultsJson(population, runs, {{bestRun, segments}}, actualBest, progression);
        entry.insert("name", name);
        entry.insert("segments", QJsonObject{{bestRun, segments}});
        variants.append(entry);
    }
    QJsonArray populationJson;
    for (const auto &row : population)
        populationJson.append(QJsonObject{{"runId", row.runId}, {"lapNumber", row.lapNumber}});
    return QJsonObject{{"file", QFileInfo(path).fileName()}, {"population", populationJson},
                       {"actualBest", QJsonObject{{"runId", bestRun}, {"lapNumber", best->number}}},
                       {"progressionRuns", QJsonArray::fromVariantList(progression.value("runs").toList())},
                       {"variants", variants}};
}

// A lap record of the ranking without its reference: run and lap number.
QJsonValue lapJson(const QJsonValue &value)
{
    if (!value.isObject()) return QJsonValue::Null;
    auto lap = value.toObject();
    lap.remove("reference");
    return lap;
}

QJsonArray lapsJson(const QJsonArray &values)
{
    QJsonArray result;
    for (const auto &value : values) result.append(lapJson(value));
    return result;
}

QJsonObject rankingJson(QJsonObject ranking)
{
    ranking.insert("bestOfDay", lapJson(ranking.value("bestOfDay")));
    ranking.insert("excludedLaps", lapsJson(ranking.value("excludedLaps").toArray()));
    QJsonArray runs;
    for (const auto &value : ranking.value("runs").toArray()) {
        auto run = value.toObject();
        run.insert("bestLap", lapJson(run.value("bestLap")));
        runs.append(run);
    }
    ranking.insert("runs", runs);
    return ranking;
}

QJsonObject progressionJson(QJsonObject progression)
{
    QJsonArray runs;
    for (const auto &value : progression.value("runs").toArray()) {
        auto run = value.toObject();
        run.insert("bestLap", lapJson(run.value("bestLap")));
        run.insert("excludedLaps", lapsJson(run.value("excludedLaps").toArray()));
        runs.append(run);
    }
    progression.insert("runs", runs);
    return progression;
}

// AnalysisController::outingLapConsistency over the eligible rows.
QJsonObject lapConsistencyJson(const QVector<const OutingLapRow *> &eligible)
{
    QVariantMap result{{"algorithm", QString::fromLatin1(consistencyAlgorithm)},
        {"minimumSamples", minimumConsistencySamples}};
    QVector<double> day;
    QStringList runOrder;
    QHash<QString, QVector<double>> byRun;
    QHash<QString, QString> runNames;
    for (const auto *row : eligible) {
        day.append(row->end - row->start);
        if (!byRun.contains(row->runId)) runOrder.append(row->runId);
        byRun[row->runId].append(row->end - row->start);
        runNames.insert(row->runId, row->runName);
    }
    result.insert("day", consistencySummaryMap(summarizeConsistency(day)));
    QVariantList runs;
    for (const auto &runId : runOrder)
        runs.append(QVariantMap{{"runId", runId}, {"runName", runNames.value(runId)},
            {"laps", consistencySummaryMap(summarizeConsistency(byRun.value(runId)))}});
    result.insert("runs", runs);
    return QJsonObject::fromVariantMap(result);
}

struct DayRun {
    QString id;
    QString name;
    QString file;
    TelemetrySession session;
    LapSession laps;
};

QString sourceRevision(const qsizetype index)
{
    return QString("%1").arg(index, 64, 16, QChar('0'));
}

// Ranking, progression and lap consistency of a day of runs. `choices`
// holds each run's configuration, the excluded lap, the stale run and the
// run metadata, and is written with the results.
// With `detectedRoutes`, each run's laps off the route its other laps took
// are left out as OutingLapDerivation does for a detected (gps-route-v1)
// layout, from Overlays' inferTrack.
QJsonObject dayJson(const QVector<DayRun> &runs, const QJsonObject &choices, const bool detectedRoutes = false)
{
    QVector<OutingLapRow> rows;
    for (qsizetype i = 0; i < runs.size(); ++i) {
        const auto &run = runs[i];
        auto runRows = outingLapRows(run.session, run.laps, run.id, run.name, i);
        const auto inference = detectedRoutes
            ? inferTrack(run.laps, run.session.metadata.value("gpsLongitudeConvention") == "west-positive")
            : TrackInference{};
        for (auto &row : runRows) {
            row.reference = makeLapReference(row, eventId, run.id, sourceRevision(i).toLatin1(), derivationKey);
            if (inference.supported() && row.type == LapSectionType::Lap && row.referenceEligible
                && !inference.matchingLaps.contains(row.lapNumber))
                row.layoutIssue = "different-recorded-route";
        }
        rows.append(runRows);
    }
    sortOutingLaps(rows);
    QHash<QString, QJsonObject> configurations;
    const auto configured = choices.value("configurations").toObject();
    for (auto it = configured.begin(); it != configured.end(); ++it) configurations.insert(it.key(), it.value().toObject());
    QJsonArray exclusions;
    const auto excluded = choices.value("excluded").toObject();
    for (const auto &row : rows) {
        if (row.type == LapSectionType::Lap && row.runId == excluded.value("runId").toString()
            && row.lapNumber == excluded.value("lapNumber").toInt())
            exclusions.append(QJsonObject{{"reference", row.reference}, {"reason", excluded.value("reason")}});
    }
    QSet<QString> stale;
    for (const auto &value : choices.value("stale").toArray()) stale.insert(value.toString());
    QJsonArray metadata;
    for (const auto &value : choices.value("metadata").toArray()) {
        auto run = value.toObject();
        run.insert("groupId", lapCompatibilityGroupId(configurations.value(run.value("id").toString())));
        metadata.append(run);
    }
    QStringList groups;
    for (const auto &config : {configurationA, configurationB, unresolved, QJsonObject{}}) {
        const auto id = lapCompatibilityGroupId(config);
        if (!groups.contains(id)) groups.append(id);
    }
    QJsonArray results;
    for (const auto &group : groups) {
        const auto ranking = rankOutingLaps(rows, group, configurations, exclusions, stale);
        const auto progression = summarizeOutingProgression(rows, ranking, metadata);
        QJsonObject entry{{"groupId", group}, {"ranking", rankingJson(ranking)},
                          {"progression", progressionJson(progression)},
                          {"lapConsistency", lapConsistencyJson(eligibleOutingLaps(rows, group, configurations, exclusions, stale))}};
        results.append(entry);
    }
    QJsonArray rowsJson;
    for (const auto &row : rows)
        rowsJson.append(QJsonObject{{"runId", row.runId}, {"type", lapSectionName(row.type)}, {"lapNumber", row.lapNumber},
                                    {"start", row.start}, {"end", row.end},
                                    {"timestamp", row.timestampMilliseconds ? QJsonValue(QString::number(*row.timestampMilliseconds))
                                                                            : QJsonValue(QJsonValue::Null)}});
    auto written = choices;
    written.insert("metadata", metadata);
    return {{"choices", written}, {"rows", rowsJson}, {"groups", results}};
}

QJsonObject syntheticDay(const QStringList &paths)
{
    QVector<DayRun> runs;
    runs.reserve(paths.size());
    for (const auto &path : paths) {
        DayRun run;
        try {
            run.session = VboParser::parseFile(path);
            run.laps = deriveSourceLapSession(run.session);
        } catch (const std::exception &) {
            continue;
        }
        run.id = QString("r%1").arg(runs.size(), 2, 10, QChar('0'));
        run.name = QString("Session %1").arg(runs.size() + 1);
        run.file = QFileInfo(path).fileName();
        runs.append(std::move(run));
    }
    QJsonObject configurations;
    QJsonArray files;
    for (qsizetype i = 0; i < runs.size(); ++i) {
        files.append(QJsonObject{{"runId", runs[i].id}, {"file", runs[i].file}});
        configurations.insert(runs[i].id, i == 5 ? unresolved : i % 4 == 3 ? configurationB : configurationA);
    }
    // The second timed lap of the first run of configuration A with three
    // timed laps; the next such run is stale.
    QJsonObject excluded;
    QJsonArray stale;
    for (qsizetype i = 0; i < runs.size(); ++i) {
        if (configurations.value(runs[i].id).toObject() != configurationA || runs[i].laps.timedLaps.size() < 3) continue;
        if (excluded.isEmpty())
            excluded = {{"runId", runs[i].id}, {"lapNumber", runs[i].laps.timedLaps[1].number},
                        {"reason", "Traffic in the last corner"}};
        else if (stale.isEmpty())
            stale.append(runs[i].id);
    }
    QJsonArray metadata;
    for (qsizetype i = runs.size() - 1; i >= 0; --i) {
        QJsonObject item{{"id", runs[i].id}, {"name", runs[i].name}};
        if (i % 3 == 0) item.insert("notes", QString("Notes %1").arg(i));
        if (i % 3 == 1) item.insert("conditions", "Damp");
        if (i % 2 == 0) item.insert("setupChanges", "Rear pressure -0.1 bar");
        metadata.append(item);
        if (i == 4) metadata.append(QJsonObject{{"id", "r99"}, {"name", "Session without recording"}});
    }
    configurations.insert("r99", configurationA);
    QJsonObject choices{{"files", files}, {"configurations", configurations}, {"excluded", excluded},
                        {"stale", stale}, {"metadata", metadata}};
    return dayJson(runs, choices);
}

QJsonObject summaryJson(const ConsistencySummary &summary)
{
    return QJsonObject::fromVariantMap(consistencySummaryMap(summary));
}

QJsonArray consistencyCases()
{
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double infinity = std::numeric_limits<double>::infinity();
    const QVector<std::pair<QVector<double>, qsizetype>> inputs{
        {{}, 3}, {{1.5}, 3}, {{2.0, 1.0}, 3}, {{3.0, 1.0, 2.0}, 3}, {{4.0, 1.0, 3.0, 2.0}, 3},
        {{90.1, 91.4, 89.9, 95.0, 90.6}, 3}, {{1.0, nan, 2.0, infinity, 3.0}, 3}, {{1.0, nan, 2.0}, 3},
        {{5.0, 5.0, 5.0}, 3}, {{1.0, 2.0}, 1}, {{7.0}, 0}, {{1.0, 2.0, 3.0}, 4},
        {{61.234, 60.987, 61.002, 62.5, 60.999, 61.111, 63.0}, 3}};
    QJsonArray cases;
    for (const auto &[values, minimum] : inputs) {
        QJsonArray written;
        for (const double value : values)
            written.append(std::isnan(value) ? QJsonValue("nan") : std::isinf(value) ? QJsonValue("inf") : QJsonValue(value));
        cases.append(QJsonObject{{"values", written}, {"minimumSamples", minimum},
                                 {"summary", summaryJson(summarizeConsistency(values, minimum))}});
    }
    return cases;
}

QJsonObject segment(const QString &id, const QString &type, const double start, const double end,
    const QString &reference = configuration)
{
    return {{"id", id}, {"type", type}, {"name", id.toUpper()}, {"startProgressMeters", start},
            {"endProgressMeters", end}, {"trackConfigurationReference", reference}};
}

// A projection with progress = 100 m/s * (time - from) + offset, sampled
// every 0.05 s, split where `gaps` remove samples, then stretched: time
// after `from` runs `slow` times slower beyond 500 m and `fast` times
// beyond 0 m otherwise.
QVector<ProgressSegment> trace(const double from, const double offset, const QVector<std::pair<double, double>> &gaps,
    const double slow, const double fast)
{
    QVector<ProgressSegment> result;
    ProgressSegment current;
    for (int i = 0; i < 200; ++i) {
        const double time = from + 0.05 * i;
        const double progress = offset + 100.0 * (time - from);
        const bool removed = std::any_of(gaps.cbegin(), gaps.cend(),
            [progress](const auto &gap) { return progress > gap.first && progress < gap.second; });
        if (removed) {
            if (!current.samples.isEmpty()) result.append(current);
            current = {};
            continue;
        }
        current.samples.append({from + (time - from) * (progress > 500 ? slow : fast), progress, true});
    }
    if (!current.samples.isEmpty()) result.append(current);
    return result;
}

QJsonArray traceJson(const QVector<ProgressSegment> &lap)
{
    QJsonArray result;
    for (const auto &part : lap) {
        QJsonArray samples;
        for (const auto &sample : part.samples) samples.append(QJsonArray{sample.telemetryTime, sample.progressMeters});
        result.append(samples);
    }
    return result;
}

// Section progression and time losses of hand-made laps: three runs of
// five, three and two laps (one lap with a gap, one timed against other
// segments), listed in the order c, a, b and a run without laps.
QJsonObject populationCase()
{
    const auto partition = QJsonArray{segment("c1", "corner", 0, 300), segment("t1", "straight", 300, 700),
                                      segment("x1", "sector", 700, 1000)};
    const auto other = QJsonArray{segment("c1", "corner", 0, 350), segment("t1", "straight", 350, 700),
                                  segment("x1", "sector", 700, 1000)};
    const auto approved = approvedSegmentation(partition, configuration);
    const auto otherApproved = approvedSegmentation(other, configuration);
    struct Lap { QString runId; QVector<std::pair<double, double>> gaps; bool other; };
    const QVector<Lap> laps{{"a", {}, false}, {"a", {}, false}, {"a", {{450.0, 520.0}}, false}, {"a", {}, false},
                            {"a", {}, true}, {"b", {}, false}, {"b", {}, false}, {"b", {{100.0, 130.0}}, false},
                            {"c", {}, false}, {"c", {}, false}};
    OutingTheoreticalBest computed;
    QVector<LapSectorTimes> population;
    QJsonArray inputs;
    std::optional<qsizetype> fastest;
    for (qsizetype i = 0; i < laps.size(); ++i) {
        const double start = 10.0 + 20.0 * static_cast<double>(i);
        const double slow = 1.0 + 0.01 * static_cast<double>((i * 7) % 5);
        const double fast = 1.0 - 0.004 * static_cast<double>((i * 3) % 4);
        const auto lap = trace(start, 3.0, laps[i].gaps, slow, fast);
        const double end = start + 10.0 * slow;
        const auto reference = lapReference(laps[i].runId, static_cast<int>(i + 1), start);
        population.append(computeLapSectorTimes(laps[i].other ? otherApproved : approved, 1000, lap, start, end, reference));
        computed.population.append({population.last(), start});
        if (!laps[i].other && laps[i].gaps.isEmpty()
            && (!fastest || population.last().lapSeconds < population[*fastest].lapSeconds)) fastest = i;
        inputs.append(QJsonObject{{"runId", laps[i].runId}, {"lapNumber", i + 1}, {"trace", traceJson(lap)},
                                  {"start", start}, {"end", end}, {"other", laps[i].other}});
    }
    computed.best = computeTheoreticalBest(approved, population);
    computed.actualBest = population[*fastest];
    computed.approved = approved;
    computed.axisLengthMeters = 1000;
    computed.canonicalRunId = "a";
    const QVariantMap progression{{"runs", QVariantList{
        QVariantMap{{"runId", "c"}, {"runName", "Run C"}, {"notes", "Last run"}},
        QVariantMap{{"runId", "a"}, {"runName", "Run A"}, {"conditions", "Dry"}},
        QVariantMap{{"runId", "z"}, {"runName", "Run Z"}},
        QVariantMap{{"runId", "b"}, {"runName", "Run B"}, {"setupChanges", "Softer rear"}}}}};
    return {{"stored", partition}, {"otherStored", other}, {"laps", inputs},
            {"actualBest", label(computed.actualBest->lapReference)},
            {"progressionRuns", QJsonArray::fromVariantList(progression.value("runs").toList())},
            {"sectorProgression", QJsonObject::fromVariantMap(publishSectorProgression(computed, "ready", {}, progression, label))},
            {"sectorProgressionLoading", QJsonObject::fromVariantMap(publishSectorProgression(computed, "loading", {}, progression, label))},
            {"timeLossRunBests", QJsonObject::fromVariantMap(publishTimeLossRanking(computed, "ready", {}, false, label))},
            {"timeLossAllLaps", QJsonObject::fromVariantMap(publishTimeLossRanking(computed, "ready", {}, true, label))}};
}

// --day: recordings, eligible laps, stored segments and the best lap, from a file.
int runDay(const QString &input, const QString &outputPath)
{
    QFile file(input);
    if (!file.open(QIODevice::ReadOnly)) return 1;
    const auto day = QJsonDocument::fromJson(file.readAll()).object();
    QVector<DayRun> dayRuns;
    const auto runList = day.value("runs").toArray();
    dayRuns.reserve(runList.size());
    QJsonObject configurations;
    QJsonArray metadata;
    for (const auto &value : runList) {
        const auto run = value.toObject();
        DayRun item;
        item.id = run.value("runId").toString();
        item.name = run.value("name").toString();
        item.file = run.value("file").toString();
        item.session = VboParser::parseFile(item.file);
        item.laps = deriveSourceLapSession(item.session);
        configurations.insert(item.id, configurationA);
        metadata.append(QJsonObject{{"id", item.id}, {"name", item.name}});
        dayRuns.append(std::move(item));
    }
    QHash<QString, Run> runs;
    for (const auto &run : dayRuns) runs.insert(run.id, {run.id, &run.session, &run.laps});
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
    const QJsonObject choices{{"configurations", configurations}, {"excluded", QJsonObject{}}, {"stale", QJsonArray{}},
                              {"metadata", metadata}};
    const auto days = dayJson(dayRuns, choices, true);
    // The section progression lists runs in the progression's order.
    QVariantMap progression;
    for (const auto &value : days.value("groups").toArray()) {
        const auto group = value.toObject();
        if (group.value("groupId").toString() == lapCompatibilityGroupId(configurationA))
            progression = group.value("progression").toObject().toVariantMap();
    }
    auto entry = resultsJson(population, runs, stored, actualBest, progression);
    entry.insert("day", days);
    QFile output(outputPath);
    if (!output.open(QIODevice::WriteOnly)) return 1;
    output.write(QJsonDocument(entry).toJson(QJsonDocument::Indented));
    return 0;
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
    QStringList paths;
    for (int index = 2; index < argc; ++index) {
        paths.append(QString::fromLocal8Bit(argv[index]));
        if (const auto entry = runFile(paths.last())) results.append(*entry);
    }
    const QJsonObject cases{{"configuration", configuration}, {"consistency", consistencyCases()},
                            {"population", populationCase()}};
    QFile output(QString::fromLocal8Bit(argv[1]));
    if (!output.open(QIODevice::WriteOnly)) return 1;
    output.write(QJsonDocument(QJsonObject{{"files", results}, {"day", syntheticDay(paths)}, {"cases", cases}})
                     .toJson(QJsonDocument::Compact));
    return 0;
}
