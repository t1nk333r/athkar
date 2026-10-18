#!/usr/bin/env bash
# Compiles actual app sources against the existing iOS SDK; executes no tests.
set -euo pipefail
exec "$(dirname "$0")/test-native-core.sh" --suite sdk "$@"
