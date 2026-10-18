#!/usr/bin/env bash
# Builds Release Athkar.app for arm64-apple-ios on Linux and packages an ad hoc signed
# sideload IPA. See docs/agents/ios-linux.md. Nothing is installed, paired or published.
set -euo pipefail
set +m # Each owned setsid child must get its own process group, not a job-control group.

usage() {
  cat <<'USAGE'
usage: ios-linux-ipa.sh [--jobs 1|2] [--out DIRECTORY] [--results NEW_DIRECTORY] [--wait]

Writes Athkar-<CFBundleShortVersionString>+<CFBundleVersion>-linux.ipa and its .sha256 to
--out (default ~/Projects/athkar-builds). An existing IPA is never replaced.
Exit 3 means a busy lane. --wait retries every 150 seconds for up to 90 minutes and holds
no lock while it waits.
ATHKAR_SWIFT, ATHKAR_XCODEGEN, ATHKAR_RCODESIGN, ATHKAR_SWIFT_SDKS_PATH and
ATHKAR_XCODE_VERSION_PLIST select installed tools. No tools are installed.
USAGE
}
fail() { echo "$*" >&2; exit 2; }
jobs=2 out='' results='' wait_for_lane=0
while (($#)); do
  case "$1" in
    --jobs) (($# >= 2)) || fail 'Missing job count.'; jobs=$2; shift 2 ;;
    --out) (($# >= 2)) && [[ -n $2 && -z $out ]] || fail 'Supply one output directory.'; out=$2; shift 2 ;;
    --results) (($# >= 2)) && [[ -n $2 && -z $results ]] || fail 'Supply one new results directory.'; results=$2; shift 2 ;;
    --wait) wait_for_lane=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done
[[ $jobs == 1 || $jobs == 2 ]] || fail 'Use at most two jobs: --jobs 1 or --jobs 2.'
[[ $(uname -s) == Linux ]] || fail 'Athkar IPAs are built on Linux.'
for tool in flock setsid realpath git tar diff stat awk python3; do
  command -v "$tool" >/dev/null || fail "Missing installed tool: $tool"
done
repo=$(cd "$(dirname "$0")/.." && pwd -P)
[[ -z $(git -C "$repo" status --porcelain) ]] || fail 'Commit source first; the build archives the exact clean HEAD.'
head=$(git -C "$repo" rev-parse HEAD)
epoch=$(git -C "$repo" log -1 --format=%ct "$head")

swift=${ATHKAR_SWIFT:-$(command -v swift || true)}
[[ -n $swift ]] || swift="$HOME/.local/share/swift-6.4.0/usr/bin/swift"
swift=$(command -v "$swift") || fail 'Select an installed Swift with ATHKAR_SWIFT.'
xcodegen=${ATHKAR_XCODEGEN:-$HOME/.cache/athkar-xcodegen/build-2.46.0/release/xcodegen}
rcodesign=${ATHKAR_RCODESIGN:-$HOME/.local/bin/rcodesign}
sdk_bundle=${ATHKAR_SWIFT_SDKS_PATH:-$HOME/.swiftpm/swift-sdks}/darwin.artifactbundle
sdk_settings=$sdk_bundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/SDKSettings.json
actool=$sdk_bundle/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/actool
[[ -x $xcodegen ]] || fail "XcodeGen 2.46.0 is missing at $xcodegen; see docs/agents/ios-linux.md."
[[ -x $rcodesign ]] || fail "rcodesign is missing at $rcodesign."
[[ -f $sdk_settings && -x $actool && -f $sdk_bundle/toolset-swb.json ]] \
  || fail 'The existing Darwin SDK is unavailable; no provisioning is performed.'
sdk_version=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["Version"])' "$sdk_settings")
# xtool records the Xcode that the SDK was taken from; Xcode writes it as DTXcode and DTXcodeBuild.
xcode_version=${ATHKAR_XCODE_VERSION_PLIST:-$HOME/.cache/xtool/darwin-iPhoneOS$sdk_version.xtoolsdk.version.plist}
[[ -f $xcode_version ]] || fail "No Xcode version is recorded for the iOS $sdk_version SDK at $xcode_version."
noise='libxml2\.so\.2: no version information available'
"$xcodegen" --version 2>&1 | grep -qx 'Version: 2.46.0' || fail "$xcodegen is not XcodeGen 2.46.0."
"$rcodesign" --version 2>&1 | grep -qx 'apple-codesign 0.29.0' || fail "$rcodesign is not apple-codesign 0.29.0."

out=$(realpath -m "${out:-$HOME/Projects/athkar-builds}")
case "$out/" in "$repo/"*) fail 'Keep the output directory outside the checkout.' ;; esac
mkdir -p "$out"
[[ -d $out && ! -L $out && $(stat -c %u "$out") == $(id -u) ]] || fail "$out is not this user's directory."
(( ($(stat -c %#a "$out") & 8#022) == 0 )) || fail "$out is writable by group or others."
# The committed generated files name this version; the build checks them against project.yml.
name=$(python3 -I "$repo/tools/ios-linux-ipa.py" name --repo "$repo")
for path in "$out/$name" "$out/$name.sha256"; do
  [[ ! -e $path && ! -L $path ]] || fail "$path exists; a version is built once."
done

# Never truncate, unlink, or replace a lock file. The build runner verifies descriptors 8 and 9.
shared_lock=${ATHKAR_SHARED_BUILD_LOCK:-/tmp/hikaya-build-suite.lock}
project_lock=/tmp/athkar-build-suite.lock
[[ $shared_lock == /* ]] || fail 'The shared lock path must be absolute.'
owned_locks=0 child_pid='' sleep_pid='' results_ready=0 terminal=not_started
# shellcheck disable=SC2329 # Invoked by the EXIT trap, including cancellation paths.
finish() {
  status=$?
  trap - EXIT
  trap '' INT TERM
  if [[ -n $sleep_pid ]]; then
    kill "$sleep_pid" 2>/dev/null || true
    wait "$sleep_pid" 2>/dev/null || true
  fi
  if [[ -n $child_pid ]]; then
    # Each step runs in its own session; the build step drains its own supervised tree.
    kill -TERM -- "-$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    terminal=terminated
  fi
  if [[ $owned_locks == 1 ]]; then
    exec 9>&- 8>&-
  fi
  if [[ $results_ready == 1 ]]; then
    printf 'exit=%s process=%s locks=%s ended=%s\n' "$status" "$terminal" \
      "$([[ $owned_locks == 1 ]] && echo released || echo none)" "$(date -u +%FT%TZ)" >> "$results/resource.log"
    printf '%s\n' "$status" > "$results/.done"
  fi
  exit "$status"
}
trap 'finish' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

lane_owner() { # Read-only: the process /proc/locks names as the holder of a lock file.
  local major minor inode pid
  read -r major minor inode < <(stat -c '%Hd %Ld %i' "$1")
  pid=$(awk -v dev="$(printf '%02x:%02x' "$major" "$minor")" -v ino="$inode" \
    '$2 == "FLOCK" && $4 == "WRITE" && $6 == dev ":" ino { print $5; exit }' /proc/locks)
  [[ -n $pid ]] && printf 'held by pid %s: %s' "$pid" "$(ps -o args= -p "$pid" 2>/dev/null | cut -c1-160)"
}
busy() { # lane name, path
  echo "$1 native lane is busy: $2 ($(lane_owner "$2" || echo 'owner unknown'))" >&2
}
acquire_lanes() {
  local path
  for path in "$shared_lock" "$project_lock"; do
    [[ ! -L $path && ( ! -e $path || -f $path ) ]] || fail "Lane is not a regular lock file: $path"
  done
  exec 8>>"$shared_lock"
  if ! flock -n 8; then
    exec 8>&-
    busy Shared "$shared_lock"; return 3
  fi
  exec 9>>"$project_lock"
  if ! flock -n 9; then
    exec 9>&- 8>&- # Release immediately; never wait while holding only the shared lane.
    busy Athkar "$project_lock"; return 3
  fi
  owned_locks=1
}
deadline=$((SECONDS + 90 * 60))
until acquire_lanes; do
  ((wait_for_lane && SECONDS + 150 <= deadline)) || exit 3
  echo "Retrying at $(date -u -d '+150 seconds' +%FT%TZ); no lock is held while waiting." >&2
  sleep 150 &
  sleep_pid=$!
  wait "$sleep_pid" || true
  sleep_pid=
done

if [[ -n $results ]]; then
  results=$(realpath -m "$results")
  case "$results/" in "$repo/"*) fail 'Keep results and scratch outside the checkout.' ;; esac
  mkdir -m 700 "$results" || fail 'Results must be a fresh directory with an existing parent.'
else
  root=${ATHKAR_CORE_RESULTS_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/athkar-native-checks}
  root=$(realpath -m "$root")
  case "$root/" in "$repo/"*) fail 'Keep results and scratch outside the checkout.' ;; esac
  mkdir -p "$root"
  results=$(mktemp -d "$root/$(basename "$repo")-ipa.XXXXXX")
fi
results_ready=1
printf 'host=%s head=%s repo=%s tool=ios-linux-ipa jobs=%s out=%s runner_pid=%s started=%s\n' \
  "$(hostname)" "$head" "$repo" "$jobs" "$out" "$$" "$(date -u +%FT%TZ)" > "$results/resource.log"
printf 'shared_lane=%s project_lane=%s ownership=runner\n' "$shared_lock" "$project_lock" >> "$results/resource.log"
echo "Results: $results"
{
  "$swift" --version 2>&1
  "$xcodegen" --version 2>&1 | grep -Ev "$noise"
  "$rcodesign" --version
  printf 'sdk=%s %s\nxcode=%s\n' "$sdk_bundle" "$sdk_version" "$xcode_version"
} > "$results/toolchain.log"

run_owned() { # step, log, command...
  local step=$1 log=$2 status=0
  shift 2
  if [[ $step == build ]]; then
    setsid "$@" > "$log" 2>&1 < /dev/null &
  else
    setsid "$@" > "$log" 2>&1 < /dev/null 8>&- 9>&- & # Only the build runner receives the lanes.
  fi
  child_pid=$!
  printf 'step=%s owned_pid=%s owned_pgid=%s started=%s\n' "$step" "$child_pid" "$child_pid" \
    "$(date -u +%FT%TZ)" >> "$results/resource.log"
  wait "$child_pid" || status=$?
  printf 'step=%s owned_pid=%s terminal_exit=%s ended=%s\n' "$step" "$child_pid" "$status" \
    "$(date -u +%FT%TZ)" >> "$results/resource.log"
  child_pid=
  terminal=exited
  return "$status"
}
step_failed() { # step, log
  grep -Ev "$noise" "$2" | tail -n 40 >&2
  echo "The $1 step failed; see $2." >&2
  exit 1
}

# XcodeGen in a fresh snapshot writes the Info.plist and Xcode project the IPA follows.
# The committed generated files must be the same, so the repository describes this app.
mkdir "$results/repo" "$results/committed"
git -C "$repo" archive "$head" | tar -x -C "$results/repo"
git -C "$repo" archive "$head" ios/Athkar.xcodeproj ios/Athkar/Info.plist | tar -x -C "$results/committed"
run_owned xcodegen "$results/xcodegen.log" env -C "$results/repo" "$xcodegen" generate --spec ios/project.yml \
  || step_failed xcodegen "$results/xcodegen.log"
if ! diff -r "$results/committed/ios/Athkar.xcodeproj" "$results/repo/ios/Athkar.xcodeproj" > "$results/generated.diff" \
  || ! diff "$results/committed/ios/Athkar/Info.plist" "$results/repo/ios/Athkar/Info.plist" >> "$results/generated.diff"; then
  cat "$results/generated.diff" >&2
  echo 'The committed Xcode project or Info.plist differs from ios/project.yml; regenerate and commit them.' >&2
  exit 1
fi
[[ $(python3 -I "$repo/tools/ios-linux-ipa.py" name --repo "$results/repo") == "$name" ]] \
  || { echo 'The generated version differs from the committed one.' >&2; exit 1; }
printf 'ipa=%s/%s\n' "$out" "$name" >> "$results/resource.log"

# The existing SDK compile route, in Release, under the lanes this script holds.
run_owned build "$results/build.log" env ATHKAR_SWIFT="$swift" ATHKAR_SHARED_BUILD_LOCK="$shared_lock" \
  "$repo/tools/ios-linux-compile.sh" --jobs "$jobs" -c release --results "$results/build" --caller-held-locks 8 9 \
  || step_failed build "$results/build.log"
grep -q "^host=.* head=$head " "$results/build/resource.log" || { echo 'The build ran on a different head.' >&2; exit 1; }
products="$results/build/scratch/out/Products/Release-iphoneos"

mkdir -m 700 "$results/stage"
run_owned package "$results/package.log" python3 -I "$repo/tools/ios-linux-ipa.py" package \
  --repo "$results/repo" --products "$products" --sdk-bundle "$sdk_bundle" --xcode-version "$xcode_version" \
  --rcodesign "$rcodesign" --stage "$results/stage" --out-dir "$out" --epoch "$epoch" \
  || step_failed package "$results/package.log"
grep -Ev "$noise" "$results/package.log"
