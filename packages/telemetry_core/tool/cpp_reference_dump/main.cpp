// Prints the C++ reference result for each input file as one JSON document:
//   cpp_reference_dump <output.json> <input>...
// Each input is parsed with VboParser::parseFile and, when parsing succeeds,
// laps are derived with deriveSourceLapSession. Floats are written as the
// double they widen to, so the Dart side can compare float32 values exactly.
// NaN is written as null.

#include "telemetry/LapTiming.h"
#include "telemetry/VboParser.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <cmath>
#include <cstdio>
#include <exception>

using namespace FlappedEar;

namespace {

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

QJsonObject coordinate(const GeoCoordinate &value)
{
    return {{"latitude", number(value.latitudeDegrees)}, {"longitude", number(value.longitudeDegrees)}};
}

QString gateType(const TimingGateType type)
{
    switch (type) {
    case TimingGateType::Start: return "start";
    case TimingGateType::Split: return "split";
    case TimingGateType::Unknown: break;
    }
    return "unknown";
}

QJsonObject gate(const TimingGate &value)
{
    return {{"type", gateType(value.type)},
            {"sourceName", value.sourceName},
            {"endpointA", coordinate(value.endpointA)},
            {"endpointB", coordinate(value.endpointB)},
            {"sourceDescription", value.sourceDescription}};
}

QString lapStatus(const LapSessionStatus status)
{
    switch (status) {
    case LapSessionStatus::Available: return "available";
    case LapSessionStatus::NoSourceStartGate: return "noSourceStartGate";
    case LapSessionStatus::AmbiguousSourceStartGate: return "ambiguousSourceStartGate";
    case LapSessionStatus::InvalidGate: return "invalidGate";
    case LapSessionStatus::NoUsableGps: return "noUsableGps";
    case LapSessionStatus::NoAcceptedPasses: return "noAcceptedPasses";
    case LapSessionStatus::InsufficientPasses: return "insufficientPasses";
    }
    return "unknown";
}

QString referenceIssue(const LapReferenceIssue issue)
{
    switch (issue) {
    case LapReferenceIssue::None: return "none";
    case LapReferenceIssue::GpsGap: return "gpsGap";
    case LapReferenceIssue::InvalidGps: return "invalidGps";
    }
    return "unknown";
}

QJsonObject sessionJson(const TelemetrySession &session)
{
    QJsonObject metadata;
    for (auto it = session.metadata.cbegin(); it != session.metadata.cend(); ++it)
        metadata.insert(it.key(), it.value());
    QJsonObject aliases;
    for (auto it = session.aliases.cbegin(); it != session.aliases.cend(); ++it)
        aliases.insert(it.key(), it.value());
    QJsonArray gates;
    for (const auto &value : session.timingGates) gates.append(gate(value));
    QJsonArray channels;
    QJsonArray timestamps;
    bool timestampsWritten = false;
    for (const auto &name : session.channelNames()) {
        const auto &channel = session.channels[name];
        if (!timestampsWritten) {
            for (const double time : channel.timestamps) timestamps.append(number(time));
            timestampsWritten = true;
        }
        QJsonArray values;
        for (const float value : channel.values) values.append(number(value));
        channels.append(QJsonObject{{"name", channel.name},
                                    {"unit", channel.unit},
                                    {"sampleCount", channel.timestamps.size()},
                                    {"gapThreshold", number(telemetryGapThreshold(channel))},
                                    {"values", values}});
    }
    QJsonArray warnings;
    for (const auto &warning : session.warnings) warnings.append(warning);
    return {{"duration", number(session.duration)},
            {"startTime", number(session.startTime)},
            {"sampleCount", session.sampleCount},
            {"metadata", metadata},
            {"aliases", aliases},
            {"warnings", warnings},
            {"timingGates", gates},
            {"timestamps", timestamps},
            {"channels", channels}};
}

QJsonObject lapsJson(const LapSession &laps)
{
    const auto &d = laps.diagnostics;
    QJsonObject diagnostics{{"usableGpsSegments", d.usableGpsSegments},
                            {"candidateClusters", d.candidateClusters},
                            {"discardedGapClusters", d.discardedGapClusters},
                            {"rejectedSlowClusters", d.rejectedSlowClusters},
                            {"rejectedParallelClusters", d.rejectedParallelClusters},
                            {"rejectedLongClusters", d.rejectedLongClusters},
                            {"rejectedOppositeDirectionClusters", d.rejectedOppositeDirectionClusters},
                            {"invalidLapDurations", d.invalidLapDurations}};
    QJsonArray passes;
    for (const auto &pass : laps.acceptedPasses) {
        passes.append(QJsonObject{{"telemetryTime", number(pass.telemetryTime)},
                                  {"closestDistanceMeters", number(pass.closestDistanceMeters)},
                                  {"direction", pass.direction},
                                  {"gateFraction", number(pass.gateFraction)},
                                  {"groundSpeedMetersPerSecond", number(pass.groundSpeedMetersPerSecond)},
                                  {"normalSpeedMetersPerSecond", number(pass.normalSpeedMetersPerSecond)}});
    }
    QJsonArray timedLaps;
    for (const auto &lap : laps.timedLaps) {
        timedLaps.append(QJsonObject{{"number", lap.number},
                                     {"startTelemetryTime", number(lap.startTelemetryTime)},
                                     {"endTelemetryTime", number(lap.endTelemetryTime)},
                                     {"durationSeconds", number(lap.durationSeconds)},
                                     {"deltaToBestSeconds", number(lap.deltaToBestSeconds)},
                                     {"referenceIssue", referenceIssue(lap.referenceIssue)}});
    }
    QJsonArray traces;
    for (const auto &trace : laps.lapTraces) {
        QJsonArray points;
        for (const auto &point : trace.points)
            points.append(QJsonArray{number(point.telemetryTime), number(point.eastMeters), number(point.northMeters)});
        traces.append(QJsonObject{{"lapNumber", trace.lapNumber},
                                  {"startTelemetryTime", number(trace.startTelemetryTime)},
                                  {"durationSeconds", number(trace.durationSeconds)},
                                  {"points", points}});
    }
    QJsonObject result{{"status", lapStatus(laps.status)},
                       {"diagnostics", diagnostics},
                       {"acceptedPasses", passes},
                       {"timedLaps", timedLaps},
                       {"lapTraces", traces},
                       {"fastestLapIndex", laps.fastestLapIndex ? QJsonValue(*laps.fastestLapIndex) : QJsonValue()}};
    if (laps.selectedStartGate) result.insert("selectedStartGate", gate(*laps.selectedStartGate));
    return result;
}

QJsonObject runFile(const QString &path)
{
    QJsonObject entry{{"file", QFileInfo(path).fileName()}};
    TelemetrySession session;
    try {
        session = VboParser::parseFile(path);
    } catch (const ResourceLimitError &error) {
        entry.insert("error", QJsonObject{{"type", "ResourceLimitError"}, {"message", QString::fromUtf8(error.what())}});
        return entry;
    } catch (const VboParseError &error) {
        entry.insert("error", QJsonObject{{"type", "VboParseError"}, {"message", QString::fromUtf8(error.what())}});
        return entry;
    }
    entry.insert("session", sessionJson(session));
    try {
        entry.insert("laps", lapsJson(deriveSourceLapSession(session)));
    } catch (const std::exception &error) {
        entry.insert("lapsError", QString::fromUtf8(error.what()));
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
    for (int index = 2; index < argc; ++index) results.append(runFile(QString::fromLocal8Bit(argv[index])));
    QJsonArray lapTimes;
    const double seconds[] = {0.0, 0.0004, 0.0005, 9.9995, 28.662, 59.94, 59.95, 59.96, 59.9995, 60.0,
                              99.5, 100.234567, 109.898, 599.999, 3599.9996, 36000.0, -0.001};
    for (const double value : seconds)
        for (int decimals = -1; decimals <= 4; ++decimals)
            lapTimes.append(QJsonArray{value, decimals, formatLapTime(value, decimals)});
    QFile output(QString::fromLocal8Bit(argv[1]));
    if (!output.open(QIODevice::WriteOnly)) return 1;
    output.write(QJsonDocument(QJsonObject{{"files", results}, {"formatLapTime", lapTimes}}).toJson(QJsonDocument::Compact));
    return 0;
}
