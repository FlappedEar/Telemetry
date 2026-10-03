# Builds a command-line tool that drives FlappedEar Overlays' own document and
# analysis controllers (DocumentController, AnalysisController through
# TelemetryController) headless: it builds and saves a day, opens and
# re-saves a day, reports what Overlays sees in a day, and prints the
# telemetry-v1 fingerprints of recordings. Not part of the app or of CI (see
# ../README.md).
cmake_minimum_required(VERSION 3.24)
project(cpp_project_roundtrip LANGUAGES CXX)

set(VBOOVERLAY_DIR "" CACHE PATH "Path to a FlappedEar/Overlay checkout")
if(NOT EXISTS "${VBOOVERLAY_DIR}/native/src/app/TelemetryController.cpp")
    message(FATAL_ERROR "Set VBOOVERLAY_DIR to a FlappedEar/Overlay checkout")
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Concurrent)
find_package(ZLIB REQUIRED)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Overlays' flappedear_telemetry_core and flappedear_telemetry_app sources:
# every file of project/ and telemetry/, and the controllers of app/.
set(src "${VBOOVERLAY_DIR}/native/src")
file(GLOB overlays_core "${src}/project/*.cpp" "${src}/project/*.h"
    "${src}/telemetry/*.cpp" "${src}/telemetry/*.h")
set(overlays_app
    ${src}/app/AppLog.cpp ${src}/app/AppLog.h
    ${src}/app/AnalysisDocument.h
    ${src}/app/AnalysisController.cpp ${src}/app/AnalysisController.h
    ${src}/app/AnalysisControllerChannelSummaries.cpp
    ${src}/app/AnalysisControllerComparison.cpp
    ${src}/app/AnalysisControllerComparisonVideo.cpp
    ${src}/app/AnalysisControllerAutomaticSegments.cpp
    ${src}/app/AnalysisControllerCornerAnalyzer.cpp
    ${src}/app/AnalysisControllerMapLayers.cpp
    ${src}/app/AnalysisControllerDayReport.cpp
    ${src}/app/AnalysisControllerOuting.cpp
    ${src}/app/AnalysisControllerSegmentReview.cpp
    ${src}/app/AnalysisControllerTheoreticalBest.cpp
    ${src}/app/DocumentController.cpp ${src}/app/DocumentController.h
    ${src}/app/DocumentControllerImport.cpp
    ${src}/app/DocumentControllerRecordings.cpp
    ${src}/app/DocumentHost.h
    ${src}/app/TelemetryController.cpp ${src}/app/TelemetryController.h
    ${src}/app/VideoLink.h)

add_executable(cpp_project_roundtrip main.cpp ${overlays_core} ${overlays_app})
target_include_directories(cpp_project_roundtrip PRIVATE ${src})
target_link_libraries(cpp_project_roundtrip PRIVATE Qt6::Core Qt6::Concurrent ZLIB::ZLIB)
