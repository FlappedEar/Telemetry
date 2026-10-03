# Builds a command-line tool that runs FlappedEar Overlays' C++ segment
# editing and review code (TrackSegmentEditing, TrackSegmentReview) over the
# automatic segments of input files and fixed cases and prints the results as
# JSON. The Dart port is checked against that output. Not part of the app or of CI: it needs a local
# checkout of FlappedEar/Overlay and Qt 6.8 (see README.md).
cmake_minimum_required(VERSION 3.24)
project(cpp_segment_editing_dump LANGUAGES CXX)

set(VBOOVERLAY_DIR "" CACHE PATH "Path to a FlappedEar/Overlay checkout")
if(NOT EXISTS "${VBOOVERLAY_DIR}/native/src/telemetry/TrackSegmentEditing.cpp")
    message(FATAL_ERROR "Set VBOOVERLAY_DIR to a FlappedEar/Overlay checkout")
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Core)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(src "${VBOOVERLAY_DIR}/native/src")

# coverageGaps and the automatic-approval loop live in Overlays' app sources,
# which need the whole Qt Quick app to compile. Their text is copied out of
# the checkout at configure time, unchanged, into a generated header.
function(extract_between file first last out)
    file(READ "${file}" text)
    string(FIND "${text}" "${first}" begin)
    if(begin EQUAL -1)
        message(FATAL_ERROR "'${first}' not found in ${file}")
    endif()
    string(SUBSTRING "${text}" ${begin} -1 rest)
    string(FIND "${rest}" "${last}" end)
    if(end EQUAL -1)
        message(FATAL_ERROR "'${last}' not found after '${first}' in ${file}")
    endif()
    string(SUBSTRING "${rest}" 0 ${end} piece)
    set(${out} "${piece}" PARENT_SCOPE)
endfunction()

extract_between("${src}/app/AnalysisControllerSegmentReview.cpp"
    "QVector<ProgressRange> coverageGaps(" "\n} // namespace" coverage_gaps)
extract_between("${src}/app/AnalysisControllerAutomaticSegments.cpp"
    "        int approved = 0;" "        if (approved == 0) return;" approval_loop)
file(WRITE "${CMAKE_BINARY_DIR}/extracted/OverlaysExtracted.h"
"// Generated from ${VBOOVERLAY_DIR}; do not edit.
#pragma once
#include \"telemetry/TrackSegmentReview.h\"
#include <QJsonValue>
#include <algorithm>

namespace FlappedEar::extracted {

${coverage_gaps}
struct AutomaticSegmentsReview {
    ProgressAxis axis;
    TrackSegmentProposals proposals;
};
struct AutomaticSegmentsResult {
    AutomaticSegmentsReview review;
    QString groupId;
};

// The loop of AnalysisController's automatic-segments handler; returns how
// many proposals it approved into `stored`.
inline int approveAutomaticSegments(const AutomaticSegmentsResult &result, QJsonValue &stored)
{
${approval_loop}        return approved;
}

} // namespace FlappedEar::extracted
")

add_executable(cpp_segment_editing_dump
    main.cpp
    ${src}/telemetry/VboParser.cpp
    ${src}/telemetry/LapTiming.cpp
    ${src}/telemetry/TelemetrySession.cpp
    ${src}/telemetry/TelemetryGeometry.cpp
    ${src}/telemetry/TelemetrySessionCache.cpp
    ${src}/telemetry/TrackProgress.cpp
    ${src}/telemetry/TrackSegments.cpp
    ${src}/telemetry/TrackSegmentProposals.cpp
    ${src}/telemetry/TrackSegmentReview.cpp
    ${src}/telemetry/TrackSegmentEditing.cpp)
target_include_directories(cpp_segment_editing_dump PRIVATE ${src} "${CMAKE_BINARY_DIR}/extracted")
target_link_libraries(cpp_segment_editing_dump PRIVATE Qt6::Core)
