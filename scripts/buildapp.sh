#!/usr/bin/env bash
# Build VoiceFlow.app into ./build for local testing, opening, and installation.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/voiceflow.xcodeproj}"
readonly SCHEME="${SCHEME:-voiceflow}"
readonly BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
readonly CONFIGURATION_DEFAULT="${CONFIGURATION:-Debug}"
readonly INSTALL_PATH="${INSTALL_PATH:-/Applications/VoiceFlow.app}"

TEMP_DIR=""
APP_PATH=""
BUILD_CONFIG="$CONFIGURATION_DEFAULT"
RUN_TESTS=0
OPEN_APP=0
REVEAL_APP=0
INSTALL_APP=0
CLEAN_OUTPUT=0

usage() {
    cat <<'USAGE'
Usage:
  ./scripts/buildapp.sh [options]

Builds VoiceFlow.app and copies the finished app to:
  ./build/VoiceFlow.app

Options:
  --debug       Build the Debug configuration (default).
  --release     Build the Release configuration without signing.
  --test        Run the complete voiceflowTests XCTest suite after building.
  --open        Launch build/VoiceFlow.app after a successful build.
  --reveal      Reveal build/VoiceFlow.app in Finder for drag-and-drop install.
  --install     Copy build/VoiceFlow.app to /Applications/VoiceFlow.app.
  --clean       Remove only this script's known build/ output before building.
  --help        Show this help text.

Environment overrides:
  DEVELOPER_DIR  Xcode developer directory.
  PROJECT_PATH   Xcode project path.
  SCHEME         Xcode scheme (default: voiceflow).
  BUILD_DIR      Output directory (default: ./build).
  CONFIGURATION  Default configuration (Debug).
  INSTALL_PATH   Installation destination (default: /Applications/VoiceFlow.app).
  BUILD_NUMBER   Optional numeric CURRENT_PROJECT_VERSION override.
  VERSION        Optional MARKETING_VERSION override.

Examples:
  ./scripts/buildapp.sh
  ./scripts/buildapp.sh --test --open
  ./scripts/buildapp.sh --release --test --reveal
  ./scripts/buildapp.sh --install
USAGE
}

fail() {
    printf 'buildapp: error: %s\n' "$*" >&2
    exit 1
}

info() {
    printf 'buildapp: %s\n' "$*"
}

on_error() {
    local exit_code=$?
    printf 'buildapp: failed at line %s with exit code %s\n' "${BASH_LINENO[0]:-unknown}" "$exit_code" >&2
    exit "$exit_code"
}

cleanup() {
    local exit_code=$?
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    if [[ "$exit_code" -ne 0 ]]; then
        printf 'buildapp: temporary build data cleaned up; output was not promoted unless the copy had completed\n' >&2
    fi
}

trap on_error ERR
trap cleanup EXIT

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

select_xcode() {
    if [[ -n "${DEVELOPER_DIR:-}" ]]; then
        export DEVELOPER_DIR
    elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    else
        export DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
    fi

    [[ -n "${DEVELOPER_DIR:-}" ]] || fail "Xcode developer directory was not found"
    [[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]] || \
        fail "DEVELOPER_DIR does not point to a full Xcode installation: $DEVELOPER_DIR"

    info "using $(DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild -version | tr '\n' ' ')"
}

validate_options() {
    [[ -f "$PROJECT_PATH/project.pbxproj" ]] || fail "Xcode project not found: $PROJECT_PATH"
    [[ "$BUILD_CONFIG" == "Debug" || "$BUILD_CONFIG" == "Release" ]] || \
        fail "configuration must be Debug or Release"

    if [[ -n "${BUILD_NUMBER:-}" && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
        fail "BUILD_NUMBER must contain only digits"
    fi
    if [[ -n "${VERSION:-}" && ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
        fail "VERSION must look like 1.0.0 or 1.0.0-rc.1"
    fi
}

clean_known_output() {
    [[ "$BUILD_DIR" != "/" && "$BUILD_DIR" != "$ROOT_DIR" ]] || \
        fail "refusing to clean an unsafe BUILD_DIR: $BUILD_DIR"

    rm -rf "$BUILD_DIR/VoiceFlow.app" "$BUILD_DIR/VoiceFlowTests.xcresult"
}

build_app() {
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voiceflow-buildapp.XXXXXX")"
    local derived_data="$TEMP_DIR/derived-data"
    local -a settings=(
        "CODE_SIGNING_ALLOWED=NO"
        "CODE_SIGNING_REQUIRED=NO"
    )

    if [[ -n "${VERSION:-}" ]]; then
        settings+=("MARKETING_VERSION=$VERSION")
    fi

    if [[ -n "${BUILD_NUMBER:-}" ]]; then
        settings+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
    fi

    info "building $BUILD_CONFIG VoiceFlow.app"
    DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$BUILD_CONFIG" \
        -derivedDataPath "$derived_data" \
        -destination 'platform=macOS' \
        ONLY_ACTIVE_ARCH=YES \
        "${settings[@]}" \
        build

    local products_dir="$derived_data/Build/Products/$BUILD_CONFIG"
    local built_app="$products_dir/VoiceFlow.app"
    if [[ ! -d "$built_app" ]]; then
        built_app="$(find "$products_dir" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)"
    fi

    if [[ -z "$built_app" || ! -d "$built_app" ]]; then
        local discovered_apps
        discovered_apps="$(find "$products_dir" -maxdepth 2 -type d -name '*.app' -print 2>/dev/null | tr '\n' ' ' || true)"
        fail "Xcode build succeeded, but no app bundle was found under $products_dir (discovered: ${discovered_apps:-none})"
    fi

    mkdir -p "$BUILD_DIR"
    local staging_app="$BUILD_DIR/.VoiceFlow.app.staging"
    rm -rf "$staging_app"
    ditto "$built_app" "$staging_app"

    [[ -d "$staging_app/Contents" ]] || fail "staged app is missing its Contents directory"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staging_app/Contents/Info.plist")" == "dha-aa.voiceflow" ]] || \
        fail "staged app has an unexpected bundle identifier"

    rm -rf "$BUILD_DIR/VoiceFlow.app"
    mv "$staging_app" "$BUILD_DIR/VoiceFlow.app"
    APP_PATH="$BUILD_DIR/VoiceFlow.app"
    info "app ready: $APP_PATH"
}

run_tests() {
    local test_temp="$TEMP_DIR/test-derived-data"
    local result_bundle="$TEMP_DIR/VoiceFlowTests.xcresult"
    info "running voiceflowTests XCTest suite"
    DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath "$test_temp" \
        -resultBundlePath "$result_bundle" \
        -destination 'platform=macOS' \
        ONLY_ACTIVE_ARCH=YES \
        -only-testing:voiceflowTests \
        test \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO
    info "XCTest suite passed"
}

install_app() {
    [[ -d "$APP_PATH" ]] || fail "app has not been built"
    if [[ -w "$(dirname "$INSTALL_PATH")" ]]; then
        ditto "$APP_PATH" "$INSTALL_PATH"
    else
        require_command sudo
        info "installing to $INSTALL_PATH with administrator permission"
        sudo ditto "$APP_PATH" "$INSTALL_PATH"
    fi
    info "installed: $INSTALL_PATH"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) BUILD_CONFIG="Debug" ;;
        --release) BUILD_CONFIG="Release" ;;
        --test) RUN_TESTS=1 ;;
        --open) OPEN_APP=1 ;;
        --reveal) REVEAL_APP=1 ;;
        --install) INSTALL_APP=1 ;;
        --clean) CLEAN_OUTPUT=1 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; fail "unknown option: $1" ;;
    esac
    shift
done

require_command xcodebuild
require_command ditto
require_command open
require_command mktemp
select_xcode
validate_options

if [[ "$CLEAN_OUTPUT" -eq 1 ]]; then
    info "cleaning known output under $BUILD_DIR"
    clean_known_output
fi

build_app

if [[ "$RUN_TESTS" -eq 1 ]]; then
    run_tests
fi

if [[ "$INSTALL_APP" -eq 1 ]]; then
    install_app
fi

if [[ "$REVEAL_APP" -eq 1 ]]; then
    open -R "$APP_PATH"
fi

if [[ "$OPEN_APP" -eq 1 ]]; then
    open "$APP_PATH"
fi

info "done"
info "To install manually, drag $APP_PATH to /Applications."
