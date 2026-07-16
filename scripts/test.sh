#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

run_step() {
    local title="$1"
    shift

    echo ""
    echo "=== $title ==="
    "$@"
}

cd "$PROJECT_DIR"

swift_test_command=(swift test --package-path Prototype)
clt_frameworks="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
clt_libraries="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
if [[ -d "$clt_frameworks/Testing.framework" ]]; then
    swift_test_command+=(
        -Xswiftc -F
        -Xswiftc "$clt_frameworks"
        -Xlinker "-F$clt_frameworks"
        -Xlinker -rpath
        -Xlinker "$clt_frameworks"
        -Xlinker -rpath
        -Xlinker "$clt_libraries"
    )
fi

run_step "Prototype Tests" "${swift_test_command[@]}"

run_step "Clean Debug Build Products" \
    xcodebuild \
        -project CCFlow.xcodeproj \
        -scheme CCFlow \
        -configuration Debug \
        clean

run_step "Root Xcode Unit Tests" \
    xcodebuild \
        -project CCFlow.xcodeproj \
        -scheme CCFlow \
        -configuration Debug \
        CODE_SIGNING_ALLOWED=NO \
        test \
        -only-testing:CCFlowTests

run_step "Clean Before Full Scheme Test" \
    xcodebuild \
        -project CCFlow.xcodeproj \
        -scheme CCFlow \
        -configuration Debug \
        clean

run_step "Root Xcode Full Test Scheme" \
    xcodebuild \
        -project CCFlow.xcodeproj \
        -scheme CCFlow \
        -configuration Debug \
        CODE_SIGN_IDENTITY=- \
        test

echo ""
echo "=== All Tests Passed ==="
