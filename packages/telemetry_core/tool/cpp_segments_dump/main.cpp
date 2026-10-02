// Prints FlappedEar Overlays' track-segment results as one JSON document:
//   cpp_segments_dump <output.json> <input>...
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession; files without lap traces or a start gate are
// skipped. For every timed lap it runs the steps of
// AnalysisController::computeSegmentReview (axis from the lap's own trace
// around the start gate's midpoint, features at segmentReviewSmoothingMeters,
// the lap projected, coverageGaps, proposeTrackSegments) and the automatic
// approval loop of KAN-136. Segment ids are random, so they are left out.
// Fixed cases for validTrackSegments, progressRangesOverlap,
// withApprovedSegment and approvedSegmentation are written with their inputs.
// NaN is written as null.

#include "OverlaysExtracted.h"
#include "telemetry/LapTiming.h"
#include "telemetry/TrackProgress.h"
#include "telemetry/TrackSegmentProposals.h"
#include "telemetry/TrackSegmentReview.h"
#include "telemetry/TrackSegments.h"
#include "telemetry/VboParser.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <cmath>
#include <cstdio>
#include <exception>
#include <optional>

using namespace FlappedEar;

namespace {

constexpr int featureStride = 50;
const QString configuration = QStringLiteral("compatibility-v1:") + QString("0123456789abcdef").repeated(4);
const QString otherConfiguration = QStringLiteral("compatibility-v1:") + QString("fedcba9876543210").repeated(4);

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

QJsonArray rangesJson(const QVector<ProgressRange> &ranges)
{
    QJsonArray result;
    for (const auto &range : ranges) result.append(QJsonArray{number(range.startMeters), number(range.endMeters)});
    return result;
}

QJsonArray boundaryJson(const SegmentProposalBoundary &boundary)
{
    return {number(boundary.progressMeters), number(boundary.toleranceMeters),
            QJsonArray::fromStringList(boundary.uncertaintyReasons)};
}

QJsonObject proposalsJson(const TrackSegmentProposals &proposals)
{
    QJsonArray items;
    for (const auto &proposal : proposals.proposals) {
        items.append(QJsonObject{{"type", trackSegmentTypeName(proposal.type)},
                                 {"name", proposal.name},
                                 {"start", boundaryJson(proposal.start)},
                                 {"end", boundaryJson(proposal.end)},
                                 {"lengthMeters", number(proposal.lengthMeters)},
                                 {"turnRadians", number(proposal.turnRadians)},
                                 {"peakCurvaturePerMeter", number(proposal.peakCurvaturePerMeter)},
                                 {"chainedCorners", proposal.chainedCorners}});
    }
    return {{"valid", proposals.valid}, {"unresolvedReason", proposals.unresolvedReason}, {"proposals", items}};
}

// A stored segment array without its random ids, and how many distinct ids it had.
QJsonObject segmentsJson(const QJsonValue &stored)
{
    QJsonArray segments;
    QSet<QString> ids;
    for (const auto &value : stored.toArray()) {
        auto segment = value.toObject();
        ids.insert(segment.value("id").toString());
        segment.remove("id");
        segments.append(segment);
    }
    return {{"valid", validTrackSegments(stored)}, {"distinctIds", ids.size()}, {"segments", segments}};
}

QJsonObject featuresJson(const TrackFeatures &features)
{
    QJsonArray samples;
    for (qsizetype i = 0; i < features.samples.size(); i += featureStride) {
        const auto &sample = features.samples[i];
        samples.append(QJsonArray{i, number(sample.progressMeters), number(sample.curvaturePerMeter)});
    }
    return {{"valid", features.valid}, {"sampleCount", features.samples.size()}, {"samples", samples}};
}

GeoCoordinate gateMidpoint(const TimingGate &gate)
{
    return {(gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
            (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0};
}

// The steps of AnalysisController::computeSegmentReview for one timed lap,
// then the automatic approval of its proposals.
QJsonObject reviewJson(const TelemetrySession &session, const LapSession &laps, const TimedLap &lap)
{
    QJsonObject entry{{"lapNumber", lap.number},
                      {"start", number(lap.startTelemetryTime)},
                      {"end", number(lap.endTelemetryTime)}};
    const auto trace = std::find_if(laps.lapTraces.cbegin(), laps.lapTraces.cend(),
        [&lap](const LapTrace &candidate) { return candidate.lapNumber == lap.number; });
    if (!laps.selectedStartGate || trace == laps.lapTraces.cend()) {
        entry.insert("unavailable", "noTrace");
        return entry;
    }
    const auto &gate = *laps.selectedStartGate;
    const ProgressAxis axis = buildProgressAxis(*trace, gateMidpoint(gate), gate);
    const auto features = axis.valid ? computeTrackFeatures(axis, segmentReviewSmoothingMeters) : TrackFeatures{};
    entry.insert("axis", QJsonObject{{"valid", axis.valid},
                                     {"pointCount", axis.points.size()},
                                     {"lengthMeters", number(axis.lengthMeters)},
                                     {"spacingMeters", number(axis.spacingMeters)}});
    if (!features.valid) {
        entry.insert("unavailable", "noAxis");
        return entry;
    }
    entry.insert("features", featuresJson(features));
    const auto lapTrace = projectLapTrace(axis, session, lap.startTelemetryTime, lap.endTelemetryTime);
    QJsonArray traceSizes;
    for (const auto &segment : lapTrace) traceSizes.append(segment.samples.size());
    entry.insert("traceSizes", traceSizes);
    const auto gaps = extracted::coverageGaps(lapTrace, axis.lengthMeters);
    entry.insert("gaps", rangesJson(gaps));
    const auto proposals = proposeTrackSegments(axis, features, gaps);
    entry.insert("proposals", proposalsJson(proposals));

    if (proposals.valid && proposals.unresolvedReason.isEmpty() && !proposals.proposals.isEmpty()) {
        extracted::AutomaticSegmentsResult result{{axis, proposals}, configuration};
        QJsonValue stored;
        const int approved = extracted::approveAutomaticSegments(result, stored);
        QJsonValue again = stored;
        const int approvedAgain = extracted::approveAutomaticSegments(result, again);
        entry.insert("automatic", QJsonObject{{"approved", approved},
                                              {"stored", segmentsJson(stored)},
                                              {"approvedAgain", approvedAgain}});
        entry.insert("proposalsToTrackSegments", segmentsJson(proposalsToTrackSegments(proposals, configuration)));
    }
    return entry;
}

QJsonArray optionsJson(const SegmentProposalOptions &options)
{
    return {number(options.cornerCurvaturePerMeter), number(options.minimumCornerTurnRadians),
            number(options.connectedStraightMeters), number(options.certainStraightMeters)};
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

    QJsonObject entry{{"file", QFileInfo(path).fileName()}};
    QJsonArray reviews;
    for (const auto &lap : laps.timedLaps) reviews.append(reviewJson(session, laps, lap));
    entry.insert("laps", reviews);

    // Every timed lap's coverage gaps on the first reference-eligible lap's
    // axis, as boundary uncertainty for that axis's proposals.
    const LapTrace *reference = nullptr;
    for (const auto &trace : laps.lapTraces) {
        for (const auto &lap : laps.timedLaps)
            if (lap.number == trace.lapNumber && lap.referenceEligible()) { reference = &trace; break; }
        if (reference) break;
    }
    if (!reference) return entry;
    const auto &gate = *laps.selectedStartGate;
    const ProgressAxis axis = buildProgressAxis(*reference, gateMidpoint(gate), gate);
    const auto features = axis.valid ? computeTrackFeatures(axis, segmentReviewSmoothingMeters) : TrackFeatures{};
    if (!features.valid) return entry;
    entry.insert("referenceLap", reference->lapNumber);
    QJsonArray cross;
    for (const auto &lap : laps.timedLaps) {
        const auto gaps = extracted::coverageGaps(
            projectLapTrace(axis, session, lap.startTelemetryTime, lap.endTelemetryTime), axis.lengthMeters);
        cross.append(QJsonObject{{"lapNumber", lap.number}, {"gaps", rangesJson(gaps)},
                                 {"proposals", proposalsJson(proposeTrackSegments(axis, features, gaps))}});
    }
    entry.insert("crossLaps", cross);

    const double length = axis.lengthMeters;
    const QVector<std::pair<SegmentProposalOptions, QVector<ProgressRange>>> variants{
        {{1.0 / 150.0, 0.2, 10.0, 60.0}, {}},
        {{1.0 / 1000.0, 0.05, 5.0, 5.0}, {}},
        {{1e-4, 1e-3, 0.5, 0.5}, {}},
        {{1.0 / 250.0, 0.35, 40.0, 20.0}, {}},
        {{1.0 / 250.0, 0.0, 20.0, 40.0}, {}},
        {{}, {{0.0, 50.0}, {length - 10.0, 5.0}, {length / 2.0, length / 2.0 + 1.0}}},
        {{}, {{-1.0, 5.0}}},
        {{}, {{0.0, length + 1.0}}},
    };
    QJsonArray variantArray;
    for (const auto &[options, gaps] : variants) {
        variantArray.append(QJsonObject{{"options", optionsJson(options)}, {"gaps", rangesJson(gaps)},
                                        {"proposals", proposalsJson(proposeTrackSegments(axis, features, gaps, options))}});
    }
    entry.insert("variants", variantArray);
    return entry;
}

QJsonObject segment(const QString &id, const QString &type, const QString &name, const double start,
    const double end, const QString &reference = configuration)
{
    return {{"id", id}, {"type", type}, {"name", name}, {"startProgressMeters", start},
            {"endProgressMeters", end}, {"trackConfigurationReference", reference}};
}

QJsonArray validityCases()
{
    const auto a = segment("a", "corner", "Corner 1", 10.0, 50.0);
    const auto b = segment("b", "straight", "Straight 1", 50.0, 200.0);
    const auto wrap = segment("w", "sector", "Last", 900.0, 20.0);
    const auto with = [](QJsonObject object, const QString &key, const QJsonValue &value) {
        object.insert(key, value);
        return object;
    };
    QJsonArray many;
    for (int i = 0; i < maximumTrackSegments + 1; ++i)
        many.append(segment(QString("s%1").arg(i), "sector", "S", i * 10.0, i * 10.0 + 5.0));
    QJsonArray sixtyFour = many;
    sixtyFour.removeLast();
    QJsonObject extra = a;
    extra.insert("extra", 1);
    QJsonObject missing = a;
    missing.remove("name");
    const QVector<QJsonValue> values{
        QJsonValue(QJsonValue::Null),
        QJsonArray{},
        QJsonArray{a, b},
        QJsonArray{a, b, wrap},
        QJsonArray{wrap, a},
        QJsonArray{b, a},
        QJsonArray{a, with(a, "startProgressMeters", 60.0)},
        QJsonArray{a, with(b, "startProgressMeters", 10.0)},
        sixtyFour,
        many,
        QJsonArray{extra},
        QJsonArray{missing},
        QJsonArray{with(a, "id", "  ")},
        QJsonArray{with(a, "id", QString("x") + QChar(0) + "y")},
        QJsonArray{with(a, "id", QString(128, 'i'))},
        QJsonArray{with(a, "id", QString(129, 'i'))},
        QJsonArray{with(a, "name", QString(160, 'n'))},
        QJsonArray{with(a, "name", QString(161, 'n'))},
        QJsonArray{with(a, "name", QString(QChar(0x00a0)) + QChar(0x2003))},
        QJsonArray{with(a, "name", QString(QChar(0x200b)))},
        QJsonArray{with(a, "type", "Corner")},
        QJsonArray{with(a, "type", 1)},
        QJsonArray{with(a, "endProgressMeters", 10.0)},
        QJsonArray{with(a, "startProgressMeters", -0.5)},
        QJsonArray{with(a, "startProgressMeters", 0.0)},
        QJsonArray{with(a, "endProgressMeters", 1'000'000.0)},
        QJsonArray{with(a, "endProgressMeters", 1'000'000.5)},
        QJsonArray{with(a, "startProgressMeters", "10")},
        QJsonArray{with(a, "trackConfigurationReference", configuration.toUpper().replace("COMPATIBILITY", "compatibility"))},
        QJsonArray{with(a, "trackConfigurationReference", configuration + "\n")},
        QJsonArray{with(a, "trackConfigurationReference", configuration + "0")},
        QJsonArray{with(a, "trackConfigurationReference", "gates-v1:" + configuration.section(':', 1))},
        QJsonArray{with(a, "trackConfigurationReference", QJsonValue(QJsonValue::Null))},
        QJsonArray{1},
        QJsonArray{QJsonArray{a}},
        a,
        QJsonValue(3.0),
        QJsonValue("segments"),
    };
    QJsonArray cases;
    for (const auto &value : values)
        cases.append(QJsonObject{{"value", value}, {"valid", validTrackSegments(value)}});
    return cases;
}

QJsonArray overlapCases()
{
    const double length = 1000.0;
    const QVector<std::pair<ProgressRange, ProgressRange>> pairs{
        {{10, 50}, {50, 90}},      {{10, 50}, {49, 90}},       {{10, 50}, {50.0000005, 90}},
        {{10, 50}, {49.9999995, 90}}, {{10, 50}, {20, 30}},    {{900, 20}, {10, 30}},
        {{900, 20}, {20, 30}},     {{900, 20}, {950, 990}},    {{900, 20}, {980, 10}},
        {{900, 20}, {100, 200}},   {{1200, 20}, {1100, 1150}}, {{1200, 20}, {0, 5}},
        {{0, 1000}, {999, 5}},     {{30, 30}, {0, 100}},       {{50, 10}, {20, 40}},
    };
    QJsonArray cases;
    for (const auto &[a, b] : pairs) {
        cases.append(QJsonObject{{"a", QJsonArray{a.startMeters, a.endMeters}},
                                 {"b", QJsonArray{b.startMeters, b.endMeters}},
                                 {"lengthMeters", length},
                                 {"overlap", progressRangesOverlap(a, b, length)}});
    }
    return cases;
}

QJsonArray approvalCases()
{
    const double length = 1000.0;
    const auto a = segment("a", "corner", "Corner 1", 100.0, 200.0);
    const auto b = segment("b", "straight", "Straight 1", 300.0, 400.0);
    const auto wrap = segment("w", "sector", "Last", 900.0, 20.0);
    QJsonArray many;
    for (int i = 0; i < maximumTrackSegments; ++i)
        many.append(segment(QString("s%1").arg(i), "sector", "S", i * 10.0, i * 10.0 + 5.0));
    const QVector<std::tuple<QJsonValue, QJsonObject, double>> inputs{
        {QJsonValue(), a, length},
        {QJsonValue(QJsonValue::Null), a, length},
        {QJsonArray{}, wrap, length},
        {QJsonArray{b}, a, length},
        {QJsonArray{a}, b, length},
        {QJsonArray{a, b}, segment("c", "corner", "Between", 200.0, 300.0), length},
        {QJsonArray{a, b}, segment("c", "corner", "Overlap", 150.0, 250.0), length},
        {QJsonArray{a, b}, segment("a", "corner", "Same id", 500.0, 600.0), length},
        {QJsonArray{a}, segment("c", "corner", "Other", 500.0, 600.0, otherConfiguration), length},
        {QJsonArray{a, b}, wrap, length},
        {QJsonArray{a, wrap}, segment("c", "corner", "After wrap", 950.0, 990.0), length},
        {QJsonArray{a, wrap}, segment("c", "corner", "Under wrap", 10.0, 50.0), length},
        {QJsonArray{a, wrap}, segment("c", "corner", "Start", 30.0, 50.0), length},
        {QJsonArray{wrap}, segment("v", "corner", "Second wrap", 950.0, 30.0), length},
        {QJsonArray{a}, segment("c", "corner", "Same start", 100.0, 99.0), length},
        {QJsonArray{a}, segment("c", "corner", "Touching", 200.0, 210.0), length},
        {many, segment("c", "corner", "Full", 900.0, 910.0), length},
        {QJsonArray{a, a}, b, length},
        {QJsonArray{a}, segment("c", "corner", "", 500.0, 600.0), length},
        {QJsonArray{a}, segment("c", "corner", "Beyond", 1500.0, 1600.0), length},
    };
    QJsonArray cases;
    for (const auto &[stored, segmentValue, lengthMeters] : inputs) {
        QString error;
        const auto result = withApprovedSegment(stored, segmentValue, lengthMeters, &error);
        QJsonObject item{{"segment", segmentValue}, {"lengthMeters", lengthMeters},
                         {"result", result ? QJsonValue(*result) : QJsonValue(QJsonValue::Null)},
                         {"error", error}};
        if (!stored.isUndefined()) item.insert("stored", stored);
        cases.append(item);
    }
    return cases;
}

QJsonArray approvedSegmentationCases()
{
    const auto a = segment("a", "corner", "Corner 1", 100.0, 200.0);
    const auto b = segment("b", "straight", "Straight 1", 300.0, 400.5);
    const auto other = segment("o", "corner", "Other", 250.0, 260.0, otherConfiguration);
    const QVector<QJsonValue> values{
        QJsonValue(QJsonValue::Null), QJsonArray{}, QJsonArray{a, b}, QJsonArray{a, other, b},
        QJsonArray{other}, QJsonArray{b, a}, QJsonValue("x"),
    };
    QJsonArray cases;
    for (const auto &value : values) {
        for (const auto &reference : {configuration, otherConfiguration}) {
            const auto approved = approvedSegmentation(value, reference);
            cases.append(QJsonObject{{"stored", value}, {"reference", reference}, {"valid", approved.valid},
                                     {"segments", approved.segments}, {"revision", approved.revision},
                                     {"otherConfigurationSegments", approved.otherConfigurationSegments}});
        }
    }
    return cases;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s <output.json> <input>...\n", argv[0]);
        return 2;
    }
    QJsonArray results;
    for (int index = 2; index < argc; ++index) {
        if (const auto entry = runFile(QString::fromLocal8Bit(argv[index]))) results.append(*entry);
    }
    const QJsonObject cases{{"configuration", configuration},
                            {"validTrackSegments", validityCases()},
                            {"progressRangesOverlap", overlapCases()},
                            {"withApprovedSegment", approvalCases()},
                            {"approvedSegmentation", approvedSegmentationCases()}};
    QFile output(QString::fromLocal8Bit(argv[1]));
    if (!output.open(QIODevice::WriteOnly)) return 1;
    output.write(QJsonDocument(QJsonObject{{"files", results}, {"cases", cases}}).toJson(QJsonDocument::Compact));
    return 0;
}
