# Builds a command-line tool that runs FlappedEar Overlays' C++ Corner
# Analyzer for two compared laps (comparisonSegmentMetrics,
# comparisonApprovedSegments, comparisonSharedSegmentation,
# comparisonTimeLossObservations and comparisonHeartRate; app member
# functions, so the tool repeats their lines over Overlays' own TrackProgress,
# SectorTiming, TimeLoss, CornerPhases, CornerSpeeds, BrakingOnset,
# BrakingMetrics, ExitMetrics and ChannelSummary) over input files, a day
# description and fixed cases, and prints the results as JSON. The Dart port
# is checked against that output. Not part of the app or of CI: it needs a
# local checkout of FlappedEar/Overlay and Qt 6.8 (see README.md).
cmake_minimum_required(VERSION 3.24)
project(cpp_corner_analyzer_dump LANGUAGES CXX)

set(VBOOVERLAY_DIR "" CACHE PATH "Path to a FlappedEar/Overlay checkout")
if(NOT EXISTS "${VBOOVERLAY_DIR}/native/src/telemetry/ExitMetrics.cpp")
    message(FATAL_ERROR "Set VBOOVERLAY_DIR to a FlappedEar/Overlay checkout")
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Core)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(src "${VBOOVERLAY_DIR}/native/src")
add_executable(cpp_corner_analyzer_dump
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
    ${src}/telemetry/SectorTiming.cpp
    ${src}/telemetry/TheoreticalBest.cpp
    ${src}/telemetry/TimeLoss.cpp
    ${src}/telemetry/Consistency.cpp
    ${src}/telemetry/CornerPhases.cpp
    ${src}/telemetry/CornerSpeeds.cpp
    ${src}/telemetry/BrakingOnset.cpp
    ${src}/telemetry/BrakingMetrics.cpp
    ${src}/telemetry/ExitMetrics.cpp
    ${src}/telemetry/ChannelSummary.cpp)
target_include_directories(cpp_corner_analyzer_dump PRIVATE ${src})
target_link_libraries(cpp_corner_analyzer_dump PRIVATE Qt6::Core)
