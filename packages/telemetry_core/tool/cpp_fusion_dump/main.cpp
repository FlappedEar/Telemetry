// Prints FlappedEar Overlays' recording alignment and channel fusion for
// fixed synthetic cases as one JSON document:
//   cpp_fusion_dump <output.json>
//   cpp_fusion_dump --pairs <pairs.json> <output.json>
//
// "sync": TelemetrySyncEngine::synchronize on a few pairs, and
// syncConfidenceLevel / shouldAutoApplySyncCandidate on fixed values.
// "alignment": alignRecordings (recording-alignment-v1) on synthetic
// recordings: a clean offset, drift, a lap-away match with and without the
// declared clock, a conflicting declared clock, a clock step, periodic, flat,
// unrelated, short and missing signals.
// "fusion": fuseChannels (channel-fusion-v1) and fusedSession on the
// sessions of ChannelFusionTests.cpp under every rule, refused sources, unit
// mismatches, two alternatives, name clashes and gap markers (KAN-188).
// "tolerances": fusionConflictTolerance for fixed units and ranges.
// "inputs": a digest of every input session (by "alignment/" or "fusion/"
// and the case), so the Dart test can confirm it
// built the same samples.
//
// The synthetic signals use `wave`, a sine built from + - * / and floor
// only, so the Dart test can build bit-identical inputs on any platform
// without depending on the C library's sin.
//
// A channel's samples are written as a digest (64-bit FNV-1a over the
// little-endian bytes of every double timestamp, then every float value) and
// every 25th sample with the last.
//
// --pairs reads {"pairs": [{"primary": <vbo path>, "alternative": <rcz
// path>}]}, parses both with Overlays' parsers and writes the alignment and
// the fusion (no rules, and fillGaps for every channel both recorded) of each
// pair in order. Use it locally only; never commit its input or output.
// NaN is written as null.

#include "telemetry/ChannelFusion.h"
#include "telemetry/RczParser.h"
#include "telemetry/RecordingAlignment.h"
#include "telemetry/TelemetrySyncEngine.h"
#include "telemetry/VboParser.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <exception>
#include <functional>
#include <limits>
#include <optional>

using namespace FlappedEar;

namespace {

QJsonValue number(const double value)
{
    return std::isfinite(value) ? QJsonValue(value) : QJsonValue(QJsonValue::Null);
}

QJsonValue optionalNumber(const std::optional<double> &value)
{
    return value ? number(*value) : QJsonValue(QJsonValue::Null);
}

// --- Synthetic signals -------------------------------------------------------

constexpr double pi = 3.141592653589793;

// sin(x) to about 2e-8, from + - * / and floor only.
double wave(const double x)
{
    const double twoPi = 2.0 * pi;
    const double r = x - std::floor(x / twoPi + 0.5) * twoPi;
    const double r2 = r * r;
    return r * (1.0 + r2 * (-1.0 / 6.0 + r2 * (1.0 / 120.0 + r2 * (-1.0 / 5040.0 + r2 * (1.0 / 362880.0
        + r2 * (-1.0 / 39916800.0 + r2 * (1.0 / 6227020800.0 + r2 * (-1.0 / 1307674368000.0
        + r2 * (1.0 / 355687428096000.0)))))))));
}

// RecordingAlignmentTests' track day: a 110 s lap shape, slower changes
// across laps, a fixed wobble, the pit-lane exit, a yellow-flag lap and the
// in-lap.
double daySpeed(const double t)
{
    const double lap = 2.0 * pi * t / 110.0;
    const double racing = 90.0 + 35.0 * wave(lap) + 15.0 * wave(3.0 * lap + 0.4) + 10.0 * wave(0.013 * t)
        + 6.0 * wave(0.0071 * t + 1.0) + 2.0 * wave(1.7 * t) * wave(0.031 * t);
    if (t < 120.0) return std::min(racing, 60.0);
    if (t > 800.0 && t < 910.0) return racing * 0.6;
    if (t > 1650.0) return racing * 0.7;
    return racing;
}

// A trace that never repeats.
double uniqueSpeed(const double t)
{
    return 80.0 + 30.0 * wave(0.002 * t * t / 10.0) + 10.0 * wave(0.05 * t);
}

// Identical 20 s cycles.
double periodicSpeed(const double t)
{
    return 80.0 + 30.0 * wave(2.0 * pi * t / 20.0);
}

TelemetrySession recording(const double start, const double end, const double rateHz,
    const std::function<double(double)> &speedAt, const std::optional<qint64> startMilliseconds = std::nullopt)
{
    TelemetrySession session;
    TelemetryChannel speed;
    speed.name = "velocity";
    speed.unit = "km/h";
    for (double time = start; time <= end + 1e-9; time += 1.0 / rateHz) {
        speed.timestamps.append(time);
        speed.values.append(static_cast<float>(speedAt(time)));
    }
    session.channels.insert(speed.name, speed);
    session.aliases.insert("speed", speed.name);
    session.duration = end - start;
    session.sampleCount = speed.values.size();
    if (startMilliseconds) session.metadata.insert("firstTimestampMilliseconds", QString::number(*startMilliseconds));
    return session;
}

TelemetrySession candidateOf(const double offset, const double driftPpm, const double length = 1500.0,
    const std::optional<qint64> startMilliseconds = std::nullopt)
{
    return recording(0.0, length, 5.0, [=](double c) { return daySpeed(c + offset + driftPpm * 1e-6 * c); },
        startMilliseconds);
}

TelemetrySession primaryDay(const std::optional<qint64> startMilliseconds = std::nullopt)
{
    return recording(0.0, 1800.0, 5.0, daySpeed, startMilliseconds);
}

TelemetryChannel makeChannel(const QString &name, const QString &unit, double start, double end, double rate,
    const std::function<double(double)> &value, const std::function<bool(double)> &present = [](double) { return true; })
{
    TelemetryChannel channel;
    channel.name = name;
    channel.unit = unit;
    for (double time = start; time <= end + 1e-9; time += 1.0 / rate) {
        if (!present(time)) continue;
        channel.timestamps.append(time);
        channel.values.append(static_cast<float>(value(time)));
    }
    return channel;
}

void add(TelemetrySession &session, const TelemetryChannel &channel, const QString &alias = {})
{
    session.channels.insert(channel.name, channel);
    if (!alias.isEmpty()) session.aliases.insert(alias, channel.name);
}

double fusionSpeed(const double t) { return 100.0 + 20.0 * wave(0.1 * t); }

// A channel with the gap markers RczParser writes: NaN one step inside every
// step longer than `gap`.
TelemetryChannel withGapMarkers(const TelemetryChannel &channel, const double gap)
{
    TelemetryChannel marked;
    marked.name = channel.name;
    marked.unit = channel.unit;
    for (qsizetype index = 0; index < channel.timestamps.size(); ++index) {
        if (index && channel.timestamps[index] - channel.timestamps[index - 1] > gap) {
            const double before = channel.timestamps[index - 1], after = channel.timestamps[index];
            marked.timestamps << std::nextafter(before, after) << std::nextafter(after, before);
            marked.values << std::numeric_limits<float>::quiet_NaN() << std::numeric_limits<float>::quiet_NaN();
        }
        marked.timestamps << channel.timestamps[index];
        marked.values << channel.values[index];
    }
    return marked;
}

// ChannelFusionTests' primary (a VBO): GPS speed, missing from 40 to 50 s.
TelemetrySession fusionPrimary()
{
    TelemetrySession session;
    add(session, makeChannel("velocity", "km/h", 0.0, 100.0, 10.0, fusionSpeed,
        [](double t) { return t < 40.0 || t > 50.0; }), "speed");
    add(session, makeChannel("latacc-calc", "g", 0.0, 100.0, 10.0, [](double t) { return wave(t); }),
        "lateralAcceleration");
    session.duration = 100.0;
    session.sampleCount = 1001;
    session.metadata.insert("source", "primary");
    return session;
}

// ChannelFusionTests' alternative (an RCZ), 5 s behind the primary.
TelemetrySession fusionAlternative(const double speedBias = 0.0, const QString &speedUnit = "km/h")
{
    TelemetrySession session;
    add(session, makeChannel("velocity", speedUnit, 0.0, 90.0, 5.0,
        [=](double c) { return fusionSpeed(c + 5.0) + speedBias; }), "speed");
    add(session, makeChannel("coolant_temp-obd", "C", 0.0, 95.0, 1.0, [](double c) { return 90.0 + 0.01 * c; }));
    add(session, makeChannel("rpm-obd", "rpm", 0.0, 95.0, 5.0, [](double c) { return 4000.0 + 1000.0 * wave(0.3 * c); },
        [](double c) { return c < 60.0 || c > 70.0; }), "rpm");
    return session;
}

// --- Digests -----------------------------------------------------------------

QString digest(const TelemetryChannel &channel)
{
    std::uint64_t hash = 0xcbf29ce484222325ULL;
    const auto feed = [&hash](const unsigned char *bytes, const int count) {
        for (int i = 0; i < count; ++i) {
            hash ^= bytes[i];
            hash *= 0x100000001b3ULL;
        }
    };
    for (const double time : channel.timestamps) {
        unsigned char bytes[8];
        std::memcpy(bytes, &time, 8); // little-endian on the supported hosts
        feed(bytes, 8);
    }
    for (const float value : channel.values) {
        unsigned char bytes[4];
        std::memcpy(bytes, &value, 4);
        feed(bytes, 4);
    }
    return QString::number(hash, 16).rightJustified(16, QLatin1Char('0'));
}

QJsonObject channelJson(const TelemetryChannel &channel, const bool samples = true)
{
    QJsonObject object{{"name", channel.name}, {"unit", channel.unit},
        {"count", static_cast<double>(channel.timestamps.size())},
        {"valueCount", static_cast<double>(channel.values.size())}, {"digest", digest(channel)}};
    if (samples) {
        QJsonArray rows;
        for (qsizetype i = 0; i < channel.timestamps.size(); ++i) {
            if (i % 25 != 0 && i != channel.timestamps.size() - 1) continue;
            rows.append(QJsonArray{static_cast<double>(i), number(channel.timestamps[i]),
                i < channel.values.size() ? number(channel.values[i]) : QJsonValue(QJsonValue::Null)});
        }
        object.insert("samples", rows);
    }
    return object;
}

QJsonObject sessionDigest(const TelemetrySession &session)
{
    QJsonObject channels;
    for (auto it = session.channels.cbegin(); it != session.channels.cend(); ++it)
        channels.insert(it.key(), channelJson(*it, false));
    QJsonObject aliases;
    for (auto it = session.aliases.cbegin(); it != session.aliases.cend(); ++it) aliases.insert(it.key(), it.value());
    QJsonObject metadata;
    for (auto it = session.metadata.cbegin(); it != session.metadata.cend(); ++it) metadata.insert(it.key(), it.value());
    return {{"channels", channels}, {"aliases", aliases}, {"metadata", metadata}, {"duration", number(session.duration)},
        {"sampleCount", static_cast<double>(session.sampleCount)}};
}

// --- JSON of the results -----------------------------------------------------

QJsonObject syncJson(const SyncCandidate &candidate)
{
    const auto &d = candidate.diagnostics;
    return {{"offset", number(candidate.offset)}, {"timeScale", number(candidate.timeScale)},
        {"confidence", number(candidate.confidence)}, {"strategy", candidate.strategy},
        {"correlation", number(d.correlation)}, {"peakUniqueness", number(d.peakUniqueness)},
        {"validSamples", d.validSamples}, {"sampleRate", number(d.sampleRate)},
        {"coarseOffset", number(d.coarseOffset)}, {"autoApply", shouldAutoApplySyncCandidate(candidate)}};
}

QJsonObject alignmentJson(const RecordingAlignment &alignment)
{
    QJsonArray windows;
    for (const auto &window : alignment.windows)
        windows.append(QJsonArray{number(window.candidateTime), number(window.offset), number(window.correlation),
            window.used});
    return {{"status", alignment.status}, {"reason", alignment.reason},
        {"declaredOffset", optionalNumber(alignment.declaredOffset)}, {"offset", optionalNumber(alignment.offset)},
        {"driftPpm", optionalNumber(alignment.driftPpm)},
        {"uncertaintySeconds", optionalNumber(alignment.uncertaintySeconds)},
        {"correlation", number(alignment.correlation)}, {"peakUniqueness", number(alignment.peakUniqueness)},
        {"confidence", number(alignment.confidence)}, {"overlapSeconds", number(alignment.overlapSeconds)},
        {"windows", windows}, {"usedWindows", static_cast<double>(alignment.usedWindows)},
        {"resolvedByDeclaredClock", alignment.resolvedByDeclaredClock}};
}

QJsonArray stringsJson(const QStringList &strings)
{
    QJsonArray array;
    for (const auto &string : strings) array.append(string);
    return array;
}

QJsonObject fusionJson(const ChannelFusionResult &result, const bool samples = true)
{
    QJsonArray channels;
    for (const auto &fused : result.channels) {
        QJsonArray segments;
        for (const auto &segment : fused.segments)
            segments.append(QJsonArray{segment.sourceId, number(segment.start), number(segment.end),
                number(segment.clock.offsetSeconds), number(segment.clock.driftPpm),
                number(segment.sampleIntervalSeconds)});
        channels.append(QJsonObject{{"key", fused.key}, {"name", fused.name}, {"unit", fused.unit},
            {"rule", fused.rule}, {"segments", segments}, {"channel", channelJson(fused.channel, samples)},
            {"comparedSourceId", fused.comparedSourceId},
            {"comparedSamples", static_cast<double>(fused.comparedSamples)},
            {"medianDifference", number(fused.medianDifference)}, {"conflicting", fused.conflicting}});
    }
    return {{"channels", channels}, {"unresolved", stringsJson(result.unresolved)},
        {"unitMismatches", stringsJson(result.unitMismatches)},
        {"refusedSources", stringsJson(result.refusedSources)}};
}

// --- Cases ------------------------------------------------------------------

constexpr qint64 dayStart = 1'756'450'000'000;

QJsonObject inputs;

QJsonObject alignmentCase(const QString &name, const TelemetrySession &primary, const TelemetrySession &candidate,
    const RecordingAlignmentOptions &options = {})
{
    inputs.insert("alignment/" + name, QJsonObject{{"primary", sessionDigest(primary)}, {"candidate", sessionDigest(candidate)}});
    return alignmentJson(alignRecordings(primary, candidate, {}, options));
}

QJsonObject alignmentCases()
{
    QJsonObject cases;
    // Decided by the match alone: a trace that never repeats.
    cases.insert("cleanOffset", alignmentCase("cleanOffset", recording(0.0, 900.0, 10.0, uniqueSpeed),
        recording(0.0, 700.0, 5.0, [](double c) { return uniqueSpeed(c + 55.5); })));
    cases.insert("cleanOffsetDeclared", alignmentCase("cleanOffsetDeclared",
        recording(0.0, 900.0, 10.0, uniqueSpeed, dayStart),
        recording(0.0, 700.0, 5.0, [](double c) { return uniqueSpeed(c + 55.5); }, dayStart + 55'000)));
    cases.insert("negativeOffset", alignmentCase("negativeOffset", recording(0.0, 900.0, 10.0, uniqueSpeed),
        recording(0.0, 950.0, 5.0, [](double c) { return uniqueSpeed(c - 30.25); })));
    // Laps repeat: measured alone the match is ambiguous; the declared clock
    // chooses the lap.
    cases.insert("lapAwayMeasuredOnly", alignmentCase("lapAwayMeasuredOnly", primaryDay(), candidateOf(123.4, 0.0)));
    cases.insert("lapAwayDeclared", alignmentCase("lapAwayDeclared", primaryDay(dayStart),
        candidateOf(123.4, 0.0, 1500.0, dayStart + 123'900)));
    cases.insert("agreeingDeclared", alignmentCase("agreeingDeclared", primaryDay(dayStart),
        candidateOf(123.4, 0.0, 1500.0, dayStart + 123'400)));
    cases.insert("conflictingDeclared", alignmentCase("conflictingDeclared", primaryDay(dayStart),
        candidateOf(123.4, 0.0, 1500.0, dayStart + 183'400)));
    // 400 ppm: the alternative clock gains 0.6 s over 25 minutes.
    cases.insert("drift", alignmentCase("drift", primaryDay(dayStart),
        candidateOf(40.0, 400.0, 1500.0, dayStart + 40'000)));
    cases.insert("driftNegative", alignmentCase("driftNegative", primaryDay(dayStart),
        candidateOf(40.0, -600.0, 1500.0, dayStart + 40'000)));
    RecordingAlignmentOptions strict;
    strict.maximumPlausibleDriftPpm = 100.0;
    cases.insert("implausibleDrift", alignmentCase("implausibleDrift", primaryDay(dayStart),
        candidateOf(40.0, 400.0, 1500.0, dayStart + 40'000), strict));
    RecordingAlignmentOptions few;
    few.maximumWindows = 3;
    few.minimumWindowSeconds = 200.0;
    cases.insert("threeWindows", alignmentCase("threeWindows", primaryDay(dayStart),
        candidateOf(40.0, 400.0, 1500.0, dayStart + 40'000), few));
    // The candidate's clock steps by 1.5 s halfway: the windows disagree.
    cases.insert("clockStep", alignmentCase("clockStep", primaryDay(dayStart),
        recording(0.0, 1500.0, 5.0, [](double c) { return daySpeed(c + 40.0 + (c > 750.0 ? 1.5 : 0.0)); },
            dayStart + 40'000)));
    cases.insert("periodic", alignmentCase("periodic", recording(0.0, 600.0, 10.0, periodicSpeed),
        recording(0.0, 500.0, 5.0, [](double c) { return periodicSpeed(c + 37.0); })));
    cases.insert("flat", alignmentCase("flat", recording(0.0, 600.0, 10.0, [](double) { return 100.0; }),
        recording(0.0, 500.0, 5.0, [](double) { return 100.0; })));
    cases.insert("unrelated", alignmentCase("unrelated", primaryDay(dayStart),
        recording(0.0, 700.0, 5.0, uniqueSpeed, dayStart + 10'000)));
    cases.insert("noSpeed", alignmentCase("noSpeed", primaryDay(), TelemetrySession{}));
    // Fifteen seconds of overlap is below the sync engine's minimum.
    cases.insert("insufficientOverlap", alignmentCase("insufficientOverlap", primaryDay(dayStart),
        candidateOf(200.0, 0.0, 15.0, dayStart + 200'000)));
    // Too few samples for the engine.
    cases.insert("tooFewSamples", alignmentCase("tooFewSamples", primaryDay(),
        recording(0.0, 1.0, 5.0, daySpeed)));
    return cases;
}

QJsonObject syncCases()
{
    QJsonObject cases;
    const auto primary = recording(0.0, 900.0, 10.0, uniqueSpeed);
    const auto candidate = recording(0.0, 700.0, 5.0, [](double c) { return uniqueSpeed(c + 55.5); });
    cases.insert("clean", syncJson(TelemetrySyncEngine::synchronize(candidate, primary)));
    cases.insert("cleanReversed", syncJson(TelemetrySyncEngine::synchronize(primary, candidate)));
    cases.insert("lapAway", syncJson(TelemetrySyncEngine::synchronize(candidateOf(123.4, 0.0), primaryDay())));
    cases.insert("drift", syncJson(TelemetrySyncEngine::synchronize(candidateOf(40.0, 400.0), primaryDay())));
    QJsonArray levels;
    for (const double value : {-0.1, 0.0, 0.44, 0.45, 0.74, 0.75, 1.0, 1.1, std::nan("")}) {
        SyncCandidate candidate;
        candidate.confidence = value;
        const auto level = syncConfidenceLevel(value);
        levels.append(QJsonArray{number(value),
            level == SyncConfidenceLevel::High ? "high" : level == SyncConfidenceLevel::Medium ? "medium" : "low",
            shouldAutoApplySyncCandidate(candidate)});
    }
    return {{"cases", cases}, {"levels", levels}};
}

struct Alternative {
    QString id;
    std::optional<TelemetrySession> session;
    SourceClock clock;
    QString status = "aligned";
};

QJsonObject fusionCase(const QString &name, const TelemetrySession &primary, const QVector<Alternative> &alternatives,
    const FusionPolicy &policy = {})
{
    QJsonObject input{{"primary", sessionDigest(primary)}};
    QVector<FusionSource> sources;
    for (const auto &alternative : alternatives) {
        if (alternative.session) input.insert(alternative.id, sessionDigest(*alternative.session));
        sources.append({alternative.id, alternative.session ? &*alternative.session : nullptr, alternative.clock,
            alternative.status});
    }
    inputs.insert("fusion/" + name, input);
    const auto result = fuseChannels(primary, "vbo", sources, policy);
    auto json = fusionJson(result);
    json.insert("session", sessionDigest(fusedSession(primary, result)));
    return json;
}

FusionPolicy rule(const QString &key, const QString &source, const FusionRule fusionRule)
{
    FusionPolicy policy;
    policy.rules.insert(key, {source, fusionRule});
    return policy;
}

QJsonObject fusionCases()
{
    QJsonObject cases;
    const auto primary = fusionPrimary();
    const SourceClock five{5.0, 0.0};
    cases.insert("added", fusionCase("added", primary, {{"rcz", fusionAlternative(), five}}));
    cases.insert("agree", fusionCase("agree", primary, {{"rcz", fusionAlternative(0.5), five}}));
    cases.insert("unresolvedConflict", fusionCase("unresolvedConflict", primary, {{"rcz", fusionAlternative(8.0), five}}));
    cases.insert("conflictPrimaryOnly", fusionCase("conflictPrimaryOnly", primary, {{"rcz", fusionAlternative(8.0), five}},
        rule("speed", "rcz", FusionRule::PrimaryOnly)));
    cases.insert("conflictRuleForAnotherSource", fusionCase("conflictRuleForAnotherSource", primary,
        {{"rcz", fusionAlternative(8.0), five}}, rule("speed", "another", FusionRule::FillGaps)));
    cases.insert("fillGaps", fusionCase("fillGaps", primary, {{"rcz", fusionAlternative(), five}},
        rule("speed", "rcz", FusionRule::FillGaps)));
    cases.insert("fillGapsConflicting", fusionCase("fillGapsConflicting", primary, {{"rcz", fusionAlternative(8.0), five}},
        rule("speed", "rcz", FusionRule::FillGaps)));
    cases.insert("preferAlternative", fusionCase("preferAlternative", primary, {{"rcz", fusionAlternative(), five}},
        rule("speed", "rcz", FusionRule::PreferAlternative)));
    cases.insert("preferAlternativeDrift", fusionCase("preferAlternativeDrift", primary,
        {{"rcz", fusionAlternative(), {5.0, 1000.0}}}, rule("speed", "rcz", FusionRule::PreferAlternative)));
    cases.insert("fillGapsNegativeDrift", fusionCase("fillGapsNegativeDrift", primary,
        {{"rcz", fusionAlternative(), {5.0, -500.0}}}, rule("speed", "rcz", FusionRule::FillGaps)));
    cases.insert("drift", fusionCase("drift", primary, {{"rcz", fusionAlternative(), {5.0, 1000.0}}}));
    cases.insert("fractionalOffset", fusionCase("fractionalOffset", primary, {{"rcz", fusionAlternative(), {5.03, 0.0}}},
        rule("speed", "rcz", FusionRule::FillGaps)));
    for (const auto &status : {"ambiguous", "conflicting", "insufficient", ""})
        cases.insert(QStringLiteral("refused-") + status, fusionCase(QStringLiteral("refused-") + status, primary,
            {{"rcz", fusionAlternative(), five, QString::fromLatin1(status)}}));
    cases.insert("refusedNanClock", fusionCase("refusedNanClock", primary,
        {{"rcz", fusionAlternative(), {std::nan(""), 0.0}}}));
    cases.insert("refusedDrift", fusionCase("refusedDrift", primary, {{"rcz", fusionAlternative(), {5.0, -2e6}}}));
    cases.insert("refusedNull", fusionCase("refusedNull", primary, {{"rcz", std::nullopt, five}}));
    // Speed in m/s against km/h: not compared, not fused, never rescaled.
    cases.insert("unitMismatch", fusionCase("unitMismatch", primary, {{"rcz", fusionAlternative(0.0, "m/s"), five}},
        rule("speed", "rcz", FusionRule::FillGaps)));
    // Units compare trimmed and case-insensitively.
    cases.insert("unitCase", fusionCase("unitCase", primary, {{"rcz", fusionAlternative(0.0, " KM/H "), five}},
        rule("speed", "rcz", FusionRule::FillGaps)));
    // A unit only one side declares (KAN-184): agreeing values are compared and
    // fused, disagreeing ones are a unit mismatch.
    cases.insert("unitUndeclaredAgree", fusionCase("unitUndeclaredAgree", primary,
        {{"rcz", fusionAlternative(0.5, ""), five}}, rule("speed", "rcz", FusionRule::FillGaps)));
    cases.insert("unitUndeclaredConflict", fusionCase("unitUndeclaredConflict", primary,
        {{"rcz", fusionAlternative(8.0, ""), five}}, rule("speed", "rcz", FusionRule::FillGaps)));
    // Two alternatives: the second's rule applies while the first left the
    // channel the primary's; an added channel is not compared again.
    {
        auto second = fusionAlternative(8.0);
        add(second, makeChannel("throttle", "%", 0.0, 95.0, 10.0, [](double c) { return 50.0 + 50.0 * wave(0.2 * c); }),
            "throttle");
        cases.insert("twoAlternatives", fusionCase("twoAlternatives", primary,
            {{"rcz", fusionAlternative(0.3), five}, {"rcz2", second, {5.2, 0.0}}},
            rule("speed", "rcz2", FusionRule::PreferAlternative)));
        cases.insert("twoAlternativesRefusedFirst", fusionCase("twoAlternativesRefusedFirst", primary,
            {{"rcz", fusionAlternative(), five, "ambiguous"}, {"rcz2", second, {5.2, 0.0}}}));
    }
    // Keys and names: an alternative "velocity" without the speed alias is
    // neither added nor compared; lateral G under its alias is compared with
    // the primary's "latacc-calc".
    {
        TelemetrySession alternative;
        add(alternative, makeChannel("velocity", "km/h", 0.0, 90.0, 5.0, [](double c) { return fusionSpeed(c + 5.0); }));
        add(alternative, makeChannel("latacc", "G", 0.0, 90.0, 25.0, [](double c) { return wave(c + 5.0) + 0.2; }),
            "lateralAcceleration");
        add(alternative, makeChannel("speed", "km/h", 0.0, 90.0, 5.0, [](double c) { return fusionSpeed(c + 5.0); }));
        cases.insert("keysAndNames", fusionCase("keysAndNames", primary, {{"rcz", alternative, five}},
            rule("lateralAcceleration", "rcz", FusionRule::FillGaps)));
    }
    // Temperatures: "C" and, since KAN-184, "°C" have a fixed tolerance (2),
    // so a 2.2 difference conflicts in both.
    {
        auto withTemperatures = primary;
        add(withTemperatures, makeChannel("oil", "C", 0.0, 100.0, 1.0, [](double t) { return 100.0 + 0.5 * t; }));
        add(withTemperatures, makeChannel("water", "°C", 0.0, 100.0, 1.0, [](double t) { return 80.0 + 0.5 * t; }));
        TelemetrySession alternative;
        add(alternative, makeChannel("oil", "c", 0.0, 95.0, 1.0, [](double c) { return 100.0 + 0.5 * (c + 5.0) + 2.5; }));
        add(alternative, makeChannel("water", "°C", 0.0, 95.0, 1.0, [](double c) { return 80.0 + 0.5 * (c + 5.0) + 2.2; }));
        cases.insert("temperatures", fusionCase("temperatures", withTemperatures, {{"rcz", alternative, five}}));
    }
    // Missing values: NaN samples are not compared but are fused as samples.
    {
        TelemetrySession alternative;
        add(alternative, makeChannel("velocity", "km/h", 0.0, 90.0, 5.0,
            [](double c) { return c > 30.0 && c < 33.0 ? std::nan("") : fusionSpeed(c + 5.0); }), "speed");
        cases.insert("missingValues", fusionCase("missingValues", primary, {{"rcz", alternative, five}},
            rule("speed", "rcz", FusionRule::PreferAlternative)));
    }
    // KAN-188: RCZ gap markers mapped through a 3000 s offset round onto
    // their neighbours unless kept inside the gap; added, and preferred over
    // a primary that fills the gap.
    {
        TelemetrySession alternative;
        add(alternative, withGapMarkers(makeChannel("rpm-obd", "rpm", 1000.0, 1010.0, 10.0,
            [](double c) { return 3000.0 + c; }, [](double c) { return c < 1004.0 || c > 1006.0; }), 1.0), "rpm");
        TelemetrySession later;
        add(later, makeChannel("velocity", "km/h", 3990.0, 4020.0, 10.0, fusionSpeed), "speed");
        cases.insert("gapMarkersAdded", fusionCase("gapMarkersAdded", later, {{"rcz", alternative, {3000.0, 0.0}}}));
        add(later, makeChannel("rpm-obd", "rpm", 3990.0, 4020.0, 10.0, [](double t) { return t + 0.5; }), "rpm");
        cases.insert("gapMarkersPreferred", fusionCase("gapMarkersPreferred", later,
            {{"rcz", alternative, {3000.0, 0.0}}}, rule("rpm", "rcz", FusionRule::PreferAlternative)));
    }
    // KAN-188: a 1 Hz primary filled by a 10 Hz alternative with a 2 s gap; the
    // merged channel's own threshold (3 s) would bridge it, so it is marked.
    {
        TelemetrySession slow;
        add(slow, makeChannel("velocity", "km/h", 0.0, 400.0, 1.0, fusionSpeed,
            [](double t) { return t < 100.0 || t > 120.0; }), "speed");
        TelemetrySession fast;
        add(fast, makeChannel("velocity", "km/h", 0.0, 30.0, 10.0, [](double c) { return fusionSpeed(c + 95.0); },
            [](double c) { return c < 13.0 || c > 15.0; }), "speed");
        cases.insert("mergedGapMarkers", fusionCase("mergedGapMarkers", slow, {{"rcz", fast, {95.0, 0.0}}},
            rule("speed", "rcz", FusionRule::FillGaps)));
    }
    return cases;
}

QJsonArray tolerances()
{
    QJsonArray rows;
    for (const auto *unit : {"km/h", "KMH", " kph ", "%", "g", "G", "c", "C", "°C", "°c", "degc", "DegC", "rpm",
             "RPM", "bar", "m/s", ""}) {
        for (const double range : {50.0, 2.0, -4.0, 0.0}) {
            rows.append(QJsonArray{QString::fromUtf8(unit), number(range),
                number(fusionConflictTolerance(QString::fromUtf8(unit), range))});
        }
    }
    return rows;
}

// --- Real pairs (local only) --------------------------------------------------

FusionPolicy fillEveryCompared(const ChannelFusionResult &result, const QString &sourceId)
{
    FusionPolicy policy;
    for (const auto &channel : result.channels)
        if (!channel.comparedSourceId.isEmpty()) policy.rules.insert(channel.key, {sourceId, FusionRule::FillGaps});
    return policy;
}

QJsonObject realPair(const QString &primaryPath, const QString &alternativePath)
{
    QJsonObject object;
    try {
        const auto primary = VboParser::parseFile(primaryPath);
        const auto alternative = RczParser::parseFile(alternativePath);
        const auto alignment = alignRecordings(primary, alternative);
        object.insert("alignment", alignmentJson(alignment));
        if (!alignment.offset) return object;
        const SourceClock clock{*alignment.offset, alignment.driftPpm.value_or(0.0)};
        // The app fuses only an aligned pair; "forced" fuses the measured
        // clock anyway, to compare the fusion itself.
        const QString status = alignment.status == QLatin1String(alignmentAligned) ? alignment.status : "aligned";
        object.insert("forced", alignment.status != QLatin1String(alignmentAligned));
        const auto plain = fuseChannels(primary, "primary", {{"alternative", &alternative, clock, status}});
        object.insert("fusion", fusionJson(plain, false));
        const auto filled = fuseChannels(primary, "primary", {{"alternative", &alternative, clock, status}},
            fillEveryCompared(plain, "alternative"));
        object.insert("filled", fusionJson(filled, false));
        object.insert("filledSession", sessionDigest(fusedSession(primary, filled)));
    } catch (const std::exception &error) {
        object.insert("error", QString::fromUtf8(error.what()));
    }
    return object;
}

bool write(const QString &path, const QJsonObject &root)
{
    QFile output(path);
    if (!output.open(QIODevice::WriteOnly)) {
        std::fprintf(stderr, "Cannot write %s\n", qPrintable(path));
        return false;
    }
    output.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    return true;
}

} // namespace

int main(int argc, char **argv)
{
    if (argc == 4 && std::strcmp(argv[1], "--pairs") == 0) {
        QFile file(QString::fromLocal8Bit(argv[2]));
        if (!file.open(QIODevice::ReadOnly)) {
            std::fprintf(stderr, "Cannot read %s\n", argv[2]);
            return 1;
        }
        QJsonArray pairs;
        for (const auto &value : QJsonDocument::fromJson(file.readAll()).object().value("pairs").toArray()) {
            const auto pair = value.toObject();
            pairs.append(realPair(pair.value("primary").toString(), pair.value("alternative").toString()));
        }
        return write(QString::fromLocal8Bit(argv[3]), {{"pairs", pairs}}) ? 0 : 1;
    }
    if (argc != 2) {
        std::fprintf(stderr, "usage: cpp_fusion_dump <output.json>\n"
                             "       cpp_fusion_dump --pairs <pairs.json> <output.json>\n");
        return 2;
    }
    QJsonObject root{{"alignmentAlgorithm", QString::fromLatin1(recordingAlignmentAlgorithm)},
        {"fusionAlgorithm", QString::fromLatin1(channelFusionAlgorithm)}};
    root.insert("sync", syncCases());
    root.insert("alignment", alignmentCases());
    root.insert("fusion", fusionCases());
    root.insert("tolerances", tolerances());
    root.insert("inputs", inputs);
    return write(QString::fromLocal8Bit(argv[1]), root) ? 0 : 1;
}
