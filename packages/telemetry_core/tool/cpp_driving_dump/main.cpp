// Prints FlappedEar Overlays' G-G pairs, driving states and coasting for
// input files as one JSON document:
//   cpp_driving_dump <output.json> <input.vbo>...
//   cpp_driving_dump --day <day.json> <output.json>
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession.
//
// "recordings": for each file, every timed lap and the whole recording:
// buildGgPairs with computeGgPeaks and decimateGgPoints (300 points),
// classifyDrivingStates (and again with inference disabled), the braking
// and cornering overlap with travelledMeters, and summarizeCoasting with
// and without a lap trace and approved segments. A lap's trace is its
// projection onto an axis built from its own trace and the recording's
// start gate; the approved segments are four fixed fractions of that axis,
// the last across start/finish.
//
// "pairs": laps compared as the comparison dump picks them (the first
// eligible lap against the fastest, the swap, the last against the second;
// a few pairs across files). For each pair the tool follows
// AnalysisController (comparisonGgScatter and comparisonTrailBraking of
// AnalysisControllerCornerAnalyzer.cpp; app member functions, so the tool
// repeats their lines) over several ranges of the shared axis, and the
// driving states and coasting of both laps over a range as Telemetry's
// comparison page asks for them (comparisonDrivingStates in Dart).
//
// "cases": the hand-made sessions of GgPairsTests.cpp and
// DrivingStatesTests.cpp.
//
// G-G points are written every "points"-th (see "strides"), always with the
// last. A --day file names a real day's recordings,
//   {"runs": [{"runId", "file"}], "pairs"?: [{"a": {"runId", "lapNumber"},
//    "b": {"runId", "lapNumber"}}]}
// and writes every point; without "pairs" each run's own pairs and its first
// eligible lap against the next run's are compared. Use it locally only;
// never commit its input or output. NaN is written as null.

#include "telemetry/CoastingAnalysis.h"
#include "telemetry/DrivingStates.h"
#include "telemetry/GgPairs.h"
#include "telemetry/LapTiming.h"
#include "telemetry/TrackProgress.h"
#include "telemetry/VboParser.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <functional>
#include <limits>
#include <memory>
#include <optional>
#include <tuple>

using namespace FlappedEar;

namespace {

int pointStride = 4;

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

QJsonValue optionalNumber(const std::optional<double> &value)
{
    return value ? number(*value) : QJsonValue(QJsonValue::Null);
}

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

// --- JSON of the results ----------------------------------------------------

QJsonArray pointJson(const qsizetype index, const GgPoint &point)
{
    return {static_cast<double>(index), number(point.time), number(point.longitudinalG), number(point.lateralG)};
}

QJsonValue peakJson(const std::optional<GgPeak> &peak)
{
    if (!peak) return QJsonValue(QJsonValue::Null);
    return QJsonArray{number(peak->value), number(peak->point.time), number(peak->point.longitudinalG),
        number(peak->point.lateralG)};
}

QJsonObject peaksJson(const GgPeaks &peaks)
{
    return {{"lateral", peakJson(peaks.lateral)}, {"braking", peakJson(peaks.braking)},
        {"acceleration", peakJson(peaks.acceleration)}, {"combined", peakJson(peaks.combined)},
        {"sampleCount", static_cast<double>(peaks.sampleCount)}};
}

QJsonArray pointsJson(const QVector<GgPoint> &points, const int stride)
{
    QJsonArray result;
    for (qsizetype i = 0; i < points.size(); ++i)
        if (i % stride == 0 || i == points.size() - 1) result.append(pointJson(i, points[i]));
    return result;
}

QJsonObject ggJson(const GgPairs &pairs)
{
    const auto peaks = computeGgPeaks(pairs.points);
    const auto shown = decimateGgPoints(pairs.points, peaks, 300);
    return {{"valid", pairs.valid}, {"reason", pairs.unavailableReason},
        {"longitudinalChannel", pairs.longitudinalChannel}, {"lateralChannel", pairs.lateralChannel},
        {"longitudinalUnit", pairs.longitudinalUnit}, {"lateralUnit", pairs.lateralUnit},
        {"unitsDeclared", pairs.unitsDeclared}, {"sharedClock", pairs.sharedClock},
        {"maximumPairingOffset", number(pairs.maximumPairingOffsetSeconds)},
        {"candidateCount", static_cast<double>(pairs.candidateCount)},
        {"skippedForGap", static_cast<double>(pairs.skippedForGap)},
        {"excludedOutliers", static_cast<double>(pairs.excludedOutliers)},
        {"count", static_cast<double>(pairs.points.size())}, {"points", pointsJson(pairs.points, pointStride)},
        {"peaks", peaksJson(peaks)}, {"decimatedCount", static_cast<double>(shown.size())},
        {"decimated", pointsJson(shown, 16)}};
}

QJsonArray intervalsJson(const QVector<DrivingStateInterval> &intervals)
{
    QJsonArray result;
    for (const auto &interval : intervals) result.append(QJsonArray{number(interval.start), number(interval.end)});
    return result;
}

QJsonObject trackJson(const DrivingStateTrack &track)
{
    return {{"provenance", track.provenance}, {"channel", track.channel}, {"unit", track.unit},
        {"threshold", QJsonArray{number(track.threshold.on), number(track.threshold.off), track.threshold.unit}},
        {"active", intervalsJson(track.active)}, {"known", intervalsJson(track.known)},
        {"reason", track.unresolvedReason}, {"spikes", track.rejectedSpikes}};
}

QJsonObject statesJson(const DrivingStateClassification &states)
{
    return {{"valid", states.valid}, {"algorithm", states.algorithm}, {"start", number(states.start)},
        {"end", number(states.end)}, {"braking", trackJson(states.braking)},
        {"accelerating", trackJson(states.accelerating)}, {"cornering", trackJson(states.cornering)},
        {"coasting", trackJson(states.coasting)}};
}

QJsonObject coastingJson(const CoastingSummary &summary)
{
    QJsonArray episodes, segments;
    for (const auto &episode : summary.episodes)
        episodes.append(QJsonArray{number(episode.startTime), number(episode.endTime), number(episode.seconds),
            number(episode.meters), optionalNumber(episode.startProgressMeters),
            optionalNumber(episode.endProgressMeters), episode.segmentId});
    for (const auto &segment : summary.segments)
        segments.append(QJsonArray{segment.segmentId, segment.name, segment.type, number(segment.seconds),
            number(segment.meters), segment.episodes});
    return {{"valid", summary.valid}, {"algorithm", summary.algorithm}, {"provenance", summary.provenance},
        {"reason", summary.unresolvedReason}, {"lapSeconds", number(summary.lapSeconds)},
        {"knownSeconds", number(summary.knownSeconds)}, {"coastingSeconds", number(summary.coastingSeconds)},
        {"coastingMeters", number(summary.coastingMeters)}, {"episodes", episodes}, {"segments", segments}};
}

// --- One lap's axis and the comparison of two laps -------------------------

struct Slot {
    const Recording *recording = nullptr;
    int lapNumber = 0;
    double start = 0.0;
    double end = 0.0;
    LapTrace referenceTrace;
    TimingGate referenceGate;
    bool hasReferenceGate = false;
};

std::optional<Slot> slotFor(const Recording &recording, const int lapNumber)
{
    for (const auto &lap : recording.laps.timedLaps) {
        if (lap.number != lapNumber) continue;
        Slot slot;
        slot.recording = &recording;
        slot.lapNumber = lapNumber;
        slot.start = lap.startTelemetryTime;
        slot.end = lap.endTelemetryTime;
        if (recording.laps.selectedStartGate) {
            const auto trace = std::find_if(recording.laps.lapTraces.cbegin(), recording.laps.lapTraces.cend(),
                [lapNumber](const LapTrace &candidate) { return candidate.lapNumber == lapNumber; });
            if (trace != recording.laps.lapTraces.cend()) {
                slot.referenceTrace = *trace;
                slot.referenceGate = *recording.laps.selectedStartGate;
                slot.hasReferenceGate = true;
            }
        }
        return slot;
    }
    return std::nullopt;
}

// The comparison state AnalysisController keeps for a ready pair (the axis
// from lap A's trace and start gate, both projections).
struct Pair {
    Slot members[2];
    ProgressAxis axis;
    QVector<ProgressSegment> traces[2];

    const TelemetrySession &session(const int slot) const { return *members[slot].recording->session; }

    void prepare()
    {
        const auto &a = members[0];
        const auto &b = members[1];
        if (a.hasReferenceGate) {
            const GeoCoordinate origin{
                (a.referenceGate.endpointA.latitudeDegrees + a.referenceGate.endpointB.latitudeDegrees) / 2.0,
                (a.referenceGate.endpointA.longitudeDegrees + a.referenceGate.endpointB.longitudeDegrees) / 2.0};
            axis = buildProgressAxis(a.referenceTrace, origin, a.referenceGate);
        }
        if (axis.valid) {
            traces[0] = projectLapTrace(axis, session(0), a.start, a.end);
            traces[1] = projectLapTrace(axis, session(1), b.start, b.end);
        }
    }

    double length() const { return axis.valid ? axis.lengthMeters : 0.0; }

    // The `timeAt` of comparisonGgScatter and comparisonTrailBraking.
    std::optional<double> timeAt(const int slot, const double meters) const
    {
        if (meters <= 1e-6) return members[slot].start;
        if (meters >= length() - 1e-6) return members[slot].end;
        return timeAtProgress(traces[slot], meters);
    }

    // AnalysisController::comparisonGgScatter, as JSON.
    QJsonObject ggScatter(const double startMeters, const double endMeters, const int maximumPoints) const
    {
        if (!axis.valid) return {{"valid", false}};
        const double from = std::clamp(startMeters, 0.0, length()), to = std::clamp(endMeters, 0.0, length());
        QJsonArray laps;
        for (int slot = 0; slot < 2; ++slot) {
            const auto t0 = timeAt(slot, from), t1 = timeAt(slot, to);
            if (!t0 || !t1 || *t1 <= *t0) {
                laps.append(QJsonObject{{"valid", false}, {"reason", "incompleteCoverage"}});
                continue;
            }
            const auto pairs = buildGgPairs(session(slot), *t0, *t1);
            if (!pairs.valid) {
                laps.append(QJsonObject{{"valid", false}, {"reason", pairs.unavailableReason}});
                continue;
            }
            const auto peaks = computeGgPeaks(pairs.points);
            const auto shown = decimateGgPoints(pairs.points, peaks, maximumPoints);
            laps.append(QJsonObject{{"valid", true}, {"start", number(*t0)}, {"end", number(*t1)},
                {"candidateCount", static_cast<double>(pairs.candidateCount)},
                {"skippedForGap", static_cast<double>(pairs.skippedForGap)},
                {"excludedOutliers", static_cast<double>(pairs.excludedOutliers)},
                {"sharedClock", pairs.sharedClock}, {"unitsDeclared", pairs.unitsDeclared},
                {"longitudinalChannel", pairs.longitudinalChannel}, {"lateralChannel", pairs.lateralChannel},
                {"peaks", peaksJson(peaks)}, {"pointCount", static_cast<double>(shown.size())},
                {"points", pointsJson(shown, pointStride)}});
        }
        return {{"valid", true}, {"startMeters", number(from)}, {"endMeters", number(to)}, {"laps", laps}};
    }

    // AnalysisController::comparisonTrailBraking, as JSON.
    QJsonObject trailBraking(const double startMeters, const double endMeters) const
    {
        if (!axis.valid) return {{"valid", false}};
        const double total = length();
        const double from = std::clamp(startMeters, 0.0, total), to = std::clamp(endMeters, 0.0, total);
        const QVector<std::pair<double, double>> ranges = from <= to
            ? QVector<std::pair<double, double>>{{from, to}}
            : QVector<std::pair<double, double>>{{from, total}, {0.0, to}};
        double span = 0.0;
        for (const auto &[a, b] : ranges) span += b - a;
        if (!(span > 0.0)) return {{"valid", false}};
        QJsonArray laps;
        for (int slot = 0; slot < 2; ++slot) {
            const auto &trace = traces[slot];
            QVariantMap lap{{"valid", true}};
            double overlapSeconds = 0, overlapMeters = 0, brakingSeconds = 0, corneringSeconds = 0, offset = 0;
            QJsonArray brakingStrip, corneringStrip, overlapStrip;
            const auto strip = [&](const QVector<DrivingStateInterval> &intervals, const double rangeStart, QJsonArray &out) {
                for (const auto &interval : intervals) {
                    const auto a = progressAtTime(trace, interval.start), b = progressAtTime(trace, interval.end);
                    if (!a || !b) continue;
                    out.append(QJsonArray{number((offset + *a - rangeStart) / span), number((offset + *b - rangeStart) / span)});
                }
            };
            const auto seconds = [](const QVector<DrivingStateInterval> &intervals) {
                double sum = 0; for (const auto &i : intervals) sum += i.end - i.start; return sum;
            };
            for (const auto &[rangeStart, rangeEnd] : ranges) {
                const auto t0 = timeAt(slot, rangeStart), t1 = timeAt(slot, rangeEnd);
                if (!t0 || !t1 || *t1 <= *t0) { lap = {{"valid", false}, {"unavailableReason", "incompleteCoverage"}}; break; }
                const auto states = classifyDrivingStates(session(slot), *t0, *t1);
                const auto overlap = overlapOf(states.braking.active, states.cornering.active);
                overlapSeconds += seconds(overlap);
                overlapMeters += travelledMeters(session(slot), overlap);
                brakingSeconds += seconds(states.braking.active);
                corneringSeconds += seconds(states.cornering.active);
                strip(states.braking.active, rangeStart, brakingStrip);
                strip(states.cornering.active, rangeStart, corneringStrip);
                strip(overlap, rangeStart, overlapStrip);
                lap.insert("brakingProvenance", states.braking.provenance);
                lap.insert("corneringProvenance", states.cornering.provenance);
                lap.insert("brakeChannel", states.braking.channel);
                lap.insert("lateralChannel", states.cornering.channel);
                offset += rangeEnd - rangeStart;
            }
            if (lap.value("valid").toBool()) {
                const bool known = lap.value("brakingProvenance") != drivingStateUnknown
                    && lap.value("corneringProvenance") != drivingStateUnknown;
                if (!known) {
                    lap = {{"valid", false}, {"unavailableReason", "stateUnknown"},
                        {"brakingProvenance", lap.value("brakingProvenance")},
                        {"corneringProvenance", lap.value("corneringProvenance")}};
                } else {
                    lap.insert("overlapSeconds", overlapSeconds);
                    lap.insert("overlapMeters", overlapMeters);
                    lap.insert("brakingSeconds", brakingSeconds);
                    lap.insert("corneringSeconds", corneringSeconds);
                }
            }
            auto json = QJsonObject::fromVariantMap(lap);
            if (lap.value("valid").toBool())
                json.insert("strips", QJsonObject{{"braking", brakingStrip}, {"cornering", corneringStrip},
                    {"overlap", overlapStrip}});
            laps.append(json);
        }
        return {{"valid", true}, {"startMeters", number(from)}, {"endMeters", number(to)},
            {"crossesStartFinish", from > to}, {"laps", laps}};
    }

    // Both laps' driving states and coasting over a range, as Telemetry's
    // comparison page asks for them.
    QJsonObject drivingStates(const double startMeters, const double endMeters) const
    {
        if (!axis.valid) return {{"valid", false}};
        const double from = std::clamp(startMeters, 0.0, length()), to = std::clamp(endMeters, 0.0, length());
        QJsonArray laps;
        for (int slot = 0; slot < 2; ++slot) {
            const auto t0 = timeAt(slot, from), t1 = timeAt(slot, to);
            if (!t0 || !t1 || *t1 <= *t0) {
                laps.append(QJsonObject{{"valid", false}, {"reason", "incompleteCoverage"}});
                continue;
            }
            const auto states = classifyDrivingStates(session(slot), *t0, *t1);
            const auto overlap = overlapOf(states.braking.active, states.cornering.active);
            laps.append(QJsonObject{{"valid", states.valid}, {"start", number(*t0)}, {"end", number(*t1)},
                {"states", statesJson(states)},
                {"coasting", coastingJson(summarizeCoasting(session(slot), *t0, *t1, &traces[slot]))},
                {"overlap", intervalsJson(overlap)}, {"overlapMeters", number(travelledMeters(session(slot), overlap))}});
        }
        return {{"valid", true}, {"laps", laps}};
    }
};

// Four approved segments at fixed fractions of an axis, the last across
// start/finish.
ApprovedSegmentation fixedSegments(const double length)
{
    ApprovedSegmentation approved;
    approved.valid = true;
    approved.trackConfigurationReference = "fixed";
    for (const auto &[id, name, type, from, to] : QVector<std::tuple<QString, QString, QString, double, double>>{
             {"s1", "Turn 1", "corner", 0.10, 0.40}, {"s2", "Back straight", "straight", 0.40, 0.70},
             {"s3", "Turn 2", "corner", 0.70, 0.95}, {"s4", "Start/finish", "straight", 0.95, 0.10}})
        approved.segments.append(QJsonObject{{"id", id}, {"name", name}, {"type", type},
            {"startProgressMeters", from * length}, {"endProgressMeters", to * length}});
    return approved;
}

QJsonObject lapJson(const Recording &recording, const int lapNumber, const double start, const double end)
{
    const auto &session = *recording.session;
    QJsonObject entry{{"lapNumber", lapNumber}, {"start", number(start)}, {"end", number(end)}};
    entry.insert("gg", ggJson(buildGgPairs(session, start, end)));
    const auto states = classifyDrivingStates(session, start, end);
    entry.insert("states", statesJson(states));
    DrivingStateOptions strict;
    strict.allowInferred = false;
    entry.insert("strict", statesJson(classifyDrivingStates(session, start, end, strict)));
    const auto overlap = overlapOf(states.braking.active, states.cornering.active);
    entry.insert("overlap", intervalsJson(overlap));
    entry.insert("overlapMeters", number(travelledMeters(session, overlap)));
    entry.insert("coastingBare", coastingJson(summarizeCoasting(session, start, end)));
    if (const auto slot = lapNumber > 0 ? slotFor(recording, lapNumber) : std::nullopt) {
        Pair own;
        own.members[0] = own.members[1] = *slot;
        own.prepare();
        entry.insert("axisValid", own.axis.valid);
        if (own.axis.valid) {
            const auto approved = fixedSegments(own.length());
            entry.insert("axisLength", number(own.length()));
            entry.insert("coasting", coastingJson(summarizeCoasting(session, start, end, &own.traces[0], &approved)));
        }
    }
    return entry;
}

QJsonObject recordingJson(const Recording &recording)
{
    QJsonArray laps;
    for (const auto &lap : recording.laps.timedLaps)
        laps.append(lapJson(recording, lap.number, lap.startTelemetryTime, lap.endTelemetryTime));
    laps.append(lapJson(recording, 0, 0.0, recording.session->duration));
    return {{"file", recording.file}, {"laps", laps}};
}

QJsonObject pairJson(const Recording &recordingA, const int lapA, const Recording &recordingB, const int lapB)
{
    QJsonObject entry{{"fileA", recordingA.file}, {"lapA", lapA}, {"fileB", recordingB.file}, {"lapB", lapB}};
    const auto slotA = slotFor(recordingA, lapA), slotB = slotFor(recordingB, lapB);
    if (!slotA || !slotB) {
        entry.insert("missing", true);
        return entry;
    }
    entry.insert("missing", false);
    Pair pair;
    pair.members[0] = *slotA;
    pair.members[1] = *slotB;
    pair.prepare();
    const double length = pair.length();
    entry.insert("axisValid", pair.axis.valid);
    entry.insert("axisLength", number(length));
    const double span = std::max(1.0, length);
    QJsonArray gg;
    for (const auto &[from, to, points] : QVector<std::tuple<double, double, int>>{{0.0, span, 1500},
             {span * 0.25, span * 0.6, 100}, {span * 0.9, span * 1.2, 1500}, {span * 0.5, span * 0.5 + 3.0, 50},
             {10.0, 5.0, 50}, {0.0, span, 0}}) {
        auto json = pair.ggScatter(from, to, points);
        json.insert("requestedStart", number(from));
        json.insert("requestedEnd", number(to));
        json.insert("maximumPoints", points);
        gg.append(json);
    }
    entry.insert("gg", gg);
    QJsonArray trail;
    for (const auto &[from, to] : QVector<std::pair<double, double>>{{0.0, span}, {span * 0.2, span * 0.5},
             {span * 0.8, span * 0.15}, {span * 0.3, span * 0.3}, {-5.0, span * 2.0}}) {
        auto json = pair.trailBraking(from, to);
        json.insert("requestedStart", number(from));
        json.insert("requestedEnd", number(to));
        trail.append(json);
    }
    entry.insert("trailBraking", trail);
    QJsonArray driving;
    for (const auto &[from, to] : QVector<std::pair<double, double>>{{0.0, span}, {span * 0.25, span * 0.6}}) {
        auto json = pair.drivingStates(from, to);
        json.insert("requestedStart", number(from));
        json.insert("requestedEnd", number(to));
        driving.append(json);
    }
    entry.insert("drivingStates", driving);
    return entry;
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

int firstEligible(const Recording &recording)
{
    for (const auto &lap : recording.laps.timedLaps)
        if (lap.referenceEligible()) return lap.number;
    return recording.laps.timedLaps.isEmpty() ? 0 : recording.laps.timedLaps.first().number;
}

// Recordings of one track, compared across files.
const QVector<QPair<QString, QString>> crossFilePairs{
    {"driving_measured.vbo", "driving_inferred.vbo"},
    {"driving_inferred.vbo", "driving_calc.vbo"},
    {"driving_calc.vbo", "driving_pressure.vbo"},
    {"driving_measured.vbo", "corners_measured.vbo"},
};

// --- Hand-made sessions ----------------------------------------------------

TelemetryChannel timedChannel(const QString &name, const QString &unit, const QVector<double> &times,
    const std::function<double(double)> &value)
{
    TelemetryChannel result;
    result.name = name;
    result.unit = unit;
    for (const double time : times) {
        result.timestamps.append(time);
        result.values.append(static_cast<float>(value(time)));
    }
    return result;
}

QVector<double> clock(const double start, const double end, const double step)
{
    QVector<double> times;
    for (double time = start; time <= end + 1e-9; time += step) times.append(time);
    return times;
}

TelemetrySession ggSession(const TelemetryChannel &longitudinal, const TelemetryChannel &lateral)
{
    TelemetrySession session;
    session.channels.insert(longitudinal.name, longitudinal);
    session.channels.insert(lateral.name, lateral);
    session.aliases.insert("longitudinalAcceleration", longitudinal.name);
    session.aliases.insert("lateralAcceleration", lateral.name);
    return session;
}

// GgPairsTests.cpp's sessions, and the windows asked of them.
QJsonArray ggCases()
{
    const double nan = std::numeric_limits<double>::quiet_NaN();
    QJsonArray cases;
    const auto add = [&cases](const QString &name, const TelemetrySession &session, const double start, const double end) {
        auto json = ggJson(buildGgPairs(session, start, end));
        json.insert("name", name);
        json.insert("start", number(start));
        json.insert("end", number(end));
        cases.append(json);
    };
    const auto shared = clock(0.0, 1.0, 0.1);
    const auto sharedSession = ggSession(
        timedChannel("longacc", "g", shared, [](double t) { return t < 0.5 ? -0.8 : 0.3; }),
        timedChannel("latacc", "g", shared, [](double t) { return t < 0.5 ? 0.6 : -0.4; }));
    add("shared", sharedSession, 0.0, 1.0);
    add("sharedPart", sharedSession, 0.25, 0.55);
    QVector<double> lateralTimes;
    for (double time = 0.025; time <= 1.525; time += 0.05)
        if (time < 0.4 || time > 0.9) lateralTimes.append(time);
    add("interpolated", ggSession(timedChannel("longacc", "g", clock(0.0, 1.5, 0.1), [](double) { return -0.5; }),
        timedChannel("latacc", "g", lateralTimes, [](double t) { return t; })), 0.0, 1.5);
    const auto short_ = clock(0.0, 0.5, 0.1);
    add("metric", ggSession(timedChannel("longacc", "m/s^2", short_, [](double) { return -9.80665; }),
        timedChannel("latacc", "m/s²", short_, [](double) { return 4.903325; })), 0.0, 0.5);
    add("metricSpaced", ggSession(timedChannel("longacc", " M/S2 ", short_, [](double) { return 3.0; }),
        timedChannel("latacc", "m / s ^ 2", short_, [](double) { return -2.0; })), 0.0, 0.5);
    add("undeclared", ggSession(timedChannel("longacc", "", short_, [](double) { return 0.2; }),
        timedChannel("latacc", "", short_, [](double) { return 0.1; })), 0.0, 0.5);
    add("unsupported", ggSession(timedChannel("longacc", "km/h", short_, [](double) { return 1.0; }),
        timedChannel("latacc", "g", short_, [](double) { return 0.1; })), 0.0, 0.5);
    const auto outlierTimes = clock(0.0, 0.9, 0.1);
    const auto outliers = ggSession(
        timedChannel("longacc", "g", outlierTimes, [nan](double t) {
            return std::abs(t - 0.3) < 1e-6 ? 12.0 : std::abs(t - 0.5) < 1e-6 ? nan : -0.4; }),
        timedChannel("latacc", "g", outlierTimes, [nan](double t) { return std::abs(t - 0.7) < 1e-6 ? nan : 0.7; }));
    add("outliers", outliers, 0.0, 0.9);
    add("inverted", outliers, 1.0, 0.5);
    add("outside", outliers, 5.0, 6.0);
    TelemetrySession missingLateral;
    missingLateral.channels.insert("longacc", timedChannel("longacc", "g", outlierTimes, [](double) { return 0.1; }));
    missingLateral.aliases.insert("longitudinalAcceleration", "longacc");
    add("missingLateral", missingLateral, 0.0, 0.9);
    add("empty", TelemetrySession{}, 0.0, 1.0);
    return cases;
}

QJsonObject peaksCase()
{
    QVector<GgPoint> points;
    for (int i = 0; i < 5000; ++i) points.append({i * 0.01, 0.3 * std::cos(i * 0.01), 0.3 * std::sin(i * 0.01)});
    points[1234].longitudinalG = -1.1;
    points[3777].lateralG = -1.05;
    const auto peaks = computeGgPeaks(points);
    QJsonArray decimated;
    for (const int maximum : {300, 1, 0, 5000, 4999}) {
        const auto shown = decimateGgPoints(points, peaks, maximum);
        decimated.append(QJsonObject{{"maximumPoints", maximum}, {"count", static_cast<double>(shown.size())},
            {"points", pointsJson(shown, 7)}});
    }
    return {{"peaks", peaksJson(peaks)}, {"decimated", decimated}, {"emptyPeaks", peaksJson(computeGgPeaks({}))}};
}

constexpr double dt = 0.05;
constexpr int sampleCount = 201;

TelemetryChannel makeChannel(const QString &name, const QString &unit, const std::function<double(double)> &value,
    const std::function<bool(double)> &present = [](double) { return true; })
{
    TelemetryChannel channel;
    channel.name = name;
    channel.unit = unit;
    for (int k = 0; k < sampleCount; ++k) {
        const double t = k * dt;
        if (!present(t)) continue;
        channel.timestamps.append(t);
        channel.values.append(static_cast<float>(value(t)));
    }
    return channel;
}

TelemetrySession sessionWith(const QVector<QPair<QString, TelemetryChannel>> &aliased)
{
    TelemetrySession session;
    for (const auto &[alias, channel] : aliased) {
        session.channels.insert(channel.name, channel);
        session.aliases.insert(alias, channel.name);
    }
    return session;
}

double brake(double t) { return t > 5.0 && t < 7.0 ? 60.0 : 0.0; }
double throttle(double t) { return t < 4.0 || t > 8.0 ? 90.0 : 0.0; }
double lateral(double t) { return t > 4.5 && t < 7.5 ? -0.9 : 0.05; }
double longitudinal(double t) { return t < 4.0 || t > 8.0 ? 0.25 : t > 5.0 && t < 7.0 ? -0.7 : 0.0; }
double speed(double) { return 110.0; }

// DrivingStatesTests.cpp's sessions (and a few more), by name; the Dart
// test builds the same ones.
QVector<QPair<QString, TelemetrySession>> drivingSessions()
{
    const auto everywhere = [](double) { return true; };
    return {
        {"measured", sessionWith({{"brake", makeChannel("brake_pos-obd", "%", brake)},
            {"throttle", makeChannel("accelerator_pos-obd", "%", throttle)},
            {"lateralAcceleration", makeChannel("latacc-calc", "g", lateral)},
            {"longitudinalAcceleration", makeChannel("longacc-calc", "g", longitudinal)},
            {"speed", makeChannel("velocity", "km/h", speed)}})},
        {"inferred", sessionWith({{"lateralAcceleration", makeChannel("latacc", "g", lateral)},
            {"longitudinalAcceleration", makeChannel("longacc", "g", longitudinal)},
            {"speed", makeChannel("velocity", "km/h", speed)}})},
        {"gapped", sessionWith({{"brake", makeChannel("brake_pos-obd", "%", brake, [](double t) { return t < 2.0 || t > 3.0; })},
            {"throttle", makeChannel("accelerator_pos-obd", "%", [](double t) { return t > 1.0 && t < 4.0 ? 0.0 : 90.0; })},
            {"speed", makeChannel("velocity", "km/h", speed)}})},
        {"bar", sessionWith({{"brake", makeChannel("brake_pressure", "bar", brake)},
            {"throttle", makeChannel("accelerator_pos-obd", "%", throttle)},
            {"longitudinalAcceleration", makeChannel("longacc", "g", longitudinal)},
            {"speed", makeChannel("velocity", "km/h", speed)}})},
        {"slow", sessionWith({{"brake", makeChannel("brake_pos-obd", "%", [](double) { return 0.0; })},
            {"throttle", makeChannel("accelerator_pos-obd", "%", [](double) { return 0.0; })},
            {"speed", makeChannel("velocity", "km/h", [](double t) { return t < 5.0 ? 5.0 : 60.0; })}})},
        {"leftFoot", sessionWith({{"brake", makeChannel("brake_pos-obd", "%", [](double t) { return t > 5.0 && t < 6.0 ? 30.0 : 0.0; })},
            {"throttle", makeChannel("accelerator_pos-obd", "%", [](double t) { return t > 4.0 && t < 7.0 ? 50.0 : 0.0; })},
            {"speed", makeChannel("velocity", "km/h", speed)}})},
        {"blip", sessionWith({{"brake", makeChannel("brake_pos-obd", "%", [](double t) { return std::abs(t - 3.0) < 0.01 ? 50.0 : 0.0; })},
            {"throttle", makeChannel("accelerator_pos-obd", "%", [](double) { return 0.0; })},
            {"speed", makeChannel("velocity", "km/h", speed)}})},
        {"coasting", sessionWith({{"brake", makeChannel("brake_pos-obd", "%", brake)},
            {"throttle", makeChannel("accelerator_pos-obd", "%", throttle)},
            {"speed", makeChannel("velocity", "km/h", [](double) { return 36.0; })}})},
        {"speedOnly", sessionWith({{"speed", makeChannel("velocity", "km/h", speed)}})},
        {"mph", sessionWith({{"brake", makeChannel("brake_pos-obd", "%", brake)},
            {"throttle", makeChannel("accelerator_pos-obd", "%", throttle)},
            {"lateralAcceleration", makeChannel("latacc", "m/s2", lateral)},
            {"speed", makeChannel("velocity", "mph", speed)}})},
        {"noSpeed", sessionWith({{"brake", makeChannel("brake_pos-obd", "PCT", brake)},
            {"throttle", makeChannel("accelerator_pos-obd", "", throttle)}})},
        {"missingSamples", sessionWith({{"brake", makeChannel("brake_pos-obd", "%",
                [](double t) { return std::abs(t - 2.5) < 0.01 || std::abs(t - 2.55) < 0.01 ? std::nan("") : brake(t + 1.0); })},
            {"throttle", makeChannel("accelerator_pos-obd", "%", throttle)},
            {"lateralAcceleration", makeChannel("latacc", "g", lateral, everywhere)},
            {"speed", makeChannel("velocity", "km/h", [](double t) { return t < 9.0 ? 110.0 : std::nan(""); })}})},
        // KAN-201: speed is lost from 5.45 s to 6.55 s, inside braking while
        // cornering; no distance is integrated across that gap.
        {"speedGap", sessionWith({{"brake", makeChannel("brake_pos-obd", "%", brake)},
            {"throttle", makeChannel("accelerator_pos-obd", "%", throttle)},
            {"lateralAcceleration", makeChannel("latacc-calc", "g", lateral)},
            {"speed", makeChannel("velocity", "km/h", speed, [](double t) { return t < 5.47 || t > 6.53; })}})},
    };
}

QVector<ProgressSegment> coastingTrace()
{
    QVector<ProgressSegment> trace(1);
    for (int k = 0; k < sampleCount; ++k) {
        ProjectedSample sample;
        sample.telemetryTime = k * dt;
        sample.progressMeters = k * dt * 10.0;
        trace[0].samples.append(sample);
    }
    return trace;
}

ApprovedSegmentation coastingSegments()
{
    ApprovedSegmentation approved;
    approved.valid = true;
    for (const auto &[id, start, end] : {std::tuple{"approach", 0.0, 50.0}, std::tuple{"corner", 50.0, 70.0},
                                         std::tuple{"exit", 70.0, 100.0}})
        approved.segments.append(QJsonObject{{"id", id}, {"name", QString(id).toUpper()}, {"type", "sector"},
            {"startProgressMeters", start}, {"endProgressMeters", end}});
    return approved;
}

QJsonArray drivingCases()
{
    QJsonArray cases;
    DrivingStateOptions strict;
    strict.allowInferred = false;
    DrivingStateOptions invalid;
    invalid.cornering = {0.2, 0.3, "g"};
    DrivingStateOptions tuned;
    tuned.minimumSpeedKmh = 1.0;
    tuned.minimumDurationSeconds = 0.5;
    tuned.cornering = {0.5, 0.4, "G"};
    const auto trace = coastingTrace();
    const auto approved = coastingSegments();
    for (const auto &[name, session] : drivingSessions()) {
        for (const auto &[label, options, start, end] : QVector<std::tuple<QString, DrivingStateOptions, double, double>>{
                 {"default", {}, 0.0, 10.0}, {"strict", strict, 0.0, 10.0}, {"invalid", invalid, 0.0, 10.0},
                 {"tuned", tuned, 0.0, 10.0}, {"window", {}, 3.02, 7.73}, {"empty", {}, 5.0, 5.0}}) {
            const auto states = classifyDrivingStates(session, start, end, options);
            const auto overlap = overlapOf(states.braking.active, states.cornering.active);
            cases.append(QJsonObject{{"session", name}, {"options", label}, {"start", start}, {"end", end},
                {"states", statesJson(states)}, {"overlap", intervalsJson(overlap)},
                {"overlapMeters", number(travelledMeters(session, overlap))},
                {"brakingMeters", number(travelledMeters(session, states.braking.active))},
                {"coasting", coastingJson(summarizeCoasting(session, start, end, &trace, &approved, options))},
                {"coastingBare", coastingJson(summarizeCoasting(session, start, end, nullptr, nullptr, options))}});
        }
    }
    return cases;
}

void write(const QString &path, const QJsonObject &document)
{
    QFile output(path);
    if (!output.open(QIODevice::WriteOnly)) std::exit(1);
    output.write(QJsonDocument(document).toJson(QJsonDocument::Compact));
}

QJsonObject strides()
{
    return {{"points", pointStride}};
}

QJsonObject casesJson()
{
    return {{"gg", ggCases()}, {"peaks", peaksCase()}, {"driving", drivingCases()}};
}

int runDay(const QString &dayPath, const QString &outputPath)
{
    QFile file(dayPath);
    if (!file.open(QIODevice::ReadOnly)) return 1;
    const auto day = QJsonDocument::fromJson(file.readAll()).object();
    pointStride = 1;
    QVector<QString> runIds;
    QHash<QString, Recording> recordings;
    for (const auto &value : day.value("runs").toArray()) {
        const auto run = value.toObject();
        auto recording = load(run.value("file").toString());
        if (!recording) return 1;
        runIds.append(run.value("runId").toString());
        recordings.insert(run.value("runId").toString(), *recording);
    }
    QJsonArray recordingEntries, pairs;
    for (const auto &runId : runIds) recordingEntries.append(recordingJson(recordings[runId]));
    if (day.contains("pairs")) {
        for (const auto &value : day.value("pairs").toArray()) {
            const auto pair = value.toObject();
            const auto a = pair.value("a").toObject(), b = pair.value("b").toObject();
            pairs.append(pairJson(recordings[a.value("runId").toString()], a.value("lapNumber").toInt(),
                recordings[b.value("runId").toString()], b.value("lapNumber").toInt()));
        }
    } else {
        for (qsizetype index = 0; index < runIds.size(); ++index) {
            const auto &recording = recordings[runIds[index]];
            for (const auto &[a, b] : pairsOf(recording)) pairs.append(pairJson(recording, a, recording, b));
            if (index + 1 < runIds.size()) {
                const auto &next = recordings[runIds[index + 1]];
                pairs.append(pairJson(recording, firstEligible(recording), next, firstEligible(next)));
            }
        }
    }
    write(outputPath, {{"strides", strides()}, {"recordings", recordingEntries}, {"pairs", pairs},
        {"cases", casesJson()}});
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
    QJsonArray recordingEntries, pairs;
    for (const auto &recording : recordings) {
        recordingEntries.append(recordingJson(recording));
        for (const auto &[a, b] : pairsOf(recording)) pairs.append(pairJson(recording, a, recording, b));
    }
    for (const auto &[nameA, nameB] : crossFilePairs) {
        const auto a = std::find_if(recordings.cbegin(), recordings.cend(), [&](const Recording &r) { return r.file == nameA; });
        const auto b = std::find_if(recordings.cbegin(), recordings.cend(), [&](const Recording &r) { return r.file == nameB; });
        if (a == recordings.cend() || b == recordings.cend()) continue;
        pairs.append(pairJson(*a, firstEligible(*a), *b, firstEligible(*b)));
    }
    write(QString::fromLocal8Bit(argv[1]), {{"strides", strides()}, {"recordings", recordingEntries},
        {"pairs", pairs}, {"cases", casesJson()}});
    return 0;
}
