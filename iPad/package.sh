#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent iPad/Forma.swiftpm build/Forma-iPad-Playgrounds.zip
echo "Packaged: $PWD/build/Forma-iPad-Playgrounds.zip"
