// Prints FlappedEar Overlays' track-progress results for each input file as
// one JSON document:
//   cpp_progress_dump <output.json> <input>...
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession; files without lap traces are skipped. The progress
// axis is built from the first reference-eligible lap trace around the start
// gate's midpoint (the origin LapTiming uses for lap traces). Only summaries
// and every n-th value are written. NaN is written as null.

#include "telemetry/LapTiming.h"
#include "telemetry/TrackProgress.h"
#include "telemetry/VboParser.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <cmath>
#include <cstdio>
#include <exception>
#include <optional>

using namespace FlappedEar;

namespace {

constexpr int axisStride = 50;
constexpr int featureStride = 50;
constexpr int projectionStride = 25;
constexpr int deltaStride = 50;
constexpr int sampledStride = 10;

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

QJsonValue optionalNumber(const std::optional<double> &value)
{
    return value ? number(*value) : QJsonValue(QJsonValue::Null);
}

QJsonObject sampledJson(const TelemetrySession &session, const QString &channel, const double start,
    const double end, const int maximumPoints)
{
    const auto segments = session.sampledSegments(channel, start, end, maximumPoints);
    QJsonArray sizes;
    QJsonArray points;
    int ordinal = 0;
    for (qsizetype s = 0; s < segments.size(); ++s) {
        sizes.append(segments[s].size());
        for (qsizetype i = 0; i < segments[s].size(); ++i, ++ordinal) {
            if (ordinal % sampledStride != 0) continue;
            points.append(QJsonArray{s, i, number(segments[s][i].x()), number(segments[s][i].y())});
        }
    }
    return {{"channel", channel},
            {"start", number(start)},
            {"end", number(end)},
            {"maximumPoints", maximumPoints},
            {"segmentSizes", sizes},
            {"points", points}};
}

QJsonObject axisJson(const ProgressAxis &axis)
{
    QJsonArray points;
    for (qsizetype i = 0; i < axis.points.size(); i += axisStride)
        points.append(QJsonArray{i, number(axis.points[i].x()), number(axis.points[i].y()), number(axis.cumulative[i])});
    return {{"valid", axis.valid},
            {"pointCount", axis.points.size()},
            {"lengthMeters", number(axis.lengthMeters)},
            {"spacingMeters", number(axis.spacingMeters)},
            {"points", points}};
}

QJsonObject featuresJson(const TrackFeatures &features)
{
    QJsonArray samples;
    for (qsizetype i = 0; i < features.samples.size(); i += featureStride) {
        const auto &sample = features.samples[i];
        samples.append(QJsonArray{i, number(sample.progressMeters), number(sample.headingRadians),
                                  number(sample.curvaturePerMeter)});
    }
    return {{"valid", features.valid},
            {"sampleCount", features.samples.size()},
            {"smoothingMeters", number(features.smoothingMeters)},
            {"samples", samples}};
}

QJsonObject projectionJson(const TimedLap &lap, const QVector<ProgressSegment> &segments)
{
    QJsonArray segmentArray;
    for (const auto &segment : segments) {
        QJsonArray samples;
        for (qsizetype i = 0; i < segment.samples.size(); i += projectionStride)
            samples.append(QJsonArray{i, number(segment.samples[i].telemetryTime), number(segment.samples[i].progressMeters)});
        const auto &first = segment.samples.first();
        const auto &last = segment.samples.last();
        segmentArray.append(QJsonObject{{"sampleCount", segment.samples.size()},
                                        {"first", QJsonArray{number(first.telemetryTime), number(first.progressMeters)}},
                                        {"last", QJsonArray{number(last.telemetryTime), number(last.progressMeters)}},
                                        {"samples", samples}});
    }
    QJsonArray timeAt;
    for (const double progress : {0.0, 100.0, 500.0})
        timeAt.append(QJsonArray{progress, optionalNumber(timeAtProgress(segments, progress))});
    QJsonArray progressAt;
    for (const double fraction : {0.0, 0.25, 0.5, 0.9}) {
        const double time = lap.startTelemetryTime + lap.durationSeconds * fraction;
        progressAt.append(QJsonArray{number(time), optionalNumber(progressAtTime(segments, time))});
    }
    return {{"lapNumber", lap.number},
            {"start", number(lap.startTelemetryTime)},
            {"end", number(lap.endTelemetryTime)},
            {"segments", segmentArray},
            {"timeAtProgress", timeAt},
            {"progressAtTime", progressAt}};
}

QJsonObject deltaJson(const QVector<QVector<DeltaPoint>> &series)
{
    QJsonArray seriesArray;
    for (const auto &points : series) {
        QJsonArray sampled;
        for (qsizetype i = 0; i < points.size(); i += deltaStride)
            sampled.append(QJsonArray{i, number(points[i].progressMeters), number(points[i].deltaSeconds)});
        seriesArray.append(QJsonObject{
            {"pointCount", points.size()},
            {"first", QJsonArray{number(points.first().progressMeters), number(points.first().deltaSeconds)}},
            {"last", QJsonArray{number(points.last().progressMeters), number(points.last().deltaSeconds)}},
            {"points", sampled}});
    }
    return {{"series", seriesArray}};
}

std::optional<QJsonObject> runFile(const QString &path)
{
    TelemetrySession session;
    try {
        session = VboParser::parseFile(path);
    } catch (const std::exception &) {
        return std::nullopt;
    }
    LapSession laps;
    try {
        laps = deriveSourceLapSession(session);
    } catch (const std::exception &) {
        return std::nullopt;
    }
    if (laps.lapTraces.isEmpty() || !laps.selectedStartGate) return std::nullopt;

    const TimingGate &gate = *laps.selectedStartGate;
    const GeoCoordinate origin{
        (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
        (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0,
    };
    const LapTrace *reference = nullptr;
    for (const auto &trace : laps.lapTraces) {
        for (const auto &lap : laps.timedLaps) {
            if (lap.number == trace.lapNumber && lap.referenceEligible()) { reference = &trace; break; }
        }
        if (reference) break;
    }
    if (!reference) return std::nullopt;

    QJsonObject entry{{"file", QFileInfo(path).fileName()}, {"referenceLap", reference->lapNumber}};
    entry.insert("sampled", QJsonArray{
        sampledJson(session, "latitude", 0.0, session.duration, 4000),
        sampledJson(session, "speed", 0.0, session.duration, 200),
        sampledJson(session, "speed", session.duration, 0.0, 7),
    });
    const ProgressAxis axis = buildProgressAxis(*reference, origin, gate);
    entry.insert("axis", axisJson(axis));
    entry.insert("features", featuresJson(computeTrackFeatures(axis, 15.0)));

    QJsonArray projections;
    QVector<QVector<ProgressSegment>> projected;
    for (const auto &lap : laps.timedLaps) {
        projected.append(projectLapTrace(axis, session, lap.startTelemetryTime, lap.endTelemetryTime));
        projections.append(projectionJson(lap, projected.last()));
    }
    entry.insert("projections", projections);
    if (!laps.timedLaps.isEmpty() && laps.fastestLapIndex) {
        entry.insert("delta", deltaJson(computeDeltaSeries(projected.first(), projected[*laps.fastestLapIndex], 5.0)));
        entry.insert("fastestLapIndex", *laps.fastestLapIndex);
    }
    return entry;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc < 3) {
        std::fprintf(stderr, "usage: %s <output.json> <input>...\n", argv[0]);
        return 2;
    }
    QJsonArray results;
    for (int index = 2; index < argc; ++index) {
        if (const auto entry = runFile(QString::fromLocal8Bit(argv[index]))) results.append(*entry);
    }
    QFile output(QString::fromLocal8Bit(argv[1]));
    if (!output.open(QIODevice::WriteOnly)) return 1;
    output.write(QJsonDocument(QJsonObject{{"files", results}}).toJson(QJsonDocument::Compact));
    return 0;
}
