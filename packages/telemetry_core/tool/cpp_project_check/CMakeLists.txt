# Builds a command-line tool that opens .fetproject documents with FlappedEar
# Overlays' own C++ code and prints what Overlays sees as JSON: whether the
# document is valid, each run's recording, fingerprint and lap derivation
# key, the laps its exclusions apply to, and whether an Overlays re-save keeps
# the event unchanged. Not part of the app or of CI (see ../README.md).
cmake_minimum_required(VERSION 3.24)
project(cpp_project_check LANGUAGES CXX)

set(VBOOVERLAY_DIR "" CACHE PATH "Path to a FlappedEar/Overlay checkout")
if(NOT EXISTS "${VBOOVERLAY_DIR}/native/src/project/EventProjectCodec.cpp")
    message(FATAL_ERROR "Set VBOOVERLAY_DIR to a FlappedEar/Overlay checkout")
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Core)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(src "${VBOOVERLAY_DIR}/native/src")
add_executable(cpp_project_check
    main.cpp
    ${src}/project/BoundedJsonLoader.cpp
    ${src}/project/EventProjectCodec.cpp
    ${src}/project/ProjectLimits.cpp
    ${src}/project/ProjectSourceReference.cpp
    ${src}/project/VideoChapters.cpp
    ${src}/telemetry/OutingLaps.cpp
    ${src}/telemetry/TrackSegments.cpp
    ${src}/telemetry/TrackSegmentReview.cpp
    ${src}/telemetry/VboParser.cpp
    ${src}/telemetry/LapTiming.cpp
    ${src}/telemetry/TelemetrySession.cpp
    ${src}/telemetry/TelemetryGeometry.cpp
    ${src}/telemetry/TelemetrySessionCache.cpp)
target_include_directories(cpp_project_check PRIVATE ${src})
target_link_libraries(cpp_project_check PRIVATE Qt6::Core)
