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

add_header() {
  file=$1
  marker=$2
  keep_first=$3
  if sed -n '1,24p' "$file" | grep -Fq "$marker Copyright © 2026 mikrokhoros contributors."; then
    return
  fi
  temporary=$(mktemp "${TMPDIR:-/tmp}/mikrokhoros-license.XXXXXX")
  if [ "$keep_first" = true ]; then
    sed -n '1p' "$file" >"$temporary"
  fi
  awk -v prefix="$marker" '{
    if (length($0) == 0) {
      print prefix
    } else {
      print prefix " " $0
    }
  }' scripts/license-header.txt >>"$temporary"
  printf '\n' >>"$temporary"
  if [ "$keep_first" = true ]; then
    sed '1d' "$file" | awk 'NR == 1 && length($0) == 0 { next } { print }' >>"$temporary"
  else
    sed -n '1,$p' "$file" >>"$temporary"
  fi
  mv "$temporary" "$file"
}

find Sources Tests -type f -name '*.swift' -print | while IFS= read -r file; do
  add_header "$file" '//' false
done
add_header Package.swift '//' true
add_header Makefile '#' false
for file in scripts/*.sh; do
  add_header "$file" '#' true
  chmod +x "$file"
done
for file in scripts/*.py; do
  add_header "$file" '#' true
  chmod +x "$file"
done
