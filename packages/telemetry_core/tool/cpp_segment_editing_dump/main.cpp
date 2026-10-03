// Prints FlappedEar Overlays' segment editing and review results as one JSON
// document:
//   cpp_segment_editing_dump <output.json> <input>...
// Each input is parsed with VboParser::parseFile and laps are derived with
// deriveSourceLapSession; files without lap traces or a start gate are
// skipped. On the first reference-eligible lap it runs the steps of
// AnalysisController::computeSegmentReview and the automatic approval loop of
// KAN-136, renames the approved ids to s0, s1, ... and then edits that set:
// every segment renamed and retyped, its boundaries moved with and without
// its neighbours, split in the middle, merged with the next one and removed,
// and one chain of edits applied in turn. It writes the review states of the
// proposals against the automatic and the edited set, and the rejections a
// run would store. Ids minted by a split are random; each id that is not in
// the input is renamed n0, n1, ... in order of appearance. Fixed cases cover
// the editing functions, SegmentEditHistory, pickProgressAt and the rest of
// TrackSegmentReview with their inputs. A non-finite number is written as
// null and read back as NaN.

#include "OverlaysExtracted.h"
#include "telemetry/LapTiming.h"
#include "telemetry/TrackProgress.h"
#include "telemetry/TrackSegmentEditing.h"
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
#include <limits>
#include <optional>

using namespace FlappedEar;

namespace {

const QString configuration = QStringLiteral("compatibility-v1:") + QString("0123456789abcdef").repeated(4);
const QString otherConfiguration = QStringLiteral("compatibility-v1:") + QString("fedcba9876543210").repeated(4);
constexpr double nan = std::numeric_limits<double>::quiet_NaN();
const QStringList types{"sector", "corner", "straight"};

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

// Renames every id that is not in `known` to n<counter>, in order, and adds
// the new names to `known`.
QJsonValue normalized(const std::optional<QJsonArray> &result, QSet<QString> &known, int &counter)
{
    if (!result) return QJsonValue(QJsonValue::Null);
    QJsonArray out;
    for (const auto &value : *result) {
        auto segment = value.toObject();
        const auto id = segment.value("id").toString();
        if (!known.contains(id)) {
            const auto renamed = QString("n%1").arg(counter++);
            segment.insert("id", renamed);
            known.insert(renamed);
        }
        out.append(segment);
    }
    return out;
}

QSet<QString> idsOf(const QJsonValue &stored)
{
    QSet<QString> ids;
    for (const auto &value : stored.toArray()) ids.insert(value.toObject().value("id").toString());
    return ids;
}

double startOf(const QJsonObject &segment) { return segment.value("startProgressMeters").toDouble(); }
double endOf(const QJsonObject &segment) { return segment.value("endProgressMeters").toDouble(); }

double forward(const double from, const double to, const double length)
{
    return to >= from ? to - from : to + length - from;
}

// One editing operation, its inputs and its normalized result.
QJsonObject edit(const QJsonValue &stored, const QJsonObject &args, const double length, int *counter = nullptr,
    QSet<QString> *known = nullptr)
{
    const auto op = args.value("op").toString();
    const auto read = [&args](const char *key) {
        const auto value = args.value(key);
        return value.isNull() ? nan : value.toDouble();
    };
    QString error;
    std::optional<QJsonArray> result;
    if (op == "edit") {
        result = withEditedSegment(stored, args.value("id").toString(), args.value("name").toString(),
            args.value("type").toString(), read("start"), read("end"), args.value("joined").toBool(), length, &error);
    } else if (op == "split") {
        result = withSplitSegment(stored, args.value("id").toString(), read("at"), args.value("name").toString(),
            length, &error);
    } else if (op == "merge") {
        result = withMergedSegments(stored, args.value("id").toString(), args.value("other").toString(), length, &error);
    } else if (op == "remove") {
        result = withoutApprovedSegment(stored, args.value("id").toString());
    }
    QSet<QString> localKnown = idsOf(stored);
    int localCounter = 0;
    auto &ids = known ? *known : localKnown;
    if (known) ids.unite(idsOf(stored));
    QJsonObject item = args;
    item.insert("result", normalized(result, ids, counter ? *counter : localCounter));
    item.insert("error", error);
    return item;
}

QJsonObject boundsJson(const TrackSegmentProposal &proposal)
{
    return {{"type", trackSegmentTypeName(proposal.type)}, {"name", proposal.name},
            {"start", number(proposal.start.progressMeters)}, {"end", number(proposal.end.progressMeters)}};
}

QJsonArray itemsJson(const QVector<SegmentReviewItem> &items)
{
    QJsonArray result;
    for (const auto &item : items)
        result.append(QJsonObject{{"state", segmentReviewStateName(item.state)},
                                  {"approvedSegmentId", item.approvedSegmentId}, {"edited", item.edited}});
    return result;
}

GeoCoordinate gateMidpoint(const TimingGate &gate)
{
    return {(gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
            (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0};
}

QJsonObject editsJson(const QJsonArray &automatic, const QVector<TrackSegmentProposal> &proposals, const double length)
{
    QJsonArray single;
    const auto count = automatic.size();
    for (qsizetype i = 0; i < count; ++i) {
        const auto segment = automatic[i].toObject();
        const auto id = segment.value("id").toString();
        const auto name = segment.value("name").toString();
        const auto start = startOf(segment), end = endOf(segment);
        const auto nextType = types[(types.indexOf(segment.value("type").toString()) + 1) % types.size()];
        const auto next = automatic[(i + 1) % count].toObject().value("id").toString();
        const QVector<QJsonObject> args{
            {{"op", "edit"}, {"id", id}, {"name", QString("  Renamed %1  ").arg(i)}, {"type", nextType},
             {"start", start}, {"end", end}, {"joined", false}},
            {{"op", "edit"}, {"id", id}, {"name", name}, {"type", segment.value("type")}, {"start", start - 7.5},
             {"end", end}, {"joined", true}},
            {{"op", "edit"}, {"id", id}, {"name", name}, {"type", segment.value("type")}, {"start", start},
             {"end", end + 7.5}, {"joined", true}},
            {{"op", "edit"}, {"id", id}, {"name", name}, {"type", segment.value("type")}, {"start", start},
             {"end", end + 7.5}, {"joined", false}},
            {{"op", "edit"}, {"id", id}, {"name", name}, {"type", segment.value("type")}, {"start", start + 3.0},
             {"end", end - 3.0}, {"joined", false}},
            {{"op", "split"}, {"id", id}, {"at", std::fmod(start + forward(start, end, length) / 2.0, length)},
             {"name", name.left(150) + " (2)"}},
            {{"op", "merge"}, {"id", id}, {"other", next}},
            {{"op", "remove"}, {"id", id}},
        };
        for (const auto &arg : args) single.append(edit(automatic, arg, length));
    }

    // One chain of edits, each on the result of the last that succeeded.
    QJsonValue state = automatic;
    QSet<QString> known = idsOf(automatic);
    int counter = 0;
    QJsonArray chain;
    const auto idAt = [&state](const qsizetype index) {
        const auto list = state.toArray();
        return list.isEmpty() ? QString() : list[((index % list.size()) + list.size()) % list.size()].toObject().value("id").toString();
    };
    const auto segmentAt = [&state](const qsizetype index) {
        const auto list = state.toArray();
        return list.isEmpty() ? QJsonObject() : list[((index % list.size()) + list.size()) % list.size()].toObject();
    };
    const auto step = [&](const QJsonObject &args) {
        const auto item = edit(state, args, length, &counter, &known);
        chain.append(item);
        if (!item.value("result").isNull()) state = item.value("result");
    };
    {
        const auto s = segmentAt(0);
        step({{"op", "split"}, {"id", idAt(0)},
              {"at", std::fmod(startOf(s) + forward(startOf(s), endOf(s), length) / 3.0, length)},
              {"name", s.value("name").toString() + " (2)"}});
    }
    step({{"op", "merge"}, {"id", idAt(2)}, {"other", idAt(1)}});
    {
        const auto s = segmentAt(3);
        step({{"op", "edit"}, {"id", idAt(3)}, {"name", s.value("name")}, {"type", s.value("type")},
              {"start", startOf(s)}, {"end", endOf(s) + 12.0}, {"joined", true}});
    }
    {
        const auto s = segmentAt(-1);
        step({{"op", "edit"}, {"id", idAt(-1)}, {"name", "Last"}, {"type", "sector"}, {"start", startOf(s)},
              {"end", endOf(s)}, {"joined", true}});
    }
    step({{"op", "remove"}, {"id", idAt(4)}});
    step({{"op", "merge"}, {"id", idAt(-1)}, {"other", idAt(0)}});
    {
        const auto s = segmentAt(1);
        step({{"op", "edit"}, {"id", idAt(1)}, {"name", s.value("name")}, {"type", s.value("type")},
              {"start", std::max(0.0, startOf(s) - 20.0)}, {"end", endOf(s)}, {"joined", true}});
    }

    const QSet<int> rejected{int(proposals.size()) - 1};
    QVector<TrackSegmentProposal> rejectedProposals{proposals.first(), proposals.last()};
    const auto review = makeTrackSegmentReview(configuration, rejectedProposals);
    return {{"single", single},
            {"chain", chain},
            {"reviewAutomatic", itemsJson(reviewSegmentProposals(proposals, {}, rejected,
                approvedSegmentation(automatic, configuration), length))},
            {"reviewEdited", itemsJson(reviewSegmentProposals(proposals, {0}, rejected,
                approvedSegmentation(state, configuration), length))},
            {"decisions", review},
            {"rejectedIndexes", [&] {
                 QList<int> indexes = rejectedProposalIndexes(review, configuration, proposals).values();
                 std::sort(indexes.begin(), indexes.end());
                 QJsonArray out;
                 for (const int index : indexes) out.append(index);
                 return out;
             }()},
            {"rejectedOther", rejectedProposalIndexes(review, otherConfiguration, proposals).size()}};
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
    const TimedLap *lap = nullptr;
    const LapTrace *trace = nullptr;
    for (const auto &candidate : laps.lapTraces) {
        for (const auto &timed : laps.timedLaps)
            if (timed.number == candidate.lapNumber && timed.referenceEligible()) { lap = &timed; trace = &candidate; break; }
        if (lap) break;
    }
    if (!lap) return std::nullopt;
    QJsonObject entry{{"file", QFileInfo(path).fileName()}, {"lapNumber", lap->number}};
    const auto &gate = *laps.selectedStartGate;
    const ProgressAxis axis = buildProgressAxis(*trace, gateMidpoint(gate), gate);
    const auto features = axis.valid ? computeTrackFeatures(axis, segmentReviewSmoothingMeters) : TrackFeatures{};
    if (!features.valid) return std::nullopt;
    const auto lapTrace = projectLapTrace(axis, session, lap->startTelemetryTime, lap->endTelemetryTime);
    const auto gaps = extracted::coverageGaps(lapTrace, axis.lengthMeters);
    const auto proposals = proposeTrackSegments(axis, features, gaps);
    if (!proposals.valid || !proposals.unresolvedReason.isEmpty() || proposals.proposals.isEmpty()) return std::nullopt;
    extracted::AutomaticSegmentsResult result{{axis, proposals}, configuration};
    QJsonValue stored;
    extracted::approveAutomaticSegments(result, stored);
    QJsonArray automatic;
    for (const auto &value : stored.toArray()) {
        auto segment = value.toObject();
        segment.insert("id", QString("s%1").arg(automatic.size()));
        automatic.append(segment);
    }
    QJsonArray bounds;
    for (const auto &proposal : proposals.proposals) bounds.append(boundsJson(proposal));
    entry.insert("lengthMeters", number(axis.lengthMeters));
    entry.insert("proposals", bounds);
    entry.insert("automatic", automatic);
    entry.insert("edits", editsJson(automatic, proposals.proposals, axis.lengthMeters));
    return entry;
}

QJsonObject segment(const QString &id, const QString &type, const QString &name, const double start,
    const double end, const QString &reference = configuration)
{
    return {{"id", id}, {"type", type}, {"name", name}, {"startProgressMeters", start},
            {"endProgressMeters", end}, {"trackConfigurationReference", reference}};
}

QJsonObject fixed(const QJsonValue &stored, QJsonObject args, const double length)
{
    auto item = edit(stored, args, length);
    item.insert("lengthMeters", number(length));
    if (!stored.isUndefined()) item.insert("stored", stored);
    return item;
}

QJsonArray editingCases()
{
    constexpr double L = 1000.0;
    const auto a = segment("a", "corner", "Turn 1", 100.0, 200.0);
    const auto b = segment("b", "straight", "Back straight", 200.0, 400.0);
    const auto c = segment("c", "corner", "Turn 2", 500.0, 600.0);
    const auto wrap = segment("w", "straight", "Main straight", 900.0, 50.0);
    const auto t1 = segment("t", "corner", "Turn 1", 50.0, 200.0);
    const auto beforeGate = segment("x", "straight", "Main A", 900.0, L);
    const auto afterGate = segment("y", "straight", "Main B", 0.0, 50.0);
    const auto half1 = segment("h1", "sector", "S1", 0.0, 500.0);
    const auto half2 = segment("h2", "sector", "S2", 500.0, L);
    const auto other = segment("o", "straight", "Other layout", 300.0, 400.0, otherConfiguration);
    QJsonArray full;
    for (int i = 0; i < maximumTrackSegments; ++i)
        full.append(segment(QString("f%1").arg(i), "sector", QString("S%1").arg(i), i * 10.0, i * 10.0 + 10.0));
    const QJsonArray ab{a, b};
    const auto e = [](const QString &id, const QString &name, const QString &type, const QJsonValue &start,
                       const QJsonValue &end, const bool joined) {
        return QJsonObject{{"op", "edit"}, {"id", id}, {"name", name}, {"type", type}, {"start", start},
                           {"end", end}, {"joined", joined}};
    };
    const auto sp = [](const QString &id, const QJsonValue &at, const QString &name) {
        return QJsonObject{{"op", "split"}, {"id", id}, {"at", at}, {"name", name}};
    };
    const auto m = [](const QString &id, const QString &otherId) {
        return QJsonObject{{"op", "merge"}, {"id", id}, {"other", otherId}};
    };
    const auto r = [](const QString &id) { return QJsonObject{{"op", "remove"}, {"id", id}}; };
    const QVector<std::tuple<QJsonValue, QJsonObject, double>> inputs{
        {ab, e("a", " Hairpin ", "straight", 100.0, 200.0, false), L},
        {ab, e("a", "Turn 1", "corner", 100.0, 250.0, false), L},
        {ab, e("a", "Turn 1", "corner", 100.0, 250.0, true), L},
        {ab, e("a", "Turn 1", "corner", 100.0, 400.0, true), L},
        {ab, e("a", "Turn 1", "corner", 100.0, 150.0, false), L},
        {ab, e("a", "Turn 1", "corner", 100.0, 150.0, true), L},
        {ab, e("b", "Back straight", "straight", 150.0, 400.0, true), L},
        {ab, e("b", "Back straight", "straight", 150.0, 400.0, false), L},
        {ab, e("b", "Back straight", "straight", 200.0, 1000.0, true), L},
        {ab, e("b", "Back straight", "straight", 200.0, 50.0, false), L},
        {ab, e("a", "Turn 1", "corner", 0.0, 200.0, true), L},
        {QJsonArray{a}, e("a", "Turn 1", "corner", 150.0, 150.0, false), L},
        {QJsonArray{a}, e("a", "Turn 1", "corner", 150.0, 150.0000005, false), L},
        {QJsonArray{a}, e("a", "Turn 1", "corner", 100.0, L + 1.0, false), L},
        {QJsonArray{a}, e("a", "Turn 1", "corner", -0.5, 200.0, false), L},
        {QJsonArray{a}, e("a", "Turn 1", "corner", QJsonValue(QJsonValue::Null), 10.0, false), L},
        {QJsonArray{a}, e("a", " ", "corner", 100.0, 200.0, false), L},
        {QJsonArray{a}, e("a", QString(161, 'n'), "corner", 100.0, 200.0, false), L},
        {QJsonArray{a}, e("a", QString(160, 'n'), "corner", 100.0, 200.0, false), L},
        {QJsonArray{a}, e("a", "x" + QString(QChar(0)), "corner", 100.0, 200.0, false), L},
        {QJsonArray{a}, e("a", "Turn 1", "chicane", 100.0, 200.0, false), L},
        {QJsonArray{a}, e("missing", "Turn 1", "corner", 100.0, 200.0, false), L},
        {QJsonValue("not an array"), e("a", "Turn 1", "corner", 100.0, 200.0, false), L},
        {QJsonValue(), e("a", "Turn 1", "corner", 100.0, 200.0, false), L},
        {QJsonArray{a, other}, e("a", "Turn 1", "corner", 100.0, 150.0, false), L},
        {QJsonArray{a}, e("a", "Turn 1", "corner", 100.0, 200.0, false), 0.0},
        {QJsonArray{a}, e("a", "Turn 1", "corner", 100.0, 200.0, false), QJsonValue(QJsonValue::Null).toDouble(nan)},
        {QJsonArray{t1, wrap}, e("w", "Main straight", "straight", 950.0, 50.0, true), L},
        {QJsonArray{t1, wrap}, e("w", "Main straight", "straight", 900.0, 80.0, true), L},
        {QJsonArray{t1, wrap}, e("w", "Main straight", "straight", 900.0, 0.0, true), L},
        {QJsonArray{t1, wrap}, e("w", "Main straight", "straight", 900.0, 1000.0, true), L},
        {QJsonArray{t1, wrap}, e("t", "Turn 1", "corner", 0.0, 200.0, true), L},
        {QJsonArray{t1, wrap}, e("t", "Turn 1", "corner", 1000.0, 200.0, true), L},
        {QJsonArray{t1, wrap}, e("t", "Turn 1", "corner", 20.0, 200.0, true), L},
        {QJsonArray{afterGate, beforeGate}, e("x", "Main A", "straight", 900.0, 0.0, true), L},
        {QJsonArray{afterGate, beforeGate}, e("y", "Main B", "straight", 10.0, 50.0, true), L},
        {QJsonArray{afterGate, beforeGate}, e("y", "Main B", "straight", 990.0, 50.0, true), L},
        {QJsonArray{a, b, c}, e("c", "Turn 2", "corner", 50.0, 90.0, false), L},
        {QJsonArray{a, b, c}, e("a", "Turn 1", "corner", 650.0, 90.0, false), L},
        {QJsonArray{a, b, wrap}, e("a", "Turn 1", "corner", 700.0, 30.0, false), L},
        {ab, sp("b", 300.0, "Back straight 2"), L},
        {ab, sp("b", 200.0, "X"), L},
        {ab, sp("b", 400.0, "X"), L},
        {ab, sp("b", 450.0, "X"), L},
        {ab, sp("b", 200.0000005, "X"), L},
        {ab, sp("b", 300.0, " "), L},
        {ab, sp("b", 300.0, "  Padded  "), L},
        {ab, sp("b", 300.0, QString(161, 'n')), L},
        {ab, sp("missing", 300.0, "X"), L},
        {ab, sp("b", QJsonValue(QJsonValue::Null), "X"), L},
        {ab, sp("b", 300.0, "X"), 0.0},
        {ab, sp("b", -1.0, "X"), L},
        {QJsonArray{t1, wrap}, sp("w", 20.0, "Main straight 2"), L},
        {QJsonArray{t1, wrap}, sp("w", L, "Main straight 2"), L},
        {QJsonArray{t1, wrap}, sp("w", 0.0, "Main straight 2"), L},
        {QJsonArray{t1, wrap}, sp("w", 950.0, "Main straight 2"), L},
        {QJsonArray{t1, wrap}, sp("w", 60.0, "X"), L},
        {QJsonArray{t1, wrap}, sp("t", 100.0, "Turn 1 (2)"), L},
        {full, sp("f0", 5.0, "Extra"), L},
        {QJsonArray{a, other}, sp("a", 150.0, "X"), L},
        {QJsonArray{a, b, c}, m("b", "a"), L},
        {QJsonArray{a, b, c}, m("a", "b"), L},
        {QJsonArray{a, b, c}, m("b", "c"), L},
        {QJsonArray{a, b, c}, m("a", "a"), L},
        {QJsonArray{a, b, c}, m("a", "missing"), L},
        {QJsonArray{afterGate, beforeGate}, m("x", "y"), L},
        {QJsonArray{afterGate, beforeGate}, m("y", "x"), L},
        {QJsonArray{half1, half2}, m("h1", "h2"), L},
        {QJsonArray{t1, wrap}, m("w", "t"), L},
        {QJsonArray{t1, wrap}, m("t", "w"), L},
        {QJsonArray{a, segment("a2", "corner", "Turn 1b", 200.0, 300.0)}, m("a", "a2"), L},
        {QJsonArray{a, other}, m("a", "o"), L},
        {QJsonArray{a, b, c}, m("a", "b"), 0.0},
        {QJsonArray{a, b, c}, r("b"), L},
        {QJsonArray{a, b, c}, r("missing"), L},
        {QJsonArray{a}, r("a"), L},
        {QJsonValue("x"), r("a"), L},
        {QJsonArray{a, other}, r("o"), L},
    };
    QJsonArray cases;
    for (const auto &[stored, args, length] : inputs) cases.append(fixed(stored, args, length));
    return cases;
}

QJsonArray proposalEditCases()
{
    const QVector<std::tuple<QString, double, double, double>> inputs{
        {"Turn 1", 10.0, 20.0, 1000.0},   {"Turn 1", 20.0, 10.0, 1000.0},  {" ", 10.0, 20.0, 1000.0},
        {QString(160, 'n'), 0.0, 1000.0, 1000.0}, {QString(161, 'n'), 10.0, 20.0, 1000.0},
        {"T", 10.0, 10.0000005, 1000.0},  {"T", 10.0, 1000.5, 1000.0},     {"T", -1.0, 20.0, 1000.0},
        {"T", nan, 20.0, 1000.0},         {"T", 10.0, 20.0, 0.0},          {"T", 10.0, 20.0, nan},
        {"T", 10.0, 20.0, 1234.56},       {"T", 10.0, 1300.0, 1234.56},    {"x" + QString(QChar(0)), 1.0, 2.0, 10.0},
    };
    QJsonArray cases;
    for (const auto &[name, start, end, length] : inputs) {
        QString error;
        const bool valid = validProposalEdit(name, start, end, length, &error);
        cases.append(QJsonObject{{"name", name}, {"start", number(start)}, {"end", number(end)},
                                 {"lengthMeters", number(length)}, {"valid", valid}, {"error", error}});
    }
    return cases;
}

QJsonArray withoutOtherCases()
{
    const auto a = segment("a", "corner", "Turn 1", 100.0, 200.0);
    const auto o = segment("o", "corner", "Other", 250.0, 260.0, otherConfiguration);
    const QVector<QJsonValue> values{QJsonValue(), QJsonArray{}, QJsonArray{a, o}, QJsonArray{o}, QJsonValue("x"),
                                     QJsonArray{a, 3}};
    QJsonArray cases;
    for (const auto &value : values) {
        QJsonObject item{{"result", withoutOtherConfigurations(value, configuration)}};
        if (!value.isUndefined()) item.insert("stored", value);
        cases.append(item);
    }
    return cases;
}

QJsonArray reviewValidityCases()
{
    const QJsonObject decision{{"type", "corner"}, {"startProgressMeters", 10.0}, {"endProgressMeters", 20.0}};
    const QJsonObject base{{"version", "track-segment-review-v1"}, {"trackConfigurationReference", configuration},
                           {"proposalAlgorithm", "track-segment-proposal-v2"}, {"rejected", QJsonArray{decision}}};
    const auto with = [](QJsonObject object, const QString &key, const QJsonValue &value) {
        if (value.isUndefined()) object.remove(key);
        else object.insert(key, value);
        return object;
    };
    QJsonArray many;
    for (int i = 0; i < maximumSegmentReviewDecisions + 1; ++i)
        many.append(QJsonObject{{"type", "sector"}, {"startProgressMeters", i * 1.0}, {"endProgressMeters", i + 0.5}});
    QJsonArray sixtyFour = many;
    sixtyFour.removeLast();
    const QVector<QJsonValue> values{
        QJsonValue(QJsonValue::Null), base, QJsonArray{base}, QJsonValue("x"),
        with(base, "version", "track-segment-review-v2"), with(base, "extra", 1), with(base, "rejected", QJsonValue()),
        with(base, "rejected", QJsonArray{}), with(base, "rejected", sixtyFour), with(base, "rejected", many),
        with(base, "proposalAlgorithm", " "), with(base, "proposalAlgorithm", QString(64, 'p')),
        with(base, "proposalAlgorithm", QString(65, 'p')), with(base, "proposalAlgorithm", 2),
        with(base, "trackConfigurationReference", configuration + "\n"),
        with(base, "trackConfigurationReference", "compatibility-v1:abc"),
        with(base, "rejected", QJsonArray{with(decision, "type", "chicane")}),
        with(base, "rejected", QJsonArray{with(decision, "endProgressMeters", 10.0)}),
        with(base, "rejected", QJsonArray{with(decision, "endProgressMeters", -1.0)}),
        with(base, "rejected", QJsonArray{with(decision, "endProgressMeters", 1'000'000.0)}),
        with(base, "rejected", QJsonArray{with(decision, "endProgressMeters", 1'000'000.5)}),
        with(base, "rejected", QJsonArray{with(decision, "endProgressMeters", "20")}),
        with(base, "rejected", QJsonArray{with(decision, "extra", 1)}),
        with(base, "rejected", QJsonArray{3}),
    };
    QJsonArray cases;
    for (const auto &value : values) cases.append(QJsonObject{{"value", value}, {"valid", validTrackSegmentReview(value)}});
    return cases;
}

QJsonArray stampCases()
{
    const QString revision = "track-segments-v1:" + QString(64, 'a');
    const QJsonObject base{{"trackConfigurationReference", configuration}, {"revision", revision},
                           {"calculationAlgorithm", "theoretical-best-v1"}};
    const auto with = [](QJsonObject object, const QString &key, const QJsonValue &value) {
        if (value.isUndefined()) object.remove(key);
        else object.insert(key, value);
        return object;
    };
    const QVector<QJsonValue> values{
        base, with(base, "calculationAlgorithm", ""), with(base, "calculationAlgorithm", QString(65, 'c')),
        with(base, "revision", revision + "\n"), with(base, "revision", "track-segments-v1:abc"),
        with(base, "revision", QJsonValue()), with(base, "extra", 1),
        with(base, "trackConfigurationReference", otherConfiguration), with(base, "trackConfigurationReference", 5),
        QJsonValue("x"), QJsonValue(QJsonValue::Null),
    };
    QJsonArray cases;
    for (const auto &value : values) {
        const auto stamp = segmentationResultStampFromJson(value);
        cases.append(QJsonObject{{"value", value},
                                 {"stamp", stamp ? QJsonValue(segmentationResultStampToJson(*stamp))
                                                 : QJsonValue(QJsonValue::Null)}});
    }
    return cases;
}

QJsonArray historyCases()
{
    const QJsonArray s0;
    const QJsonArray s1{segment("a", "corner", "Turn 1", 100.0, 200.0)};
    const QJsonArray s2{s1.first(), segment("b", "straight", "Back", 200.0, 400.0)};
    const QJsonArray s3{segment("a", "corner", "Turn 1", 100.0, 210.0)};
    const QVector<QJsonArray> states{s0, s1, s2, s3};
    // [op, before, after]: record, undo, redo, clear.
    const QVector<std::tuple<QString, int, int>> ops{
        {"record", 0, 0}, {"record", 0, 1}, {"record", 1, 2}, {"undo", 0, 0}, {"redo", 0, 0}, {"redo", 0, 0},
        {"undo", 0, 0},   {"record", 1, 0}, {"record", 0, 2}, {"record", 2, 3}, {"undo", 0, 0}, {"undo", 0, 0},
        {"undo", 0, 0},   {"redo", 0, 0},   {"clear", 0, 0},  {"undo", 0, 0},
    };
    const auto index = [&states](const QJsonArray &value) { return int(states.indexOf(value)); };
    SegmentEditHistory history(2);
    QJsonArray steps;
    for (const auto &[op, before, after] : ops) {
        if (op == "record") history.record("run", states[before], states[after]);
        else if (op == "undo") history.commitUndo();
        else if (op == "redo") history.commitRedo();
        else history.clear();
        const auto *undo = history.nextUndo();
        const auto *redo = history.nextRedo();
        steps.append(QJsonObject{{"op", op}, {"before", before}, {"after", after},
                                 {"undoCount", history.undoCount()}, {"redoCount", history.redoCount()},
                                 {"nextUndo", undo ? QJsonValue(QJsonArray{index(undo->before), index(undo->after)}) : QJsonValue(QJsonValue::Null)},
                                 {"nextRedo", redo ? QJsonValue(QJsonArray{index(redo->before), index(redo->after)}) : QJsonValue(QJsonValue::Null)}});
    }
    QJsonArray stateJson;
    for (const auto &state : states) stateJson.append(state);
    return {QJsonObject{{"limit", 2}, {"states", stateJson}, {"steps", steps}}};
}

QJsonObject pickCases()
{
    // A figure-eight crossing: (0,0)->(1,1) is progress 0..100, (1,0)->(0,1) is 100..200.
    QVector<ProgressMapPoint> trace;
    for (int i = 0; i <= 100; ++i) trace.append({double(i), QPointF(i / 100.0, i / 100.0)});
    for (int i = 0; i <= 100; ++i) trace.append({100.0 + i, QPointF(1.0 - i / 100.0, i / 100.0)});
    QJsonArray traceJson;
    for (const auto &point : trace) traceJson.append(QJsonArray{point.progressMeters, point.point.x(), point.point.y()});
    const QVector<std::tuple<QPointF, double, double, double, double>> inputs{
        {{0.25, 0.26}, 0.03, 0.01, 30.0, 200.0}, {{0.5, 0.5}, 0.03, 0.01, 30.0, 200.0},
        {{0.9, 0.3}, 0.03, 0.01, 30.0, 200.0},   {{0.5, 0.5}, 0.03, 0.01, 300.0, 200.0},
        {{0.6, 0.55}, 0.03, 0.01, 30.0, 200.0},  {{0.6, 0.55}, 0.03, 0.2, 30.0, 200.0},
        {{0.02, 0.0}, 0.03, 0.01, 30.0, 200.0},  {{0.99, 0.0}, 0.03, 0.01, 30.0, 200.0},
        {{0.3, 0.3}, 0.03, 0.01, 30.0, 0.0},     {{nan, 0.3}, 0.03, 0.01, 30.0, 200.0},
        {{0.3, 0.3}, 0.0, 0.0, 30.0, 200.0},     {{0.995, 0.995}, 0.03, 0.05, 30.0, 200.0},
    };
    QJsonArray cases;
    for (const auto &[target, maximum, margin, separation, length] : inputs) {
        const auto pick = pickProgressAt(trace, target, maximum, margin, separation, length);
        cases.append(QJsonObject{{"x", number(target.x())}, {"y", number(target.y())}, {"maximumDistance", maximum},
                                 {"ambiguityMargin", margin}, {"separationMeters", separation},
                                 {"lengthMeters", length},
                                 {"progressMeters", pick.progressMeters ? QJsonValue(*pick.progressMeters) : QJsonValue(QJsonValue::Null)},
                                 {"reason", pick.reason}});
    }
    const auto empty = pickProgressAt({}, {0.5, 0.5}, 0.03, 0.01, 30.0, 200.0);
    return {{"trace", traceJson}, {"cases", cases}, {"emptyReason", empty.reason}};
}

TrackSegmentProposal proposal(const TrackSegmentType type, const QString &name, const double start, const double end)
{
    TrackSegmentProposal result;
    result.type = type;
    result.name = name;
    result.start = {start, 7.0, {}};
    result.end = {end, 7.0, {}};
    return result;
}

QJsonArray reviewCases()
{
    const QVector<TrackSegmentProposal> proposals{
        proposal(TrackSegmentType::Straight, "Straight 1", 0.0, 100.0),
        proposal(TrackSegmentType::Corner, "Corner 1", 100.0, 200.0),
        proposal(TrackSegmentType::Straight, "Straight 2", 200.0, 600.0),
        proposal(TrackSegmentType::Corner, "Corner 2", 600.0, 700.0),
        proposal(TrackSegmentType::Straight, "Straight 3", 700.0, 1000.0),
    };
    QJsonArray proposalJson;
    for (const auto &item : proposals) proposalJson.append(boundsJson(item));
    const auto a = segment("a", "corner", "Corner 1", 100.0, 200.0);
    const auto aShifted = segment("a", "corner", "Corner 1", 100.0000005, 200.0);
    const auto aRetyped = segment("a", "sector", "Corner 1", 100.0, 200.0);
    const auto wide = segment("w", "sector", "Wide", 150.0, 650.0);
    const auto wrap = segment("x", "straight", "Wrap", 950.0, 50.0);
    const auto touch = segment("t", "corner", "Touch", 200.0000005, 210.0);
    const auto other = segment("o", "corner", "Other", 600.0, 700.0, otherConfiguration);
    const QVector<std::tuple<QJsonValue, QList<int>, QList<int>>> inputs{
        {QJsonArray{}, {}, {}},
        {QJsonArray{a}, {}, {0, 1}},
        {QJsonArray{aShifted}, {1}, {}},
        {QJsonArray{aRetyped}, {}, {}},
        {QJsonArray{a, wide}, {}, {3}},
        {QJsonArray{a, segment("d", "corner", "Dup", 600.0, 700.0), wrap}, {}, {4}},
        {QJsonArray{touch}, {}, {}},
        {QJsonArray{a, other}, {}, {3}},
        {QJsonValue("x"), {}, {2}},
    };
    QJsonArray cases;
    for (const auto &[stored, edited, rejected] : inputs) {
        const auto approved = approvedSegmentation(stored, configuration);
        QJsonArray editedJson, rejectedJson;
        for (const int index : edited) editedJson.append(index);
        for (const int index : rejected) rejectedJson.append(index);
        cases.append(QJsonObject{{"stored", stored}, {"edited", editedJson}, {"rejected", rejectedJson},
                                 {"lengthMeters", 1000.0},
                                 {"items", itemsJson(reviewSegmentProposals(proposals,
                                     QSet<int>(edited.cbegin(), edited.cend()),
                                     QSet<int>(rejected.cbegin(), rejected.cend()), approved, 1000.0))}});
    }
    QJsonArray decisions;
    for (const auto &rejected : QVector<QVector<int>>{{}, {1}, {0, 4}, {2, 2}}) {
        QVector<TrackSegmentProposal> chosen;
        QJsonArray indexes;
        for (const int index : rejected) { chosen.append(proposals[index]); indexes.append(index); }
        const auto review = makeTrackSegmentReview(configuration, chosen);
        QList<int> found = rejectedProposalIndexes(review, configuration, proposals).values();
        std::sort(found.begin(), found.end());
        QJsonArray foundJson;
        for (const int index : found) foundJson.append(index);
        decisions.append(QJsonObject{{"rejected", indexes}, {"review", review}, {"found", foundJson}});
    }
    return {QJsonObject{{"proposals", proposalJson}, {"cases", cases}, {"decisions", decisions}}};
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
                            {"editing", editingCases()},
                            {"validProposalEdit", proposalEditCases()},
                            {"withoutOtherConfigurations", withoutOtherCases()},
                            {"validTrackSegmentReview", reviewValidityCases()},
                            {"stamps", stampCases()},
                            {"history", historyCases()},
                            {"pick", pickCases()},
                            {"review", reviewCases()}};
    QFile output(QString::fromLocal8Bit(argv[1]));
    if (!output.open(QIODevice::WriteOnly)) return 1;
    output.write(QJsonDocument(QJsonObject{{"files", results}, {"cases", cases}}).toJson(QJsonDocument::Compact));
    return 0;
}
