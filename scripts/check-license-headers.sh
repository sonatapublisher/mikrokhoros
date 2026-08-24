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

status=0
files=$(find Sources Tests -type f -name '*.swift' -print)
files="$files
Package.swift
Makefile"
for script in scripts/*.sh; do
  files="$files
$script"
done
for script in scripts/*.py; do
  files="$files
$script"
done

for file in $files; do
  case "$file" in
    *.swift) marker='//' ;;
    Makefile | *.sh | *.py) marker='#' ;;
    *) continue ;;
  esac
  header=$(sed -n '1,24p' "$file")
  if ! printf '%s\n' "$header" | grep -Fq "$marker Copyright © 2026 mikrokhoros contributors." \
    || ! printf '%s\n' "$header" | grep -Fq "$marker Licensed under the Apache License, Version 2.0 (the \"License\");" \
    || ! printf '%s\n' "$header" | grep -Fq "$marker   https://www.apache.org/licenses/LICENSE-2.0" \
    || ! printf '%s\n' "$header" | grep -Fq "$marker limitations under the License."
  then
    printf 'missing or incomplete license header: %s\n' "$file" >&2
    status=1
  fi
done

exit "$status"
