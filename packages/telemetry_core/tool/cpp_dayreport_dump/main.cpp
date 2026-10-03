// Prints FlappedEar Overlays' channel summaries, temperature associations,
// focus areas and day report as one JSON document:
//   cpp_dayreport_dump <output.json> <input.vbo>...
//   cpp_dayreport_dump --day <day.json> <output.json>
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession.
//
// "files": each file with lap traces, a start gate and an eligible lap
// becomes a day of two runs of the same recording ("run-a" named "Run A",
// "run-b" named "Run B"), whose sections come from outingLapRows and are
// sorted with sortOutingLaps (segments on the group's configuration). Both runs get one track configuration; the
// user excluded run A's even laps and run B's odd laps, so the eligible laps
// are those of cpp_theoretical_best_dump. For each segment set (the best
// lap's proposals approved into its run with ids s0, s1, ..., the same
// shifted 37 m and every other one) it follows
// AnalysisController::computeOutingDayReport: the ranking
// (rankOutingLaps), progression, lap consistency, theoretical best (the
// loop of calculateOutingTheoreticalBest with the corner observations),
// time losses, section progression, Overlays' own summarizeOutingChannels
// and the focus inputs, assembled by buildOutingDayReport. It writes the
// report, the selected focus areas in full, the channel summaries and the
// temperature associations (AnalysisController::outingTemperatureAssociations
// is an app member function; the tool repeats its lines). The first file
// also gets reports for other states (loading, not calculated, failed,
// unavailable, stale, no focus inputs, no group, every lap's losses).
//
// "cases": summarizeChannel, combineChannelSummaries,
// recordedTemperatureChannels and findCoolingIntervals on hand-made
// sessions; spearmanCorrelation, associateTemperature and
// lapStrongAcceleration; selectFocusAreas on hand-made and generated
// inputs; buildDayReport and validateDayReport on fixed documents; and a
// hand-made day of four runs (temperatures with placeholders, a glitch and a
// gap, heart rate, longitudinal acceleration, a run without recording and a
// run without channels) through summarizeOutingChannels, the temperature
// associations and buildOutingDayReport. The sessions are written so the
// Dart side reads exactly the same samples.
//
// A --day file names a real day's recordings (runs: runId, name, file and
// optionally sourceRevision), the eligible laps (population), each run's
// stored segments and the best lap, as for cpp_progression_dump; every run
// gets the same track configuration (trackConfiguration, by default
// configuration A) and laps off a run's detected route are left out. The
// optional groupLabel names the group and configuration is the reference
// the segments carry (by default the tool's). It writes the report, focus
// areas, channel summaries and temperature associations of that day.
//
// Lap references are written as runId, sourceRevision, type, startTime and
// endTime. NaN is written as null.

#include "telemetry/BrakingMetrics.h"
#include "telemetry/ChannelSummary.h"
#include "telemetry/Consistency.h"
#include "telemetry/CornerSpeeds.h"
#include "telemetry/DayReport.h"
#include "telemetry/DrivingVariability.h"
#include "telemetry/ExitMetrics.h"
#include "telemetry/FocusAreas.h"
#include "telemetry/LapTiming.h"
#include "telemetry/OutingChannelSummaries.h"
#include "telemetry/OutingDayReport.h"
#include "telemetry/OutingLapLoader.h"
#include "telemetry/OutingLaps.h"
#include "telemetry/OutingTheoreticalBest.h"
#include "telemetry/OutingTheoreticalBestResults.h"
#include "telemetry/SectorTiming.h"
#include "telemetry/TelemetryGeometry.h"
#include "telemetry/TemperatureAssociation.h"
#include "telemetry/TheoreticalBest.h"
#include "telemetry/TimeLoss.h"
#include "telemetry/TrackInference.h"
#include "telemetry/TrackProgress.h"
#include "telemetry/TrackSegmentProposals.h"
#include "telemetry/TrackSegmentReview.h"
#include "telemetry/TrackSegments.h"
#include "telemetry/VboParser.h"

#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QMap>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <functional>
#include <limits>
#include <memory>
#include <optional>
#include <stdexcept>

using namespace FlappedEar;

namespace {
// The recordings summarizeOutingChannels reads, by the "key" of a run's source.
QHash<QString, std::shared_ptr<const TelemetrySession>> sessionsByKey;
}

namespace FlappedEar {
// Overlays' loader resolves, verifies and decodes a run's recording from the
// project; here the session is already in memory.
OutingLapDetail loadOutingLapDetail(const QJsonObject &source, const QString &, const QVariantMap &, const quint64 request,
    const std::shared_ptr<std::atomic_bool> &, const std::shared_ptr<TelemetrySessionCache> &, const bool)
{
    OutingLapDetail detail;
    detail.request = request;
    detail.session = sessionsByKey.value(source.value("key").toString());
    return detail;
}
} // namespace FlappedEar

namespace {

const QString configuration = QStringLiteral("compatibility-v1:") + QString("0123456789abcdef").repeated(4);
const QString gates = QStringLiteral("gates-v1:") + QString("a").repeated(64);
const QJsonObject configurationA{{"layoutId", "Test circuit"}, {"direction", "clockwise"}, {"gateRevision", gates}};
const QString eventId = QStringLiteral("event-1");
const QString groupLabel = QStringLiteral("Test circuit");
const QByteArray derivationKey = QByteArray("d").repeated(64);
const QByteArray decisionsKey = QByteArray("decisions");

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

QJsonValue optional(const std::optional<double> &value)
{
    return value ? number(*value) : QJsonValue(QJsonValue::Null);
}

QString sourceRevision(const qsizetype index)
{
    return QString("%1").arg(index, 64, 16, QChar('0'));
}

// A lap reference as written: the fields both apps keep.
QJsonObject shortReference(const QJsonObject &reference)
{
    return {{"runId", reference.value("runId")}, {"sourceRevision", reference.value("sourceRevision")},
            {"type", reference.value("type")}, {"startTime", reference.value("startTime")},
            {"endTime", reference.value("endTime")}};
}

// Every lap reference (makeLapReference's, with a derivation key) shortened.
QJsonValue normalized(const QJsonValue &value)
{
    if (value.isArray()) {
        QJsonArray result;
        for (const auto &item : value.toArray()) result.append(normalized(item));
        return result;
    }
    if (!value.isObject()) return value;
    const auto object = value.toObject();
    if (object.contains("derivationKey") && object.contains("sourceRevision")) return shortReference(object);
    QJsonObject result;
    for (auto it = object.begin(); it != object.end(); ++it) result.insert(it.key(), normalized(it.value()));
    return result;
}

QJsonObject json(const QVariantMap &map)
{
    return normalized(QJsonObject::fromVariantMap(map)).toObject();
}

GeoCoordinate gateMidpoint(const TimingGate &gate)
{
    return {(gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
            (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0};
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

// The loop of calculateOutingTheoreticalBest with the sessions in memory,
// with the corner observations, as in cpp_corner_metrics_dump.
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
        const auto features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
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
    return result;
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

// AnalysisController::outingLapConsistency over the eligible rows.
QVariantMap lapConsistency(const QVector<const OutingLapRow *> &eligible, const bool withDay = true)
{
    QVariantMap result{{"algorithm", QString::fromLatin1(consistencyAlgorithm)},
        {"minimumSamples", minimumConsistencySamples}};
    if (!withDay) return result;
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
    return result;
}

QVariantMap correlationMap(const RankCorrelation &correlation)
{
    QVariantMap map{{"count", correlation.count}, {"available", correlation.coefficient.has_value()}};
    if (correlation.coefficient) {
        map.insert("coefficient", *correlation.coefficient);
        map.insert("strength", associationStrength(*correlation.coefficient));
    } else {
        map.insert("unavailableReason", correlation.unavailableReason);
    }
    return map;
}

// AnalysisController::outingTemperatureAssociations over the channel
// summaries' runs and the eligible laps.
QVariantMap temperatureAssociations(const QVariantList &summaryRuns, const QVector<QJsonObject> &eligible)
{
    QVariantMap result{{"algorithm", QString::fromLatin1(temperatureAssociationAlgorithm)},
        {"minimumLaps", minimumAssociationSamples}, {"minimumCoverage", minimumAssociationCoverage},
        {"orderConfoundLevel", associationOrderConfoundLevel}, {"channels", QVariantList{}}};
    QSet<QByteArray> eligibleKeys;
    for (const auto &reference : eligible) eligibleKeys.insert(lapReferenceKey(reference));
    result.insert("eligibleLaps", eligible.size());
    QStringList names;
    QHash<QString, QString> units;
    for (const auto &runValue : summaryRuns)
        for (const auto &channelValue : runValue.toMap().value("channels").toList()) {
            const auto channel = channelValue.toMap();
            const auto name = channel.value("channel").toString();
            if (!names.contains(name)) { names.append(name); units.insert(name, channel.value("unit").toString()); }
        }
    QVariantList channels;
    for (const auto &name : names) {
        QVector<AssociationObservation> lapTimes, accelerations;
        QVariantList observations;
        qsizetype lowCoverage = 0, notRecorded = 0;
        for (const auto &runValue : summaryRuns) {
            const auto run = runValue.toMap();
            const auto laps = run.value("laps").toList();
            QVariantMap channel;
            for (const auto &channelValue : run.value("channels").toList())
                if (channelValue.toMap().value("channel") == name) channel = channelValue.toMap();
            const auto sections = channel.value("sections").toList();
            for (qsizetype index = 0; index < laps.size(); ++index) {
                const auto lap = laps[index].toMap();
                if (!eligibleKeys.contains(lapReferenceKey(QJsonObject::fromVariantMap(lap.value("reference").toMap()))))
                    continue;
                const auto section = sections.value(index).toMap();
                if (section.isEmpty() || !section.value("valid").toBool()) { ++notRecorded; continue; }
                if (section.value("coverage").toDouble() < minimumAssociationCoverage) { ++lowCoverage; continue; }
                const double temperature = section.value("mean").toDouble();
                const double start = lap.value("startTime").toDouble(), end = lap.value("endTime").toDouble();
                const double lapTime = end - start;
                const auto order = static_cast<double>(observations.size());
                lapTimes.append({temperature, lapTime, order});
                QVariantMap observation{{"runName", run.value("runName")}, {"lapNumber", lap.value("lapNumber")},
                    {"temperature", temperature}, {"lapTime", lapTime}, {"coverage", section.value("coverage")},
                    {"reference", lap.value("reference")}};
                if (lap.contains("strongAccelerationG")) {
                    const double acceleration = lap.value("strongAccelerationG").toDouble();
                    accelerations.append({temperature, acceleration, order});
                    observation.insert("strongAccelerationG", acceleration);
                }
                observations.append(observation);
            }
        }
        const auto withLapTime = associateTemperature(lapTimes);
        const auto withAcceleration = associateTemperature(accelerations);
        channels.append(QVariantMap{{"channel", name}, {"unit", units.value(name)},
            {"lapTime", correlationMap(withLapTime.withValue)},
            {"acceleration", correlationMap(withAcceleration.withValue)},
            {"order", correlationMap(withLapTime.withOrder)},
            {"confoundedByOrder", withLapTime.confoundedByOrder},
            {"lowCoverageLaps", lowCoverage}, {"notRecordedLaps", notRecorded},
            {"observations", observations}});
    }
    result.insert("channels", channels);
    return result;
}

// summarizeOutingChannels over sessions in memory: run `id` reads the
// session registered under `id` (none: the run is unavailable).
QVariantMap channelSummaries(const QVector<OutingLapRow> &rows)
{
    QHash<QString, QJsonObject> sources;
    for (const auto &row : rows) sources.insert(row.runId, QJsonObject{{"key", row.runId}});
    const auto result = summarizeOutingChannels(rows, sources, {}, 1, std::make_shared<std::atomic_bool>(false));
    return {{"state", result.error.isEmpty() ? "ready" : "error"}, {"message", result.error},
            {"algorithm", QString::fromLatin1(channelSummaryAlgorithm)}, {"runs", result.runs}};
}

QJsonObject areaJson(const FocusArea &area)
{
    return {{"kind", area.kind}, {"segmentId", area.segmentId}, {"name", area.name},
            {"observation", area.observation}, {"hypothesis", area.hypothesis}, {"metric", area.metric},
            {"value", number(area.value)}, {"unit", area.unit}, {"sampleCount", area.sampleCount},
            {"lap", normalized(area.lap)}, {"against", normalized(area.against)}, {"score", number(area.score)}};
}

QJsonArray areasJson(const QVector<FocusArea> &areas)
{
    QJsonArray result;
    for (const auto &area : areas) result.append(areaJson(area));
    return result;
}

// What AnalysisController::computeOutingDayReport hands to buildOutingDayReport.
struct Published {
    QVariantMap ranking, progression, consistency, theoretical, timeLosses, timeLossesAllLaps, sectionProgression,
        channelSummaries;
    QJsonArray eligibleLaps;
    std::optional<FocusInputs> focus;
    std::function<QString(const QJsonObject &)> label;
};

QJsonObject report(const Published &published, const QByteArray &theoreticalKey = decisionsKey, const bool lapsLoading = false)
{
    OutingDayReportSources sources;
    sources.eventId = eventId;
    sources.groupId = published.ranking.value("groupId").toString();
    sources.decisionsKey = decisionsKey;
    sources.theoreticalKey = theoreticalKey;
    sources.lapsLoading = lapsLoading;
    sources.ranking = published.ranking;
    sources.progression = published.progression;
    sources.consistency = published.consistency;
    sources.theoretical = published.theoretical;
    sources.timeLosses = published.timeLosses;
    sources.sectionProgression = published.sectionProgression;
    sources.channelSummaries = published.channelSummaries;
    sources.eligibleLaps = published.eligibleLaps;
    sources.focus = published.focus;
    sources.lapLabel = published.label;
    try {
        return normalized(buildOutingDayReport(sources)).toObject();
    } catch (const std::exception &error) {
        return {{"error", QString::fromUtf8(error.what())}};
    }
}

// The focus inputs of AnalysisController::computeOutingDayReport.
std::optional<FocusInputs> focusInputs(const OutingTheoreticalBest &computed, const QVariantMap &theoretical,
    const std::function<QString(const QJsonObject &)> &label)
{
    if (!computed.error.isEmpty() || !computed.actualBest) return std::nullopt;
    FocusInputs focus;
    focus.referenceLap = computed.actualBest->lapReference;
    focus.referenceLabel = label(focus.referenceLap);
    for (const auto &value : theoretical.value("sectors").toList()) {
        const auto sector = value.toMap();
        if (!sector.contains("lossSeconds") || !sector.contains("sourceLapReference")) continue;
        focus.gaps.append({sector.value("segmentId").toString(), sector.value("name").toString(),
            sector.value("lossSeconds").toDouble(), focus.referenceLap, focus.referenceLabel,
            QJsonObject::fromVariantMap(sector.value("sourceLapReference").toMap()), sector.value("sourceLapLabel").toString()});
    }
    const auto ranking = rankOutingTimeLosses(computed, false, maximumOutingLapRows);
    if (ranking.valid) {
        focus.comparedLapCount = ranking.comparedLapCount;
        for (const auto &loss : ranking.losses)
            focus.losses.append({loss.window.segmentId, loss.window.name, loss.lossSeconds, loss.lapReference});
    }
    QStringList cornerIds = computed.cornerObservations.keys();
    cornerIds.sort();
    for (const auto &segmentId : cornerIds) {
        QString name = segmentId;
        for (const auto &sector : computed.best.sectors)
            if (sector.segmentId == segmentId) name = sector.name;
        focus.corners.append({segmentId, name, computed.cornerObservations.value(segmentId)});
    }
    return focus;
}

struct DayRun {
    QString id;
    QString name;
    std::shared_ptr<TelemetrySession> session;
    std::shared_ptr<LapSession> laps;
    QString revision; // empty: the run's index
};

struct Day {
    QVector<OutingLapRow> rows;
    QHash<QString, QJsonObject> configurations;
    QJsonArray exclusions;
    QString groupId;
    QJsonObject ranking;
    QJsonObject progression;
    QVector<const OutingLapRow *> eligible;
    std::function<QString(const QJsonObject &)> label;
};

// Sections, ranking, progression and eligible laps of `runs`, every run on
// configuration A. `excluded` leaves laps out as the user's exclusions do;
// with `detectedRoutes`, each run's laps off the route its other laps took
// are left out as OutingLapDerivation does for a detected layout.
Day dayOf(const QVector<DayRun> &runs, const std::function<bool(const OutingLapRow &)> &excluded, const bool detectedRoutes,
    const QJsonObject &trackConfiguration = configurationA, const QString &label = groupLabel)
{
    Day day;
    for (qsizetype i = 0; i < runs.size(); ++i) {
        const auto &run = runs[i];
        auto runRows = outingLapRows(*run.session, *run.laps, run.id, run.name, i);
        const auto inference = detectedRoutes
            ? inferTrack(*run.laps, run.session->metadata.value("gpsLongitudeConvention") == "west-positive")
            : TrackInference{};
        for (auto &row : runRows) {
            row.reference = makeLapReference(row, eventId, run.id,
                (run.revision.isEmpty() ? sourceRevision(i) : run.revision).toLatin1(), derivationKey);
            if (inference.supported() && row.type == LapSectionType::Lap && row.referenceEligible
                && !inference.matchingLaps.contains(row.lapNumber))
                row.layoutIssue = "different-recorded-route";
        }
        day.rows.append(runRows);
        day.configurations.insert(run.id, trackConfiguration);
    }
    sortOutingLaps(day.rows);
    for (const auto &row : day.rows)
        if (row.type == LapSectionType::Lap && excluded(row))
            day.exclusions.append(QJsonObject{{"reference", row.reference}, {"reason", "The other half of the laps"}});
    day.groupId = lapCompatibilityGroupId(trackConfiguration);
    QJsonArray metadata;
    for (const auto &run : runs) metadata.append(QJsonObject{{"id", run.id}, {"name", run.name}, {"groupId", day.groupId}});
    day.ranking = rankOutingLaps(day.rows, day.groupId, day.configurations, day.exclusions);
    day.ranking.insert("groupLabel", label);
    day.progression = summarizeOutingProgression(day.rows, day.ranking, metadata);
    day.eligible = eligibleOutingLaps(day.rows, day.groupId, day.configurations, day.exclusions);
    QHash<QByteArray, QString> labels;
    for (const auto &row : day.rows)
        labels.insert(lapReferenceKey(row.reference), QStringLiteral("%1 · LAP %2").arg(row.runName).arg(row.lapNumber));
    day.label = [labels](const QJsonObject &reference) { return labels.value(lapReferenceKey(reference)); };
    for (const auto &run : runs) sessionsByKey.insert(run.id, run.session);
    return day;
}

QJsonArray eligibleEvidence(const Day &day)
{
    QJsonArray evidence;
    for (const auto *row : day.eligible)
        evidence.append(QJsonObject{{"kind", "lap"}, {"reference", row->reference},
            {"label", QStringLiteral("%1 · LAP %2").arg(row->runName).arg(row->lapNumber)}});
    return evidence;
}

struct Computed {
    OutingTheoreticalBest computed;
    Published published;
};

// Everything computeOutingDayReport reads, for one population and segment set.
Computed publish(const Day &day, const QHash<QString, Run> &runs, const QVector<Row> &population,
    const QHash<QString, QJsonValue> &storedSegments, const QJsonObject &actualBest, const QString &segmentConfiguration)
{
    Computed result;
    auto &published = result.published;
    published.label = day.label;
    published.ranking = day.ranking.toVariantMap();
    published.progression = day.progression.toVariantMap();
    published.consistency = lapConsistency(day.eligible);
    published.eligibleLaps = eligibleEvidence(day);
    QStringList runOrder;
    for (const auto &row : population) if (!runOrder.contains(row.runId)) runOrder.append(row.runId);
    std::sort(runOrder.begin(), runOrder.end());
    QString canonicalRunId;
    ApprovedSegmentation approved;
    for (const auto &runId : runOrder) {
        auto candidate = approvedSegmentation(storedSegments.value(runId), segmentConfiguration);
        if (candidate.valid && !candidate.revision.isEmpty() && !candidate.segments.isEmpty()) {
            canonicalRunId = runId;
            approved = candidate;
            break;
        }
    }
    if (canonicalRunId.isEmpty()) {
        result.computed.error = QStringLiteral("No run in this group has an approved segment review yet.");
    } else {
        result.computed = calculate(population, runs, approved, canonicalRunId, actualBest);
    }
    const auto &computed = result.computed;
    const QString state = computed.error.isEmpty() ? "ready" : "error";
    published.theoretical = publishTheoreticalBest(computed, state, computed.error, day.label);
    published.timeLosses = publishTimeLossRanking(computed, state, computed.error, false, day.label);
    published.timeLossesAllLaps = publishTimeLossRanking(computed, state, computed.error, true, day.label);
    published.sectionProgression = publishSectorProgression(computed, state, computed.error, published.progression, day.label);
    published.channelSummaries = channelSummaries(day.rows);
    if (state == "ready") published.focus = focusInputs(computed, published.theoretical, day.label);
    return result;
}

QJsonObject publishedJson(const Day &day, const Computed &result)
{
    const auto &published = result.published;
    QVector<QJsonObject> eligible;
    for (const auto *row : day.eligible) eligible.append(row->reference);
    QJsonObject entry{{"error", result.computed.error}, {"report", report(published)},
        {"focusAreas", published.focus ? areasJson(selectFocusAreas(*published.focus)) : QJsonArray{}},
        {"hasFocus", published.focus.has_value()},
        {"comparedLapCount", published.focus ? QJsonValue(published.focus->comparedLapCount) : QJsonValue(QJsonValue::Null)},
        {"channelSummaries", json(published.channelSummaries)},
        {"associations", json(temperatureAssociations(published.channelSummaries.value("runs").toList(), eligible))}};
    return entry;
}

// The first file's reports in other states.
QJsonArray stateVariants(const Day &day, const Computed &result)
{
    const auto &computed = result.computed;
    const auto &base = result.published;
    QJsonArray variants;
    const auto add = [&](const QString &name, const Published &published, const QByteArray &theoreticalKey = decisionsKey,
                         const bool lapsLoading = false) {
        variants.append(QJsonObject{{"name", name}, {"report", report(published, theoreticalKey, lapsLoading)}});
    };
    const auto withTheoretical = [&](const QString &state, const QString &message) {
        auto published = base;
        published.theoretical = publishTheoreticalBest(computed, state, message, day.label);
        published.timeLosses = publishTimeLossRanking(computed, state, message, false, day.label);
        published.sectionProgression = publishSectorProgression(computed, state, message, base.progression, day.label);
        published.focus.reset();
        return published;
    };
    const auto withChannels = [](Published published, const QString &state, const QString &message) {
        published.channelSummaries = {{"state", state}, {"message", message},
            {"algorithm", QString::fromLatin1(channelSummaryAlgorithm)}, {"runs", QVariantList{}}};
        return published;
    };
    {
        auto published = withChannels(withTheoretical("loading", ""), "loading", "");
        published.ranking = {{"state", "loading"}};
        published.progression = {{"state", "loading"}};
        published.consistency = lapConsistency({}, false);
        add("loading", published, decisionsKey, true);
    }
    add("idle", withChannels(withTheoretical("idle", ""), "idle", ""));
    add("error", withChannels(withTheoretical("error", "The calculation failed."), "error", "Channel summaries were cancelled."));
    add("unavailable", withChannels(withTheoretical("unavailable", "No eligible laps in this group to calculate a theoretical best from."),
        "unavailable", "Import the day's recordings first."));
    add("stale", base, QByteArray("older decisions"));
    {
        auto published = base;
        published.focus.reset();
        add("noFocus", published);
    }
    {
        auto published = base;
        published.timeLosses = base.timeLossesAllLaps;
        add("allLaps", published);
    }
    {
        auto published = withTheoretical("idle", "");
        auto ranking = rankOutingLaps(day.rows, {}, day.configurations, day.exclusions);
        ranking.insert("groupLabel", QString());
        published.ranking = ranking.toVariantMap();
        published.progression = summarizeOutingProgression(day.rows, ranking, {}).toVariantMap();
        published.consistency = lapConsistency({}, false);
        published.eligibleLaps = {};
        add("noGroup", published);
    }
    return variants;
}

std::optional<QJsonObject> runFile(const QString &path, const bool variants)
{
    auto session = std::make_shared<TelemetrySession>();
    auto laps = std::make_shared<LapSession>();
    try {
        *session = VboParser::parseFile(path);
        *laps = deriveSourceLapSession(*session);
    } catch (const std::exception &) {
        return std::nullopt;
    }
    if (laps->lapTraces.isEmpty() || !laps->selectedStartGate) return std::nullopt;
    const QVector<DayRun> runs{{"run-a", "Run A", session, laps}, {"run-b", "Run B", session, laps}};
    const auto day = dayOf(runs, [](const OutingLapRow &row) {
        return (row.runId == "run-a") == (row.lapNumber % 2 == 0);
    }, false);
    if (day.eligible.isEmpty()) return std::nullopt;
    const auto best = day.ranking.value("bestOfDay").toObject();
    const QString bestRun = best.value("runId").toString();
    const int bestNumber = best.value("lapNumber").toInt();
    const auto trace = std::find_if(laps->lapTraces.cbegin(), laps->lapTraces.cend(),
        [bestNumber](const LapTrace &candidate) { return candidate.lapNumber == bestNumber; });
    if (trace == laps->lapTraces.cend()) return std::nullopt;
    const auto &gate = *laps->selectedStartGate;
    const auto axis = buildProgressAxis(*trace, gateMidpoint(gate), gate);
    const auto features = axis.valid ? computeTrackFeatures(axis, segmentReviewSmoothingMeters) : TrackFeatures{};
    if (!features.valid) return std::nullopt;
    const auto automatic = withIds(proposalsToTrackSegments(proposeTrackSegments(axis, features, {}), day.groupId));
    if (automatic.isEmpty()) return std::nullopt;
    QHash<QString, Run> runMap{{"run-a", {"run-a", session.get(), laps.get()}}, {"run-b", {"run-b", session.get(), laps.get()}}};
    QVector<Row> population;
    QJsonArray populationJson;
    for (const auto *row : day.eligible) {
        population.append({row->runId, row->lapNumber, row->start, row->end, row->reference});
        populationJson.append(QJsonObject{{"runId", row->runId}, {"lapNumber", row->lapNumber}});
    }
    QJsonArray sets;
    const QVector<std::pair<QString, QJsonArray>> segmentSets{
        {"automatic", automatic}, {"shifted", shifted(automatic, axis.lengthMeters)}, {"everyOther", everyOther(automatic)}};
    bool first = true;
    for (const auto &[name, segments] : segmentSets) {
        if (segments.isEmpty()) continue;
        const auto result = publish(day, runMap, population, {{bestRun, segments}}, best.value("reference").toObject(), day.groupId);
        auto entry = publishedJson(day, result);
        entry.insert("name", name);
        entry.insert("segments", QJsonObject{{bestRun, segments}});
        if (variants && first) entry.insert("states", stateVariants(day, result));
        first = false;
        sets.append(entry);
    }
    return QJsonObject{{"file", QFileInfo(path).fileName()}, {"eligible", populationJson},
                       {"best", QJsonObject{{"runId", bestRun}, {"lapNumber", bestNumber}}}, {"sets", sets}};
}

// --- Hand-made sessions ----------------------------------------------------

struct ChannelSpec {
    QString name;
    QString unit;
    double rate = 1.0; // Hz
    std::function<double(double)> shape;
    QVector<std::pair<double, double>> gaps; // samples removed in [from, to)
};

std::shared_ptr<TelemetrySession> makeSession(const double duration, const QVector<ChannelSpec> &specs,
    const QHash<QString, QString> &aliases, QJsonObject &json)
{
    auto session = std::make_shared<TelemetrySession>();
    QJsonArray channels;
    for (const auto &spec : specs) {
        TelemetryChannel channel;
        channel.name = spec.name;
        channel.unit = spec.unit;
        QJsonArray times, values;
        for (int i = 0;; ++i) {
            const double time = i / spec.rate;
            if (time > duration + 1e-9) break;
            if (std::any_of(spec.gaps.cbegin(), spec.gaps.cend(),
                    [time](const auto &gap) { return time >= gap.first && time < gap.second; }))
                continue;
            const float value = static_cast<float>(spec.shape(time));
            channel.timestamps.append(time);
            channel.values.append(value);
            times.append(time);
            values.append(number(value));
        }
        session->channels.insert(spec.name, channel);
        channels.append(QJsonObject{{"name", spec.name}, {"unit", spec.unit}, {"times", times}, {"values", values}});
    }
    QJsonObject aliasJson;
    for (auto it = aliases.cbegin(); it != aliases.cend(); ++it) aliasJson.insert(it.key(), it.value());
    session->aliases = aliases;
    session->duration = duration;
    json = {{"duration", duration}, {"channels", channels}, {"aliases", aliasJson}};
    return session;
}

QJsonObject summaryJson(const ChannelSummary &summary)
{
    QJsonObject map{{"channel", summary.channel}, {"unit", summary.unit}, {"startTime", number(summary.startTime)},
        {"endTime", number(summary.endTime)}, {"sampleCount", summary.sampleCount},
        {"excludedArtifacts", summary.excludedArtifacts}, {"minimum", optional(summary.minimum)},
        {"maximum", optional(summary.maximum)}, {"mean", optional(summary.mean)},
        {"minimumTime", optional(summary.minimumTime)}, {"maximumTime", optional(summary.maximumTime)},
        {"coveredSeconds", number(summary.coveredSeconds)}, {"coverage", number(summary.coverage)},
        {"unavailableReason", summary.unavailableReason}, {"valid", summary.valid}};
    return map;
}

QJsonObject policyJson(const QString &name, const ChannelSummaryPolicy &policy)
{
    return {{"name", name}, {"minimumPlausible", number(policy.minimumPlausible)},
            {"maximumPlausible", number(policy.maximumPlausible)}, {"zeroIsPlaceholder", policy.zeroIsPlaceholder},
            {"placeholderTypicalAbove", number(policy.placeholderTypicalAbove)}};
}

constexpr double pi = 3.14159265358979323846;

QJsonObject channelCases()
{
    QJsonObject sessionJson;
    const auto session = makeSession(600.0, {
        {"engine_oil_temp", "C", 2.0, [](double t) { return t <= 200 ? 80 + t / 10 : t <= 420 ? 100 - (t - 200) / 11 + 0.3 * std::sin(t) : 80 + (t - 420) / 9; }, {{300.0, 330.0}}},
        {"coolant_temp-obd", "", 1.0, [](double t) { return t < 4 ? 0.0 : std::abs(t - 250) < 1e-9 ? 900.0 : 90 + 3 * std::sin(t / 40); }, {{100.0, 120.0}}},
        {"Intake_Temp", "C", 1.0, [](double t) { return t < 300 ? 0.0 : 2.0; }, {}},
        {"gearbox_temp", "C", 0.5, [](double t) { return t > 500 ? std::nan("") : 70 + 20 * std::sin(t / 60); }, {}},
        {"heart_rate", "bpm", 1.0, [](double t) { return std::fmod(t, 97) < 2 ? 255.0 : 120 + 25 * std::sin(t / 80); }, {{400.0, 450.0}}},
        {"single", "C", 0.01, [](double t) { return 50 + t; }, {}},
        {"velocity", "km/h", 1.0, [](double t) { return 100 + t; }, {}},
    }, {{"heartRate", "heart_rate"}, {"oil", "engine_oil_temp"}}, sessionJson);
    const QVector<std::pair<QString, ChannelSummaryPolicy>> policies{
        {"temperature", temperatureSummaryPolicy()}, {"heartRate", heartRateSummaryPolicy()},
        {"default", ChannelSummaryPolicy{}}, {"placeholderAbove100", ChannelSummaryPolicy{-40.0, 250.0, true, 100.0}}};
    const QVector<std::pair<double, double>> intervals{{0, 600}, {0, 10}, {3.5, 4.5}, {95, 125}, {101, 119},
        {200, 260}, {249, 251}, {290, 340}, {499, 501}, {600, 700}, {10, 10}, {20, 10}, {0.25, 0.75}, {-5, 3}};
    QJsonArray summaries;
    QMap<QString, QVector<ChannelSummary>> forCombining;
    for (const auto *name : {"engine_oil_temp", "oil", "coolant_temp-obd", "Intake_Temp", "gearbox_temp", "heart_rate",
             "heartRate", "single", "missing"}) {
        for (const auto &[policyName, policy] : policies) {
            for (const auto &[from, to] : intervals) {
                const auto summary = summarizeChannel(*session, name, from, to, policy);
                summaries.append(QJsonObject{{"channel", name}, {"policy", policyName}, {"from", from}, {"to", to},
                    {"summary", summaryJson(summary)}});
                if (policyName == "temperature") forCombining[name].append(summary);
            }
        }
    }
    QJsonArray combined;
    for (auto it = forCombining.cbegin(); it != forCombining.cend(); ++it) {
        const auto &parts = it.value();
        const QVector<QVector<int>> picks{{}, {0}, {1, 2}, {9, 1}, {3, 5, 7}, {10, 11}, {9, 10}, {4, 8, 12}, {13, 1}};
        for (const auto &pick : picks) {
            QVector<ChannelSummary> chosen;
            QJsonArray indices;
            for (const int index : pick) { chosen.append(parts[index]); indices.append(index); }
            combined.append(QJsonObject{{"channel", it.key()}, {"parts", indices},
                {"summary", summaryJson(combineChannelSummaries(chosen))}});
        }
    }
    QJsonArray placeholders;
    auto names = session->channels.keys();
    names.sort();
    for (const auto &name : names)
        for (const auto &[policyName, policy] : policies)
            placeholders.append(QJsonObject{{"channel", name}, {"policy", policyName},
                {"zeroIsPlaceholder", zeroIsPlaceholder(session->channels.value(name), policy)}});
    QJsonArray plausible;
    for (const double value : {0.0, -40.0, -40.5, 250.0, 251.0, 95.0, std::nan(""), std::numeric_limits<double>::infinity()})
        for (const bool zero : {false, true})
            plausible.append(QJsonObject{{"value", std::isnan(value) ? QJsonValue("nan") : std::isinf(value) ? QJsonValue("inf") : QJsonValue(value)},
                {"zeroPlaceholder", zero}, {"plausible", plausibleSample(value, temperatureSummaryPolicy(), zero)}});
    QJsonArray cooling;
    const QVector<std::pair<QString, CoolingOptions>> options{{"default", {}}, {"sensitive", {2.0, 10.0, 2.0}},
        {"long", {5.0, 120.0, 20.0}}, {"unsmoothed", {1.0, 5.0, 0.0}}};
    for (const auto *name : {"engine_oil_temp", "oil", "coolant_temp-obd", "gearbox_temp", "Intake_Temp", "missing"}) {
        for (const auto &[optionName, option] : options) {
            QJsonArray found;
            for (const auto &interval : findCoolingIntervals(*session, name, temperatureSummaryPolicy(), option))
                found.append(QJsonObject{{"startTime", interval.startTime}, {"endTime", interval.endTime},
                    {"startValue", interval.startValue}, {"endValue", interval.endValue}});
            cooling.append(QJsonObject{{"channel", name}, {"options", optionName}, {"intervals", found}});
        }
    }
    QJsonArray policyList;
    for (const auto &[name, policy] : policies) policyList.append(policyJson(name, policy));
    QJsonArray optionList;
    for (const auto &[name, option] : options)
        optionList.append(QJsonObject{{"name", name}, {"minimumDrop", option.minimumDrop},
            {"minimumSeconds", option.minimumSeconds}, {"smoothingSeconds", option.smoothingSeconds}});
    return {{"session", sessionJson}, {"policies", policyList}, {"coolingOptions", optionList},
            {"temperatureChannels", QJsonArray::fromStringList(recordedTemperatureChannels(*session))},
            {"summaries", summaries}, {"combined", combined}, {"placeholders", placeholders},
            {"plausible", plausible}, {"cooling", cooling}};
}

QJsonValue special(const double value)
{
    if (std::isnan(value)) return "nan";
    if (std::isinf(value)) return value > 0 ? "inf" : "-inf";
    return value;
}

QJsonArray specials(const QVector<double> &values)
{
    QJsonArray result;
    for (const double value : values) result.append(special(value));
    return result;
}

QJsonObject correlationJson(const RankCorrelation &correlation)
{
    return {{"count", correlation.count}, {"coefficient", optional(correlation.coefficient)},
            {"unavailableReason", correlation.unavailableReason}};
}

// A small linear congruential generator, so generated inputs are the same
// everywhere.
struct Generator {
    quint64 state;
    double next()
    {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        return static_cast<double>(state >> 11) / static_cast<double>(1ULL << 53);
    }
};

QJsonObject associationCases()
{
    const double nan = std::nan(""), inf = std::numeric_limits<double>::infinity();
    QVector<std::tuple<QVector<double>, QVector<double>, qsizetype>> pairs{
        {{90, 91, 92, 93, 94, 95, 96, 97, 98, 99}, {1, 2, 3, 4, 5, 6, 7, 8, 10, 9}, 8},
        {{90, 90, 91, 91, 92, 92, 93, 93}, {110, 111, 110, 111, 112, 113, 112, 113}, 8},
        {{1, 2, 3, 4, 5, 6, 7}, {1, 2, 3, 4, 5, 6, 7}, 8},
        {{1, 2, 3, 4, 5, 6, 7}, {7, 6, 5, 4, 3, 2, 1}, 3},
        {{95, 95, 95, 95, 95, 95, 95, 95, 95, 95}, {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, 8},
        {{}, {}, 8}, {{1}, {1}, 0}, {{1, 2, 3}, {1, 2}, 2},
        {{90, 91, nan, 92, 93, 94, 95, 96, 97, inf, 98}, {100, 101, 102, 103, nan, 104, 105, 106, 107, 108, -inf}, 8},
        {{3, 1, 2, 2, 5, 4, 4, 4, 9, 0}, {2, 2, 2, 1, 1, 3, 3, 3, 0, 5}, 8},
    };
    Generator generator{42};
    for (int n : {8, 9, 12, 25, 40}) {
        QVector<double> x, y;
        for (int i = 0; i < n; ++i) {
            x.append(std::round(generator.next() * 20.0) / 2.0);
            y.append(generator.next() < 0.1 ? x.last() : std::round((x.last() * 0.3 + generator.next() * 10.0) * 4.0) / 4.0);
        }
        pairs.append({x, y, 8});
    }
    QJsonArray spearman;
    for (const auto &[x, y, minimum] : pairs)
        spearman.append(QJsonObject{{"x", specials(x)}, {"y", specials(y)}, {"minimum", minimum},
            {"result", correlationJson(spearmanCorrelation(x, y, minimum))}});
    QJsonArray strengths;
    for (const double value : {0.0, 0.29, -0.3, 0.45, -0.59999, 0.6, -0.95, 1.0})
        strengths.append(QJsonObject{{"value", value}, {"strength", associationStrength(value)}});
    QJsonArray associations;
    for (int n : {5, 8, 12, 30}) {
        QVector<AssociationObservation> observations;
        QJsonArray written;
        for (int i = 0; i < n; ++i) {
            const double temperature = std::round((95.0 + i * 0.4 + generator.next() * 6.0) * 10.0) / 10.0;
            const double value = 100.0 + generator.next() * 3.0;
            const double order = i * (n == 12 ? -1.0 : 1.0);
            observations.append({temperature, value, order});
            written.append(QJsonArray{temperature, value, order});
        }
        const auto result = associateTemperature(observations);
        associations.append(QJsonObject{{"observations", written}, {"withValue", correlationJson(result.withValue)},
            {"withOrder", correlationJson(result.withOrder)}, {"confoundedByOrder", result.confoundedByOrder}});
    }
    // Strong acceleration on hand-made channels.
    QJsonArray accelerations;
    for (const auto *unit : {"", "g", " G ", "m/s^2"}) {
        QJsonObject sessionJson;
        const auto session = makeSession(30.0, {
            {"longacc", unit, 10.0, [](double t) { return std::fmod(t, 7.0) < 0.05 ? 9.0 : 0.6 * std::sin(t * 1.3) + 0.05 * std::cos(t * 7.0); }, {{12.0, 13.0}}},
        }, {{"longitudinalAcceleration", "longacc"}}, sessionJson);
        QJsonArray results;
        for (const auto &[from, to] : QVector<std::pair<double, double>>{{0, 30}, {0, 3}, {5, 5}, {2.05, 17.3}, {10, 14}, {-1, 40}, {20, 10}}) {
            const auto lap = lapStrongAcceleration(*session, from, to);
            results.append(QJsonObject{{"from", from}, {"to", to}, {"strongG", optional(lap.strongG)},
                {"channel", lap.channel}, {"sampleCount", lap.sampleCount}});
        }
        accelerations.append(QJsonObject{{"session", sessionJson}, {"results", results}});
    }
    return {{"spearman", spearman}, {"strengths", strengths}, {"associations", associations},
            {"accelerations", accelerations}};
}

QJsonObject lapObject(const QString &name) { return {{"runId", name}}; }

QJsonObject observationJson(const CornerLapObservation &observation)
{
    return {{"lap", observation.lapReference}, {"brakingPointMeters", optional(observation.brakingPointMeters)},
            {"brakingProvenance", observation.brakingProvenance}, {"minimumSpeed", optional(observation.minimumSpeed)}};
}

QJsonObject inputsJson(const FocusInputs &inputs)
{
    QJsonArray gaps, losses, corners;
    for (const auto &gap : inputs.gaps)
        gaps.append(QJsonObject{{"segmentId", gap.segmentId}, {"name", gap.name}, {"gapSeconds", special(gap.gapSeconds)},
            {"bestLap", gap.bestLap}, {"bestLapLabel", gap.bestLapLabel}, {"sourceLap", gap.sourceLap},
            {"sourceLapLabel", gap.sourceLapLabel}});
    for (const auto &loss : inputs.losses)
        losses.append(QJsonObject{{"segmentId", loss.segmentId}, {"name", loss.name},
            {"lossSeconds", special(loss.lossSeconds)}, {"lap", loss.lap}});
    for (const auto &corner : inputs.corners) {
        QJsonArray observations;
        for (const auto &observation : corner.observations) observations.append(observationJson(observation));
        corners.append(QJsonObject{{"segmentId", corner.segmentId}, {"name", corner.name}, {"observations", observations}});
    }
    return {{"referenceLap", inputs.referenceLap}, {"referenceLabel", inputs.referenceLabel},
            {"comparedLapCount", inputs.comparedLapCount}, {"gaps", gaps}, {"losses", losses}, {"corners", corners},
            {"speedUnit", inputs.speedUnit}};
}

CornerLapObservation braking(const double meters, const QString &provenance, const QString &lap, const double minimumSpeed = 80.0)
{
    CornerLapObservation observation;
    observation.lapReference = lapObject(lap);
    observation.brakingPointMeters = meters;
    observation.brakingProvenance = provenance;
    observation.minimumSpeed = minimumSpeed;
    return observation;
}

QJsonArray focusCases()
{
    QVector<std::pair<FocusInputs, qsizetype>> cases;
    {
        FocusInputs inputs;
        inputs.referenceLap = lapObject("best");
        inputs.referenceLabel = "Session 5 · LAP 2";
        inputs.comparedLapCount = 5;
        inputs.gaps = {{"7", "Corner 7", 0.412, lapObject("best"), "Session 5 · LAP 2", lapObject("s3l2"), "Session 3 · LAP 2"},
            {"8", "Corner 8", 0.2, lapObject("best"), "Session 5 · LAP 2", lapObject("s4l1"), "Session 4 · LAP 1"}};
        inputs.losses = {{"2", "Corner 2", 0.25, lapObject("a")}, {"2", "Corner 2", 0.30, lapObject("b")},
            {"2", "Corner 2", 0.31, lapObject("c")}, {"2", "Corner 2", 0.6, lapObject("d")},
            {"7", "Corner 7", 0.5, lapObject("a")}, {"7", "Corner 7", 0.5, lapObject("b")}, {"7", "Corner 7", 0.5, lapObject("c")}};
        inputs.corners = {{"4", "Corner 4", {braking(100, "measured", "a"), braking(120, "measured", "b"),
            braking(140, "measured", "c"), braking(160, "measured", "d")}}};
        for (const qsizetype maximum : {3, 1, 0, 10}) cases.append({inputs, maximum});
        inputs.speedUnit = "km/h";
        inputs.corners.append({"5", "Corner 5", {braking(100, "measured", "a", 70), braking(101, "measured", "b", 78),
            braking(102, "measured", "c", 86), braking(103, "inferred", "d", 94), braking(40, "inferred", "e", 99)}});
        cases.append({inputs, 10});
    }
    cases.append({FocusInputs{}, 3});
    // Generated inputs: overlapping segments across kinds, ties, thresholds.
    Generator generator{7};
    for (int round = 0; round < 12; ++round) {
        FocusInputs inputs;
        inputs.referenceLap = lapObject("best");
        inputs.referenceLabel = "Best · LAP 1";
        inputs.comparedLapCount = 2 + round % 5;
        inputs.speedUnit = round % 3 == 0 ? "" : round % 3 == 1 ? "km/h" : "mph";
        const int segments = 3 + round % 6;
        for (int s = 0; s < segments; ++s) {
            const QString id = QString("s%1").arg(s);
            const QString name = QString("Corner %1").arg(s + 1);
            if (generator.next() < 0.6) {
                const double gap = generator.next() < 0.2 ? 0.05 : std::round(generator.next() * 400.0) / 1000.0;
                inputs.gaps.append({id, name, gap, lapObject("best"), "Best · LAP 1", lapObject(QString("g%1").arg(s)), QString("Run · LAP %1").arg(s)});
            }
            const int lossCount = static_cast<int>(generator.next() * 7.0);
            for (int l = 0; l < lossCount; ++l)
                inputs.losses.append({id, name, std::round(generator.next() * 300.0) / 1000.0, lapObject(QString("l%1-%2").arg(s).arg(l))});
            if (generator.next() < 0.7) {
                QVector<CornerLapObservation> observations;
                const int laps = static_cast<int>(generator.next() * 8.0);
                for (int l = 0; l < laps; ++l) {
                    CornerLapObservation observation;
                    observation.lapReference = lapObject(QString("c%1-%2").arg(s).arg(l));
                    if (generator.next() < 0.9) {
                        observation.brakingPointMeters = 100.0 + std::round(generator.next() * 40.0);
                        observation.brakingProvenance = generator.next() < 0.8 ? "measured" : "inferred";
                    }
                    if (generator.next() < 0.9) observation.minimumSpeed = 60.0 + std::round(generator.next() * 16.0) / 2.0;
                    observations.append(observation);
                }
                inputs.corners.append({id, name, observations});
            }
        }
        cases.append({inputs, round % 4 == 0 ? 6 : 3});
    }
    QJsonArray result;
    for (const auto &[inputs, maximum] : cases)
        result.append(QJsonObject{{"inputs", inputsJson(inputs)}, {"maximum", maximum},
            {"areas", areasJson(selectFocusAreas(inputs, maximum))}});
    return result;
}

DayReportResult reportResult(const QString &id, const QString &algorithm, const DayResultStatus status, const QByteArray &key)
{
    DayReportResult result;
    result.id = id;
    result.algorithm = algorithm;
    result.status = status;
    result.range = {{"scope", "day"}, {"groupId", "g1"}};
    result.value = {{"seconds", 109.898}, {"label", "Session 5 · LAP 2"}};
    result.evidence = {QJsonObject{{"kind", "lap"}, {"reference", QJsonObject{{"runId", "r5"}}}}};
    result.decisionsKey = key;
    return result;
}

QJsonObject resultJson(const DayReportResult &result)
{
    return {{"id", result.id}, {"algorithm", result.algorithm}, {"revision", result.revision},
            {"status", dayResultStatusName(result.status)}, {"reason", result.reason}, {"range", result.range},
            {"value", result.value}, {"evidence", result.evidence}, {"decisionsKey", QString::fromLatin1(result.decisionsKey)}};
}

QJsonObject reportCases()
{
    QJsonArray builds;
    const auto build = [&builds](const QString &name, const DayReportInput &input) {
        QJsonArray results;
        for (const auto &result : input.results) results.append(resultJson(result));
        QJsonObject entry{{"name", name}, {"eventId", input.eventId}, {"groupId", input.groupId},
            {"groupLabel", input.groupLabel}, {"decisionsKey", QString::fromLatin1(input.decisionsKey)}, {"results", results}};
        try {
            const auto report = buildDayReport(input);
            entry.insert("report", report);
            entry.insert("validation", validateDayReport(report));
        } catch (const std::invalid_argument &error) {
            entry.insert("error", QString::fromUtf8(error.what()));
        }
        builds.append(entry);
    };
    auto pending = reportResult("theoreticalBest", "theoretical-best-v1", DayResultStatus::NotComputed, {});
    pending.reason = "Not calculated yet.";
    pending.revision = "rev-1";
    build("provenance", {"event", "g1", "Group 1", "key-1", {reportResult("bestLap", "outing-ranking-v1", DayResultStatus::Available, "key-1"), pending}});
    build("stale", {"event", "g1", "Group 1", "key-2", {reportResult("bestLap", "outing-ranking-v1", DayResultStatus::Available, "key-1")}});
    build("independent", {"event", "g1", "Group 1", "key-2", {reportResult("temperatures", "channel-summary-v1", DayResultStatus::Available, {})}});
    auto computing = reportResult("bestLap", "a", DayResultStatus::Computing, "k");
    auto unavailable = reportResult("progression", "a", DayResultStatus::Unavailable, "k");
    unavailable.reason = "No session in this group.";
    auto stale = reportResult("consistency", "a", DayResultStatus::Stale, "k");
    build("statuses", {"e", "", "", "k", {computing, unavailable, stale}});
    build("duplicate", {"event", "g1", "Group 1", "k", {reportResult("bestLap", "a", DayResultStatus::Available, "k"),
        reportResult("bestLap", "a", DayResultStatus::Available, "k")}});
    build("noAlgorithm", {"event", "g1", "Group 1", "k", {reportResult("bestLap", "", DayResultStatus::Available, "k")}});
    build("noId", {"event", "g1", "Group 1", "k", {reportResult("", "a", DayResultStatus::Available, "k")}});
    auto badEvidence = reportResult("bestLap", "a", DayResultStatus::Unavailable, "k");
    badEvidence.evidence = {QJsonObject{{"kind", "video"}}};
    build("badEvidence", {"event", "g1", "Group 1", "k", {badEvidence}});
    // Documents read from elsewhere.
    const auto good = buildDayReport({"event", "g1", "Group 1", "k", {reportResult("bestLap", "a", DayResultStatus::Available, "k")}});
    QJsonArray documents;
    const auto check = [&documents](const QString &name, const QJsonObject &document) {
        documents.append(QJsonObject{{"name", name}, {"document", document}, {"validation", validateDayReport(document)}});
    };
    const auto withEntry = [&good](const std::function<void(QJsonObject &)> &change) {
        auto results = good.value("results").toArray();
        auto entry = results[0].toObject();
        change(entry);
        results[0] = entry;
        auto document = good;
        document.insert("results", results);
        return document;
    };
    check("good", good);
    check("empty", {});
    auto wrongVersion = good; wrongVersion.insert("version", 99); check("wrongVersion", wrongVersion);
    auto doubleVersion = good; doubleVersion.insert("version", 1.0); check("doubleVersion", doubleVersion);
    auto notArray = good; notArray.insert("results", "x"); check("notArray", notArray);
    auto notObject = good; notObject.insert("results", QJsonArray{1}); check("notObject", notObject);
    check("staleWithValue", withEntry([](QJsonObject &entry) { entry.insert("status", "stale"); }));
    check("unknownStatus", withEntry([](QJsonObject &entry) { entry.insert("status", "guessed"); }));
    check("noRange", withEntry([](QJsonObject &entry) { entry.remove("range"); }));
    check("noAlgorithm", withEntry([](QJsonObject &entry) { entry.insert("algorithm", ""); }));
    check("noId", withEntry([](QJsonObject &entry) { entry.remove("id"); }));
    check("noEvidence", withEntry([](QJsonObject &entry) { entry.remove("evidence"); }));
    check("evidenceKind", withEntry([](QJsonObject &entry) { entry.insert("evidence", QJsonArray{QJsonObject{{"kind", "video"}}}); }));
    check("evidenceNotObject", withEntry([](QJsonObject &entry) { entry.insert("evidence", QJsonArray{"lap"}); }));
    {
        auto results = good.value("results").toArray();
        results.append(results[0]);
        auto document = good; document.insert("results", results); check("duplicateId", document);
    }
    {
        QJsonArray many;
        for (qsizetype i = 0; i <= maximumDayReportResults; ++i) {
            auto item = good.value("results").toArray()[0].toObject(); item.insert("id", QString("r%1").arg(i)); many.append(item);
        }
        auto document = good; document.insert("results", many); check("tooManyResults", document);
    }
    {
        QJsonArray evidence;
        for (qsizetype i = 0; i <= maximumDayReportEvidence; ++i) evidence.append(QJsonObject{{"kind", "lap"}});
        check("tooMuchEvidence", withEntry([&evidence](QJsonObject &entry) { entry.insert("evidence", evidence); }));
    }
    return {{"builds", builds}, {"documents", documents}};
}

// A hand-made day: four runs with OUT, LAP and IN sections; s3 has no
// recording and s4 none of the channels.
QJsonObject outingCase()
{
    struct RunSpec { QString id; QString name; double outEnd; QVector<double> laps; double duration; };
    const QVector<RunSpec> runSpecs{{"s1", "Session 1", 40.0, {61.2, 60.4, 60.8, 59.9, 60.1, 61.6, 60.0, 60.3}, 600.0},
        {"s2", "Session 2", 30.0, {62.0, 60.9, 61.4, 60.2, 60.7, 61.1}, 470.0},
        {"s3", "Session 3", 20.0, {60.0, 61.0}, 160.0},
        {"s4", "Session 4", 25.0, {63.0, 62.0, 62.5}, 240.0}};
    QVector<OutingLapRow> rows;
    QJsonArray rowJson;
    for (qsizetype r = 0; r < runSpecs.size(); ++r) {
        const auto &spec = runSpecs[r];
        const auto add = [&](const LapSectionType type, const int number, const double start, const double end) {
            OutingLapRow row;
            row.runId = spec.id;
            row.runName = spec.name;
            row.type = type;
            row.lapNumber = number;
            row.start = start;
            row.end = end;
            row.sourceOrder = r;
            row.reference = {{"runId", spec.id}, {"sourceRevision", ""}, {"type", lapSectionName(type)},
                {"startTime", start}, {"endTime", end}};
            rows.append(row);
            rowJson.append(QJsonObject{{"runId", spec.id}, {"runName", spec.name}, {"type", lapSectionName(type)},
                {"lapNumber", number}, {"start", start}, {"end", end}});
        };
        add(LapSectionType::Out, 0, 0.0, spec.outEnd);
        double start = spec.outEnd;
        for (qsizetype l = 0; l < spec.laps.size(); ++l) {
            add(LapSectionType::Lap, static_cast<int>(l + 1), start, start + spec.laps[l]);
            start += spec.laps[l];
        }
        add(LapSectionType::In, 0, start, spec.duration);
    }
    // Lap times, temperatures and acceleration of each lap, hand-made.
    const auto lapIndex = [](double t, double outEnd) { return t < outEnd ? -1 : static_cast<int>((t - outEnd) / 60.5); };
    QJsonObject sessions;
    QJsonObject json1, json2, json4;
    const auto s1 = makeSession(600.0, {
        {"engine_oil_temp", "C", 2.0, [](double t) { return t < 530 ? 85 + 25 * (1 - std::exp(-t / 150)) + 0.4 * std::sin(t / 7) : 110 - (t - 530) / 4; }, {}},
        {"coolant_temp-obd", "", 1.0, [](double t) { return t < 6 ? 0.0 : std::abs(t - 200) < 1e-9 ? 900.0 : 88 + 4 * std::sin(t / 45); }, {{300.0, 345.0}}},
        {"intake_temp", "C", 1.0, [](double t) { return 18 + 4 * std::sin(t / 90 + 1); }, {}},
        {"heart_rate", "bpm", 1.0, [](double t) { return std::fmod(t, 151) < 1 ? 255.0 : 130 + 20 * std::sin(t / 70); }, {{150.0, 158.0}}},
        {"longacc", "g", 5.0, [lapIndex](double t) { const int lap = lapIndex(t, 40.0); return std::sin(t * 1.7) * (0.35 + 0.02 * ((lap * 3) % 7)); }, {}},
    }, {{"heartRate", "heart_rate"}, {"longitudinalAcceleration", "longacc"}}, json1);
    const auto s2 = makeSession(470.0, {
        {"engine_oil_temp", "C", 2.0, [](double t) { return 104 - 6 * std::sin(t / 60) + (std::fmod(t, 61) < 30 ? 0.5 : -0.5); }, {{200.0, 202.5}}},
        {"intake_temp", "", 0.5, [](double t) { return 21 + t / 100; }, {}},
        {"longacc", "g", 5.0, [lapIndex](double t) { const int lap = lapIndex(t, 30.0); return std::sin(t * 1.3) * (0.3 + 0.03 * ((lap * 5) % 4)); }, {{100.0, 140.0}}},
    }, {{"longitudinalAcceleration", "longacc"}}, json2);
    const auto s4 = makeSession(240.0, {{"velocity", "km/h", 1.0, [](double t) { return 100 + std::sin(t); }, {}}}, {}, json4);
    sessionsByKey.insert("s1", s1);
    sessionsByKey.insert("s2", s2);
    sessionsByKey.remove("s3");
    sessionsByKey.insert("s4", s4);
    sessions.insert("s1", json1);
    sessions.insert("s2", json2);
    sessions.insert("s4", json4);
    const auto summaries = channelSummaries(rows);
    // Eligible: every lap but s1's third and s2's first, and s3's laps.
    QVector<QJsonObject> eligible;
    QJsonArray eligibleJson;
    for (const auto &row : rows) {
        if (row.type != LapSectionType::Lap) continue;
        if ((row.runId == "s1" && row.lapNumber == 3) || (row.runId == "s2" && row.lapNumber == 1)) continue;
        eligible.append(row.reference);
        eligibleJson.append(row.reference);
    }
    // Reports of these summaries; no group, nothing else calculated.
    Published published;
    published.ranking = {{"state", "selection-required"}, {"groupId", ""}, {"lapCount", 0}, {"eligibleLapCount", 0}};
    published.progression = {{"state", "selection-required"}, {"groupId", ""}, {"runs", QVariantList{}}};
    published.consistency = lapConsistency({}, false);
    published.theoretical = {{"state", "idle"}, {"message", ""}};
    published.timeLosses = {{"state", "idle"}, {"message", ""}};
    published.sectionProgression = {{"state", "idle"}, {"message", ""}, {"algorithm", QString::fromLatin1(consistencyAlgorithm)}};
    published.channelSummaries = summaries;
    published.label = [](const QJsonObject &) { return QString(); };
    auto onlyMissing = published;
    QVariantList noChannels;
    for (const auto &run : summaries.value("runs").toList())
        if (run.toMap().value("runId") == "s3" || run.toMap().value("runId") == "s4") noChannels.append(run);
    onlyMissing.channelSummaries.insert("runs", noChannels);
    return {{"rows", rowJson}, {"sessions", sessions}, {"eligible", eligibleJson},
            {"channelSummaries", json(summaries)},
            {"associations", json(temperatureAssociations(summaries.value("runs").toList(), eligible))},
            {"report", report(published)}, {"reportWithoutChannels", report(onlyMissing)}};
}

// --day: recordings, eligible laps, stored segments and the best lap, from a file.
int runDay(const QString &input, const QString &outputPath)
{
    QFile file(input);
    if (!file.open(QIODevice::ReadOnly)) return 1;
    const auto description = QJsonDocument::fromJson(file.readAll()).object();
    // The track configuration of every run (configuration A by default), the
    // group's label and the configuration reference the segments carry.
    const auto trackConfiguration = description.contains("trackConfiguration")
        ? description.value("trackConfiguration").toObject() : configurationA;
    const QString label = description.value("groupLabel").toString(groupLabel);
    const QString segmentConfiguration = description.value("configuration").toString(configuration);
    QVector<DayRun> runs;
    for (const auto &value : description.value("runs").toArray()) {
        const auto run = value.toObject();
        DayRun item{run.value("runId").toString(), run.value("name").toString(),
                    std::make_shared<TelemetrySession>(), std::make_shared<LapSession>(),
                    run.value("sourceRevision").toString()};
        *item.session = VboParser::parseFile(run.value("file").toString());
        *item.laps = deriveSourceLapSession(*item.session);
        runs.append(item);
    }
    const auto day = dayOf(runs, [](const OutingLapRow &) { return false; }, true, trackConfiguration, label);
    QHash<QString, Run> runMap;
    for (const auto &run : runs) runMap.insert(run.id, {run.id, run.session.get(), run.laps.get()});
    QHash<QByteArray, const OutingLapRow *> byKey;
    QVector<Row> population;
    for (const auto &value : description.value("population").toArray()) {
        const auto lap = value.toObject();
        for (const auto &row : day.rows)
            if (row.type == LapSectionType::Lap && row.runId == lap.value("runId").toString()
                && row.lapNumber == lap.value("lapNumber").toInt())
                population.append({row.runId, row.lapNumber, row.start, row.end, row.reference});
    }
    QHash<QString, QJsonValue> stored;
    const auto segments = description.value("segments").toObject();
    for (auto it = segments.begin(); it != segments.end(); ++it) stored.insert(it.key(), it.value());
    const auto best = description.value("actualBest").toObject();
    QJsonObject actualBest;
    for (const auto &row : population)
        if (row.runId == best.value("runId").toString() && row.lapNumber == best.value("lapNumber").toInt()) actualBest = row.reference;
    const auto result = publish(day, runMap, population, stored, actualBest, segmentConfiguration);
    auto entry = publishedJson(day, result);
    QJsonArray eligible;
    for (const auto *row : day.eligible) eligible.append(QJsonObject{{"runId", row->runId}, {"lapNumber", row->lapNumber}});
    entry.insert("eligible", eligible);
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
    QJsonArray files;
    for (int index = 2; index < argc; ++index) {
        if (const auto entry = runFile(QString::fromLocal8Bit(argv[index]), files.isEmpty())) files.append(*entry);
    }
    const QJsonObject cases{{"configuration", configuration}, {"eventId", eventId}, {"groupLabel", groupLabel},
                            {"decisionsKey", QString::fromLatin1(decisionsKey)}, {"channels", channelCases()},
                            {"associations", associationCases()}, {"focus", focusCases()},
                            {"dayReport", reportCases()}, {"outing", outingCase()}};
    QFile output(QString::fromLocal8Bit(argv[1]));
    if (!output.open(QIODevice::WriteOnly)) return 1;
    output.write(QJsonDocument(QJsonObject{{"files", files}, {"cases", cases}}).toJson(QJsonDocument::Compact));
    return 0;
}
