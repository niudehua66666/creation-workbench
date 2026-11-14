#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
TEST_FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
if [[ ! -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
    TEST_FRAMEWORKS="$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks"
fi
if [[ -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
    TEST_RUNTIME="$(dirname "$TEST_FRAMEWORKS")/usr/lib"
    EXTRA_TEST_FLAGS=()
    if [[ -f "$TEST_RUNTIME/lib_TestingInterop.dylib" ]]; then
        EXTRA_TEST_FLAGS=(-Xlinker -rpath -Xlinker "$TEST_RUNTIME")
    fi
    swift test --disable-xctest \
        -Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" \
        -Xlinker -F -Xlinker "$TEST_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" "${EXTRA_TEST_FLAGS[@]}"
else
    swift test --disable-xctest
fi
