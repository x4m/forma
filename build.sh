#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
forma_cache="${FORMA_MODULE_CACHE:-.build/module-cache}"
mkdir -p "$forma_cache" build/Forma.app/Contents/MacOS build/Forma.app/Contents/Resources
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$forma_cache" \
    Sources/Forma/*.swift -o build/Forma.app/Contents/MacOS/Forma
cp Resources/*.png build/Forma.app/Contents/Resources/
cp Info.plist build/Forma.app/Contents/Info.plist
codesign --force --sign - build/Forma.app
echo "Built: $PWD/build/Forma.app"
