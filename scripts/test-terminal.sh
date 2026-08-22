#!/bin/sh
# Copyright © 2026 MikroKhoros contributors.
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

if [ -n "${KHOROS_BIN:-}" ]; then
  khoros_binary=$KHOROS_BIN
elif [ -n "${SWIFT_BUILD_FLAGS:-}" ]; then
  # shellcheck disable=SC2086
  swift build $SWIFT_BUILD_FLAGS
  # shellcheck disable=SC2086
  build_directory=$(swift build $SWIFT_BUILD_FLAGS --show-bin-path)
  khoros_binary="$build_directory/khoros"
else
  swift build
  build_directory=$(swift build --show-bin-path)
  khoros_binary="$build_directory/khoros"
fi

python3 "$project_root/scripts/test-terminal.py" "$khoros_binary"
