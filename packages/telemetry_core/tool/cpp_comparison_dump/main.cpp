// Prints FlappedEar Overlays' A/B lap comparison, overlay-map layers and
// lap-detail charts for input files as one JSON document:
//   cpp_comparison_dump <output.json> <input.vbo>...
//   cpp_comparison_dump --day <day.json> <output.json>
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession.
//
// "pairs": for each file with lap traces, a start gate and an eligible lap,
// laps of that file are compared: the first eligible lap against the
// fastest, the fastest against the first (the swap), and the last eligible
// lap against the second when there are three or more (a single eligible
// lap is compared with itself). A few pairs across files of one corpus track
// follow (crossFilePairs). For each pair the tool follows
// AnalysisController (AnalysisControllerComparison.cpp,
// AnalysisControllerMapLayers.cpp, comparisonPreferredChannels of
// AnalysisControllerCornerAnalyzer.cpp and sessionSeries of
// AnalysisController.cpp; app member functions, so the tool repeats their
// lines over Overlays' own TrackProgress, TrackGeometry, MapLayers and
// ChannelSummary): the shared axis from lap A's trace and start gate, both
// projections, the shared map geometry and overlay tracks, the available
// and preferred channels, Δ time series by progress over several ranges,
// channel series by progress, positions and times at progress, the map
// layer options and every layer on both laps, and lap A's lap-detail charts
// (the default channels of AnalysisControllerOuting.cpp, sessionSeries,
// valueAt, and the lap's own map geometry of loadOutingLapDetail with
// currentTrackPoint). Series points are written every "series"-th, map
// points every "map"-th (see "strides"), always with each run's last point.
//
// "cases": MapLayers on hand-made sessions (those of MapLayersTests.cpp) and
// buildTrackGeometry of a west-positive recording.
//
// A --day file names a real day's recordings and the pairs to compare:
//   {"runs": [{"runId", "file"}], "pairs": [{"a": {"runId", "lapNumber"},
//    "b": {"runId", "lapNumber"}}]}
// and writes every point. Use it locally only; never commit its input or
// output. NaN is written as null.

#include "telemetry/ChannelSummary.h"
#include "telemetry/LapTiming.h"
#include "telemetry/MapLayers.h"
#include "telemetry/TrackGeometry.h"
#include "telemetry/TrackProgress.h"
#include "telemetry/VboParser.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointF>
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

int seriesStride = 4;
int mapStride = 16;

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

QJsonValue optionalNumber(const std::optional<double> &value)
{
    return value ? number(*value) : QJsonValue(QJsonValue::Null);
}

QJsonArray stringArray(const QStringList &values)
{
    QJsonArray result;
    for (const auto &value : values) result.append(value);
    return result;
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

// One slot of AnalysisController's comparison: the row's bounds and, as
// loadOutingLapDetail(deriveReferenceGate = true) finds them, the lap's own
// trace and the recording's start gate.
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

// The comparison state AnalysisController keeps for a ready pair.
struct Pair {
    Slot members[2];
    ProgressAxis axis;
    QVector<ProgressSegment> traces[2];
    TrackGeometry geometry;
    QVariantList overlay[2];

    const TelemetrySession &session(const int slot) const { return *members[slot].recording->session; }

    // ensureComparisonProgressAxis and ensureComparisonSharedGeometry.
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
        geometry = buildSharedTrackGeometry(session(0), a.start, a.end, session(1), b.start, b.end);
        overlay[0] = geometry.valid ? buildTrackSegments(session(0), a.start, a.end, geometry) : QVariantList{};
        overlay[1] = geometry.valid ? buildTrackSegments(session(1), b.start, b.end, geometry) : QVariantList{};
    }

    QStringList availableChannels() const
    {
        const auto a = session(0).channelNames();
        const auto b = session(1).channelNames();
        QStringList shared;
        for (const auto &channel : a)
            if (b.contains(channel)) shared.append(channel);
        return shared;
    }

    QStringList preferredChannels() const
    {
        const auto available = availableChannels();
        if (available.isEmpty()) return {};
        const auto &aliases = session(0).aliases;
        QStringList preferred;
        for (const auto *alias : {"speed", "throttle", "brake"}) {
            const auto name = aliases.value(QString::fromLatin1(alias), QString::fromLatin1(alias));
            if (available.contains(name) && !preferred.contains(name)) preferred.append(name);
        }
        return preferred;
    }

    QVariantMap positionAtProgress(const int slot, const double progressMeters) const
    {
        if (slot < 0 || slot > 1) return {};
        if (!axis.valid) return {};
        const auto time = timeAtProgress(traces[slot], progressMeters);
        if (!time) return {};
        if (!geometry.valid) return {};
        const auto point = FlappedEar::currentTrackPoint(session(slot), *time, geometry);
        if (!point) return {};
        return {{"x", point->x()}, {"y", point->y()}};
    }

    // AnalysisController::comparisonDeltaTiming (KAN-152).
    DeltaTiming deltaTiming() const
    {
        return {members[0].start, members[0].end, members[1].start, members[1].end, axis.lengthMeters};
    }

    QVariantMap deltaSeriesByProgress(const double startProgress, const double endProgress, const int maximumPoints) const
    {
        if (maximumPoints < 2) return {};
        if (!axis.valid) return {};
        if (!std::isfinite(startProgress) || !std::isfinite(endProgress) || endProgress <= startProgress)
            return {{"reason", QStringLiteral("invalidRange")}};
        const auto deltaSegments = computeDeltaSeries(
            traces[0], traces[1], (endProgress - startProgress) / maximumPoints, deltaTiming());
        QVariantList segments;
        double minimum = 0.0, maximum = 0.0;
        bool haveExtent = false;
        for (const auto &deltaSegment : deltaSegments) {
            QVariantList points;
            for (const auto &point : deltaSegment) {
                if (point.progressMeters < startProgress || point.progressMeters > endProgress) continue;
                if (!haveExtent) { minimum = maximum = point.deltaSeconds; haveExtent = true; }
                else { minimum = std::min(minimum, point.deltaSeconds); maximum = std::max(maximum, point.deltaSeconds); }
                points.append(QPointF((point.progressMeters - startProgress) / (endProgress - startProgress), point.deltaSeconds));
            }
            if (!points.isEmpty()) segments.append(QVariant::fromValue(points));
        }
        if (segments.isEmpty()) return {};
        return {{"segments", segments}, {"minimum", minimum}, {"maximum", maximum}, {"unit", QStringLiteral("s")}};
    }

    QVariantMap channelSeriesByProgress(const int slot, const QString &channel, const double startProgress,
        const double endProgress, const int maximumPoints) const
    {
        if (slot < 0 || slot > 1 || maximumPoints < 2) return {};
        const auto &session = this->session(slot);
        const QString resolved = session.aliases.value(channel, channel);
        const auto channelIterator = session.channels.constFind(resolved);
        if (channelIterator == session.channels.cend()) return {{"reason", QStringLiteral("channelMissing")}};
        if (!std::isfinite(startProgress) || !std::isfinite(endProgress) || endProgress <= startProgress)
            return {{"reason", QStringLiteral("invalidRange")}};
        if (!axis.valid) return {{"reason", QStringLiteral("channelMissing")}};
        const auto interpolation = channel.compare("gear", Qt::CaseInsensitive) == 0
            ? InterpolationMode::Previous : InterpolationMode::Linear;
        const double span = endProgress - startProgress;
        QVariantList segments;
        QVariantList current;
        double minimum = 0.0, maximum = 0.0;
        bool haveExtent = false;
        for (int index = 0; index < maximumPoints; ++index) {
            const double targetProgress = startProgress + span * index / (maximumPoints - 1);
            const auto time = timeAtProgress(traces[slot], targetProgress);
            const auto value = time ? session.valueAt(channel, *time, interpolation) : std::nullopt;
            if (!time || !value) {
                if (!current.isEmpty()) { segments.append(QVariant::fromValue(current)); current.clear(); }
                continue;
            }
            if (!haveExtent) { minimum = maximum = *value; haveExtent = true; }
            else { minimum = std::min(minimum, *value); maximum = std::max(maximum, *value); }
            current.append(QPointF((targetProgress - startProgress) / span, *value));
        }
        if (!current.isEmpty()) segments.append(QVariant::fromValue(current));
        if (segments.isEmpty()) return {};
        return {{"segments", segments},
                {"brakingUp", resolved == session.aliases.value("longitudinalAcceleration")},
                {"minimum", minimum},
                {"maximum", maximum},
                {"unit", channelIterator->unit}};
    }

    // AnalysisControllerMapLayers.cpp
    struct MapLayerSpec {
        QString id, label, alias, scale, negativeLabel, positiveLabel;
        bool temperature = false;
    };

    static QVector<MapLayerSpec> fixedLayers()
    {
        return {
            {"speed", QStringLiteral("Speed"), "speed", "sequential", {}, {}},
            {"delta", QStringLiteral("Δ time (A−B)"), {}, "diverging", QStringLiteral("A ahead"), QStringLiteral("A behind")},
            {"lateralG", QStringLiteral("Lateral G"), "lateralAcceleration", "diverging", QStringLiteral("−"), QStringLiteral("+")},
            {"longitudinalG", QStringLiteral("Longitudinal G"), "longitudinalAcceleration", "diverging",
                QStringLiteral("braking"), QStringLiteral("accelerating")},
            {"throttle", QStringLiteral("Throttle"), "throttle", "sequential", {}, {}},
            {"brake", QStringLiteral("Brake (measured)"), "brake", "sequential", {}, {}},
        };
    }

    static const TelemetryChannel *layerChannel(const TelemetrySession &session, const MapLayerSpec &spec, QString *name)
    {
        *name = spec.temperature ? spec.alias : session.aliases.value(spec.alias);
        const auto found = session.channels.constFind(*name);
        return name->isEmpty() || found == session.channels.cend() ? nullptr : &*found;
    }

    QVariantList mapLayerOptions() const
    {
        const QString temperaturePrefix = QStringLiteral("temperature:");
        auto specs = fixedLayers();
        QStringList temperatures;
        for (int slot = 0; slot < 2; ++slot)
            for (const auto &name : recordedTemperatureChannels(session(slot)))
                if (!temperatures.contains(name)) temperatures.append(name);
        std::sort(temperatures.begin(), temperatures.end());
        for (const auto &name : temperatures)
            specs.append({temperaturePrefix + name, name, name, "sequential", {}, {}, true});
        QVariantList options;
        for (const auto &spec : specs) {
            bool available = false;
            if (spec.id == QLatin1String("delta")) {
                available = axis.valid;
            } else {
                QString name;
                for (int slot = 0; slot < 2; ++slot) available = available || layerChannel(session(slot), spec, &name);
            }
            options.append(QVariantMap{{"id", spec.id}, {"label", spec.label}, {"available", available},
                {"temperature", spec.temperature}});
        }
        if (temperatures.isEmpty())
            options.append(QVariantMap{{"id", QStringLiteral("temperature")}, {"label", QStringLiteral("Temperature")},
                {"available", false}, {"temperature", true}});
        return options;
    }

    QVariantMap mapLayer(const QString &layerId, const int slot) const
    {
        constexpr int mapLayerPoints = 800;
        const QString temperaturePrefix = QStringLiteral("temperature:");
        if (slot < 0 || slot > 1) return {{"valid", false}, {"reason", "pairNotReady"}};
        MapLayerSpec spec;
        for (const auto &candidate : fixedLayers())
            if (candidate.id == layerId) spec = candidate;
        if (spec.id.isEmpty() && layerId.startsWith(temperaturePrefix)) {
            const auto name = layerId.mid(temperaturePrefix.size());
            spec = {layerId, name, name, "sequential", {}, {}, true};
        }
        if (spec.id.isEmpty()) return {{"valid", false}, {"reason", "unknownLayer"}};
        QVariantMap result{{"id", spec.id}, {"label", spec.label}, {"scale", spec.scale}, {"slot", slot},
            {"negativeLabel", spec.negativeLabel}, {"positiveLabel", spec.positiveLabel},
            {"algorithm", QString::fromLatin1(mapLayerAlgorithm)}};
        if (!axis.valid || !geometry.valid) {
            result.insert("valid", false);
            result.insert("reason", "noProgressAxis");
            return result;
        }
        const auto &session = this->session(slot);
        const auto &trace = traces[slot];
        const double length = axis.lengthMeters;
        ProgressValueSegments values;
        if (spec.id == QLatin1String("delta")) {
            for (const auto &segment : computeDeltaSeries(traces[0], traces[1], length / mapLayerPoints, deltaTiming())) {
                QVector<QPointF> points;
                for (const auto &point : segment) points.append({point.progressMeters, point.deltaSeconds});
                values.append(points);
            }
            result.insert("unit", QStringLiteral("s"));
            result.insert("provenance", QStringLiteral("calculated"));
        } else {
            QString name;
            const auto *channel = layerChannel(session, spec, &name);
            if (!channel) {
                result.insert("valid", false);
                result.insert("reason", "channelMissing");
                return result;
            }
            values = channelAlongProgress(session, name, trace, length, mapLayerPoints,
                spec.temperature ? temperatureSummaryPolicy() : ChannelSummaryPolicy{});
            result.insert("channel", name);
            result.insert("unit", channel->unit);
            result.insert("provenance", name.endsWith(QStringLiteral("-calc"), Qt::CaseInsensitive)
                ? QStringLiteral("calculated") : QStringLiteral("measured"));
        }
        const auto layer = placeOnMap(session, trace, geometry, values);
        if (layer.polylines.isEmpty()) {
            result.insert("valid", false);
            result.insert("reason", "noSamples");
            return result;
        }
        QVariantList polylines;
        for (const auto &polyline : layer.polylines) {
            QVariantList points, pointValues;
            for (const auto &point : polyline) {
                points.append(QPointF(point.x, point.y));
                pointValues.append(point.value);
            }
            polylines.append(QVariantMap{{"points", points}, {"values", pointValues}});
        }
        result.insert("valid", true);
        result.insert("polylines", polylines);
        result.insert("minimum", *layer.minimum);
        result.insert("maximum", *layer.maximum);
        return result;
    }
};

// AnalysisController::sessionSeries.
QVariantMap sessionSeries(const TelemetrySession &session, const QString &channelName, double telemetryStart,
    double telemetryEnd, int maximumPoints)
{
    SampledSegmentsStatus status = SampledSegmentsStatus::Ok;
    const QVector<QVector<QPointF>> sampledSegments = session.sampledSegments(
        channelName, telemetryStart, telemetryEnd, qBound(2, maximumPoints, 2000), &status);
    if (sampledSegments.isEmpty()) {
        if (status == SampledSegmentsStatus::Ok) return {};
        QString reason;
        switch (status) {
        case SampledSegmentsStatus::InvalidRange: reason = QStringLiteral("invalidRange"); break;
        case SampledSegmentsStatus::ChannelMissing: reason = QStringLiteral("channelMissing"); break;
        case SampledSegmentsStatus::ChannelMalformed: reason = QStringLiteral("channelMalformed"); break;
        case SampledSegmentsStatus::Ok: break;
        }
        return {{"reason", reason}};
    }
    double minimum = sampledSegments.front().front().y();
    double maximum = minimum;
    for (const QVector<QPointF> &segment : sampledSegments) {
        for (const QPointF &sample : segment) {
            minimum = std::min(minimum, sample.y());
            maximum = std::max(maximum, sample.y());
        }
    }
    const double telemetrySpan = telemetryEnd - telemetryStart;
    QVariantList segments;
    for (const QVector<QPointF> &sampledSegment : sampledSegments) {
        QVariantList points;
        for (const QPointF &sample : sampledSegment) {
            const double normalizedTime = telemetrySpan == 0.0 ? 0.0 : (sample.x() - telemetryStart) / telemetrySpan;
            points.append(QVariantMap{{"x", normalizedTime}, {"y", sample.y()}});
        }
        segments.append(QVariant::fromValue(points));
    }
    const QString resolved = session.aliases.value(channelName, channelName);
    const auto channel = session.channels.constFind(resolved);
    return {{"segments", segments},
            {"brakingUp", resolved == session.aliases.value("longitudinalAcceleration")},
            {"minimum", minimum},
            {"maximum", maximum},
            {"unit", channel == session.channels.cend() ? QString() : channel->unit}};
}

// The lap page's channels without a remembered choice
// (AnalysisControllerOuting.cpp).
QStringList lapChannels(const TelemetrySession &session)
{
    QStringList channels;
    for (const auto *alias : {"speed", "lateralAcceleration", "longitudinalAcceleration"}) {
        const auto name = session.aliases.value(alias, alias);
        if (session.channels.contains(name) && !channels.contains(name)) channels.append(name);
    }
    return channels;
}

QPointF pointOf(const QVariant &value)
{
    if (value.typeId() == QMetaType::QPointF) return value.toPointF();
    const auto map = value.toMap();
    return {map.value("x").toDouble(), map.value("y").toDouble()};
}

QJsonObject seriesJson(const QVariantMap &series)
{
    QJsonObject result{{"reason", series.value("reason").toString()}};
    if (!series.contains("segments")) {
        result.insert("empty", true);
        return result;
    }
    QJsonArray sizes, points;
    const auto segments = series.value("segments").toList();
    for (qsizetype s = 0; s < segments.size(); ++s) {
        const auto list = segments[s].toList();
        sizes.append(list.size());
        for (qsizetype i = 0; i < list.size(); ++i) {
            if (i % seriesStride != 0 && i != list.size() - 1) continue;
            const auto point = pointOf(list[i]);
            points.append(QJsonArray{s, i, number(point.x()), number(point.y())});
        }
    }
    result.insert("empty", false);
    result.insert("segmentSizes", sizes);
    result.insert("points", points);
    result.insert("minimum", number(series.value("minimum").toDouble()));
    result.insert("maximum", number(series.value("maximum").toDouble()));
    result.insert("unit", series.value("unit").toString());
    result.insert("brakingUp", series.value("brakingUp").toBool());
    return result;
}

QJsonObject trackJson(const QVariantList &track)
{
    QJsonArray sizes, points;
    for (qsizetype s = 0; s < track.size(); ++s) {
        const auto list = track[s].toList();
        sizes.append(list.size());
        for (qsizetype i = 0; i < list.size(); ++i) {
            if (i % mapStride != 0 && i != list.size() - 1) continue;
            const auto point = pointOf(list[i]);
            points.append(QJsonArray{s, i, number(point.x()), number(point.y())});
        }
    }
    return {{"segmentSizes", sizes}, {"points", points}};
}

QJsonObject geometryJson(const TrackGeometry &geometry)
{
    return {{"valid", geometry.valid},
            {"pointCount", geometry.points.size()},
            {"minimumX", number(geometry.localBounds.left())},
            {"minimumY", number(geometry.localBounds.top())},
            {"width", number(geometry.localBounds.width())},
            {"height", number(geometry.localBounds.height())},
            {"centerX", number(geometry.localCenter.x())},
            {"centerY", number(geometry.localCenter.y())},
            {"scale", number(geometry.normalizationScale)},
            {"originLatitude", number(geometry.originLatitude)},
            {"originLongitude", number(geometry.originLongitude)},
            {"westPositive", geometry.longitudeIsWestPositive}};
}

QJsonObject layerJson(const QVariantMap &layer)
{
    QJsonObject result;
    for (const auto *key : {"id", "label", "scale", "negativeLabel", "positiveLabel", "algorithm", "reason", "unit",
             "provenance", "channel"})
        result.insert(key, layer.value(key).toString());
    result.insert("valid", layer.value("valid").toBool());
    result.insert("slot", layer.contains("slot") ? QJsonValue(layer.value("slot").toInt()) : QJsonValue(QJsonValue::Null));
    if (!layer.value("valid").toBool()) return result;
    result.insert("minimum", number(layer.value("minimum").toDouble()));
    result.insert("maximum", number(layer.value("maximum").toDouble()));
    QJsonArray sizes, points;
    const auto polylines = layer.value("polylines").toList();
    for (qsizetype p = 0; p < polylines.size(); ++p) {
        const auto polyline = polylines[p].toMap();
        const auto list = polyline.value("points").toList();
        const auto values = polyline.value("values").toList();
        sizes.append(list.size());
        for (qsizetype i = 0; i < list.size(); ++i) {
            if (i % mapStride != 0 && i != list.size() - 1) continue;
            const auto point = list[i].toPointF();
            points.append(QJsonArray{p, i, number(point.x()), number(point.y()), number(values[i].toDouble())});
        }
    }
    result.insert("polylineSizes", sizes);
    result.insert("points", points);
    return result;
}

QJsonObject pairJson(const Recording &a, const int lapA, const Recording &b, const int lapB)
{
    QJsonObject entry{{"fileA", a.file}, {"lapA", lapA}, {"fileB", b.file}, {"lapB", lapB}};
    const auto slotA = slotFor(a, lapA);
    const auto slotB = slotFor(b, lapB);
    if (!slotA || !slotB) {
        entry.insert("missing", true);
        return entry;
    }
    Pair pair;
    pair.members[0] = *slotA;
    pair.members[1] = *slotB;
    pair.prepare();
    entry.insert("missing", false);
    entry.insert("startA", number(slotA->start));
    entry.insert("endA", number(slotA->end));
    entry.insert("startB", number(slotB->start));
    entry.insert("endB", number(slotB->end));
    const double length = pair.axis.valid ? pair.axis.lengthMeters : 0.0;
    entry.insert("axisValid", pair.axis.valid);
    entry.insert("axisLength", number(length));
    entry.insert("traceSizes", QJsonArray{pair.traces[0].size(), pair.traces[1].size()});
    const auto available = pair.availableChannels();
    entry.insert("availableChannels", stringArray(available));
    entry.insert("preferredChannels", stringArray(pair.preferredChannels()));
    entry.insert("geometry", geometryJson(pair.geometry));
    entry.insert("overlay", QJsonArray{trackJson(pair.overlay[0]), trackJson(pair.overlay[1])});

    // Δ time over the whole lap, a zoomed range, a range past the end, a
    // short range and invalid input, as the charts and map ask for them.
    const double span = std::max(1.0, length);
    QJsonArray delta;
    const QVector<std::tuple<double, double, int>> deltaRanges{{0.0, span, 300}, {0.0, span, 1200},
        {span * 0.25, span * 0.6, 400}, {span * 0.9, span * 1.2, 100}, {span * 0.5, span * 0.5 + 3.0, 50},
        {10.0, 5.0, 50}, {0.0, span, 1}};
    for (const auto &[start, end, points] : deltaRanges) {
        auto json = seriesJson(pair.deltaSeriesByProgress(start, end, points));
        json.insert("start", number(start));
        json.insert("end", number(end));
        json.insert("maximumPoints", points);
        delta.append(json);
    }
    entry.insert("delta", delta);

    // Channels: those the charts show first and a few more, both laps.
    QStringList channels;
    const auto &aliases = pair.session(0).aliases;
    for (const auto *alias : {"speed", "throttle", "brake", "longitudinalAcceleration", "lateralAcceleration", "latitude"}) {
        const auto name = aliases.value(QString::fromLatin1(alias));
        if (!name.isEmpty() && !channels.contains(name)) channels.append(name);
    }
    for (const auto &name : available) {
        if (channels.size() >= 9) break;
        if (!channels.contains(name)) channels.append(name);
    }
    if (!channels.contains("gear")) channels.append("gear");
    channels.append("not-a-channel");
    for (const auto &name : pair.session(0).channelNames()) {
        if (!available.contains(name)) { channels.append(name); break; }
    }
    QJsonArray channelSeries;
    for (const auto &name : channels) {
        for (int slot = 0; slot < 2; ++slot) {
            for (const auto &[start, end, points] :
                QVector<std::tuple<double, double, int>>{{0.0, span, 120}, {span * 0.3, span * 0.45, 60}}) {
                auto json = seriesJson(pair.channelSeriesByProgress(slot, name, start, end, points));
                json.insert("channel", name);
                json.insert("slot", slot);
                json.insert("start", number(start));
                json.insert("end", number(end));
                json.insert("maximumPoints", points);
                channelSeries.append(json);
            }
        }
    }
    {
        auto json = seriesJson(pair.channelSeriesByProgress(0, channels.first(), 5.0, 5.0, 50));
        json.insert("channel", channels.first());
        json.insert("slot", 0);
        json.insert("start", 5.0);
        json.insert("end", 5.0);
        json.insert("maximumPoints", 50);
        channelSeries.append(json);
    }
    entry.insert("channelSeries", channelSeries);

    // Markers on the map and times at 41 positions, and one past the end.
    QJsonArray positions;
    for (int index = 0; index <= 41; ++index) {
        const double progress = index <= 40 ? span * index / 40.0 : span * 1.5;
        QJsonArray row{number(progress)};
        for (int slot = 0; slot < 2; ++slot) {
            const auto point = pair.positionAtProgress(slot, progress);
            row.append(point.isEmpty() ? QJsonValue(QJsonValue::Null)
                                       : QJsonValue(QJsonArray{number(point.value("x").toDouble()),
                                             number(point.value("y").toDouble())}));
            row.append(pair.axis.valid ? optionalNumber(timeAtProgress(pair.traces[slot], progress))
                                       : QJsonValue(QJsonValue::Null));
        }
        positions.append(row);
    }
    entry.insert("positions", positions);

    // The overlay map's layers, every one on both laps.
    QJsonArray options, layers;
    QStringList ids;
    for (const auto &value : pair.mapLayerOptions()) {
        const auto option = value.toMap();
        options.append(QJsonObject{{"id", option.value("id").toString()}, {"label", option.value("label").toString()},
            {"available", option.value("available").toBool()}, {"temperature", option.value("temperature").toBool()}});
        ids.append(option.value("id").toString());
    }
    ids.append("nonsense");
    for (const auto &id : ids)
        for (int slot = 0; slot < 3; ++slot) {
            auto json = layerJson(pair.mapLayer(id, slot));
            json.insert("requestedId", id);
            json.insert("requestedSlot", slot);
            layers.append(json);
        }
    entry.insert("mapLayerOptions", options);
    entry.insert("mapLayers", layers);

    // Lap A's page: its charts on a time axis, values at the cursor and the
    // lap's own map.
    const auto &session = pair.session(0);
    QJsonObject lap{{"channels", stringArray(lapChannels(session))}};
    QStringList lapSeriesChannels = lapChannels(session);
    for (const auto *alias : {"throttle", "brake"}) {
        const auto name = session.aliases.value(QString::fromLatin1(alias));
        if (!name.isEmpty() && !lapSeriesChannels.contains(name)) lapSeriesChannels.append(name);
    }
    QJsonArray lapSeries;
    const double start = slotA->start, end = slotA->end;
    for (const auto &name : lapSeriesChannels + QStringList{"not-a-channel"}) {
        for (const auto &[from, to, points] : QVector<std::tuple<double, double, int>>{
                 {start, end, 300}, {start + (end - start) * 0.25, start + (end - start) * 0.75, 300},
                 {end, start, 50}, {start, start, 50}, {std::nan(""), end, 50}}) {
            auto json = seriesJson(sessionSeries(session, name, from, to, points));
            json.insert("channel", name);
            json.insert("start", number(from));
            json.insert("end", number(to));
            json.insert("maximumPoints", points);
            lapSeries.append(json);
        }
    }
    lap.insert("series", lapSeries);
    TelemetrySession mapSession;
    {
        // loadOutingLapDetail's lap map.
        const auto latitude = session.sampledSegments("latitude", start, end, 2000);
        mapSession.metadata.insert("gpsLongitudeConvention", session.metadata.value("gpsLongitudeConvention"));
        mapSession.aliases = {{"latitude", "lat"}, {"longitude", "lon"}};
        mapSession.channels.insert("lat", {});
        mapSession.channels.insert("lon", {});
        auto &lat = mapSession.channels["lat"];
        auto &lon = mapSession.channels["lon"];
        for (const auto &segment : latitude) {
            for (const auto &point : segment) {
                const auto longitude = session.valueAt("longitude", point.x());
                if (!longitude) continue;
                lat.values.append(static_cast<float>(point.y()));
                lon.values.append(static_cast<float>(*longitude));
            }
        }
    }
    const auto lapGeometry = buildTrackGeometry(mapSession);
    lap.insert("geometry", geometryJson(lapGeometry));
    lap.insert("track", trackJson(buildTrackSegments(session, start, end, lapGeometry)));
    QJsonArray cursor;
    for (int index = 0; index <= 20; ++index) {
        const double time = start + (end - start) * index / 20.0;
        QJsonArray row{number(time)};
        for (const auto &name : lapSeriesChannels) row.append(optionalNumber(session.valueAt(name, time)));
        const auto point = currentTrackPoint(session, time, lapGeometry);
        row.append(point ? QJsonValue(QJsonArray{number(point->x()), number(point->y())}) : QJsonValue(QJsonValue::Null));
        cursor.append(row);
    }
    lap.insert("cursorChannels", stringArray(lapSeriesChannels));
    lap.insert("cursor", cursor);
    entry.insert("lap", lap);
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

// Corpus recordings of one track, compared across files.
const QVector<QPair<QString, QString>> crossFilePairs{
    {"corners_measured.vbo", "corners_inferred.vbo"},
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

// MapLayersTests.cpp's hand-made sessions.
constexpr double dt = 0.1;
constexpr int sampleCount = 101;
constexpr double metersPerSecond = 20.0;

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

TelemetrySession straightRun(const std::function<double(double)> &temperature,
    const std::function<bool(double)> &gpsPresent = [](double) { return true; }, const bool westPositive = false)
{
    TelemetrySession session;
    const auto add = [&session](const QString &alias, const TelemetryChannel &channel) {
        session.channels.insert(channel.name, channel);
        session.aliases.insert(alias, channel.name);
    };
    add("latitude", makeChannel("lat", "deg", [](double) { return 50.0; }, gpsPresent));
    add("longitude", makeChannel("lon", "deg", [westPositive](double t) {
        return 19.0 + (westPositive ? -1.0 : 1.0) * t * metersPerSecond / 71500.0; }, gpsPresent));
    add("speed", makeChannel("velocity", "km/h", [](double t) { return 60.0 + t; },
        [](double t) { return t < 4.0 || t > 6.0; }));
    session.channels.insert("oil_temp", makeChannel("oil_temp", "C", temperature));
    if (westPositive) session.metadata.insert("gpsLongitudeConvention", "west-positive");
    return session;
}

QVector<ProgressSegment> straightTrace(const std::function<bool(double)> &present)
{
    QVector<ProgressSegment> trace(1);
    for (int k = 0; k < sampleCount; ++k) {
        const double t = k * dt;
        if (!present(t)) {
            if (!trace.last().samples.isEmpty()) trace.append(ProgressSegment{});
            continue;
        }
        trace.last().samples.append(ProjectedSample{t, t * metersPerSecond, true});
    }
    if (trace.last().samples.isEmpty()) trace.removeLast();
    return trace;
}

QJsonArray valuesJson(const ProgressValueSegments &segments)
{
    QJsonArray result;
    for (const auto &segment : segments) {
        QJsonArray points;
        for (const auto &point : segment) points.append(QJsonArray{number(point.x()), number(point.y())});
        result.append(points);
    }
    return result;
}

QJsonObject traceJson(const MapLayerTrace &layer)
{
    QJsonArray polylines;
    for (const auto &polyline : layer.polylines) {
        QJsonArray points;
        for (const auto &point : polyline) points.append(QJsonArray{number(point.x), number(point.y), number(point.value)});
        polylines.append(points);
    }
    return {{"polylines", polylines}, {"minimum", optionalNumber(layer.minimum)}, {"maximum", optionalNumber(layer.maximum)}};
}

QJsonObject casesJson()
{
    const auto temperature = [](const double t) {
        if (std::abs(t - 3.0) < 1e-6) return 0.0;
        if (std::abs(t - 7.0) < 1e-6) return 900.0;
        return 90.0;
    };
    const auto everywhere = [](double) { return true; };
    const auto gpsGap = [](const double t) { return t < 3.0 || t > 5.0; };
    QJsonArray runs;
    for (const auto &[name, gps, west] : QVector<std::tuple<QString, bool, bool>>{
             {"straight", false, false}, {"gpsGap", true, false}, {"westPositive", false, true}}) {
        const std::function<bool(double)> present = gps ? std::function<bool(double)>(gpsGap) : everywhere;
        const auto session = straightRun(temperature, present, west);
        const auto trace = straightTrace(present);
        const auto geometry = buildTrackGeometry(session);
        QJsonObject run{{"name", name}, {"gpsGap", gps}, {"westPositive", west}, {"geometry", geometryJson(geometry)}};
        QJsonArray along;
        for (const auto &[channel, length, points, temperaturePolicy] : QVector<std::tuple<QString, double, int, bool>>{
                 {"speed", 200.0, 41, false}, {"oil_temp", 200.0, 201, false}, {"oil_temp", 200.0, 201, true},
                 {"brake", 200.0, 21, false}, {"speed", std::nan(""), 21, false}, {"speed", 0.0, 21, false},
                 {"speed", 200.0, 1, false}, {"speed", 150.0, 5000, false}}) {
            const auto values = channelAlongProgress(session, channel, trace, length, points,
                temperaturePolicy ? temperatureSummaryPolicy() : ChannelSummaryPolicy{});
            along.append(QJsonObject{{"channel", channel}, {"length", number(length)}, {"points", points},
                {"temperature", temperaturePolicy}, {"values", valuesJson(values)},
                {"layer", traceJson(placeOnMap(session, trace, geometry, values))}});
        }
        run.insert("along", along);
        const ProgressValueSegments handMade{{{0.0, 1.0}, {50.0, 2.0}, {100.0, std::nan("")}, {150.0, 3.0},
            {190.0, 4.0}, {400.0, 5.0}}, {{10.0, 7.0}}, {{20.0, -1.0}, {30.0, -2.0}}};
        run.insert("handMade", traceJson(placeOnMap(session, trace, geometry, handMade)));
        QJsonArray plausible;
        const auto &oil = session.channels["oil_temp"];
        for (const double time : {-1.0, 0.0, 2.95, 3.0, 5.05, 6.97, 7.0, 9.99, 10.0, 10.5}) {
            for (const bool policy : {false, true}) {
                const auto chosen = policy ? temperatureSummaryPolicy() : ChannelSummaryPolicy{};
                plausible.append(QJsonArray{time, policy,
                    optionalNumber(plausibleChannelValue(oil, time, chosen, zeroIsPlaceholder(oil, chosen)))});
            }
        }
        const auto &speed = session.channels["velocity"];
        for (const double time : {3.95, 4.0, 5.0, 6.05, 6.1})
            plausible.append(QJsonArray{time, "speed", optionalNumber(plausibleChannelValue(speed, time, {}, false))});
        run.insert("plausible", plausible);
        QJsonArray points;
        for (const double time : {0.0, 2.5, 4.0, 10.0, 11.0}) {
            const auto point = currentTrackPoint(session, time, geometry);
            points.append(QJsonArray{time, point ? QJsonValue(QJsonArray{number(point->x()), number(point->y())})
                                                 : QJsonValue(QJsonValue::Null)});
        }
        run.insert("trackPoints", points);
        run.insert("track", trackJson(buildTrackSegments(session, 0.0, 10.0, geometry)));
        run.insert("shared", geometryJson(buildSharedTrackGeometry(session, 0.0, 5.0, session, 5.0, 10.0)));
        runs.append(run);
    }
    return {{"runs", runs}};
}

void write(const QString &path, const QJsonObject &document)
{
    QFile output(path);
    if (!output.open(QIODevice::WriteOnly)) std::exit(1);
    output.write(QJsonDocument(document).toJson(QJsonDocument::Compact));
}

QJsonObject strides()
{
    return {{"series", seriesStride}, {"map", mapStride}};
}

int runDay(const QString &dayPath, const QString &outputPath)
{
    QFile file(dayPath);
    if (!file.open(QIODevice::ReadOnly)) return 1;
    const auto day = QJsonDocument::fromJson(file.readAll()).object();
    seriesStride = 1;
    mapStride = 1;
    QHash<QString, Recording> recordings;
    for (const auto &value : day.value("runs").toArray()) {
        const auto run = value.toObject();
        auto recording = load(run.value("file").toString());
        if (!recording) return 1;
        recordings.insert(run.value("runId").toString(), *recording);
    }
    QJsonArray pairs;
    for (const auto &value : day.value("pairs").toArray()) {
        const auto pair = value.toObject();
        const auto a = pair.value("a").toObject(), b = pair.value("b").toObject();
        pairs.append(pairJson(recordings[a.value("runId").toString()], a.value("lapNumber").toInt(),
            recordings[b.value("runId").toString()], b.value("lapNumber").toInt()));
    }
    write(outputPath, {{"strides", strides()}, {"pairs", pairs}, {"cases", casesJson()}});
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
    QJsonArray pairs;
    for (const auto &recording : recordings)
        for (const auto &[a, b] : pairsOf(recording)) pairs.append(pairJson(recording, a, recording, b));
    for (const auto &[nameA, nameB] : crossFilePairs) {
        const auto a = std::find_if(recordings.cbegin(), recordings.cend(), [&](const Recording &r) { return r.file == nameA; });
        const auto b = std::find_if(recordings.cbegin(), recordings.cend(), [&](const Recording &r) { return r.file == nameB; });
        if (a == recordings.cend() || b == recordings.cend()) continue;
        pairs.append(pairJson(*a, firstEligible(*a), *b, firstEligible(*b)));
    }
    write(QString::fromLocal8Bit(argv[1]), {{"strides", strides()}, {"pairs", pairs}, {"cases", casesJson()}});
    return 0;
}
