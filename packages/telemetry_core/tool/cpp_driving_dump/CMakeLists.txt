# Builds a command-line tool that runs FlappedEar Overlays' C++ G-G pairs,
# driving states and coasting (GgPairs, DrivingStates, CoastingAnalysis and
# the AnalysisController functions comparisonGgScatter and
# comparisonTrailBraking, which the tool repeats because they are app member
# functions) over input files, a day description and fixed cases, and prints
# the results as JSON. The Dart port is checked against that output.
# Not part of the app or of CI: it needs a local checkout of
# FlappedEar/Overlay and Qt 6.8 (see README.md).
cmake_minimum_required(VERSION 3.24)
project(cpp_driving_dump LANGUAGES CXX)

set(VBOOVERLAY_DIR "" CACHE PATH "Path to a FlappedEar/Overlay checkout")
if(NOT EXISTS "${VBOOVERLAY_DIR}/native/src/telemetry/CoastingAnalysis.cpp")
    message(FATAL_ERROR "Set VBOOVERLAY_DIR to a FlappedEar/Overlay checkout")
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Core)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(src "${VBOOVERLAY_DIR}/native/src")
add_executable(cpp_driving_dump
    main.cpp
    ${src}/telemetry/VboParser.cpp
    ${src}/telemetry/LapTiming.cpp
    ${src}/telemetry/TelemetrySession.cpp
    ${src}/telemetry/TelemetryGeometry.cpp
    ${src}/telemetry/TelemetrySessionCache.cpp
    ${src}/telemetry/TrackProgress.cpp
    ${src}/telemetry/GgPairs.cpp
    ${src}/telemetry/DrivingStates.cpp
    ${src}/telemetry/CoastingAnalysis.cpp)
target_include_directories(cpp_driving_dump PRIVATE ${src})
target_link_libraries(cpp_driving_dump PRIVATE Qt6::Core)
