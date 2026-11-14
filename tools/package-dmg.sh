#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

zsh tools/build.sh

VERSION="$(plutil -extract CFBundleShortVersionString raw tools/Info.plist)"
DIST_DIR="$PWD/dist/$VERSION"
APP="$DIST_DIR/P-125 Control.app"
LOGIN_APP="$APP/Contents/Library/LoginItems/P-125 Login Launcher.app"
DMG_NAME="P-125-Control-${VERSION}-arm64.dmg"

for BUNDLE in "$APP" "$LOGIN_APP"; do
    PLIST="$BUNDLE/Contents/Info.plist"
    EXECUTABLE="$BUNDLE/Contents/MacOS/$(plutil -extract CFBundleExecutable raw "$PLIST")"
    if [[ "$(lipo -archs "$EXECUTABLE")" != arm64 ]]; then
        print -u2 -r -- "Expected an arm64-only executable: $EXECUTABLE"
        exit 1
    fi
    if [[ "$(plutil -extract LSMinimumSystemVersion raw "$PLIST")" != 14.0 ||
          "$(vtool -show-build "$EXECUTABLE" | awk '$1 == "minos" { print $2 }')" != 14.0 ]]; then
        print -u2 -r -- "Expected a macOS 14.0 deployment target: $EXECUTABLE"
        exit 1
    fi
    otool -L "$EXECUTABLE" | awk '
        NR > 1 && $1 !~ /^\/(System\/Library|usr\/lib)\// {
            print "Non-system runtime dependency: " $1 > "/dev/stderr"
            failed = 1
        }
        END { exit failed }
    '
done
codesign --verify --deep --strict "$APP"

WORK_DIR="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/p125-dmg.XXXXXX")"
MOUNTED=0
cleanup() {
    if (( MOUNTED )); then
        hdiutil detach "$MOUNT_DIR" || return
    fi
    rmdir "$MOUNT_DIR"
    rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT
mkdir "$WORK_DIR/image"
ditto --noextattr --noacl --norsrc "$APP" "$WORK_DIR/image/P-125 Control.app"
ln -s /Applications "$WORK_DIR/image/Applications"

# Build an HFS+ filesystem without copying build-host extended attributes.
hdiutil makehybrid -hfs -hfs-volume-name 'P-125 Control' \
    -o "$WORK_DIR/filesystem.dmg" "$WORK_DIR/image"
hdiutil convert "$WORK_DIR/filesystem.dmg" -format UDRW -o "$WORK_DIR/writable.dmg"
hdiutil attach -readwrite -nobrowse -mountpoint "$MOUNT_DIR" "$WORK_DIR/writable.dmg"
MOUNTED=1
# Remove Finder flags synthesized by the filesystem builder before verification.
xattr -cr "$MOUNT_DIR/P-125 Control.app"
codesign --verify --deep --strict "$MOUNT_DIR/P-125 Control.app"
hdiutil detach "$MOUNT_DIR"
MOUNTED=0
hdiutil convert "$WORK_DIR/writable.dmg" -format UDZO -o "$WORK_DIR/$DMG_NAME"
hdiutil verify "$WORK_DIR/$DMG_NAME"

(
    cd "$WORK_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
mv -f -- "$WORK_DIR/$DMG_NAME" "$WORK_DIR/$DMG_NAME.sha256" "$DIST_DIR/"
print -r -- "DMG: $DIST_DIR/$DMG_NAME"
print -r -- "Checksum: $DIST_DIR/$DMG_NAME.sha256"
