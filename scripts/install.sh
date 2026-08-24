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
install_root=${KHOROS_INSTALL_ROOT:-"$HOME/.local"}
install_directory="$install_root/bin"

cd "$project_root"
if [ -n "${SWIFT_BUILD_FLAGS:-}" ]; then
  # The value is intentionally word-split so callers can provide multiple SwiftPM flags.
  # shellcheck disable=SC2086
  swift build -c release $SWIFT_BUILD_FLAGS
  # shellcheck disable=SC2086
  binary_directory=$(swift build -c release $SWIFT_BUILD_FLAGS --show-bin-path)
else
  swift build -c release
  binary_directory=$(swift build -c release --show-bin-path)
fi

mkdir -p "$install_directory"
install -m 755 "$binary_directory/khoros" "$install_directory/khoros"
printf 'installed khoros at %s\n' "$install_directory/khoros"
case ":${PATH:-}:" in
  *:"$install_directory":*) ;;
  *) printf 'add %s to PATH to run khoros from any terminal\n' "$install_directory" ;;
esac
