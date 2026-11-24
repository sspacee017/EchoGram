#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
WORKSPACE="$PWD"
FORK="$WORKSPACE/Upstream/TelegramSwift"
BUILD_DIR="$WORKSPACE/.build/native"
OUTPUT="$WORKSPACE/dist"
APP="$OUTPUT/EchoGram.app"
APP_ONLY=NO
BUILD_MODE=optimized

for argument in "$@"; do
    case "$argument" in
        --app-only) APP_ONLY=YES ;;
        --debug) BUILD_MODE=debug ;;
        *) printf 'Unknown argument: %s\n' "$argument" >&2; exit 2 ;;
    esac
done

BUILD_SETTINGS=(ONLY_ACTIVE_ARCH=YES)
DERIVED_DATA="$BUILD_DIR/derived"
if [[ "$BUILD_MODE" == optimized ]]; then
    DERIVED_DATA="$BUILD_DIR/derived-optimized"
    BUILD_SETTINGS=(
        ONLY_ACTIVE_ARCH=YES
        SWIFT_OPTIMIZATION_LEVEL=-O
        SWIFT_COMPILATION_MODE=wholemodule
        GCC_OPTIMIZATION_LEVEL=2
        DEBUG_INFORMATION_FORMAT=dwarf-with-dsym
        ENABLE_DEBUG_DYLIB=NO
        DEPLOYMENT_POSTPROCESSING=YES
        STRIP_INSTALLED_PRODUCT=YES
        STRIP_STYLE=non-global
        COPY_PHASE_STRIP=YES
    )
fi

test -d "$FORK/Telegram-Mac.xcworkspace"
mkdir -p "$BUILD_DIR" "$OUTPUT"

export PATH="$(brew --prefix rustup)/bin:$PATH"
export RUSTUP_HOME="$BUILD_DIR/rustup"
export CARGO_HOME="$BUILD_DIR/cargo"
export DEVELOPER_DIR="$(xcode-select -p)"
export CMAKE_POLICY_VERSION_MINIMUM=3.5

cd "$FORK"
if [[ "$APP_ONLY" != YES ]]; then
    RUST_VERSION="$(sed -n 's/^channel = "\(.*\)"$/\1/p' submodules/telegram-ios/third-party/mtproto-engine/rust-toolchain.toml)"
    [[ -n "$RUST_VERSION" ]]
    rustup toolchain install "$RUST_VERSION" --profile minimal --component clippy --component rustfmt \
        --target aarch64-apple-darwin --target x86_64-apple-darwin
    export RUSTUP_TOOLCHAIN="$RUST_VERSION"

    ABSL_ATTRIBUTES="submodules/tg_owt/src/third_party/abseil-cpp/absl/base/attributes.h"
    test -f "$ABSL_ATTRIBUTES"
    sed -i '' \
        -e 's|^#define ABSL_ATTRIBUTE_LIFETIME_BOUND \[\[clang::lifetimebound\]\]|#define ABSL_ATTRIBUTE_LIFETIME_BOUND|' \
        -e 's|^#define ABSL_ATTRIBUTE_LIFETIME_BOUND __attribute__((lifetimebound))|#define ABSL_ATTRIBUTE_LIFETIME_BOUND|' \
        "$ABSL_ATTRIBUTES"

    /bin/bash scripts/configure_frameworks.sh
fi
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$DERIVED_DATA" \
    -jobs "${ECHOGRAM_BUILD_JOBS:-6}" "${BUILD_SETTINGS[@]}" build

BUILT="$DERIVED_DATA/Build/Products/Debug/EchoGram.app"
test -x "$BUILT/Contents/MacOS/EchoGram"
codesign --verify --deep --strict "$BUILT"
STAGING="$(mktemp -d "$OUTPUT/.native.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$BUILT" "$STAGING/EchoGram.app"
if [[ -d "$APP" ]]; then mv "$APP" "$STAGING/previous.app"; fi
if ! mv "$STAGING/EchoGram.app" "$APP"; then
    if [[ -d "$STAGING/previous.app" ]]; then mv "$STAGING/previous.app" "$APP"; fi
    exit 1
fi
printf '%s\n' "$APP"
