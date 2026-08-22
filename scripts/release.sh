#!/usr/bin/env bash
# VoiceFlow release pipeline: build, sign, package, notarize, staple, verify, checksum.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/voiceflow.xcodeproj}"
readonly SCHEME="${SCHEME:-voiceflow}"
readonly CONFIGURATION="Release"
readonly OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
readonly DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/.release/derived-data}"
readonly BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
readonly SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-Developer ID Application}"
readonly CHECK_ONLY="${RELEASE_CHECK_ONLY:-0}"

usage() {
    cat <<'USAGE'
Usage:
  ./scripts/release.sh VERSION
  ./scripts/release.sh --check

VERSION must be a semantic version such as 1.0.0. The version is supplied to
xcodebuild as MARKETING_VERSION; it is not written into source files.

Required for a real release:
  DEVELOPER_ID_APPLICATION  Developer ID Application identity or identity prefix
  One notarization method:
    APPLE_API_KEY_PATH, APPLE_API_KEY_ID, APPLE_ISSUER_ID
    OR NOTARY_KEYCHAIN_PROFILE

Optional:
  BUILD_NUMBER              Numeric build number (defaults to GITHUB_RUN_NUMBER or 1)
  DEVELOPER_DIR             Xcode developer directory
  OUTPUT_DIR                Final artifact directory (defaults to ./dist)
  DERIVED_DATA_DIR          Release derived-data directory
USAGE
}

die() {
    printf 'release: error: %s\n' "$*" >&2
    exit 1
}

info() {
    printf 'release: %s\n' "$*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

validate_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || \
        die "version must look like 1.0.0 or 1.0.0-rc.1 (received: $1)"
}

select_xcode() {
    if [[ -n "${DEVELOPER_DIR:-}" ]]; then
        export DEVELOPER_DIR
    elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    else
        export DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
    fi

    [[ -n "${DEVELOPER_DIR:-}" ]] || die "Xcode developer directory was not found"
    [[ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]] || die "DEVELOPER_DIR does not point to a full Xcode installation: $DEVELOPER_DIR"
    info "using $(DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild -version | tr '\n' ' ')"
}

load_build_settings() {
    BUILD_SETTINGS="$(DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -showBuildSettings 2>/dev/null)" || die "could not read Xcode build settings"
}

setting() {
    local key="$1"
    printf '%s\n' "$BUILD_SETTINGS" | awk -F ' = ' -v key="$key" \
        '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" { print $2; exit }'
}

check_project_configuration() {
    local product_name bundle_id hardened sandbox app_icon
    product_name="$(setting PRODUCT_NAME)"
    bundle_id="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
    hardened="$(setting ENABLE_HARDENED_RUNTIME)"
    sandbox="$(setting ENABLE_APP_SANDBOX)"
    app_icon="$(setting ASSETCATALOG_COMPILER_APPICON_NAME)"

    [[ -n "$product_name" ]] || die "Xcode scheme '$SCHEME' has no PRODUCT_NAME"
    [[ -n "$bundle_id" ]] || die "Xcode scheme '$SCHEME' has no PRODUCT_BUNDLE_IDENTIFIER"
    [[ "$hardened" == "YES" ]] || die "Release must enable Hardened Runtime (ENABLE_HARDENED_RUNTIME=YES)"
    [[ "$sandbox" != "YES" ]] || die "VoiceFlow requires App Sandbox to be disabled for global Fn and Accessibility injection"
    [[ "$app_icon" == "AppIcon" ]] || die "Release app icon is not AppIcon"

    info "configuration: product=$product_name bundle=$bundle_id icon=$app_icon hardened-runtime=$hardened sandbox=${sandbox:-NO}"
}

check_signing_identity() {
    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    printf '%s\n' "$identities" | grep -F "$SIGNING_IDENTITY" >/dev/null || \
        die "Developer ID signing identity not found; configure DEVELOPER_ID_APPLICATION without printing certificate secrets"
}

check_notarization_credentials() {
    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        info "notarization credentials: keychain profile configured"
        return
    fi

    if [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_ISSUER_ID:-}" ]]; then
        [[ -r "$APPLE_API_KEY_PATH" ]] || die "APPLE_API_KEY_PATH is not readable"
        info "notarization credentials: App Store Connect API key configured"
        return
    fi

    die "configure NOTARY_KEYCHAIN_PROFILE or APPLE_API_KEY_PATH + APPLE_API_KEY_ID + APPLE_ISSUER_ID"
}

check_requirements() {
    local command
    for command in xcodebuild xcrun codesign security hdiutil shasum; do
        require_command "$command"
    done
    xcrun --find notarytool >/dev/null 2>&1 || die "xcrun notarytool is unavailable in the selected Xcode"
    xcrun --find stapler >/dev/null 2>&1 || die "xcrun stapler is unavailable in the selected Xcode"
    require_command spctl
    [[ -f "$PROJECT_PATH/project.pbxproj" ]] || die "Xcode project not found: $PROJECT_PATH"
    load_build_settings
    check_project_configuration
    check_signing_identity
    check_notarization_credentials
}

notarize() {
    local dmg_path="$1"
    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        DEVELOPER_DIR="$DEVELOPER_DIR" xcrun notarytool submit "$dmg_path" \
            --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    else
        DEVELOPER_DIR="$DEVELOPER_DIR" xcrun notarytool submit "$dmg_path" \
            --key "$APPLE_API_KEY_PATH" \
            --key-id "$APPLE_API_KEY_ID" \
            --issuer "$APPLE_ISSUER_ID" \
            --wait
    fi
}

verify_mounted_dmg() {
    local dmg_path="$1"
    local mount_dir="$2"
    local run_gatekeeper_assessment="${3:-0}"
    local mounted_app="$mount_dir/VoiceFlow.app"

    hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$dmg_path" >/dev/null
    trap 'hdiutil detach "$mount_dir" >/dev/null 2>&1 || true' RETURN
    [[ -d "$mounted_app" ]] || die "DMG does not contain VoiceFlow.app"
    [[ -L "$mount_dir/Applications" ]] || die "DMG does not contain an Applications shortcut"
    codesign --verify --deep --strict --verbose=2 "$mounted_app"
    if [[ "$run_gatekeeper_assessment" == "1" ]]; then
        spctl --assess --type execute --verbose=4 "$mounted_app"
    fi
    hdiutil detach "$mount_dir" >/dev/null
    trap - RETURN
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--check" ]]; then
    select_xcode
    check_requirements
    info "check passed; no build, notarization submission, or artifact was created"
    exit 0
fi

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { usage >&2; exit 2; }
validate_version "$VERSION"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "BUILD_NUMBER must be numeric"

select_xcode
check_requirements

mkdir -p "$OUTPUT_DIR" "$DERIVED_DATA_DIR"
rm -f "$OUTPUT_DIR/VoiceFlow-"*.dmg "$OUTPUT_DIR/VoiceFlow-"*.dmg.sha256 "$OUTPUT_DIR/SHA256SUMS.txt"

info "cleaning Release derived data"
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    clean >/dev/null

info "building Release $VERSION (build $BUILD_NUMBER)"
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -destination 'platform=macOS' \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    build

APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/VoiceFlow.app"
[[ -d "$APP_PATH" ]] || die "Release app was not produced at $APP_PATH"

info "verifying application signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -E 's/(TeamIdentifier=|Authority=Developer ID Application: ).*/\0/' >/dev/null

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voiceflow-dmg-staging.XXXXXX")"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voiceflow-dmg-mount.XXXXXX")"
cleanup() {
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    rm -rf "$STAGING_DIR" "$MOUNT_DIR"
}
trap cleanup EXIT

ln -s /Applications "$STAGING_DIR/Applications"
cp -R "$APP_PATH" "$STAGING_DIR/VoiceFlow.app"
DMG_PATH="$OUTPUT_DIR/VoiceFlow-$VERSION.dmg"
CHECKSUM_PATH="$OUTPUT_DIR/SHA256SUMS.txt"

info "creating $DMG_PATH"
hdiutil create \
    -volname "VoiceFlow $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

info "verifying DMG structure and application signature"
hdiutil verify "$DMG_PATH"
verify_mounted_dmg "$DMG_PATH" "$MOUNT_DIR"

info "submitting DMG for notarization"
notarize "$DMG_PATH"

info "stapling notarization ticket"
DEVELOPER_DIR="$DEVELOPER_DIR" xcrun stapler staple "$DMG_PATH"
DEVELOPER_DIR="$DEVELOPER_DIR" xcrun stapler validate "$DMG_PATH"

info "verifying Gatekeeper assessment"
hdiutil verify "$DMG_PATH"
verify_mounted_dmg "$DMG_PATH" "$MOUNT_DIR" 1

info "generating SHA-256 checksum from the stapled DMG"
shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

info "release artifacts ready"
printf 'DMG: %s\nSHA256: %s\n' "$DMG_PATH" "$CHECKSUM_PATH"
