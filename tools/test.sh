#!/usr/bin/env bash
# Athkar's checks for what changed. Each lane runs only what the changes since the merge base
# with origin/main reach; tools/affected-tests.py works that out and says why.
#
#   selector   Linux   the selection's own tests (tools/affected-tests-test.py)
#   content    Linux   the Node content, fixture and backup checks the changes reach
#   core       Linux   AthkarCore Swift Testing suites (tools/test-native-core.sh)
#   models     Linux   portable production-model XCTest classes (tools/test-native-models.sh)
#   ios-build  Linux   the app compiled for iOS (tools/ios-linux-compile.sh); compiling
#                      AthkarTests is listed: its bundle can't be packaged on Linux yet
#   app-unit   device  hosted AthkarTests classes   } listed only: Linux can't run them;
#   ui         Mac     AthkarUITests classes        } tools/ios-mac-run.sh test selects both
#
#   tools/test.sh [--plan] [--all | --base REF] [--lanes selector,content,...]
#
# --plan shows what each lane would run and why, and runs nothing. --all runs every lane in
# full. --base REF compares with REF instead of origin/main ($ATHKAR_TEST_BASE also sets it).
# The changes include uncommitted and untracked files, but the native lanes build the clean
# committed HEAD, so commit before running them. They take the shared and Athkar build lanes
# without waiting; see docs/agents/ios-linux.md. ATHKAR_RUQYAH_CONTENT names the ruqyah PWA's
# content.js for content-export-pwa (default ../ruqyah-al-qareen/content.js). The last line is
#   RESULT status=pass|fail|incomplete lanes=<lane>:<outcome>,...
# where an outcome is pass, fail, none (nothing to run), listed (app-unit and ui), busy or
# unavailable. Exit 0, 1, or 3 when a lane with work couldn't run.
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
SELECT=(python3 tools/affected-tests.py)
PLAN=0 MODE=() LANES=selector,content,core,models,ios-build,app-unit,ui

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  case $1 in
    --plan) PLAN=1 ;;
    --all) MODE=(--all) ;;
    --base) [ $# -ge 2 ] || usage; MODE=(--base "$2"); shift ;;
    --lanes) [ $# -ge 2 ] || usage; LANES=$2; shift ;;
    *) usage ;;
  esac
  shift
done
for lane in ${LANES//,/ }; do
  case $lane in selector | content | core | models | ios-build | app-unit | ui) ;; *) echo "unknown lane $lane" >&2; usage ;; esac
done

"${SELECT[@]}" check || { echo "RESULT status=fail lanes=selector"; exit 1; }
"${SELECT[@]}" plan "${MODE[@]}" || { echo "RESULT status=fail lanes=selector"; exit 1; }
[ $PLAN = 1 ] && exit 0

OUTCOMES=() FAILED=0 MISSING=0
outcome() {
  OUTCOMES+=("$1:$2")
  case $2 in fail) FAILED=1 ;; busy | unavailable) MISSING=1 ;; esac
}
# Sets ATHKAR_TEST_RUN, ATHKAR_TEST_FULL, ATHKAR_TEST_WHAT and the lane's own values.
selected() {
  local out
  out=$("${SELECT[@]}" select "$1" "${MODE[@]}") || return 1
  eval "$out"
}
# A native runner's exit: 0 passed, 3 its build lane busy, 2 a precondition (such as
# uncommitted changes) kept it from running.
native() {
  local lane=$1 status
  shift
  "$@"
  status=$?
  case $status in
    0) outcome "$lane" pass ;;
    3) outcome "$lane" busy ;;
    2) outcome "$lane" unavailable ;;
    *) outcome "$lane" fail ;;
  esac
}
# The selection's own filter, or --all when the lane runs in full.
filter_args() {
  if [ "$ATHKAR_TEST_FULL" = 1 ]; then FILTER=(--all); else FILTER=(--filter "$ATHKAR_TEST_FILTER"); fi
}
ruqyah_content() {
  local path
  for path in ${ATHKAR_RUQYAH_CONTENT:-} ../ruqyah-al-qareen/content.js; do
    [ -f "$path" ] && { echo "$path"; return; }
  done
}
# fixtures-generate.mjs rewrites spec/; it runs in a copy and must reproduce spec/ exactly.
fixtures_check() {
  local copy status
  copy=$(mktemp -d) || return 1
  git ls-files -z --cached --others --exclude-standard -- index.html content spec tools \
    | xargs -0 tar -cf - | tar -xf - -C "$copy" \
    && node "$copy/tools/fixtures-generate.mjs" \
    && diff -r spec "$copy/spec"
  status=$?
  rm -rf -- "$copy"
  return $status
}
content_check() {
  case $1 in
    content-validate) node tools/content-validate.mjs ;;
    content-review-test) node tools/content-review-test.mjs ;;
    content-export-pwa)
      local ruqyah
      ruqyah=$(ruqyah_content)
      if [ -n "$ruqyah" ]; then
        node tools/content-export-pwa.mjs --check --ruqyah "$ruqyah"
      else
        echo "no ruqyah content.js (set ATHKAR_RUQYAH_CONTENT): checking index.html only"
        node tools/content-export-pwa.mjs --check
      fi
      ;;
    fixtures) fixtures_check ;;
    backup-validate) node tools/backup-validate.mjs spec/backup/examples/*.athkarbackup ;;
    *) echo "no command for content check $1"; return 1 ;;
  esac
}

for lane in ${LANES//,/ }; do
  echo "== $lane"
  selected "$lane" || { outcome "$lane" fail; continue; }
  if [ "$ATHKAR_TEST_RUN" = 0 ]; then
    echo "nothing to run"
    outcome "$lane" none
    continue
  fi
  echo "$ATHKAR_TEST_WHAT"
  case $lane in
    selector) python3 tools/affected-tests-test.py && outcome selector pass || outcome selector fail ;;
    content)
      result=pass
      for check in $ATHKAR_TEST_CHECKS; do
        echo "-- $check"
        content_check "$check" || { echo "-- $check failed"; result=fail; }
      done
      outcome content $result
      ;;
    core) filter_args; native core tools/test-native-core.sh --jobs 2 "${FILTER[@]}" ;;
    models) filter_args; native models tools/test-native-models.sh --jobs 2 "${FILTER[@]}" ;;
    ios-build)
      # --build-tests compiles and links AthkarTests, then fails packaging its bundle
      # (CopySwiftLibs: --strip-bitcode without --strip-bitcode-tool); docs/agents/ios-linux.md.
      [ "$ATHKAR_TEST_BUILD_TESTS" = 0 ] \
        || echo "listed: tools/ios-linux-compile.sh --jobs 2 --build-tests (AthkarTests bundle packaging fails on Linux)"
      if [ "$ATHKAR_TEST_BUILD_APP" = 1 ]; then
        native ios-build tools/ios-linux-compile.sh --jobs 2
      else
        outcome ios-build listed
      fi
      ;;
    app-unit)
      echo "listed: hosted AthkarTests need an authorized iOS device (docs/agents/ios-linux.md): $ATHKAR_TEST_ONLY_TESTING"
      outcome app-unit listed
      ;;
    ui)
      echo "listed: on the Mac, tools/ios-mac-run.sh test runs these: $ATHKAR_TEST_ONLY_TESTING"
      outcome ui listed
      ;;
  esac
done

status=pass code=0
[ $MISSING = 1 ] && status=incomplete code=3
[ $FAILED = 1 ] && status=fail code=1
lanes=$(IFS=,; echo "${OUTCOMES[*]}")
echo "RESULT status=$status lanes=$lanes"
exit $code
