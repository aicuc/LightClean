#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
TEST_BIN="$(mktemp -d)/scanner-tests"
trap 'rm -rf "${TEST_BIN:h}"' EXIT
swiftc -parse-as-library Sources/LightClean/Scanner.swift Sources/LightClean/DeepScanner.swift Sources/LightClean/SpecialScanner.swift Tests/LightCleanTests/ScannerTests.swift -o "$TEST_BIN"
"$TEST_BIN"
