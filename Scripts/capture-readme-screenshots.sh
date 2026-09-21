#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
device_name=${VARAN_SCREENSHOT_DEVICE:-iPhone 17}
device_id=$(
  xcrun simctl list devices available |
    awk -v name="$device_name" 'index($0, "    " name " (") == 1 { print; exit }' |
    sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
)

if [ -z "$device_id" ]; then
  echo "No available simulator named '$device_name' was found." >&2
  exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/varan-screenshots.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT INT TERM
derived_data="$temporary_root/DerivedData"
app_path="$derived_data/Build/Products/Debug-iphonesimulator/Varan.app"
screenshots="$project_root/Docs/Screenshots"

xcodebuild \
  -project "$project_root/Varan.xcodeproj" \
  -scheme Varan \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" "$app_path"
xcrun simctl ui "$device_id" appearance dark
xcrun simctl status_bar "$device_id" override \
  --time '9:41' --batteryState charged --batteryLevel 100 --wifiBars 3

mkdir -p "$screenshots"

capture() {
  screen=$1
  destination=$2
  temporary_image="$temporary_root/$destination"

  xcrun simctl terminate "$device_id" de.example.Varan 2>/dev/null || true
  xcrun simctl launch "$device_id" de.example.Varan \
    --screenshot-demo \
    --screenshot-screen "$screen" \
    -AppleLanguages '(en)' \
    -AppleLocale en_US
  sleep 3
  xcrun simctl io "$device_id" screenshot "$temporary_image"
  cp "$temporary_image" "$screenshots/$destination"
}

capture server ios-server-detail.png
capture stack ios-stack-detail.png
capture container ios-container-detail.png

echo "Captured real simulator screenshots in $screenshots"
