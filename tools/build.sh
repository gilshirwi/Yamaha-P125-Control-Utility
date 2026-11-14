#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
VERSION="$(plutil -extract CFBundleShortVersionString raw tools/Info.plist)"
DIST_DIR="$PWD/dist/$VERSION"
BUILD_ARGS=(-c release --arch arm64 --scratch-path .build/release)
swift build "${BUILD_ARGS[@]}" --disable-local-rpath \
    -Xswiftc -file-prefix-map -Xswiftc "$PWD=/P125Control" \
    -Xswiftc -debug-prefix-map -Xswiftc "$PWD=/P125Control" \
    -Xswiftc -debug-prefix-map -Xswiftc "$HOME=/BuildHome" \
    -Xswiftc -no-serialize-debugging-options \
    -Xcc "-ffile-prefix-map=$PWD=/P125Control" \
    -Xcc "-fdebug-prefix-map=$HOME=/BuildHome"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$PWD/.build/staged/P-125 Control.app"
LOGIN_APP="$APP_DIR/Contents/Library/LoginItems/P-125 Login Launcher.app"
mkdir -p "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$LOGIN_APP/Contents/MacOS"
cp "$BIN_DIR/P125Control" "$APP_DIR/Contents/MacOS/P125Control"
cp "$BIN_DIR/p125" "$DIST_DIR/p125"
cp tools/Info.plist "$APP_DIR/Contents/Info.plist"
cp "$BIN_DIR/P125LoginLauncher" "$LOGIN_APP/Contents/MacOS/P125LoginLauncher"
cp tools/LoginLauncherInfo.plist "$LOGIN_APP/Contents/Info.plist"
swiftc -module-cache-path .build/module-cache tools/make-icon.swift -o .build/make-icon
mkdir -p .build/P125.iconset
.build/make-icon .build/P125-1024.png
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" .build/P125-1024.png --out ".build/P125.iconset/icon_${SIZE}x${SIZE}.png" > /dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" .build/P125-1024.png --out ".build/P125.iconset/icon_${SIZE}x${SIZE}@2x.png" > /dev/null
done
iconutil -c icns .build/P125.iconset -o "$APP_DIR/Contents/Resources/P125.icns"
# Keep the system Swift search path and remove build-machine paths before signing.
for EXECUTABLE in "$APP_DIR/Contents/MacOS/P125Control" "$LOGIN_APP/Contents/MacOS/P125LoginLauncher" "$DIST_DIR/p125"; do
    otool -l "$EXECUTABLE" | awk '
        $1 == "cmd" { rpath = ($2 == "LC_RPATH") }
        rpath && $1 == "path" {
            sub(/^[[:space:]]*path /, "")
            sub(/ \(offset [0-9]+\)$/, "")
            print
        }
    ' | while IFS= read -r RPATH; do
        if [[ "$RPATH" != /usr/lib/swift ]]; then
            install_name_tool -delete_rpath "$RPATH" "$EXECUTABLE"
        fi
    done
done
# Strip shipped executables before signing, including the diagnostic tool.
for EXECUTABLE in "$APP_DIR/Contents/MacOS/P125Control" "$LOGIN_APP/Contents/MacOS/P125LoginLauncher" "$DIST_DIR/p125"; do
    xcrun strip -S -x "$EXECUTABLE"
done
codesign --force --sign - "$DIST_DIR/p125"
codesign --force --sign - "$LOGIN_APP"
codesign --force --sign - "$APP_DIR"
# Rename complete bundles, preserving the executable inode used by an already
# running app. Building an update never interrupts the piano-control session.
if [[ -d "$DIST_DIR/P-125 Control.app" ]]; then
    PREVIOUS_DIR="$(mktemp -d "$PWD/.build/previous-app.XXXXXX")"
    mv "$DIST_DIR/P-125 Control.app" "$PREVIOUS_DIR/"
fi
mv "$APP_DIR" "$DIST_DIR/P-125 Control.app"
print "Built: $DIST_DIR/P-125 Control.app"
