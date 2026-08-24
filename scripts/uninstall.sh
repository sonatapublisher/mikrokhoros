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

install_root=${KHOROS_INSTALL_ROOT:-"$HOME/.local"}
binary="$install_root/bin/khoros"

if [ -f "$binary" ]; then
  rm -f "$binary"
  printf 'removed %s\n' "$binary"
else
  printf 'khoros is not installed at %s\n' "$binary"
fi
printf 'user data under %s was preserved\n' "${MIKROKHOROS_HOME:-$HOME/.mikrokhoros}"
