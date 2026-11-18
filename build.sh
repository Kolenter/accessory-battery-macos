#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_name="Заряд аксессуаров"
info_plist="$project_dir/Info.plist"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$info_plist")"
minimum_macos="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw "$info_plist")"

staging_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/accessory-battery.XXXXXXXX")"
trap '/bin/rm -rf -- "$staging_dir"' EXIT

volume_dir="$staging_dir/image"
app="$volume_dir/$app_name.app"
executable="$app/Contents/MacOS/AccessoryBattery"
build_dir="$project_dir/build"
image="$build_dir/accessory-battery-$version.dmg"

/bin/mkdir -p "$app/Contents/MacOS" "$build_dir"
/bin/cp "$info_plist" "$app/Contents/Info.plist"

for architecture in arm64 x86_64; do
    /usr/bin/swiftc -swift-version 6 -O -warnings-as-errors \
        -target "$architecture-apple-macos$minimum_macos" \
        "$project_dir/AccessoryBattery.swift" -o "$staging_dir/AccessoryBattery-$architecture"
done

/usr/bin/lipo -create "$staging_dir/AccessoryBattery-arm64" \
    "$staging_dir/AccessoryBattery-x86_64" -output "$executable"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict --all-architectures "$app"
/bin/ln -s /Applications "$volume_dir/Applications"
/usr/bin/hdiutil create -ov -volname "$app_name" -fs HFS+ -srcfolder "$volume_dir" \
    -format UDZO -imagekey zlib-level=9 "$image"
