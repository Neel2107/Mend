#!/bin/bash

set -euo pipefail

developer_dir="$(xcode-select -p)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
testing_libraries="$developer_dir/Library/Developer/usr/lib"

if [[ -d "$testing_frameworks/Testing.framework" && -d "$testing_libraries" ]]; then
  swift test \
    -Xswiftc "-F$testing_frameworks" \
    -Xlinker "-F$testing_frameworks" \
    -Xlinker -rpath \
    -Xlinker "$testing_frameworks" \
    -Xlinker -rpath \
    -Xlinker "$testing_libraries"
else
  swift test
fi
