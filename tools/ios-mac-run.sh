#!/usr/bin/env bash
# Run in an isolated copy of this repo on the Mac. See docs/agents/ios-linux.md.
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
  echo "Run this script on the Mac over SSH; AthkarCore tests run directly on Linux." >&2
  exit 2
fi
action=${1:-}
case "$action" in test|ipa) shift ;; *) echo "usage: $0 test [--all | --base REF | test identifier] | ipa" >&2; exit 2 ;; esac
if [[ $action == ipa && $# != 0 ]] || [[ $action == test && $# -gt 2 ]] \
  || [[ $action == test && $# == 2 && $1 != --base ]] || [[ $action == test && $* == --base ]]; then
  echo "ipa takes no arguments; test takes --all, --base REF or one test identifier." >&2
  exit 2
fi
repo=$(cd "$(dirname "$0")/.." && pwd)
# Without an argument, test runs only the app-unit and UI classes the changes since the merge
# base with origin/main reach (tools/affected-tests.py prints which and why); --all runs both
# targets in full.
if [[ $action == test && ( $# == 0 || $1 == --base ) ]]; then
  only=()
  for lane in app-unit ui; do
    selection=$(python3 "$repo/tools/affected-tests.py" select "$lane" "$@") || exit 2
    eval "$selection"
    # Test identifiers have no spaces.
    [[ $ATHKAR_TEST_RUN == 0 ]] || read -ra picked <<< "$ATHKAR_TEST_ONLY_TESTING"
    [[ $ATHKAR_TEST_RUN == 0 ]] || only+=("${picked[@]}")
  done
  if ((${#only[@]} == 0)); then
    echo "Nothing to run: no change since $ATHKAR_TEST_BASE_LABEL reaches AthkarTests or AthkarUITests. --all runs them."
    exit 0
  fi
  set -- "${only[@]}"
elif [[ $action == test && $1 == --all ]]; then
  set --
elif [[ $action == test && $# == 1 ]]; then
  set -- "-only-testing:$1"
fi
simulator=${ATHKAR_SIMULATOR:-Athkar-Agent}
if [[ $action == test && $simulator != Athkar-* ]]; then
  echo "Use a dedicated Athkar-* simulator." >&2
  exit 2
fi
results=${ATHKAR_RESULTS:?Set ATHKAR_RESULTS to a fresh results directory}
mkdir -p "$results"
results=$(cd "$results" && pwd)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Hikaya's Jenkins job and manual runner already use this lock on terra.
lock=/tmp/mangasync-ios-lane.lock
held=0
token="athkar-$$-$(date +%s)"
finish() {
  status=$?
  printf '%s\n' "$status" > "$results/$action.done"
  if [[ $held == 1 ]] && [[ $(cat "$lock/owner" 2>/dev/null) == *"token=$token" ]]; then
    rm "$lock/owner"
    rmdir "$lock"
  fi
  exit "$status"
}
trap finish EXIT
if ! mkdir "$lock" 2>/dev/null; then
  echo "Shared Mac iOS lane is busy; retry after its owner finishes." >&2
  cat "$lock/owner" >&2 || true
  exit 3
fi
held=1
printf 'tag=athkar-%s host=%s pid=%s since=%s token=%s\n' \
  "$action" "$(hostname)" "$$" "$(date +%s)" "$token" > "$lock/owner"

cd "$repo/ios"
xcodegen generate
if [[ $action == test ]]; then
  device=$(xcrun simctl list devices available --json | python3 -c '
import json,sys
devices=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d["name"] == sys.argv[1]]
if len(devices)>1: sys.exit("Duplicate simulator names; choose a unique Athkar-* name")
print(devices[0]["udid"] if devices else "")' "$simulator")
  if [[ -z $device ]]; then
    runtime=$(xcrun simctl list runtimes --json | python3 -c '
import json,sys
r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
if not r: sys.exit("Install an iOS simulator runtime in Xcode first")
print(max(r,key=lambda x:tuple(map(int,x["version"].split("."))))["identifier"])')
    device=$(xcrun simctl create "$simulator" com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro "$runtime")
  fi
  caffeinate -i xcodebuild -project Athkar.xcodeproj -scheme Athkar \
    -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO \
    -derivedDataPath "$results/DerivedData" -resultBundlePath "$results/test.xcresult" \
    CODE_SIGNING_ALLOWED=NO test "$@"
else
  caffeinate -i xcodebuild -project Athkar.xcodeproj -scheme Athkar \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$results/DerivedData" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
  mkdir "$results/Payload"
  ditto "$results/DerivedData/Build/Products/Release-iphoneos/Athkar.app" "$results/Payload/Athkar.app"
  app="$results/Payload/Athkar.app"
  # Sign embedded code first so the app seals its final bytes.
  for framework in "$app"/Frameworks/*; do
    [[ -e $framework ]] || continue
    codesign --force --sign - --generate-entitlement-der "$framework"
  done
  codesign --force --sign - --generate-entitlement-der "$app"
  codesign --verify --deep --strict "$app"
  [[ ! -f $app/embedded.mobileprovision ]] || { echo "IPA must have no device-bound profile." >&2; exit 1; }
  version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist")
  build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Info.plist")
  ipa="$results/Athkar-$version+$build.ipa"
  ditto -c -k --keepParent "$results/Payload" "$ipa"
  shasum -a 256 "$ipa"
fi
