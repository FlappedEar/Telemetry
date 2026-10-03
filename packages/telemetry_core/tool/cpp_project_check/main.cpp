// Prints what FlappedEar Overlays sees in each .fetproject as one JSON document:
//   cpp_project_check <project.fetproject>...
// Each document is loaded and validated as Overlays opens it. For each run,
// the primary VBO recording is resolved, parsed and given its laps; the run's
// lap exclusions are applied with the binding Overlays builds, and the
// excluded laps are listed, with its approved segments (valid, count,
// revision). The event is also passed through Overlays'
// editor projection and back, as a re-save does, and compared.

#include "project/BoundedJsonLoader.h"
#include "project/EventProjectCodec.h"
#include "project/ProjectLimits.h"
#include "project/ProjectSourceReference.h"
#include "telemetry/LapTiming.h"
#include "telemetry/OutingLaps.h"
#include "telemetry/TrackSegmentReview.h"
#include "telemetry/TrackSegments.h"
#include "telemetry/VboParser.h"

#include <QCryptographicHash>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <cstdio>
#include <exception>

using namespace FlappedEar;

namespace {

QByteArray fileSha256(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return {};
    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(&file);
    return hash.result().toHex();
}

QString fingerprintMatch(SourceFingerprintMatch match)
{
    switch (match) {
    case SourceFingerprintMatch::Match: return "match";
    case SourceFingerprintMatch::Mismatch: return "mismatch";
    case SourceFingerprintMatch::Unknown: break;
    }
    return "unknown";
}

QJsonObject checkRun(const QJsonObject &event, const QJsonObject &run, const QString &projectPath)
{
    QJsonObject result{{"runId", run.value("id")},
                       {"derivationKey", QString::fromLatin1(EventProjectCodec::lapDerivationKey(run))},
                       {"trackConfiguration", EventProjectCodec::trackConfiguration(run)}};
    // The approved segments as Overlays reads them: valid, how many, and the
    // revision a segment result is stamped with.
    const auto segments = run.value("trackSegments");
    result.insert("trackSegments", QJsonObject{{"valid", validTrackSegments(segments)},
        {"count", segments.toArray().size()},
        {"revision", segments.toArray().isEmpty() ? QString() : trackSegmentSetRevision(segments.toArray())}});
    QJsonObject source;
    for (const auto &value : run.value("sources").toObject().value("telemetry").toArray()) {
        if (value.toObject().value("id") == run.value("primaryTelemetrySourceId")) source = value.toObject();
    }
    result.insert("expectedRevision", QString::fromLatin1(EventProjectCodec::sourceContentRevision(source)));
    const auto reference = ProjectSourceReferenceCodec::fromProject(
        QJsonObject{{"sources", QJsonObject{{"primary", source.value("reference")}}}}, "primary", {});
    const QString path = ProjectSourceReferenceCodec::resolve(reference, projectPath);
    result.insert("resolved", !path.isEmpty());
    if (path.isEmpty()) return result;
    const QByteArray revision = fileSha256(path);
    result.insert("contentRevision", QString::fromLatin1(revision));
    try {
        const TelemetrySession session = VboParser::parseFile(path);
        result.insert("fingerprint", fingerprintMatch(ProjectSourceReferenceCodec::compareFingerprints(
            reference.fingerprint, ProjectSourceReferenceCodec::telemetryFingerprint(path, session))));
        LapSession laps = deriveSourceLapSession(session);
        const QJsonObject binding{{"eventId", event.value("id")}, {"runId", run.value("id")},
                                  {"sourceId", source.value("id")},
                                  {"sourceRevision", QString::fromLatin1(revision)},
                                  {"derivationKey", result.value("derivationKey")}};
        applyLapExclusions(laps, binding, event.value("lapExclusions").toArray());
        QJsonArray excluded;
        for (const auto &lap : laps.timedLaps) {
            if (lap.userExclusionReason.isEmpty()) continue;
            excluded.append(QJsonObject{{"start", lap.startTelemetryTime}, {"end", lap.endTelemetryTime},
                                        {"reason", lap.userExclusionReason}});
        }
        result.insert("timedLaps", laps.timedLaps.size());
        result.insert("excludedLaps", excluded);
    } catch (const std::exception &error) {
        result.insert("error", QString::fromUtf8(error.what()));
    }
    return result;
}

QJsonObject checkProject(const QString &path)
{
    QJsonObject result{{"file", path}};
    const auto loaded = BoundedJsonLoader::loadFile(path, ProjectLimits::projectBytes, "Project");
    if (!loaded.success() || !loaded.document.isObject()) {
        result.insert("valid", false);
        result.insert("error", loaded.error);
        return result;
    }
    const QJsonObject project = loaded.document.object();
    QString error;
    const bool valid = ProjectLimits::validateProject(project, &error);
    result.insert("valid", valid);
    if (!valid) {
        result.insert("error", error);
        return result;
    }
    result.insert("documentState", project.value("documentState"));
    const QJsonObject event = project.value("event").toObject();
    QJsonArray runs;
    for (const auto &value : event.value("runs").toArray()) runs.append(checkRun(event, value.toObject(), path));
    result.insert("runs", runs);
    const QJsonObject resaved = EventProjectCodec::withEditorState(
        project, EventProjectCodec::editorProjection(project), path, path);
    result.insert("resaveKeepsEvent", resaved.value("event") == project.value("event"));
    return result;
}

} // namespace

int main(int argc, char **argv)
{
    QJsonArray results;
    for (int i = 1; i < argc; ++i) results.append(checkProject(QString::fromLocal8Bit(argv[i])));
    const QByteArray json = QJsonDocument(results).toJson(QJsonDocument::Indented);
    std::fwrite(json.constData(), 1, json.size(), stdout);
    return 0;
}
