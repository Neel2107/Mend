#!/bin/bash

set -euo pipefail

developer_dir="$(xcode-select -p)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
testing_libraries="$developer_dir/Library/Developer/usr/lib"
swift_test_args=()

if [[ -d "$testing_frameworks/Testing.framework" ]]; then
  swift_test_args+=(
    -Xswiftc "-F$testing_frameworks"
    -Xlinker "-F$testing_frameworks"
    -Xlinker -rpath
    -Xlinker "$testing_frameworks"
  )
fi

if [[ -d "$testing_libraries" ]]; then
  swift_test_args+=(
    -Xlinker -rpath
    -Xlinker "$testing_libraries"
  )
fi

swift test "${swift_test_args[@]}"
