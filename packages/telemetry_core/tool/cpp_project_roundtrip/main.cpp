// Drives FlappedEar Overlays' own document and analysis controllers headless
// (TelemetryController: DocumentController and AnalysisController, as
// Overlays' own TelemetryAppTests do) and prints JSON:
//
//   cpp_project_roundtrip fingerprint <recording>...
//       Overlays' telemetry-v1 fingerprint of each VBO or RCZ recording
//       (TelemetrySource::load, ProjectSourceReferenceCodec::telemetryFingerprint),
//       or the error Overlays reports.
//   cpp_project_roundtrip create <project> <name> <recording>...
//       Overlays imports the recordings as a day ("Session N"), approves the
//       best lap's segments automatically (as the Overlays app does), renames
//       one segment and merges two, excludes a lap, writes notes, conditions
//       and setup changes on the first session, saves the comparison group,
//       pair, range and channels, and saves the day at <project>. The
//       editor state of Overlays' overlay editor (a run's sync and video, the
//       chart channels and the widget scene) is then added as Overlays'
//       TelemetryAppTests add it, and Overlays opens and saves the day again.
//   cpp_project_roundtrip resave <project> [<target>]
//       Overlays opens the day and saves it, at <target> when given (Save As).
//   cpp_project_roundtrip inspect <project>...
//       What Overlays sees in each day: validity, identity, runs with their
//       metadata and approved segments, every lap section with its group and
//       exclusion, the group shown and the day report's headline results. A
//       run with a `fusion` decision also gets what Overlays applies (FET-55).
//   cpp_project_roundtrip import <project> <name> <recording>...
//       Overlays imports the recordings as a day and saves it, nothing else.
//   cpp_project_roundtrip attach <project> <run> <recording>
//       Overlays adds the recording to the run (its id or 1-based position)
//       as an alternative, as Run details does (KAN-90: attachRunRecording,
//       the match evidence, confirmRunRecording), and saves the day.
//   cpp_project_roundtrip fuse <project> <run> [<channel key>=<rule>...]
//       Overlays reviews fusing the run's alternative recording into it and
//       approves the fusion with the given rules (KAN-103: reviewRunFusion,
//       approveRunFusion; a rule is primaryOnly, fillGaps or
//       preferAlternative; "*=<rule>" gives every other conflicting channel
//       that rule), and saves the day.
//
// Nothing is copied from Overlays: its sources are compiled from a read-only
// checkout (see CMakeLists.txt).

#include "app/TelemetryController.h"
#include "project/BoundedJsonLoader.h"
#include "project/EventProjectCodec.h"
#include "project/ProjectLimits.h"
#include "project/ProjectSourceReference.h"
#include "telemetry/ChannelFusion.h"
#include "telemetry/OutingLapLoader.h"
#include "telemetry/TelemetrySessionCache.h"
#include "telemetry/TelemetrySource.h"
#include "telemetry/TrackSegments.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QThread>
#include <QUrl>
#include <QtEndian>
#include <algorithm>
#include <cstdio>
#include <exception>
#include <functional>

using namespace FlappedEar;

namespace {

[[noreturn]] void fail(const QString &message)
{
    std::fprintf(stderr, "%s\n", message.toLocal8Bit().constData());
    std::exit(2);
}

bool waitFor(const std::function<bool()> &condition, const int timeoutMs)
{
    QElapsedTimer timer;
    timer.start();
    while (!condition()) {
        if (timer.elapsed() > timeoutMs) return false;
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        QThread::msleep(2);
    }
    return true;
}

// Waits until the controllers have nothing running for a short while: laps,
// automatic segments and every other worker.
void settle(TelemetryController &controller, const int timeoutMs = 600'000)
{
    auto &document = *controller.document();
    auto &analysis = *controller.analysis();
    QElapsedTimer quiet;
    quiet.start();
    const bool done = waitFor([&] {
        if (document.projectLoading() || document.importRunning() || analysis.outingLapsLoading()
            || analysis.workRunning())
            quiet.restart();
        return quiet.elapsed() > 300;
    }, timeoutMs);
    if (!done) fail(QStringLiteral("Overlays did not settle."));
}

QJsonObject readJson(const QString &path)
{
    const auto loaded = BoundedJsonLoader::loadFile(path, ProjectLimits::projectBytes, QStringLiteral("Project"));
    if (!loaded.success() || !loaded.document.isObject()) fail(QStringLiteral("Cannot read %1: %2").arg(path, loaded.error));
    return loaded.document.object();
}

void writeJson(const QString &path, const QJsonObject &object)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) fail(QStringLiteral("Cannot write %1").arg(path));
    file.write(QJsonDocument(object).toJson());
}

// A fresh controller, with its recovery file in [scratch]. Automatic segments
// are on, as in the Overlays app (main.cpp).
std::unique_ptr<TelemetryController> newController(const QTemporaryDir &scratch)
{
    auto controller = std::make_unique<TelemetryController>(scratch.filePath(QStringLiteral("recovery.json")));
    controller->analysis()->setAutomaticSegments(true);
    return controller;
}

void open(TelemetryController &controller, const QString &path)
{
    controller.document()->requestOpenProject(QUrl::fromLocalFile(path));
    if (!waitFor([&] { return !controller.document()->eventRuns().isEmpty()
                       || !controller.document()->projectLoadError().isEmpty(); }, 60'000)
        || controller.document()->eventRuns().isEmpty())
        fail(QStringLiteral("Overlays could not open %1: %2").arg(path, controller.document()->projectLoadError()));
    settle(controller);
}

void save(TelemetryController &controller, const QString &path)
{
    if (!controller.document()->saveProject(QUrl::fromLocalFile(path)))
        fail(QStringLiteral("Overlays could not save %1: %2").arg(path, controller.statusText()));
}

QVariantMap reportResult(const QVariantMap &report, const QString &id)
{
    for (const auto &value : report.value("results").toList())
        if (value.toMap().value("id") == id) return value.toMap();
    return {};
}

bool reportSettled(const QVariantMap &report)
{
    if (report.value("results").toList().isEmpty()) return false;
    for (const auto &value : report.value("results").toList()) {
        const auto status = value.toMap().value("status").toString();
        if (status == "notComputed" || status == "computing" || status == "stale") return false;
    }
    return true;
}

// 64-bit FNV-1a over the little-endian bytes of every timestamp (double),
// then every value (float), as cpp_fusion_dump writes a channel.
QString channelDigest(const TelemetryChannel &channel)
{
    quint64 hash = 0xcbf29ce484222325ULL;
    const auto feed = [&hash](const uchar *bytes, int count) {
        for (int i = 0; i < count; ++i) hash = (hash ^ bytes[i]) * 0x100000001b3ULL;
    };
    for (const double time : channel.timestamps) {
        uchar bytes[8];
        qToLittleEndian(time, bytes);
        feed(bytes, 8);
    }
    for (const float value : channel.values) {
        uchar bytes[4];
        qToLittleEndian(value, bytes);
        feed(bytes, 4);
    }
    return QStringLiteral("%1").arg(hash, 16, 16, QLatin1Char('0'));
}

QString resolvedSource(const QJsonObject &run, const QString &sourceId, const QString &projectPath)
{
    for (const auto &value : run.value("sources").toObject().value("telemetry").toArray()) {
        const auto source = value.toObject();
        if (source.value("id").toString() != sourceId) continue;
        const auto json = source.value("reference").toObject();
        return ProjectSourceReferenceCodec::resolve({json.value("relativePath").toString(),
            json.value("absolutePath").toString(), json.value("fingerprint").toObject()}, projectPath);
    }
    return {};
}

// What Overlays does with a run's `fusion` decision (KAN-103): whether Run
// details shows it applied, the decision itself, and the run's session as
// Overlays' analysis loads it (loadOutingLapDetail with the descriptor
// outingLapSources gives, which carries the decision only while it is bound
// to both recordings): every channel's name, unit, sample count and digest.
// "origins" are the channels that take samples from the alternative, by name,
// with their rule: Overlays' fuseChannels with the decision's clock and
// rules, as loadOutingLapDetail calls it.
QJsonObject inspectFusion(TelemetryController &controller, const QJsonObject &run)
{
    auto &document = *controller.document();
    auto &analysis = *controller.analysis();
    const auto runId = run.value("id").toString();
    const auto decision = run.value("fusion").toObject();
    QJsonObject result{{"decision", decision}};
    for (const auto &value : document.runRecordings(runId)) {
        const auto row = value.toMap();
        if (row.contains("fusion")) result.insert("state", row.value("fusion").toString());
    }
    QJsonObject descriptor;
    for (const auto &value : analysis.outingLapSources())
        if (value.toObject().value("runId").toString() == runId) descriptor = value.toObject();
    result.insert("applied", descriptor.contains("fusion"));
    if (!descriptor.contains("fusion")) return result;
    QVariantMap lap;
    for (const auto &value : analysis.outingLaps())
        if (value.toMap().value("runId").toString() == runId) { lap = value.toMap(); break; }
    if (lap.isEmpty()) fail(QStringLiteral("The fused run has no lap section."));
    const auto detail = loadOutingLapDetail(descriptor, document.documentPath(), lap, 0,
        std::make_shared<std::atomic_bool>(false), std::make_shared<TelemetrySessionCache>());
    if (!detail.session) fail(QStringLiteral("Overlays could not load the fused run: %1").arg(detail.error));
    QJsonObject channels;
    for (auto it = detail.session->channels.cbegin(); it != detail.session->channels.cend(); ++it)
        channels.insert(it.key(), QJsonObject{{"name", it->name}, {"unit", it->unit},
            {"count", it->timestamps.size()}, {"digest", channelDigest(*it)}});
    result.insert("channels", channels);

    const auto projectPath = document.documentPath();
    const auto primaryId = run.value("primaryTelemetrySourceId").toString();
    const auto alternativeId = decision.value("alternativeSourceId").toString();
    const auto primary = TelemetrySource::load(resolvedSource(run, primaryId, projectPath));
    const auto alternative = TelemetrySource::load(resolvedSource(run, alternativeId, projectPath));
    FusionPolicy policy;
    for (const auto &value : decision.value("rules").toArray()) {
        const auto rule = value.toObject().value("rule").toString();
        policy.rules.insert(value.toObject().value("key").toString(), {alternativeId,
            rule == QLatin1String("fillGaps") ? FusionRule::FillGaps
            : rule == QLatin1String("preferAlternative") ? FusionRule::PreferAlternative : FusionRule::PrimaryOnly});
    }
    const auto clock = decision.value("clock").toObject();
    const auto fused = fuseChannels(primary, primaryId, {{alternativeId, &alternative,
        {clock.value("offsetSeconds").toDouble(), clock.value("driftPpm").toDouble()}, QStringLiteral("aligned")}}, policy);
    QJsonObject origins;
    for (const auto &channel : fused.channels)
        if (channel.rule == QLatin1String("added") || channel.rule == QLatin1String("fillGaps")
            || channel.rule == QLatin1String("preferAlternative"))
            origins.insert(channel.name, channel.rule);
    result.insert("origins", origins);
    return result;
}

QJsonObject inspectOpened(TelemetryController &controller, const QString &path)
{
    auto &document = *controller.document();
    auto &analysis = *controller.analysis();
    const QJsonObject project = document.storedProject();
    const QJsonObject event = project.value("event").toObject();
    QJsonObject result{{"file", QFileInfo(path).fileName()}, {"valid", true},
                       {"documentState", project.value("documentState")},
                       {"eventId", event.value("id")}, {"eventName", event.value("name")},
                       {"dirty", document.dirty()},
                       {"comparisonGroupId", analysis.outingComparisonGroupId()},
                       {"comparisonSelectionState", analysis.outingComparisonSelectionState()},
                       {"messages", QJsonArray::fromStringList(analysis.outingLapMessages())}};
    QJsonArray runs;
    for (const auto &value : event.value("runs").toArray()) {
        const auto run = value.toObject();
        const auto metadata = analysis.runMetadata(run.value("id").toString());
        const auto segments = run.value("trackSegments").toArray();
        QJsonArray names;
        for (const auto &segment : segments) names.append(segment.toObject().value("name"));
        QJsonObject item{{"id", run.value("id")}, {"name", metadata.value("name").toString()},
            {"trackSegments", QJsonObject{{"valid", validTrackSegments(run.value("trackSegments"))},
                {"count", segments.size()}, {"names", names},
                {"revision", segments.isEmpty() ? QString() : trackSegmentSetRevision(segments)}}}};
        for (const auto *key : {"notes", "conditions", "setupChanges"})
            item.insert(key, QJsonValue::fromVariant(metadata.value(key)));
        QJsonArray recordings;
        for (const auto &recording : document.runRecordings(run.value("id").toString())) {
            const auto row = recording.toMap();
            recordings.append(QJsonObject{{"sourceId", row.value("sourceId").toString()},
                {"format", row.value("format").toString()}, {"primary", row.value("primary").toBool()},
                {"available", row.value("available").toBool()}});
        }
        item.insert("recordings", recordings);
        if (run.contains("fusion")) item.insert("fusion", inspectFusion(controller, run));
        runs.append(item);
    }
    result.insert("runs", runs);
    QJsonArray laps;
    for (const auto &value : analysis.outingLaps()) {
        const auto row = value.toMap();
        laps.append(QJsonObject{{"runId", row.value("runId").toString()},
            {"label", QStringLiteral("%1 · %2 %3").arg(row.value("runName").toString(), row.value("type").toString())
                          .arg(row.value("lapNumber").toInt())},
            {"type", row.value("type").toString()}, {"lapNumber", row.value("lapNumber").toInt()},
            {"startTime", row.value("startTime").toDouble()}, {"endTime", row.value("endTime").toDouble()},
            {"excluded", row.value("excluded").toBool()}, {"exclusionReason", row.value("exclusionReason").toString()},
            {"groupId", row.value("compatibilityGroupId").toString()},
            {"referenceEligible", row.value("referenceEligible").toBool()},
            {"bestOfDay", row.value("bestOfDay").toBool()}});
    }
    result.insert("laps", laps);
    analysis.requestOutingDayReport();
    if (!waitFor([&] { return reportSettled(analysis.outingDayReport()); }, 600'000))
        fail(QStringLiteral("The day report did not settle for %1").arg(path));
    const auto report = analysis.outingDayReport();
    const auto best = reportResult(report, "bestLap");
    const auto theoretical = reportResult(report, "theoreticalBest");
    result.insert("report", QJsonObject{
        {"bestLap", QJsonObject{{"status", best.value("status").toString()},
            {"seconds", best.value("value").toMap().value("seconds").toDouble()},
            {"label", best.value("value").toMap().value("label").toString()}}},
        {"theoreticalBest", QJsonObject{{"status", theoretical.value("status").toString()},
            {"totalSeconds", theoretical.value("value").toMap().value("totalSeconds").toDouble()}}},
        {"eligibleLaps", reportResult(report, "consistency").value("value").toMap().value("day").toMap()
             .value("count").toInt()}});
    return result;
}

QJsonObject inspect(const QString &path, const QTemporaryDir &scratch)
{
    const QJsonObject project = readJson(path);
    QString error;
    if (!ProjectLimits::validateProject(project, &error))
        return {{"file", QFileInfo(path).fileName()}, {"valid", false}, {"error", error}};
    auto controller = newController(scratch);
    open(*controller, path);
    return inspectOpened(*controller, path);
}

QJsonArray fingerprints(const QStringList &paths)
{
    QJsonArray results;
    for (const auto &path : paths) {
        QJsonObject item{{"file", path}};
        try {
            const auto session = TelemetrySource::load(path);
            item.insert("fingerprint", ProjectSourceReferenceCodec::telemetryFingerprint(path, session));
        } catch (const std::exception &error) {
            item.insert("error", QString::fromUtf8(error.what()));
        }
        results.append(item);
    }
    return results;
}

QVariantMap lapRow(AnalysisController &analysis, const std::function<bool(const QVariantMap &)> &matches)
{
    for (const auto &value : analysis.outingLaps())
        if (matches(value.toMap())) return value.toMap();
    return {};
}

void create(const QString &path, const QString &name, const QStringList &recordings, const QTemporaryDir &scratch)
{
    {
        auto controller = newController(scratch);
        auto &document = *controller->document();
        auto &analysis = *controller->analysis();
        int committed = 0;
        QObject::connect(&document, &DocumentController::batchImportCommitted, [&committed] { ++committed; });
        QList<QUrl> urls;
        for (const auto &recording : recordings) urls.append(QUrl::fromLocalFile(QFileInfo(recording).absoluteFilePath()));
        if (!document.importAnalysisRuns(name, urls)) fail(QStringLiteral("Overlays refused the import: %1").arg(document.batchImportError()));
        if (!waitFor([&] { return committed > 0 || !document.batchImportError().isEmpty(); }, 120'000) || committed == 0)
            fail(QStringLiteral("Overlays did not import the day: %1").arg(document.batchImportError()));
        settle(*controller);
        const QString group = analysis.outingComparisonGroupId();
        if (group.isEmpty()) fail(QStringLiteral("Overlays found no comparison group."));
        if (!waitFor([&] {
                for (const auto &value : document.storedProject().value("event").toObject().value("runs").toArray())
                    if (!value.toObject().value("trackSegments").toArray().isEmpty()) return true;
                return false;
            }, 120'000))
            fail(QStringLiteral("Overlays approved no automatic segments."));
        settle(*controller);

        // The best lap's segment review: rename the first segment, merge the next two.
        const auto best = analysis.outingRanking().value("bestOfDay").toMap();
        if (!analysis.selectOutingLapReference(best.value("reference").toMap())) fail(QStringLiteral("Cannot open the best lap."));
        if (!waitFor([&] { return analysis.outingLapDetailState() == "ready"; }, 120'000)) fail(QStringLiteral("The best lap did not load."));
        analysis.requestSegmentReview();
        if (!waitFor([&] { return analysis.segmentReviewState() == "ready"; }, 120'000)) fail(QStringLiteral("The segment review did not load."));
        auto segments = analysis.segmentReviewApproved().value("segments").toList();
        if (segments.size() < 3) fail(QStringLiteral("Too few segments to edit."));
        const auto first = segments.first().toMap();
        QString error = analysis.editApprovedSegment(first.value("id").toString(), QStringLiteral("Hairpin (Overlays)"),
            first.value("type").toString(), first.value("startMeters").toDouble(), first.value("endMeters").toDouble(), true);
        if (!error.isEmpty()) fail(QStringLiteral("Rename refused: %1").arg(error));
        segments = analysis.segmentReviewApproved().value("segments").toList();
        error = analysis.mergeApprovedSegments(segments[1].toMap().value("id").toString(), segments[2].toMap().value("id").toString());
        if (!error.isEmpty()) fail(QStringLiteral("Merge refused: %1").arg(error));
        analysis.closeOutingLap();
        settle(*controller);

        // Exclude the first eligible lap that is not the best of the day.
        const auto excluded = lapRow(analysis, [](const QVariantMap &row) {
            return row.value("type") == "LAP" && row.value("referenceEligible").toBool() && !row.value("bestOfDay").toBool();
        });
        if (excluded.isEmpty() || !analysis.setOutingLapExcluded(excluded.value("reference").toMap(), true, QStringLiteral("Traffic")))
            fail(QStringLiteral("Cannot exclude a lap."));
        settle(*controller);

        const auto runId = document.eventRuns().first().toMap().value("id").toString();
        const auto metadata = analysis.runMetadata(runId);
        if (!analysis.updateRunMetadata(runId, metadata.value("editToken").toString(), metadata.value("name").toString(),
                QStringLiteral("Synthetic notes"), QStringLiteral("Dry, 18 °C"), QStringLiteral("Tyres +0.1 bar")))
            fail(QStringLiteral("Cannot write the run's notes."));
        settle(*controller);

        if (!analysis.selectOutingComparisonGroup(analysis.outingComparisonGroupId())) fail(QStringLiteral("Cannot save the group."));
        const auto partner = lapRow(analysis, [](const QVariantMap &row) {
            return row.value("type") == "LAP" && row.value("referenceEligible").toBool() && !row.value("bestOfDay").toBool()
                && !row.value("excluded").toBool();
        });
        const auto bestNow = analysis.outingRanking().value("bestOfDay").toMap();
        analysis.selectComparisonLap(0, bestNow.value("reference").toMap());
        if (!partner.isEmpty()) analysis.selectComparisonLap(1, partner.value("reference").toMap());
        analysis.persistComparisonRange(10.0, 120.5);
        analysis.persistComparisonChannels({QStringLiteral("velocity")});
        settle(*controller);
        save(*controller, path);
        settle(*controller);
    }

    // The overlay editor's state, as Overlays' TelemetryAppTests write it, then
    // one more open and save by Overlays.
    auto project = readJson(path);
    auto event = project.value("event").toObject();
    auto runs = event.value("runs").toArray();
    auto run = runs[0].toObject();
    run.insert("sync", QJsonObject{{"offset", 12.5}, {"timeScale", 1.0}});
    auto runSources = run.value("sources").toObject();
    runSources.insert("video", QJsonObject{{"relativePath", "clip.mp4"}});
    run.insert("sources", runSources);
    runs[0] = run;
    event.insert("runs", runs);
    project.insert("event", event);
    project.insert("analysis", QJsonObject{{"channels", QJsonArray{"speed"}}});
    project.insert("scene", QJsonObject{{"widgets", QJsonArray{}}});
    QString error;
    if (!ProjectLimits::validateProject(project, &error)) fail(QStringLiteral("Editor state refused: %1").arg(error));
    writeJson(path, project);
    auto controller = newController(scratch);
    open(*controller, path);
    save(*controller, path);
    settle(*controller);
}

// Overlays imports [recordings] as a day and saves it at [path].
void importDay(const QString &path, const QString &name, const QStringList &recordings, const QTemporaryDir &scratch)
{
    auto controller = newController(scratch);
    auto &document = *controller->document();
    int committed = 0;
    QObject::connect(&document, &DocumentController::batchImportCommitted, [&committed] { ++committed; });
    QList<QUrl> urls;
    for (const auto &recording : recordings) urls.append(QUrl::fromLocalFile(QFileInfo(recording).absoluteFilePath()));
    if (!document.importAnalysisRuns(name, urls)) fail(QStringLiteral("Overlays refused the import: %1").arg(document.batchImportError()));
    if (!waitFor([&] { return committed > 0 || !document.batchImportError().isEmpty(); }, 120'000) || committed == 0)
        fail(QStringLiteral("Overlays did not import the day: %1").arg(document.batchImportError()));
    settle(*controller);
    save(*controller, path);
    settle(*controller);
}

// The id of [run]: a run id of the day, or its 1-based position.
QString runIdOf(DocumentController &document, const QString &run)
{
    const auto runs = document.eventRuns();
    bool number = false;
    const int position = run.toInt(&number);
    if (number && position >= 1 && position <= runs.size()) return runs[position - 1].toMap().value("id").toString();
    for (const auto &value : runs)
        if (value.toMap().value("id").toString() == run) return run;
    fail(QStringLiteral("No run %1 in the day.").arg(run));
}

QString reviewState(DocumentController &document) { return document.runRecordingReview().value("state").toString(); }

// Overlays attaches [recording] to [run] as an alternative and saves the day.
QJsonObject attach(const QString &path, const QString &run, const QString &recording, const QTemporaryDir &scratch)
{
    auto controller = newController(scratch);
    auto &document = *controller->document();
    open(*controller, path);
    const auto runId = runIdOf(document, run);
    if (!document.attachRunRecording(runId, QUrl::fromLocalFile(QFileInfo(recording).absoluteFilePath())))
        fail(QStringLiteral("Overlays refused to attach: %1").arg(document.runRecordingReview().value("message").toString()));
    if (!waitFor([&] { return reviewState(document) == "review" || reviewState(document) == "error"; }, 120'000)
        || reviewState(document) != "review")
        fail(QStringLiteral("Overlays did not offer the recording: %1").arg(document.runRecordingReview().value("message").toString()));
    const auto evidence = QJsonObject::fromVariantMap(document.runRecordingReview().value("evidence").toMap());
    if (!document.confirmRunRecording()) fail(QStringLiteral("Overlays refused to confirm the recording."));
    if (!waitFor([&] { return reviewState(document) != "attaching"; }, 120'000) || !reviewState(document).isEmpty())
        fail(QStringLiteral("Overlays did not add the recording: %1").arg(document.runRecordingReview().value("message").toString()));
    settle(*controller);
    save(*controller, path);
    settle(*controller);
    return {{"runId", runId}, {"evidence", evidence}};
}

// Overlays reviews fusing [run]'s alternative recording, approves it with
// [rules] ("key=rule") and saves the day.
QJsonObject fuse(const QString &path, const QString &run, const QStringList &rules, const QTemporaryDir &scratch)
{
    auto controller = newController(scratch);
    auto &document = *controller->document();
    open(*controller, path);
    const auto runId = runIdOf(document, run);
    QString alternativeId;
    for (const auto &value : document.runRecordings(runId))
        if (!value.toMap().value("primary").toBool()) alternativeId = value.toMap().value("sourceId").toString();
    if (alternativeId.isEmpty()) fail(QStringLiteral("The run has no alternative recording."));
    if (!document.reviewRunFusion(runId, alternativeId))
        fail(QStringLiteral("Overlays refused the review: %1").arg(document.runRecordingReview().value("message").toString()));
    if (!waitFor([&] { return reviewState(document) == "fusionReview" || reviewState(document) == "error"; }, 120'000)
        || reviewState(document) != "fusionReview")
        fail(QStringLiteral("Overlays did not review the fusion: %1").arg(document.runRecordingReview().value("message").toString()));
    const auto review = document.runRecordingReview();
    QVariantMap chosen;
    for (const auto &rule : rules) {
        const auto parts = rule.split(QLatin1Char('='));
        if (parts.size() != 2) fail(QStringLiteral("A rule is <channel key>=<rule>: %1").arg(rule));
        chosen.insert(parts[0], parts[1]);
    }
    // "*=<rule>": that rule for every other conflicting channel.
    if (chosen.contains(QStringLiteral("*"))) {
        const auto rule = chosen.take(QStringLiteral("*"));
        for (const auto &key : review.value("preview").toMap().value("conflicts").toStringList())
            if (!chosen.contains(key)) chosen.insert(key, rule);
    }
    if (!document.approveRunFusion(chosen))
        fail(QStringLiteral("Overlays refused to approve the fusion (approvable %1, conflicts %2): %3")
                 .arg(review.value("preview").toMap().value("approvable").toBool())
                 .arg(review.value("preview").toMap().value("conflicts").toStringList().join(QLatin1Char(',')),
                      document.runRecordingReview().value("message").toString()));
    settle(*controller);
    save(*controller, path);
    settle(*controller);
    return {{"runId", runId}, {"alternativeSourceId", alternativeId},
            {"alignment", QJsonObject::fromVariantMap(review.value("alignment").toMap())},
            {"preview", QJsonObject::fromVariantMap(review.value("preview").toMap())}};
}

void print(const QJsonValue &value)
{
    const QByteArray json = value.isArray() ? QJsonDocument(value.toArray()).toJson(QJsonDocument::Indented)
                                            : QJsonDocument(value.toObject()).toJson(QJsonDocument::Indented);
    std::fwrite(json.constData(), 1, json.size(), stdout);
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    // Overlays' controllers remember the last project in QSettings: keep that
    // away from any real installation.
    QStandardPaths::setTestModeEnabled(true);
    QCoreApplication::setOrganizationName(QStringLiteral("FlappedEarRoundtrip"));
    QCoreApplication::setApplicationName(QStringLiteral("cpp_project_roundtrip"));
    QSettings().clear();
    const QStringList arguments = application.arguments().mid(1);
    if (arguments.isEmpty()) fail(QStringLiteral("usage: cpp_project_roundtrip fingerprint|create|resave|inspect|import|attach|fuse ..."));
    QTemporaryDir scratch;
    if (!scratch.isValid()) fail(QStringLiteral("No temporary folder."));
    const QString command = arguments.first();
    if (command == "fingerprint") {
        print(fingerprints(arguments.mid(1)));
    } else if (command == "create" && arguments.size() >= 4) {
        create(arguments[1], arguments[2], arguments.mid(3), scratch);
        print(inspect(arguments[1], scratch));
    } else if (command == "resave" && (arguments.size() == 2 || arguments.size() == 3)) {
        const QString target = arguments.size() == 3 ? arguments[2] : arguments[1];
        QJsonObject before;
        {
            auto controller = newController(scratch);
            open(*controller, arguments[1]);
            before = inspectOpened(*controller, arguments[1]);
            save(*controller, target);
            settle(*controller);
        }
        print(QJsonObject{{"opened", before}, {"saved", inspect(target, scratch)}});
    } else if (command == "import" && arguments.size() >= 4) {
        importDay(arguments[1], arguments[2], arguments.mid(3), scratch);
        print(inspect(arguments[1], scratch));
    } else if (command == "attach" && arguments.size() == 4) {
        auto result = attach(arguments[1], arguments[2], arguments[3], scratch);
        result.insert("inspected", inspect(arguments[1], scratch));
        print(result);
    } else if (command == "fuse" && arguments.size() >= 3) {
        auto result = fuse(arguments[1], arguments[2], arguments.mid(3), scratch);
        result.insert("inspected", inspect(arguments[1], scratch));
        print(result);
    } else if (command == "inspect") {
        QJsonArray results;
        for (const auto &path : arguments.mid(1)) results.append(inspect(path, scratch));
        print(results);
    } else {
        fail(QStringLiteral("usage: cpp_project_roundtrip fingerprint|create|resave|inspect|import|attach|fuse ..."));
    }
    QSettings().clear();
    return 0;
}
