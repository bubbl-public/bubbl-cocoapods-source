#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUBBL_IOS_XCFRAMEWORK_BUILD_DIR:-/tmp/bubbl-ios-xcframework}"
OUTPUT_DIR="${BUBBL_IOS_XCFRAMEWORK_OUTPUT_DIR:-$ROOT_DIR/ios/build}"
DERIVED_DATA_IOS="$BUILD_DIR/DerivedData-iOS"
DERIVED_DATA_SIM="$BUILD_DIR/DerivedData-iOS-Simulator"
IOS_ARCHIVE="$BUILD_DIR/BubblSDK-iOS.xcarchive"
SIM_ARCHIVE="$BUILD_DIR/BubblSDK-iOS-Simulator.xcarchive"
IOS_FRAMEWORK="$BUILD_DIR/Frameworks/iOS/BubblSDK.framework"
SIM_FRAMEWORK="$BUILD_DIR/Frameworks/iOS-Simulator/BubblSDK.framework"
OUTPUT_XCFRAMEWORK="$OUTPUT_DIR/Bubbl.xcframework"

rm -rf "$BUILD_DIR" "$OUTPUT_XCFRAMEWORK"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

make_static_framework() {
  archive_path="$1"
  derived_data_path="$2"
  framework_path="$3"

  object_file="$(find "$archive_path/Products" -name 'BubblSDK.o' -print -quit)"
  module_dir="$(find "$derived_data_path/Build/Intermediates.noindex/ArchiveIntermediates/BubblSDK/BuildProductsPath" -path '*/BubblSDK.swiftmodule' -type d -print -quit)"

  if [ -z "$object_file" ] || [ ! -f "$object_file" ]; then
    echo "Missing BubblSDK.o in $archive_path"
    exit 1
  fi

  if [ -z "$module_dir" ] || [ ! -d "$module_dir" ]; then
    echo "Missing BubblSDK.swiftmodule in $derived_data_path"
    exit 1
  fi

  rm -rf "$framework_path"
  mkdir -p "$framework_path/Headers" "$framework_path/Modules/BubblSDK.swiftmodule"

  libtool -static -o "$framework_path/BubblSDK" "$object_file"
  cp -R "$module_dir/"* "$framework_path/Modules/BubblSDK.swiftmodule/"

  cat > "$framework_path/Headers/BubblSDK.h" <<'HEADER'
#import <Foundation/Foundation.h>
HEADER

  cat > "$framework_path/Modules/module.modulemap" <<'MODULEMAP'
framework module BubblSDK {
  umbrella header "BubblSDK.h"
  export *
  module * { export * }
}
MODULEMAP

  cat > "$framework_path/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>BubblSDK</string>
  <key>CFBundleIdentifier</key>
  <string>tech.bubbl.sdk</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>BubblSDK</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>3.1.6</string>
  <key>CFBundleVersion</key>
  <string>3.1.6</string>
</dict>
</plist>
PLIST
}

(
  cd "$ROOT_DIR/ios"

  xcodebuild archive \
    -scheme BubblSDK \
    -destination "generic/platform=iOS" \
    -archivePath "$IOS_ARCHIVE" \
    -derivedDataPath "$DERIVED_DATA_IOS" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

  xcodebuild archive \
    -scheme BubblSDK \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "$SIM_ARCHIVE" \
    -derivedDataPath "$DERIVED_DATA_SIM" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES
)

make_static_framework "$IOS_ARCHIVE" "$DERIVED_DATA_IOS" "$IOS_FRAMEWORK"
make_static_framework "$SIM_ARCHIVE" "$DERIVED_DATA_SIM" "$SIM_FRAMEWORK"

xcodebuild -create-xcframework \
  -framework "$IOS_FRAMEWORK" \
  -framework "$SIM_FRAMEWORK" \
  -output "$OUTPUT_XCFRAMEWORK"

echo "Built $OUTPUT_XCFRAMEWORK"
