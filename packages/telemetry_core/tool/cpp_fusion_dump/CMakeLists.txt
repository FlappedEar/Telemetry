# Builds a command-line tool that runs FlappedEar Overlays' C++ recording
# alignment and channel fusion (TelemetrySyncEngine, RecordingAlignment and
# ChannelFusion) over fixed synthetic cases, or over pairs of real recordings,
# and prints the results as JSON. The Dart port is checked against that
# output. Not part of the app or of CI: it needs a local checkout of
# FlappedEar/Overlay, Qt 6.8 and zlib (see README.md).
cmake_minimum_required(VERSION 3.24)
project(cpp_fusion_dump LANGUAGES CXX)

set(VBOOVERLAY_DIR "" CACHE PATH "Path to a FlappedEar/Overlay checkout")
if(NOT EXISTS "${VBOOVERLAY_DIR}/native/src/telemetry/ChannelFusion.cpp")
    message(FATAL_ERROR "Set VBOOVERLAY_DIR to a FlappedEar/Overlay checkout")
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Core)
find_package(ZLIB REQUIRED)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(src "${VBOOVERLAY_DIR}/native/src")
add_executable(cpp_fusion_dump
    main.cpp
    ${src}/telemetry/VboParser.cpp
    ${src}/telemetry/RczParser.cpp
    ${src}/telemetry/LapTiming.cpp
    ${src}/telemetry/OutingLaps.cpp
    ${src}/telemetry/TelemetrySession.cpp
    ${src}/telemetry/TelemetryGeometry.cpp
    ${src}/telemetry/TelemetrySessionCache.cpp
    ${src}/telemetry/TelemetrySyncEngine.cpp
    ${src}/telemetry/RecordingAlignment.cpp
    ${src}/telemetry/ChannelFusion.cpp)
target_include_directories(cpp_fusion_dump PRIVATE ${src})
target_link_libraries(cpp_fusion_dump PRIVATE Qt6::Core ZLIB::ZLIB)
