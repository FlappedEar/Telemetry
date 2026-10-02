# Builds a command-line tool that runs FlappedEar Overlays' C++ VBO parser and
# lap timing over input files and prints the results as JSON. The Dart port is
# checked against that output. Not part of the app or of CI: it needs a local
# checkout of arekkozuch/VBOOverlay and Qt 6.8 (see README.md).
cmake_minimum_required(VERSION 3.24)
project(cpp_reference_dump LANGUAGES CXX)

set(VBOOVERLAY_DIR "" CACHE PATH "Path to an arekkozuch/VBOOverlay checkout")
if(NOT EXISTS "${VBOOVERLAY_DIR}/native/src/telemetry/VboParser.cpp")
    message(FATAL_ERROR "Set VBOOVERLAY_DIR to an arekkozuch/VBOOverlay checkout")
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Core)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(src "${VBOOVERLAY_DIR}/native/src")
add_executable(cpp_reference_dump
    main.cpp
    ${src}/telemetry/VboParser.cpp
    ${src}/telemetry/LapTiming.cpp
    ${src}/telemetry/TelemetrySession.cpp
    ${src}/telemetry/TelemetryGeometry.cpp
    ${src}/telemetry/TelemetrySessionCache.cpp)
target_include_directories(cpp_reference_dump PRIVATE ${src})
target_link_libraries(cpp_reference_dump PRIVATE Qt6::Core)
