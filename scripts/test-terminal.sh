#!/bin/sh
# Copyright © 2026 mikrokhoros contributors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

project_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

if [ -n "${SWIFT_BUILD_FLAGS:-}" ]; then
  # shellcheck disable=SC2086
  swift build $SWIFT_BUILD_FLAGS
  # shellcheck disable=SC2086
  build_directory=$(swift build $SWIFT_BUILD_FLAGS --show-bin-path)
else
  swift build
  build_directory=$(swift build --show-bin-path)
fi

case "$build_directory" in
  /*) ;;
  *)
    echo "SwiftPM returned a non-absolute binary directory" >&2
    exit 2
    ;;
esac

if [ ! -d "$build_directory" ]; then
  echo "SwiftPM binary directory does not exist" >&2
  exit 2
fi

build_directory=$(CDPATH='' cd -P -- "$build_directory" && pwd)
khoros_binary="$build_directory/khoros"
if [ -L "$khoros_binary" ] || [ ! -f "$khoros_binary" ] || [ ! -x "$khoros_binary" ]; then
  echo "SwiftPM binary directory does not contain a regular executable khoros" >&2
  exit 2
fi

cd "$build_directory"
exec python3 "$project_root/scripts/test-terminal.py"
