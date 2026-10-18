#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/test-native-core.sh" --suite models "$@"
