# ============================================================================
#  WhisperType — CMake entry point (orchestrates Swift Package Manager)
#
#  The app is built with SwiftPM (see Package.swift): WhisperKit and the Swift
#  sources are compiled by `swift build`. CMake does NOT compile Swift here — it
#  drives the build and reuses scripts/build-app.sh to:
#    1. run `swift build -c <config>` (compiles WhisperType + WhisperKit),
#    2. download + bundle the Whisper model for offline use,
#    3. assemble and code-sign <binary-dir>/WhisperType.app.
#
#  This keeps SwiftPM as the single source of truth for compilation/linking
#  while still supporting a CMake-driven workflow:
#
#    cmake -B build-cmake
#    cmake --build build-cmake --config Release
#    open build-cmake/WhisperType.app
#
#  (Prefix with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer if your
#  active `swift` resolves to CommandLineTools and lacks the macOS SDK.)
# ============================================================================

cmake_minimum_required(VERSION 3.26)

# No languages: SwiftPM compiles everything, so CMake needs no compiler.
project(WhisperType VERSION 1.0.0 LANGUAGES NONE)

if(NOT APPLE)
    message(FATAL_ERROR "WhisperType can only be built on macOS.")
endif()

find_program(SWIFT_EXECUTABLE swift REQUIRED)

# Download + bundle the model into the .app for offline use (ON), or skip it and
# let WhisperKit download on demand at first launch (OFF).
option(WHISPERTYPE_BUNDLE_MODEL "Bundle the Whisper model into the app for offline use" ON)
if(WHISPERTYPE_BUNDLE_MODEL)
    set(_bundle_model 1)
else()
    set(_bundle_model 0)
endif()

set(APP_BUNDLE "${CMAKE_BINARY_DIR}/WhisperType.app")

# SwiftPM only knows debug/release; map the CMake configuration to it. The
# generator expression resolves for both single- and multi-config generators.
set(_swift_config "$<IF:$<CONFIG:Debug>,debug,release>")

# build-app.sh does: swift build -c <config> → bundle model → assemble + sign,
# writing the app to the path given as its second argument (CMake's binary dir).
add_custom_target(WhisperType ALL
    COMMAND ${CMAKE_COMMAND} -E env "WHISPERTYPE_BUNDLE_MODEL=${_bundle_model}"
            "${CMAKE_CURRENT_SOURCE_DIR}/scripts/build-app.sh"
            "${_swift_config}"
            "${APP_BUNDLE}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    USES_TERMINAL
    VERBATIM
    COMMENT "Building WhisperType.app via SwiftPM + scripts/build-app.sh"
)
