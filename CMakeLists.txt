# ============================================================================
#  WhisperType — self-contained native macOS menu bar dictation app
#
#  This build script:
#    1. Pulls whisper.cpp (a stable tag) via FetchContent and builds the CLI.
#    2. Downloads the ggml-base.en Whisper model from Hugging Face at
#       configure time (only if it is not already present locally).
#    3. Builds the SwiftUI app as a proper macOS .app bundle.
#    4. Copies the whisper CLI (renamed to `whisper-cpp`) and the model into
#       the bundle's Resources directory as a post-build step.
#
#  Usage:
#    cmake -G Xcode -B build
#    cmake --build build --config Release
#    open build/Release/WhisperType.app
# ============================================================================

cmake_minimum_required(VERSION 3.26)

project(WhisperType
    VERSION 1.0.0
    LANGUAGES Swift C CXX
)

if(NOT APPLE)
    message(FATAL_ERROR "WhisperType can only be built on macOS.")
endif()

# ----------------------------------------------------------------------------
#  Global toolchain configuration
# ----------------------------------------------------------------------------
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum supported macOS version")
set(CMAKE_Swift_LANGUAGE_VERSION 5)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

# ----------------------------------------------------------------------------
#  1. whisper.cpp (built statically so the CLI is fully self-contained)
# ----------------------------------------------------------------------------
set(BUILD_SHARED_LIBS         OFF CACHE BOOL "" FORCE)  # static -> single relocatable binary
set(WHISPER_BUILD_TESTS       OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER      OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES    ON  CACHE BOOL "" FORCE)  # we need the `whisper-cli` example
set(GGML_ACCELERATE           ON  CACHE BOOL "" FORCE)  # Apple Accelerate framework
set(GGML_METAL                ON  CACHE BOOL "" FORCE)  # GPU acceleration on Apple Silicon
set(GGML_METAL_EMBED_LIBRARY  ON  CACHE BOOL "" FORCE)  # embed metallib so no .metal file is needed at runtime

FetchContent_Declare(
    whisper_cpp
    GIT_REPOSITORY https://github.com/ggml-org/whisper.cpp.git
    GIT_TAG        v1.8.6
    GIT_SHALLOW    TRUE
)

message(STATUS "Fetching whisper.cpp (v1.8.6)...")
FetchContent_MakeAvailable(whisper_cpp)

# ----------------------------------------------------------------------------
#  2. Whisper model download (configure-time, cached)
# ----------------------------------------------------------------------------
set(MODEL_DIR  "${CMAKE_BINARY_DIR}/models")
set(MODEL_NAME "ggml-base.en.bin")
set(MODEL_FILE "${MODEL_DIR}/${MODEL_NAME}")
set(MODEL_URL  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}")

file(MAKE_DIRECTORY "${MODEL_DIR}")

if(NOT EXISTS "${MODEL_FILE}")
    message(STATUS "Downloading Whisper model '${MODEL_NAME}' from Hugging Face...")
    file(DOWNLOAD
        "${MODEL_URL}"
        "${MODEL_FILE}"
        SHOW_PROGRESS
        STATUS  _model_dl_status
        TLS_VERIFY ON
    )
    list(GET _model_dl_status 0 _model_dl_code)
    list(GET _model_dl_status 1 _model_dl_msg)
    if(NOT _model_dl_code EQUAL 0)
        file(REMOVE "${MODEL_FILE}")  # don't leave a truncated file behind
        message(FATAL_ERROR "Failed to download Whisper model: ${_model_dl_msg}")
    endif()
    message(STATUS "Whisper model downloaded to ${MODEL_FILE}")
else()
    message(STATUS "Whisper model already present at ${MODEL_FILE} (skipping download)")
endif()

# ----------------------------------------------------------------------------
#  2b. Determine the code-signing identity
#
#  A *stable* identity (rather than ad-hoc "-") is important: macOS keys the
#  Accessibility (TCC) permission grant on the signature, so an ad-hoc binary
#  whose hash changes every rebuild forces the user to re-approve every time.
#  If the dedicated self-signed identity exists we use it; otherwise we fall
#  back to ad-hoc signing so the project still builds on a clean machine.
# ----------------------------------------------------------------------------
set(WHISPERTYPE_SIGN_IDENTITY "WhisperType Self-Signed")
execute_process(
    COMMAND security find-identity -p codesigning
    OUTPUT_VARIABLE _wt_identities
    ERROR_QUIET
)
string(FIND "${_wt_identities}" "${WHISPERTYPE_SIGN_IDENTITY}" _wt_idx)
if(_wt_idx EQUAL -1)
    set(WHISPERTYPE_SIGN_IDENTITY "-")
    message(STATUS "Code signing: stable identity not found — using ad-hoc signing "
                   "(Accessibility permission will reset on each rebuild). "
                   "Run ./scripts/create-signing-cert.sh to create a stable identity.")
else()
    message(STATUS "Code signing: using stable identity '${WHISPERTYPE_SIGN_IDENTITY}'")
endif()

# ----------------------------------------------------------------------------
#  3. The WhisperType application bundle
# ----------------------------------------------------------------------------
set(APP_SOURCES
    src/main.swift
    src/Settings.swift
    src/AudioRecorder.swift
    src/WhisperRunner.swift
    src/HotkeyManager.swift
)

add_executable(WhisperType MACOSX_BUNDLE ${APP_SOURCES})

set_target_properties(WhisperType PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST            "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
    MACOSX_BUNDLE_BUNDLE_NAME           "WhisperType"
    MACOSX_BUNDLE_EXECUTABLE_NAME       "WhisperType"
    MACOSX_BUNDLE_GUI_IDENTIFIER        "com.whispertype.app"
    MACOSX_BUNDLE_BUNDLE_VERSION        "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING  "${PROJECT_VERSION}"
    # Xcode-specific signing settings (ad-hoc sign for local builds)
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.whispertype.app"
    # Xcode runs its own CodeSign phase *after* our POST_BUILD script, so it
    # must use the same stable identity or it would clobber our signature with
    # an ad-hoc one (which resets the Accessibility grant on every rebuild).
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY        "${WHISPERTYPE_SIGN_IDENTITY}"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE           "Manual"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED      "YES"
    XCODE_ATTRIBUTE_SWIFT_VERSION             "5.0"
    XCODE_ATTRIBUTE_MACOSX_DEPLOYMENT_TARGET  "13.0"
)

# System frameworks used by the Swift sources.
target_link_libraries(WhisperType PRIVATE
    "-framework AppKit"
    "-framework SwiftUI"
    "-framework AVFoundation"
    "-framework Carbon"
    "-framework CoreGraphics"
    "-framework ApplicationServices"
    "-framework Foundation"
)

# Make sure the CLI exists before we try to bundle it.
add_dependencies(WhisperType whisper-cli)

# ----------------------------------------------------------------------------
#  4. Bundle assets into <App>.app/Contents/Resources
# ----------------------------------------------------------------------------
set(BUNDLE_RESOURCES "$<TARGET_BUNDLE_CONTENT_DIR:WhisperType>/Resources")

add_custom_command(TARGET WhisperType POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_RESOURCES}"
    # Copy the compiled CLI in, renamed to the name the Swift code looks for.
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:whisper-cli>" "${BUNDLE_RESOURCES}/whisper-cpp"
    COMMAND chmod +x "${BUNDLE_RESOURCES}/whisper-cpp"
    # Copy the downloaded model weights in.
    COMMAND ${CMAKE_COMMAND} -E copy "${MODEL_FILE}" "${BUNDLE_RESOURCES}/${MODEL_NAME}"
    # Re-sign last: Xcode signs before this script runs, and adding the
    # resources above invalidates that signature. Sign the nested CLI first,
    # then re-seal the whole bundle with the stable identity so the
    # Accessibility grant persists across rebuilds.
    COMMAND codesign --force --sign "${WHISPERTYPE_SIGN_IDENTITY}" "${BUNDLE_RESOURCES}/whisper-cpp"
    COMMAND codesign --force --sign "${WHISPERTYPE_SIGN_IDENTITY}"
            --identifier "com.whispertype.app" "$<TARGET_BUNDLE_DIR:WhisperType>"
    COMMENT "Bundling whisper-cpp CLI + model and code-signing WhisperType.app"
    VERBATIM
)
