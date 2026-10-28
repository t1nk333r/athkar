#!/usr/bin/env bash
# Coordinator-granted Linux checks only. See docs/agents/ios-linux.md.
set -euo pipefail
set +m # The owned setsid child must get its own process group, not a job-control group.

usage() {
  cat <<'USAGE'
usage: test-native-core.sh [--filter REGEX | --all | --base REF] [--jobs 1|2]
                          [--results NEW_DIRECTORY] [-c debug|release]
                          [--caller-held-locks SHARED_FD PROJECT_FD]
       test-native-models.sh [same options]
       ios-linux-compile.sh [--build-tests] [same options except --filter, --all and --base]

Without --filter or --all, the suite runs only the tests the changes since the merge
base with origin/main (--base REF, or $ATHKAR_TEST_BASE) reach, and exits 0 when no
change reaches it; tools/affected-tests.py prints the selection and why.
--all runs the whole suite.
ATHKAR_SWIFT selects an installed Swift executable. No tools are installed.
Results and scratch are retained outside the checkout. Exit 3 means a busy lane.
Caller-held descriptors must already hold exclusive locks on the two fixed lanes.
The caller retains and releases its locks after the wrapper returns.
USAGE
}
fail() { echo "$*" >&2; exit 2; }
suite=core jobs=2 configuration=debug filter='' results='' shared_fd='' project_fd='' build_tests=0
select_all=0 base=
while (($#)); do
  case "$1" in
    --suite) (($# >= 2)) || fail 'Missing suite.'; suite=$2; shift 2 ;;
    --filter) (($# >= 2)) && [[ -n $2 && -z $filter ]] || fail 'Supply one nonempty filter.'; filter=$2; shift 2 ;;
    --all) select_all=1; shift ;;
    --base) (($# >= 2)) && [[ -n $2 && -z $base ]] || fail 'Supply one base branch or commit.'; base=$2; shift 2 ;;
    --jobs) (($# >= 2)) || fail 'Missing job count.'; jobs=$2; shift 2 ;;
    -c|--configuration) (($# >= 2)) || fail 'Missing configuration.'; configuration=$2; shift 2 ;;
    --results) (($# >= 2)) && [[ -n $2 && -z $results ]] || fail 'Supply one new results directory.'; results=$2; shift 2 ;;
    --caller-held-locks)
      (($# >= 3)) && [[ -z $shared_fd ]] || fail 'Supply shared and project descriptors once.'
      shared_fd=$2 project_fd=$3; shift 3 ;;
    --build-tests) build_tests=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done
[[ $suite == core || $suite == models || $suite == sdk ]] || fail 'Unknown suite.'
[[ $jobs == 1 || $jobs == 2 ]] || fail 'Use at most two jobs: --jobs 1 or --jobs 2.'
[[ $configuration == debug || $configuration == release ]] || fail 'Use debug or release configuration.'
[[ $suite != sdk || -z $filter ]] || fail 'SDK compilation executes no tests and takes no filter.'
[[ $suite == sdk || $build_tests == 0 ]] || fail '--build-tests is only for SDK compilation.'
[[ $suite != sdk || ( $select_all == 0 && -z $base ) ]] \
  || fail 'SDK compilation builds what it is asked to; tools/test.sh decides whether it is needed.'
(( (${#filter} > 0) + select_all + (${#base} > 0) <= 1 )) || fail 'Use one of --filter, --all and --base.'
[[ $(uname -s) == Linux ]] || fail 'New native checks run on Linux.'
for tool in flock setsid realpath git tar grep python3; do command -v "$tool" >/dev/null || fail "Missing installed tool: $tool"; done
repo=$(cd "$(dirname "$0")/.." && pwd -P)
[[ -z $(git -C "$repo" status --porcelain) ]] || fail 'Commit source first; the runner archives the exact clean HEAD.'
head=$(git -C "$repo" rev-parse HEAD)
if [[ $suite != sdk && -z $filter && $select_all == 0 ]]; then
  # The selection prints what it picked and why; a selector error selects the whole suite.
  selection=$(python3 "$repo/tools/affected-tests.py" select "$suite" ${base:+--base "$base"}) \
    || fail 'The affected-test selection failed; --all runs the whole suite.'
  eval "$selection"
  if [[ $ATHKAR_TEST_RUN == 0 ]]; then
    echo "Nothing to run: no change since $ATHKAR_TEST_BASE_LABEL reaches the $suite suite. --all runs it in full."
    exit 0
  fi
  filter=$ATHKAR_TEST_FILTER
fi
swift=${ATHKAR_SWIFT:-$(command -v swift || true)}
[[ -n $swift ]] || swift="$HOME/.local/share/swift-6.4.0/usr/bin/swift"
swift=$(command -v "$swift") || fail 'Select an installed Swift with ATHKAR_SWIFT.'
[[ -x $swift ]] || fail 'Swift is not executable.'

# Never truncate, unlink, or replace a shared lock file.
shared_lock=${ATHKAR_SHARED_BUILD_LOCK:-/tmp/hikaya-build-suite.lock}
project_lock=/tmp/athkar-build-suite.lock
[[ $shared_lock == /* ]] || fail 'The shared lock path must be absolute.'
owned_locks=0 child_pid='' results_ready=0 terminal=not_started
# shellcheck disable=SC2329 # Invoked by the EXIT trap, including cancellation paths.
finish() {
  status=$?
  trap - EXIT
  trap '' INT TERM
  if [[ -n $child_pid ]]; then
    # The owned subreaper drains descendants, including children that change process group.
    kill -TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    terminal=terminated
  fi
  if [[ $owned_locks == 1 ]]; then
    exec {project_fd}>&-
    exec {shared_fd}>&-
  fi
  if [[ $results_ready == 1 ]]; then
    printf 'exit=%s process=%s locks=%s\n' "$status" "$terminal" \
      "$([[ $owned_locks == 1 ]] && echo released || echo caller_retained)" >> "$results/resource.log"
    printf '%s\n' "$status" > "$results/exit-status"
  fi
  exit "$status"
}
trap 'finish' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -n $shared_fd ]]; then
  [[ $shared_fd =~ ^[3-9]$ && $project_fd =~ ^[3-9]$ && $shared_fd != "$project_fd" ]] || fail 'Use distinct inherited descriptors 3 through 9.'
  for pair in "$shared_fd:$shared_lock" "$project_fd:$project_lock"; do
    fd=${pair%%:*} path=${pair#*:}
    [[ $(realpath "/proc/$$/fd/$fd" 2>/dev/null) == "$path" ]] || fail "Descriptor $fd is not the required lane."
    grep -Eq '^lock:.*FLOCK[[:space:]]+ADVISORY[[:space:]]+WRITE' "/proc/$$/fdinfo/$fd" \
      || fail "Descriptor $fd does not hold an exclusive flock."
  done
else
  for path in "$shared_lock" "$project_lock"; do
    [[ ! -L $path && ( ! -e $path || -f $path ) ]] || fail "Lane is not a regular lock file: $path"
  done
  exec {shared_fd}>>"$shared_lock"
  if ! flock -n "$shared_fd"; then
    exec {shared_fd}>&-
    echo "Shared native lane is busy: $shared_lock" >&2; exit 3
  fi
  exec {project_fd}>>"$project_lock"
  if ! flock -n "$project_fd"; then
    exec {project_fd}>&-
    exec {shared_fd}>&- # Release immediately; never wait while holding only the shared lane.
    echo "Athkar native lane is busy: $project_lock" >&2; exit 3
  fi
  owned_locks=1
fi

if [[ -n $results ]]; then
  results=$(realpath -m "$results")
  case "$results/" in "$repo/"*) fail 'Keep results and scratch outside the checkout.' ;; esac
  mkdir "$results" || fail 'Results must be a fresh directory with an existing parent.'
else
  root=${ATHKAR_CORE_RESULTS_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/athkar-native-checks}
  root=$(realpath -m "$root")
  case "$root/" in "$repo/"*) fail 'Keep results and scratch outside the checkout.' ;; esac
  mkdir -p "$root"
  results=$(mktemp -d "$root/$(basename "$repo")-$suite.XXXXXX")
fi
results_ready=1
printf 'host=%s head=%s repo=%s suite=%s configuration=%s jobs=%s runner_pid=%s\n' \
  "$(hostname)" "$head" "$repo" "$suite" "$configuration" "$jobs" "$$" > "$results/resource.log"
printf 'shared_lane=%s project_lane=%s ownership=%s\n' "$shared_lock" "$project_lock" \
  "$([[ $owned_locks == 1 ]] && echo runner || echo caller)" >> "$results/resource.log"
echo "Results: $results"
"$swift" --version > "$results/toolchain.log" 2>&1
mkdir "$results/repo" "$results/test-data"
git -C "$repo" archive "$head" | tar -x -C "$results/repo"
snapshot="$results/repo"
unset ATHKAR_LINUX_SDK_BUILD
export ATHKAR_TEST_TMP="$results/test-data"
common=(--configuration "$configuration" --scratch-path "$results/scratch" --cache-path "$results/cache"
        --config-path "$results/config" --security-path "$results/security"
        --disable-dependency-cache --manifest-cache local --jobs "$jobs")
if [[ $suite == sdk ]]; then
  export ATHKAR_LINUX_SDK_BUILD=1
  sdk_root=${ATHKAR_SWIFT_SDKS_PATH:-$HOME/.swiftpm/swift-sdks}
  sdk_bundle="$sdk_root/darwin.artifactbundle"
  [[ -f $sdk_bundle/swift-sdk.json && -f $sdk_bundle/toolset-swb.json && -d $sdk_bundle/Developer/Platforms ]] \
    || fail 'The existing Darwin SDK is unavailable; no provisioning is performed.'
  # Match the installed xtool BuildSettings SwiftBuild route without configuring the host.
  unset SDKROOT
  export XCODE_EXTRA_PLATFORM_FOLDERS="$sdk_bundle/Developer/Platforms"
  export PATH="$sdk_bundle/toolset/bin:$PATH"
  printf 'XCODE_EXTRA_PLATFORM_FOLDERS=%s PATH_prefix=%s SDKROOT=unset\n' \
    "$XCODE_EXTRA_PLATFORM_FOLDERS" "$sdk_bundle/toolset/bin" >> "$results/resource.log"
  resources="$snapshot/ios/Athkar/Resources"
  mkdir "$resources"
  for path in content/manifest.json content/adhkar.v1.json content/ruqyah.v1.json content/suwar.v1.json \
              fonts/kfgqpc-uthman-taha-naskh.ttf fonts/kfgqpc-hafs-v30.ttf data/cities.tsv; do
    cp "$snapshot/$path" "$resources/"
  done
  # SwiftBuild may generate asset symbols; this is not installable-app packaging.
  command=("$swift" build --package-path "$snapshot/ios" "${common[@]}"
           --build-system swiftbuild --triple arm64-apple-ios --toolset "$sdk_bundle/toolset-swb.json")
  [[ ! -f $snapshot/ios/Package.resolved ]] || command+=(--force-resolved-versions)
  if [[ $build_tests == 1 ]]; then
    frameworks="$sdk_bundle/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks"
    # SwiftPM forbids --build-tests together with --target. Select the test target directly.
    command+=(--target AthkarTests -Xswiftc -enable-testing
              -Xswiftc -F -Xswiftc "$frameworks" -Xlinker -F -Xlinker "$frameworks")
  else
    command+=(--target Athkar)
  fi
else
  package="$snapshot/ios"
  [[ $suite != core ]] || package="$package/AthkarCore"
  command=("$swift" test --package-path "$package" "${common[@]}" --no-parallel)
  [[ $configuration != release ]] || command+=(-Xswiftc -enable-testing)
  [[ -z $filter ]] || command+=(--filter "$filter")
  # The first portable run resolves in the snapshot. Return that lockfile, commit it, then rerun.
  [[ ! -f $package/Package.resolved ]] || command+=(--force-resolved-versions)
fi
if [[ $suite == sdk ]]; then
  printf 'env -u SDKROOT %q %q %q %q ' "ATHKAR_LINUX_SDK_BUILD=1" "ATHKAR_TEST_TMP=$ATHKAR_TEST_TMP" \
    "XCODE_EXTRA_PLATFORM_FOLDERS=$XCODE_EXTRA_PLATFORM_FOLDERS" "PATH=$PATH" > "$results/command.log"
else
  printf 'env -u ATHKAR_LINUX_SDK_BUILD %q ' "ATHKAR_TEST_TMP=$ATHKAR_TEST_TMP" > "$results/command.log"
fi
printf '%q ' "${command[@]}" >> "$results/command.log"
printf '\n' >> "$results/command.log"
# A Linux child subreaper adopts orphaned descendants. Its terminal return, rather
# than the Swift driver's return, controls the locks and completion marker.
setsid python3 - "$results/resource.log" "$shared_fd" "$project_fd" "${command[@]}" \
  > "$results/check.log" 2>&1 <<'PY' &
import ctypes
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

log_path, shared_fd, project_fd, *command = sys.argv[1:]
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
    raise OSError(ctypes.get_errno(), "Cannot establish owned process-tree supervision")
stopping = None
deadline = None
signalled = set()
seen = set()
owner = os.getpid()

def request_stop(number, frame):
    global stopping, deadline
    if stopping is None:
        deadline = time.monotonic() + 5
        stopping = number

signal.signal(signal.SIGTERM, request_stop)
signal.signal(signal.SIGINT, request_stop)

def record(message):
    with open(log_path, "a") as log:
        log.write(message + "\n")

def identity(pid):
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()
        return int(fields[1]), int(fields[2]), fields[19], fields[0]
    except (OSError, IndexError, ValueError):
        return None

def descendants():
    processes = {}
    for path in Path("/proc").iterdir():
        if path.name.isdecimal():
            details = identity(int(path.name))
            if details:
                processes[int(path.name)] = details
    owned = {owner}
    while True:
        expanded = owned | {pid for pid, data in processes.items() if data[0] in owned}
        if expanded == owned:
            return {pid: processes[pid] for pid in owned - {owner}}
        owned = expanded

child = subprocess.Popen(command, pass_fds=(int(shared_fd), int(project_fd)))
record(f"swift_pid={child.pid} supervisor_pid={owner}")
root_status = None
while True:
    if stopping and deadline is None:
        deadline = time.monotonic() + 5
    for pid, data in descendants().items():
        token = (pid, data[2])
        if token not in seen:
            record(f"owned_tree_pid={pid} ppid={data[0]} pgid={data[1]} start_ticks={data[2]}")
            seen.add(token)
        if stopping and data[3] != "Z":
            number = signal.SIGKILL if time.monotonic() >= deadline else signal.SIGTERM
            current = identity(pid)
            if (token, number) not in signalled and current and current[2] == data[2]:
                try:
                    os.kill(pid, number)
                    signalled.add((token, number))
                except ProcessLookupError:
                    pass
    no_children = False
    while True:
        try:
            pid, status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            no_children = True
            break
        if pid == 0:
            break
        code = os.waitstatus_to_exitcode(status)
        record(f"owned_tree_pid={pid} terminal_exit={code}")
        if pid == child.pid:
            root_status = code
            child.returncode = code
    if no_children:
        record("owned_tree_terminal=1")
        break
    time.sleep(0.05)
sys.exit(128 + stopping if stopping else (root_status if root_status >= 0 else 128 - root_status))
PY
child_pid=$!
printf 'owned_pid=%s owned_pgid=%s started=%s\n' "$child_pid" "$child_pid" "$(date -u +%FT%TZ)" >> "$results/resource.log"
status=0
wait "$child_pid" || status=$?
printf 'owned_pid=%s terminal_exit=%s ended=%s\n' "$child_pid" "$status" "$(date -u +%FT%TZ)" >> "$results/resource.log"
child_pid=
terminal=exited
cat "$results/check.log"
if [[ $status == 0 && $suite == core ]]; then
  grep -Eq 'Test run with [1-9][0-9]* tests?( in [0-9]+ suites?)? passed' "$results/check.log" \
    || { echo 'No passing nonempty Swift Testing run was reported.' >&2; status=1; }
elif [[ $status == 0 && $suite == models ]]; then
  grep -Eq 'Executed [1-9][0-9]* tests?, with 0 failures' "$results/check.log" \
    || { echo 'No passing nonempty production XCTest run was reported.' >&2; status=1; }
fi
exit "$status"
